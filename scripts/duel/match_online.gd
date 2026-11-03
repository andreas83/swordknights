extends "res://scripts/duel/match_scene.gd"
## The tug of war between two devices: lobby, connection, then the same match
## as the local mode with a NetSession stepping it.
##
## On a desktop two players share one keyboard (the local Duel). Two players do
## not fit on one phone, so on a phone each plays on their own and the phones
## are paired here: one hosts and shows a one-number code, the other types it
## (scripts/net/lan_code.gd), or both use a relay room.
##
## Everything the match looks like -- zones, fighters, gore, the dusk over the
## last rooms, the camera -- is the parent scene's. This file only adds the
## lobby, the transport and the session, in the shape the retired round duel's
## online scene first used.
##
## WHO STEPS THE MATCH
##   in the lobby   nobody: the fighters stand on their marks
##   online         NetSession.poll(), from _physics_process. It may step the
##                  match twice in a frame to catch up, or not at all to let the
##                  host come to it, and it rewinds and replays whenever the host
##                  corrects it -- which is why DuelMatch.step() takes its inputs
##                  as arguments. tests/match_net_test.gd plays exactly this.
##   local          the parent, from two keyboard seats, if the lobby's local
##                  option is chosen or a connection fails

@onready var lobby: DuelLobby = $LobbyLayer/Lobby

var transport: WsTransport
var session: NetSession

var _online := false
var _local := false
## The seat this phone was given, once seated; -1 before and after.
var _my_slot := -1


func _ready() -> void:
	super._ready()
	hud.footer = "WAITING FOR A SECOND PLAYER"
	lobby.host_room_requested.connect(_host_room)
	lobby.join_room_requested.connect(_join_room)
	lobby.host_direct_requested.connect(_host_direct)
	lobby.join_direct_requested.connect(_join_direct)
	lobby.local_requested.connect(_play_locally)
	lobby.back_requested.connect(_to_menu)
	_pair_from_arguments()


## `--host` or `--join=CODE` in the user arguments skip the lobby's taps: for
## two desktop windows, and for checking the whole path -- lobby, code,
## connection, seating -- between two processes without touching a screen.
func _pair_from_arguments() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--host":
			lobby._on_host_direct()
		elif arg.begins_with("--join="):
			var target := LanCode.resolve(arg.trim_prefix("--join="), LanCode.my_address())
			lobby.show_busy("CONNECTING TO %s…" % target)
			_join_direct(target)


func _physics_process(delta: float) -> void:
	if _online:
		# NetSession.poll() pumps the transport, steps, rewinds and replays.
		session.poll()
		if session == null:
			return
		_follow_the_match()
		if session.stage == NetSession.Stage.ENDED:
			_offer_fallback(session.status_detail)
		elif Input.is_action_just_pressed("pause"):
			_to_menu()
		return

	if _local:
		super._physics_process(delta)
		return

	# Still in the lobby. A relay room needs its transport pumped before there
	# is any session to do it, or ROOM_OK never arrives.
	if transport != null:
		transport.poll()
	if Input.is_action_just_pressed("pause") and not lobby.is_typing():
		if lobby.page == DuelLobby.Page.MENU:
			_to_menu()
		else:
			lobby.show_menu()
	elif Input.is_action_just_pressed("attack") and lobby.page == DuelLobby.Page.BUSY:
		_offer_fallback("gave up waiting")


## --- opening a connection ---------------------------------------------------

func _host_room(relay_url: String) -> void:
	_begin(func(net: WsTransport) -> Error: return net.join_room(relay_url, ""))


func _join_room(relay_url: String, code: String) -> void:
	_begin(func(net: WsTransport) -> Error: return net.join_room(relay_url, code))


func _host_direct(port: int) -> void:
	_begin(func(net: WsTransport) -> Error: return net.host(port), true)


func _join_direct(url: String) -> void:
	_begin(func(net: WsTransport) -> Error: return net.join(url), false)


