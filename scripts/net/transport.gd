class_name NetTransport
extends RefCounted
## What a duel needs from a network, and nothing more.
##
## A duel has exactly two seats, so this is deliberately not a general peer
## interface: there is one remote peer or there is none. `send` goes to it,
## `received` comes from it. Everything above this line — NetSession, the
## lobby, the duel — is written against these eight methods and never touches a
## socket.
##
## Three implementations:
##   ws_transport.gd        WebSocket, which is the only thing a web export can
##                          use; direct host/join, or through a relay by code
##   loopback_transport.gd  a pair in one process, with latency, jitter and
##                          loss dialled in; what the netplay tests run on
##   (an ENet transport)    not written. The reason this interface exists is
##                          that it can be: see docs/netplay.md.
##
## The contract:
##   * poll() is called once per frame and is where everything happens. The
##     signals below are only ever emitted from inside it, so a session never
##     has to reason about a packet arriving halfway through its own update.
##   * send() may silently do nothing when there is no peer. Callers check
##     has_peer() when they care.
##   * close() is idempotent.

## A message from the remote peer. The bytes are whatever it sent; NetProtocol
## decides whether they mean anything.
signal received(bytes: PackedByteArray)
## The other seat is filled.
signal peer_joined()
## The other seat emptied — a disconnect, a closed room, a dropped connection.
signal peer_left()
signal link_changed(link: Link, detail: String)
## Relay only: the room is open. `as_host` decides which seat runs the
## authoritative simulation.
signal room_assigned(code: String, as_host: bool)

enum Link {
	IDLE, ## nothing started
	CONNECTING, ## dialling, or waiting on a relay's answer
	WAITING, ## we are reachable but the other seat is empty
	LIVE, ## both seats filled
	CLOSED, ## shut down on purpose
	FAILED, ## could not connect, or lost the connection
}

var link: Link = Link.IDLE
## Human-readable reason for the current link state, for the lobby to show.
var detail: String = ""


## Listen for a direct connection. Not available on the web, where a page
## cannot accept incoming sockets — check supports_hosting() first.
func host(_port: int) -> Error:
	return ERR_UNAVAILABLE


## Dial a host directly, e.g. "ws://198.51.100.7:45678".
func join(_url: String) -> Error:
	return ERR_UNAVAILABLE


## Meet the other player at a relay. An empty `code` asks for a new room and
## takes the host seat; a code joins an existing room as the guest. Either way
## the answer arrives as `room_assigned`.
func join_room(_url: String, _code: String) -> Error:
	return ERR_UNAVAILABLE


func send(_bytes: PackedByteArray) -> void:
	pass


func poll() -> void:
	pass


func close() -> void:
	pass


func has_peer() -> bool:
	return false


## True if this transport can accept incoming connections at all. False for a
## web build, which is why the relay exists.
func supports_hosting() -> bool:
	return false


## One short line for the lobby: what we are and where we are.
func describe() -> String:
	return "no transport"


func _set_link(next: Link, why: String = "") -> void:
	if link == next and why == detail:
		return
	link = next
	detail = why
	link_changed.emit(link, detail)
