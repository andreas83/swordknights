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
## The other player's look as received in the handshake and checked against
## this build's options; null before seating, after leaving, and in the lobby.
var _their_look: CharacterLook = null


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
		else:
			_drive_online_menu(delta)
		return

	if _local:
		super._physics_process(delta)
		return

	# Still in the lobby. A relay room needs its transport pumped before there
	# is any session to do it, or ROOM_OK never arrives.
	if transport != null:
		transport.poll()
	var thumbs := lobby.thumb_labels()
	TouchControls.label(self, thumbs[0], thumbs[1])
	if lobby.is_typing():
		return
	lobby.drive()
	# Enter is SWORD as well as the GUI's accept: pressed on a row, it is the
	# row's, never also a step back.
	var sword := DuelLobby.pressed_alone(&"attack", &"ui_accept")
	if Input.is_action_just_pressed("pause"):
		_lobby_back()
	elif sword:
		if lobby.page == DuelLobby.Page.BUSY:
			_offer_fallback("gave up waiting")
		else:
			_lobby_back()


## Back one step from the lobby: a text page to its list, the list to the
## duel page.
func _lobby_back() -> void:
	if lobby.page == DuelLobby.Page.MENU:
		_to_menu()
	else:
		lobby.show_menu()


## --- the menu, online ---------------------------------------------------------
##
## The match cannot stop: the other phone is still stepping it, and the frame
## this one is on is the host's. So the menu is two rows -- KEEP FIGHTING,
## LEAVE MATCH -- over a lighter scrim, its heading says the match goes on,
## and while it is up this phone sends no input at all (_local_bits()):
## the fighter stands where he was, as he would if the player put the phone
## down. Leaving is the session's own shutdown, which says BYE, so the other
## phone hears "the other player left" and goes back to its lobby rather than
## timing out on a silent socket. Once the match is over there is no rematch
## to offer -- both phones would have to agree to it -- so SWORD or PAUSE
## leaves.

func menu_rows() -> Array[Dictionary]:
	return [
		{"id": &"resume", "title": "KEEP FIGHTING", "enabled": true},
		{"id": &"leave", "title": "LEAVE MATCH", "enabled": true},
	]


func over_jump_label() -> String:
	return ""


func _drive_online_menu(delta: float) -> void:
	_label_thumbs()
	var over := fight.phase == DuelMatch.Phase.MATCH_OVER
	if over:
		menu.close()
		hud.footer = "SWORD OR PAUSE TO LEAVE"
		if Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("attack"):
			_to_menu()
		return
	if Input.is_action_just_pressed("pause"):
		if menu.is_open():
			menu.close()
		else:
			menu.title = "THE MATCH GOES ON"
			menu.scrim = 0.5
			menu.open(menu_rows())
		_label_thumbs()
		return
	menu.step(delta)


## This phone's byte for the frame: nothing while the menu is up.
func _local_bits() -> int:
	if menu != null and menu.is_open():
		return 0
	# And not the press that chose KEEP FIGHTING, while it is still down.
	if _held_over:
		if _menu_press_held():
			return 0
		_held_over = false
	return PlayerInput.bits_from_actions("")


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
	session.local_input = _local_bits
	# Sent once, in the handshake, so the other phone can draw this player as
	# they chose. Player one's look: a phone is one player.
	session.local_look = _my_look().to_ids()
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
	# Checked against this build's options by the rule the wardrobe reads its
	# own file by: a field that is missing or names nothing stays the default,
	# alone. An older build sends nothing, and its player is the prince.
	_their_look = CharacterLook.from_ids(session.remote_look if session != null else {})
	if session != null and session.remote_look_error != "":
		push_warning("the other player's look was dropped: %s" % session.remote_look_error)
	dress_fighters()
	hud.your_slot = slot
	hud.footer = "YOU ARE %s  ·  %s" % ["CRIMSON" if slot == 0 else "SEA-GREEN", PLAY_FOOTER]
	camera.setup(fight)


## --- who wears what ---------------------------------------------------------

## Online, each phone shows its own player in the look chosen on it -- player
## one's, since a phone is one player -- and the other player in the look their
## phone sent in the handshake (docs/netplay.md, "The looks"). Whatever either
## look says, dress_fighters() puts it on through FighterArt.dress(), which
## imposes the seat's colour last, so a received look cannot put a player in
## the other team's robe. Until seated, both seats are the defaults; played
## locally from the lobby, it is the one-keyboard duel's two looks.
func look_for(slot: int) -> CharacterLook:
	if _local:
		return super.look_for(slot)
	if _online and _my_slot >= 0:
		if slot == _my_slot:
			return _my_look()
		if _their_look != null:
			return _their_look.duplicate_look()
	return CharacterLook.new()


func _my_look() -> CharacterLook:
	return Wardrobe.open(wardrobe_path).look(Wardrobe.PLAYER_ONE)



## --- giving up --------------------------------------------------------------

## A refused connection, a relay that is not running, a peer that walked away:
## say what happened and put the lobby back.
func _offer_fallback(reason: String) -> void:
	_teardown()
	menu.close()
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
	hud.footer = "TWO PLAYERS, ONE KEYBOARD  ·  " + PLAY_FOOTER


func _teardown() -> void:
	if session != null:
		session.shutdown()
		session = null
	hud.session = null
	hud.your_slot = -1
	_my_slot = -1
	_their_look = null
	if transport != null:
		transport.close()
		transport = null
	_online = false


## Leaves cleanly: the session's shutdown says BYE before the socket closes,
## and only then does the scene go.
func _to_menu() -> void:
	_teardown()
	super._to_menu()


func _exit_tree() -> void:
	_teardown()


func _on_desync(frame: int, mine: int, theirs: int) -> void:
	push_warning("match desync at frame %d: %08x vs %08x" % [frame, mine, theirs])
