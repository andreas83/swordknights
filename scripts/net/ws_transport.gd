class_name WsTransport
extends NetTransport
## WebSocket transport, in three modes: direct host, direct join, and relayed
## by room code.
##
## WHY WEBSOCKET AND NOT ENET
## The web export is the build you can send someone a link to, and a browser
## has no UDP: Godot's ENetMultiplayerPeer simply does not exist there. A
## WebSocket is the only transport a web build and a phone build can share, so
## it is the one the duel is built on. The cost is honest and documented — it is
## TCP, so a lost packet is not dropped but retransmitted, and a loss spike
## arrives as a latency spike with everything behind it held up. The prediction
## and reconciliation in session.gd is what absorbs that.
##
## WHY THERE IS A RELAY
## A browser cannot accept an incoming connection either, so a web player can
## never be the host of a direct link, and two web players could never meet at
## all. `join_room` sends both of them to a small WebSocket server that pairs
## them by code and forwards bytes between them (scripts/net/rendezvous.gd).
## That also removes port forwarding from the picture for native players.
##
## The room handshake is handled here rather than in the session, because
## "which seat am I" is a property of how the connection was made.

enum Mode { NONE, DIRECT_HOST, DIRECT_GUEST, RELAY }

const RELAY_PEER := 1 ## a relay is a WebSocket server, so it is always peer 1
const DEFAULT_PORT := 45678

var mode: Mode = Mode.NONE
var room_code := ""
var is_host_seat := false

var _peer: WebSocketMultiplayerPeer
var _remote_id := 0
var _url := ""
var _port := 0
var _want_code := ""
var _room_requested := false


## --- opening ----------------------------------------------------------------

func host(port: int = DEFAULT_PORT) -> Error:
	if not supports_hosting():
		_set_link(Link.FAILED, "this build cannot accept connections")
		return ERR_UNAVAILABLE
	_reset()
	mode = Mode.DIRECT_HOST
	is_host_seat = true
	_port = port
	_peer = WebSocketMultiplayerPeer.new()
	_wire_signals()
	var err := _peer.create_server(port)
	if err != OK:
		_set_link(Link.FAILED, "could not listen on port %d (%d)" % [port, err])
		return err
	_set_link(Link.WAITING, "listening on port %d" % port)
	return OK


func join(url: String) -> Error:
	_reset()
	mode = Mode.DIRECT_GUEST
	is_host_seat = false
	_url = normalise_url(url)
	_peer = WebSocketMultiplayerPeer.new()
	_wire_signals()
	var err := _peer.create_client(_url)
	if err != OK:
		_set_link(Link.FAILED, "could not dial %s (%d)" % [_url, err])
		return err
	_remote_id = RELAY_PEER
	_set_link(Link.CONNECTING, "dialling %s" % _url)
	return OK


## An empty `code` opens a new room and takes the host seat.
func join_room(url: String, code: String) -> Error:
	var wanted := code.strip_edges().to_upper()
	if wanted != "" and not NetProtocol.is_room_code(wanted):
		_set_link(Link.FAILED, "'%s' is not a room code" % wanted)
		return ERR_INVALID_PARAMETER
	_reset()
	mode = Mode.RELAY
	_url = normalise_url(url)
	_want_code = wanted
	_peer = WebSocketMultiplayerPeer.new()
	_wire_signals()
	var err := _peer.create_client(_url)
	if err != OK:
		_set_link(Link.FAILED, "could not reach the relay at %s (%d)" % [_url, err])
		return err
	_remote_id = RELAY_PEER
	_set_link(Link.CONNECTING, "reaching the relay")
	return OK


## Accepts "1.2.3.4", "1.2.3.4:45678", "ws://host:port" or "wss://host/path"
## and always returns something create_client will take. Typing a bare address
## is what people actually do.
static func normalise_url(url: String) -> String:
	var text := url.strip_edges()
	if text == "":
		return "ws://127.0.0.1:%d" % DEFAULT_PORT
	if text.begins_with("ws://") or text.begins_with("wss://"):
		return text
	if not text.contains(":"):
		return "ws://%s:%d" % [text, DEFAULT_PORT]
	return "ws://%s" % text


## --- running ----------------------------------------------------------------

