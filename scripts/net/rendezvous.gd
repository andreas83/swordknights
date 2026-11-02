extends Node
## A tiny WebSocket relay: pairs two players by a four-character room code and
## forwards bytes between them.
##
##     godot --headless --path . res://scenes/rendezvous.tscn -- --port 45678
##
## WHY THIS EXISTS
## A browser cannot open a listening socket, so a web player can never be the
## host of a direct connection, and two web players could never meet at all.
## A relay solves that, and incidentally removes port forwarding and NAT from
## the picture for native players too: both sides dial *out* to the relay.
##
## WHAT IT IS NOT
## It is not a game server and it knows nothing about duelling. It reads only
## the ROOM_* messages in NetProtocol and forwards everything else untouched,
## so the host-authoritative simulation still runs on one of the two players'
## machines. The cost is a second hop: round trip becomes player -> relay ->
## player, so put the relay somewhere between the two of you.
##
## It is also a public endpoint, so it assumes nothing about what arrives:
## oversized packets are dropped, unparseable ones are ignored, rooms are
## capped and expire, and a peer that has not joined a room cannot make it
## forward anything.

const DEFAULT_PORT := 45678
## A room with nobody in it, or one nobody ever joined, is collected.
const ROOM_IDLE_SECONDS := 600.0
const MAX_ROOMS := 512
const MAX_MESSAGE_BYTES := 64 * 1024
## Codes are four characters from a 29-letter alphabet; give up well before
## exhausting the space rather than spinning.
const CODE_ATTEMPTS := 32

var port := DEFAULT_PORT

var _peer: WebSocketMultiplayerPeer
var _rooms := {} # code -> {host: int, guest: int, opened: float}
var _room_of := {} # peer id -> code
var _rng := RandomNumberGenerator.new()
var _sweep := 0.0


func _ready() -> void:
	_rng.randomize()
	_parse_args()

	_peer = WebSocketMultiplayerPeer.new()
	_peer.inbound_buffer_size = MAX_MESSAGE_BYTES
	var err := _peer.create_server(port)
	if err != OK:
		push_error("rendezvous: could not listen on port %d (%d)" % [port, err])
		get_tree().quit(1)
		return
	_peer.peer_connected.connect(_on_peer_connected)
	_peer.peer_disconnected.connect(_on_peer_disconnected)
	print("rendezvous listening on port %d — room codes are %d characters"
		% [port, NetProtocol.CODE_LENGTH])


func _process(delta: float) -> void:
	if _peer == null:
		return
	_peer.poll()

	while _peer.get_available_packet_count() > 0:
		# get_packet_peer() must be read before get_packet().
		var from := _peer.get_packet_peer()
		var bytes := _peer.get_packet()
		if bytes.size() > MAX_MESSAGE_BYTES:
			continue
		_handle(from, bytes)

	_sweep += delta
	if _sweep >= 30.0:
		_sweep = 0.0
		_collect_idle_rooms()


## --- messages ---------------------------------------------------------------

func _handle(from: int, bytes: PackedByteArray) -> void:
	var message := NetProtocol.decode(bytes)

	# Anything we cannot read is forwarded if the sender is in a room, and
	# dropped otherwise. A relay should not need to understand a duel to carry
	# one, and a future protocol version must still be able to pass through.
	if message.has("error"):
		_forward(from, bytes)
		return

	match int(message["type"]):
		NetProtocol.Type.ROOM_OPEN:
			_open_room(from)
		NetProtocol.Type.ROOM_JOIN:
			_join_room(from, String(message["code"]))
		NetProtocol.Type.ROOM_OK, NetProtocol.Type.ROOM_ERROR, \
		NetProtocol.Type.ROOM_PEER:
			pass # the relay says these; it does not relay them
		_:
			_forward(from, bytes)