## `as_host` is known up front for a direct connection; for a relayed one it
## arrives with the room, so the session is not started until then.
func _begin(open: Callable, as_host: Variant = null) -> void:
	_teardown()
	transport = WsTransport.new()
	transport.link_changed.connect(_on_link_changed)
	transport.room_assigned.connect(_on_room_assigned)
	var err: Error = open.call(transport)
	if err != OK:
		_offer_fallback(transport.detail)
		return
	if as_host != null:
		_start_session(bool(as_host))


func _on_room_assigned(code: String, as_host: bool) -> void:
	lobby.show_busy(
		"ROOM %s  ·  TELL THE OTHER PLAYER" % code if as_host
		else "ROOM %s  ·  CONNECTED" % code
	)
	if session == null:
		_start_session(as_host)


func _start_session(as_host: bool) -> void:
	session = NetSession.new()
	# One player per device: the unsuffixed actions, which the keyboard, a
	# gamepad and the touch controls all drive.
	session.local_input = func() -> int: return PlayerInput.bits_from_actions("")
	session.desync_detected.connect(_on_desync)
	session.handshake_complete.connect(_on_seated)
	# Deferred: these fire from inside session.poll(), and tearing the session
	# and its socket down there left poll() running on a closed transport --
	# a crash every time the other player closed the app.
	session.link_failed.connect(_offer_fallback, CONNECT_DEFERRED)
	session.peer_departed.connect(
		func() -> void: _offer_fallback("the other player left"), CONNECT_DEFERRED)
	session.start(transport, fight, as_host)
	hud.session = session
	_online = true


func _on_link_changed(link: NetTransport.Link, detail: String) -> void:
	lobby.set_status(detail)
	if link == NetTransport.Link.FAILED and not _online:
		_offer_fallback(detail)


func _on_seated(slot: int) -> void:
	lobby.visible = false
	_my_slot = slot
	dress_fighters()
	hud.your_slot = slot
	hud.footer = "YOU ARE %s  ·  PAUSE TO LEAVE" % ("CRIMSON" if slot == 0 else "SEA-GREEN")
	camera.setup(fight)


## --- who wears what ---------------------------------------------------------

## Online, each phone shows its own player in the look chosen on it -- player
## one's, since a phone is one player -- and the other seat in that seat's
## default: the prince, in the seat's colour. The protocol carries inputs and
## nothing else, and a look is not worth a protocol change (docs/netplay.md,
## open items). Until seated, both seats are the defaults; played locally from
## the lobby, it is the one-keyboard duel's two looks.
func look_for(slot: int) -> CharacterLook:
	if _local:
		return super.look_for(slot)
	if _online and slot == _my_slot:
		return Wardrobe.open(wardrobe_path).look(Wardrobe.PLAYER_ONE)
	return CharacterLook.new()


## --- giving up --------------------------------------------------------------

## A refused connection, a relay that is not running, a peer that walked away:
## say what happened and put the lobby back.
func _offer_fallback(reason: String) -> void:
	_teardown()
	lobby.visible = true
	lobby.show_menu()
	lobby.set_status(reason if reason != "" else "could not connect")
	hud.footer = "WAITING FOR A SECOND PLAYER"
	dress_fighters()


func _play_locally() -> void:
	_teardown()
	_local = true
	dress_fighters()
	lobby.visible = false
	hud.footer = "TWO PLAYERS, ONE KEYBOARD  ·  PAUSE TO QUIT"


func _teardown() -> void:
	if session != null:
		session.shutdown()
		session = null
	hud.session = null
	hud.your_slot = -1
	_my_slot = -1
	if transport != null:
		transport.close()
		transport = null
	_online = false


func _to_menu() -> void:
	_teardown()
	get_tree().change_scene_to_file(MENU_SCENE)


func _exit_tree() -> void:
	_teardown()


func _on_desync(frame: int, mine: int, theirs: int) -> void:
	push_warning("match desync at frame %d: %08x vs %08x" % [frame, mine, theirs])