func poll() -> void:
	if _peer == null:
		return
	_peer.poll()

	var status := _peer.get_connection_status()
	if status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		if link == Link.CONNECTING:
			_set_link(Link.FAILED, "could not connect to %s" % _url)
		elif link == Link.LIVE or link == Link.WAITING:
			_set_link(Link.FAILED, "connection lost")
			peer_left.emit()
		return

	if mode == Mode.RELAY and status == MultiplayerPeer.CONNECTION_CONNECTED \
			and not _room_requested:
		_room_requested = true
		_send_raw(
			NetProtocol.room_open() if _want_code == ""
			else NetProtocol.room_join(_want_code)
		)
		_set_link(Link.CONNECTING, "asking the relay for a room")

	if mode == Mode.DIRECT_GUEST and status == MultiplayerPeer.CONNECTION_CONNECTED \
			and link == Link.CONNECTING:
		_set_link(Link.LIVE, "connected to %s" % _url)
		peer_joined.emit()

	while _peer.get_available_packet_count() > 0:
		# get_packet_peer() has to be read BEFORE get_packet(); afterwards the
		# queue has already moved on and it errors.
		var _from := _peer.get_packet_peer()
		var bytes := _peer.get_packet()
		if mode == Mode.RELAY and _handle_room_message(bytes):
			continue
		received.emit(bytes)


func send(bytes: PackedByteArray) -> void:
	if _peer == null or not has_peer():
		return
	_send_raw(bytes)


func _send_raw(bytes: PackedByteArray) -> void:
	if _peer == null:
		return
	_peer.set_target_peer(_remote_id if _remote_id != 0 else RELAY_PEER)
	_peer.put_packet(bytes)


func close() -> void:
	if _peer != null:
		_peer.close()
		_peer = null
	_remote_id = 0
	_room_requested = false
	_set_link(Link.CLOSED, "closed")


func has_peer() -> bool:
	return link == Link.LIVE and _remote_id != 0


func supports_hosting() -> bool:
	# A web page has no listening socket. Everything else does.
	return OS.get_name() != "Web"


func describe() -> String:
	match mode:
		Mode.DIRECT_HOST:
			return "hosting on port %d" % _port
		Mode.DIRECT_GUEST:
			return "joined %s" % _url
		Mode.RELAY:
			return "room %s via %s (%s)" % [
				room_code, _url, "host" if is_host_seat else "guest",
			]
		_:
			return "idle"


## The port a direct host is listening on, for the lobby to show.
func listening_port() -> int:
	return _port


## --- internals --------------------------------------------------------------

func _reset() -> void:
	if _peer != null:
		_peer.close()
	_peer = null
	_remote_id = 0
	room_code = ""
	_room_requested = false
	mode = Mode.NONE


func _wire_signals() -> void:
	_peer.peer_connected.connect(_on_peer_connected)
	_peer.peer_disconnected.connect(_on_peer_disconnected)


func _on_peer_connected(id: int) -> void:
	if mode == Mode.DIRECT_HOST:
		if _remote_id != 0:
			# The seat is taken. A duel has two chairs.
			_peer.disconnect_peer(id)
			return
		_remote_id = id
		_set_link(Link.LIVE, "a challenger connected")
		peer_joined.emit()
	elif mode == Mode.DIRECT_GUEST:
		_remote_id = id
	# In relay mode the only peer is the relay itself; the real other seat is
	# announced by ROOM_PEER, so nothing to do here.


func _on_peer_disconnected(id: int) -> void:
	if id != _remote_id and mode != Mode.RELAY:
		return
	if mode == Mode.DIRECT_HOST:
		_remote_id = 0
		_set_link(Link.WAITING, "the challenger left")
	else:
		_set_link(Link.FAILED, "disconnected")
	peer_left.emit()


## Returns true when the message was room bookkeeping and must not be passed up
## to the session.
func _handle_room_message(bytes: PackedByteArray) -> bool:
	var message := NetProtocol.decode(bytes)
	if message.has("error"):
		# Not ours to judge: hand it up and let the session log it.
		return false

	match int(message["type"]):
		NetProtocol.Type.ROOM_OK:
			room_code = String(message["code"])
			is_host_seat = bool(message["as_host"])
			_remote_id = RELAY_PEER
			_set_link(
				Link.WAITING,
				"room %s — waiting for the other player" % room_code if is_host_seat
				else "room %s — joined" % room_code
			)
			room_assigned.emit(room_code, is_host_seat)
			return true

		NetProtocol.Type.ROOM_PEER:
			if bool(message["present"]):
				_set_link(Link.LIVE, "room %s — both seats filled" % room_code)
				peer_joined.emit()
			else:
				_set_link(Link.WAITING, "room %s — the other player left" % room_code)
				peer_left.emit()
			return true

		NetProtocol.Type.ROOM_ERROR:
			_set_link(Link.FAILED, String(message["message"]))
			return true

	return false