func _open_room(from: int) -> void:
	if _room_of.has(from):
		_leave(from)
	if _rooms.size() >= MAX_ROOMS:
		_send(from, NetProtocol.room_error(
			NetProtocol.RoomError.TOO_MANY_ROOMS, "the relay is full, try later"
		))
		return

	var code := ""
	for i: int in CODE_ATTEMPTS:
		var candidate := NetProtocol.make_room_code(_rng)
		if not _rooms.has(candidate):
			code = candidate
			break
	if code == "":
		_send(from, NetProtocol.room_error(
			NetProtocol.RoomError.TOO_MANY_ROOMS, "could not find a free code"
		))
		return

	_rooms[code] = {"host": from, "guest": 0, "opened": _now()}
	_room_of[from] = code
	_send(from, NetProtocol.room_ok(code, true))
	print("room %s opened by peer %d (%d open)" % [code, from, _rooms.size()])


func _join_room(from: int, raw: String) -> void:
	var code := raw.strip_edges().to_upper()
	if not NetProtocol.is_room_code(code):
		_send(from, NetProtocol.room_error(
			NetProtocol.RoomError.BAD_CODE, "'%s' is not a room code" % code
		))
		return
	if not _rooms.has(code):
		_send(from, NetProtocol.room_error(
			NetProtocol.RoomError.NO_SUCH_ROOM, "no room %s" % code
		))
		return

	var room: Dictionary = _rooms[code]
	if int(room["guest"]) != 0 or int(room["host"]) == from:
		_send(from, NetProtocol.room_error(
			NetProtocol.RoomError.ROOM_FULL, "room %s is full" % code
		))
		return

	if _room_of.has(from):
		_leave(from)
	room["guest"] = from
	_room_of[from] = code
	_send(from, NetProtocol.room_ok(code, false))
	# Both sides are told the room is complete, so neither has to poll for it.
	_send(from, NetProtocol.room_peer(true))
	_send(int(room["host"]), NetProtocol.room_peer(true))
	print("room %s joined by peer %d" % [code, from])


func _forward(from: int, bytes: PackedByteArray) -> void:
	var other := _other_in_room(from)
	if other != 0:
		_send(other, bytes)


## --- peers ------------------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	print("peer %d connected" % id)


func _on_peer_disconnected(id: int) -> void:
	print("peer %d disconnected" % id)
	_leave(id)


## Takes a peer out of its room and tells whoever is left. A room whose host
## leaves is closed: the authoritative simulation was running there.
func _leave(id: int) -> void:
	if not _room_of.has(id):
		return
	var code: String = _room_of[id]
	_room_of.erase(id)
	if not _rooms.has(code):
		return

	var room: Dictionary = _rooms[code]
	var host := int(room["host"])
	var guest := int(room["guest"])

	if id == host:
		if guest != 0:
			_send(guest, NetProtocol.room_error(
				NetProtocol.RoomError.NO_SUCH_ROOM, "the host left room %s" % code
			))
			_room_of.erase(guest)
		_rooms.erase(code)
		print("room %s closed (host left)" % code)
	elif id == guest:
		room["guest"] = 0
		room["opened"] = _now()
		_send(host, NetProtocol.room_peer(false))
		print("room %s: guest left" % code)


func _other_in_room(id: int) -> int:
	if not _room_of.has(id):
		return 0
	var code: String = _room_of[id]
	if not _rooms.has(code):
		return 0
	var room: Dictionary = _rooms[code]
	var host := int(room["host"])
	var guest := int(room["guest"])
	if id == host:
		return guest
	return host if id == guest else 0


func _collect_idle_rooms() -> void:
	var now := _now()
	for code: String in _rooms.keys():
		var room: Dictionary = _rooms[code]
		if int(room["guest"]) != 0:
			continue
		if now - float(room["opened"]) < ROOM_IDLE_SECONDS:
			continue
		var host := int(room["host"])
		_send(host, NetProtocol.room_error(
			NetProtocol.RoomError.NO_SUCH_ROOM, "room %s expired" % code
		))
		_room_of.erase(host)
		_rooms.erase(code)
		print("room %s expired" % code)


func _send(to: int, bytes: PackedByteArray) -> void:
	if to == 0 or _peer == null:
		return
	_peer.set_target_peer(to)
	_peer.put_packet(bytes)


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		if args[i] == "--port" and i + 1 < args.size():
			port = int(args[i + 1])
			i += 2
		else:
			i += 1
	if port <= 0 or port > 65535:
		port = DEFAULT_PORT
