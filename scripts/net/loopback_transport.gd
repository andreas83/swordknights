class_name LoopbackTransport
extends NetTransport
## Two transports wired to each other inside one process, with a bad connection
## simulated on purpose.
##
## This is what the netplay tests run on, and it is the reason they can assert
## anything about prediction or reconciliation at all: latency, jitter and loss
## are exact numbers here, not weather. `pair()` builds both ends.
##
##     var ends := LoopbackTransport.pair()
##     ends[0].latency_frames = 6        # 100 ms each way
##     ends[0].jitter_frames = 2
##     ends[1].drop_rate = 0.1
##
## Delivery is measured in frames, because the only clock a duel has is its
## own step. Both ends must be polled once per frame, and a message sent on
## frame N arrives no earlier than frame N + latency.
##
## Reordering is modelled too: with jitter on, a later message can arrive
## before an earlier one, exactly as it would over UDP. A WebSocket would never
## do that, which is precisely why the tests should.

## One-way delay, in frames of 1/60 s.
var latency_frames := 0
## Random extra delay, 0..jitter_frames, drawn per message.
var jitter_frames := 0
## Chance in 0..1 that a message is simply never delivered.
var drop_rate := 0.0

## Counters the tests assert on.
var sent_count := 0
var delivered_count := 0
var dropped_count := 0

var _other: LoopbackTransport
var _inbox: Array[Dictionary] = []
var _frame := 0
var _rng := RandomNumberGenerator.new()
var _label := "loopback"


## Builds a connected pair, both already LIVE. `[0]` is conventionally the host.
static func pair(rng_seed: int = 1) -> Array[LoopbackTransport]:
	var a := LoopbackTransport.new()
	var b := LoopbackTransport.new()
	a._label = "loopback:host"
	b._label = "loopback:guest"
	a._rng.seed = rng_seed
	b._rng.seed = rng_seed ^ 0x9e3779b9
	a._other = b
	b._other = a
	a._set_link(Link.LIVE, "loopback")
	b._set_link(Link.LIVE, "loopback")
	return [a, b]


## Mirror the same conditions onto both ends.
func apply_to_both(latency: int, jitter: int, loss: float) -> void:
	for end: LoopbackTransport in [self, _other]:
		if end == null:
			continue
		end.latency_frames = latency
		end.jitter_frames = jitter
		end.drop_rate = loss


func send(bytes: PackedByteArray) -> void:
	if _other == null or link != Link.LIVE:
		return
	sent_count += 1
	if drop_rate > 0.0 and _rng.randf() < drop_rate:
		dropped_count += 1
		return
	var delay := latency_frames
	if jitter_frames > 0:
		delay += _rng.randi_range(0, jitter_frames)
	# Queued against the RECEIVER's clock, so the receiver alone decides when a
	# message is due and neither end needs the other's frame counter.
	_other._inbox.append({"due": _other._frame + delay, "bytes": bytes.duplicate()})


func poll() -> void:
	_frame += 1
	if _inbox.is_empty():
		return
	var still_waiting: Array[Dictionary] = []
	var due_now: Array[Dictionary] = []
	for message: Dictionary in _inbox:
		if int(message["due"]) <= _frame:
			due_now.append(message)
		else:
			still_waiting.append(message)
	_inbox = still_waiting
	for message: Dictionary in due_now:
		delivered_count += 1
		received.emit(message["bytes"] as PackedByteArray)


## Pull the plug, the way a closed laptop lid does.
func close() -> void:
	if link == Link.CLOSED:
		return
	_inbox.clear()
	_set_link(Link.CLOSED, "closed")
	var peer := _other
	_other = null
	if peer != null and peer._other != null:
		peer._other = null
		peer._set_link(Link.FAILED, "peer closed the connection")
		peer.peer_left.emit()


func has_peer() -> bool:
	return _other != null and link == Link.LIVE


func supports_hosting() -> bool:
	return true


func describe() -> String:
	return "%s (lat %d, jit %d, loss %d%%)" % [
		_label, latency_frames, jitter_frames, int(drop_rate * 100.0),
	]


## How many messages are in flight. Lets a test drain the wire deterministically.
func in_flight() -> int:
	return _inbox.size()
