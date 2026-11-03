class_name DuelOnlineScene
extends Node2D
## The networked duel: lobby, connection, and then the same duel as the local
## mode with a NetSession stepping it.
##
## The lobby is an overlay on the live scene rather than a separate scene, so
## the arena is already built and the first frame of the fight costs nothing
## once a connection lands — and so failing back to a local duel is a matter of
## hiding a panel, not loading anything.
##
## WHO STEPS THE DUEL
##   local mode    this file, from _physics_process
##   online mode   NetSession.poll(), also from _physics_process. It may step
##                 the duel twice in a frame to catch up, or not at all to let
##                 the host come to it, and it rewinds and replays whenever the
##                 host corrects it. That is the whole reason Duel.step() takes
##                 its inputs as arguments instead of reading a device.

const MENU_SCENE := "res://scenes/menu.tscn"

@onready var duel: Duel = $Duel
@onready var camera: DuelCamera = $Camera
@onready var sky: ParallaxSky = $Sky/ParallaxSky
@onready var hud: DuelHud = $HudLayer/Hud
@onready var lobby: DuelLobby = $LobbyLayer/Lobby

var transport: WsTransport
var session: NetSession

var _online := false
var _local_fallback := false


func _ready() -> void:
	var arena := AsciiLevel.from_file(DuelRules.ARENA_PATH)
	if arena == null:
		push_error("no arena at %s" % DuelRules.ARENA_PATH)
		return

	duel.setup(arena)
	camera.setup(duel)
	sky.camera = camera
	sky.seed_value = hash(arena.name)

	hud.duel = duel
	hud.visible = false

	duel.cut_landed.connect(_on_cut_landed)
	duel.cut_blocked.connect(_on_cut_blocked)
	duel.swords_clashed.connect(_on_clash)

	lobby.host_room_requested.connect(_host_room)
	lobby.join_room_requested.connect(_join_room)
	lobby.host_direct_requested.connect(_host_direct)
	lobby.join_direct_requested.connect(_join_direct)
	lobby.local_requested.connect(_play_locally)
	lobby.back_requested.connect(_to_menu)


func _physics_process(_delta: float) -> void:
	if _online:
		# NetSession.poll() pumps the transport for us.
		session.poll()
		if session == null:
			return
		if session.stage == NetSession.Stage.ENDED and not _local_fallback:
			_offer_fallback(session.status_detail)
		return

	# No session yet, but there may already be a transport dialling a relay.
	# Nothing else pumps it, and until it is pumped the room's ROOM_OK never
	# arrives — so the lobby would sit on "opening a room" for ever.
	if transport != null:
		transport.poll()

	if _local_fallback:
		_local_frame()
		return

	# Still in the lobby. Escape leaves, unless a field has the keyboard.
	if Input.is_action_just_pressed("pause") and not lobby.is_typing():
		if lobby.page == DuelLobby.Page.MENU:
			_to_menu()
		else:
			lobby.show_menu()
	elif Input.is_action_just_pressed("attack") and lobby.page == DuelLobby.Page.BUSY:
		_give_up()


## --- local fallback ---------------------------------------------------------

func _local_frame() -> void:
	if duel.phase == Duel.Phase.MATCH_OVER:
		hud.footer = "JUMP FOR A REMATCH  ·  SWORD FOR THE MENU"
		if Input.is_action_just_pressed("jump"):
			duel.reset_match()
			camera.setup(duel)
		elif Input.is_action_just_pressed("attack"):
			_to_menu()
		return
	duel.step(
		PlayerInput.bits_from_actions("_p1"),
		PlayerInput.bits_from_actions("_p2")
	)


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
	# Otherwise wait for room_assigned.
	set_process_internal(true)


func _on_room_assigned(code: String, as_host: bool) -> void:
	lobby.show_busy(
		"ROOM %s  ·  TELL THE OTHER PLAYER" % code if as_host
		else "ROOM %s  ·  CONNECTED" % code
	)
	if session == null:
		_start_session(as_host)


func _start_session(as_host: bool) -> void:
	session = NetSession.new()
	session.local_input = func() -> int: return PlayerInput.bits_from_actions("")
	session.desync_detected.connect(_on_desync)
	session.handshake_complete.connect(_on_seated)
	# Deferred: both fire from inside session.poll(), and tearing the session
	# down there leaves poll() running on a closed transport.
	session.link_failed.connect(_offer_fallback, CONNECT_DEFERRED)
	session.peer_departed.connect(_on_peer_departed, CONNECT_DEFERRED)
	session.start(transport, duel, as_host)

	hud.session = session
	_online = true


func _on_link_changed(link: NetTransport.Link, detail: String) -> void:
	lobby.set_status(detail)
	if link == NetTransport.Link.FAILED and not _online:
		_offer_fallback(detail)


func _on_seated(slot: int) -> void:
	# Connected and seated: the lobby's work is done.
	lobby.visible = false
	hud.visible = true
	hud.your_slot = slot
	hud.footer = "PAUSE TO LEAVE"
	for seat: int in 2:
		DuelArt.dress(duel.players[seat], seat, seat == slot)
	duel.reset_match()
	camera.setup(duel)


func _on_peer_departed() -> void:
	_offer_fallback("the other player left")


## --- giving up --------------------------------------------------------------

## Anything that goes wrong lands here: a refused connection, a relay that is
## not running, a peer that walked away. The honest answer is to say what
## happened and offer the duel that cannot fail.
func _offer_fallback(reason: String) -> void:
	if _local_fallback:
		return
	_online = false
	_teardown()
	hud.session = null
	hud.visible = false
	lobby.visible = true
	lobby.show_menu()
	lobby.set_status(reason if reason != "" else "could not connect")


func _give_up() -> void:
	_offer_fallback("gave up waiting")


func _play_locally() -> void:
	_teardown()
	_online = false
	_local_fallback = true
	lobby.visible = false
	hud.visible = true
	hud.session = null
	hud.your_slot = -1
	hud.footer = "LOCAL TWO-PLAYER  ·  PAUSE TO LEAVE"
	for seat: int in 2:
		DuelArt.dress(duel.players[seat], seat, false)
	duel.reset_match()
	camera.setup(duel)


func _teardown() -> void:
	if session != null:
		session.shutdown()
		session = null
	if transport != null:
		transport.close()
		transport = null
	_online = false


func _to_menu() -> void:
	_teardown()
	get_tree().change_scene_to_file(MENU_SCENE)


func _exit_tree() -> void:
	_teardown()


## --- presentation reactions -------------------------------------------------

func _on_cut_landed(victim: int, _at: Vector2) -> void:
	camera.shake(3.4, 0.4)
	hud.flash("%s DOWN" % DuelRules.slot_label(victim))


func _on_cut_blocked(_defender: int, parried: bool, _at: Vector2) -> void:
	camera.shake(2.6 if parried else 1.5, 0.22)
	hud.flash("PARRY" if parried else "BLOCKED")


func _on_clash(_at: Vector2) -> void:
	camera.shake(2.0, 0.2)
	hud.flash("CLASH")


func _on_desync(frame: int, mine: int, theirs: int) -> void:
	push_warning("duel desync at frame %d: %08x vs %08x" % [frame, mine, theirs])
	camera.shake(1.2, 0.3)
