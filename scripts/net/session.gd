class_name NetSession
extends RefCounted
## Runs one networked duel: handshake, prediction, reconciliation, divergence
## detection and the latency bookkeeping.
##
## HOST-AUTHORITATIVE, NOT LOCKSTEP
## Godot's physics is reproducible for one binary on one platform — that is what
## tests/duel_determinism_test.gd pins down — but it is not guaranteed identical
## across a web export, an Android build and a desktop build. A lockstep duel
## between a phone and a browser would therefore desync, and lockstep has no way
## to recover when it does. So one peer is the host and its simulation is the
## truth. Both peers send input; the host broadcasts state; the client predicts
## and then corrects itself.
##
## WHAT EACH SIDE DOES, PER FRAME
##   host    reads its own input, takes the client's input for this frame if it
##           has arrived (and repeats the last one if it has not), steps once,
##           and every SNAPSHOT_INTERVAL frames sends the state, its checksum,
##           and the input it applied to get there.
##   client  steps immediately on its own input so the sword answers the button
##           with no delay, predicting the host's input by repeating the last
##           one it was told about. When a snapshot arrives it throws its
##           prediction away, loads the host's state, and replays the frames
##           since — which is exact, because a replayed frame is the same frame.
##
## DIVERGENCE, AS OPPOSED TO MISPREDICTION
## These are different things and conflating them makes a desync detector that
## cries wolf. A mispredicted frame is normal and expected: the client guessed
## the host's input and guessed wrong. A divergence is the two machines
## computing different results *from the same inputs*, which is a bug or a
## platform difference and cannot be recovered from by prediction.
##
## This tells them apart. Each snapshot carries the input the host applied, so
## the client can take the PREVIOUS authoritative state, apply those exact
## authoritative inputs, and arrive at this snapshot's frame with no guessing
## anywhere. If its checksum still disagrees, that is a real divergence, and it
## is reported and surfaced. Misprediction is counted separately, as
## `corrections`, and is just the cost of doing business.
##
## The client needs no second simulation to do this: it reuses the one duel it
## has, because reconciliation is about to overwrite it anyway.

signal desync_detected(frame: int, mine: int, theirs: int)
signal handshake_complete(local_slot: int)
signal link_failed(reason: String)
signal peer_departed()

enum Role { HOST, CLIENT }

enum Stage {
	OFFLINE,
	WAITING, ## connected to something, but the other seat is empty
	HANDSHAKE, ## saying hello
	RUNNING, ## stepping the duel
	ENDED,
}

## How often the host sends state. Every other frame: ~230 bytes at 30 Hz is
## about 7 kB/s down, which a duel can afford and a phone will not notice.
const SNAPSHOT_INTERVAL := 2
## How many recent input frames the client repeats in every INPUT message. Free
## over TCP; the point is that an unreliable transport can be dropped in.
const INPUT_REDUNDANCY := 6
## Round trip measurement.
const PING_INTERVAL := 20
## How far ahead of the newest snapshot the client runs, on top of the measured
## one-way latency. Two frames of slack for jitter.
const LEAD_SLACK := 2
const MIN_LEAD := 2
const MAX_LEAD := 24
## Frames of history kept for replay. 2 s is far more than any sane correction.
const HISTORY := 120
## Give up on a handshake that never completes.
const HANDSHAKE_TIMEOUT_FRAMES := 600
## How often the guest repeats HELLO while waiting to be seated. A WebSocket
## cannot lose it, but an unreliable transport can, and a handshake with no
## retry would simply hang — so it is repeated rather than assumed.
const HANDSHAKE_RETRY_FRAMES := 30

var role: Role = Role.HOST
var stage: Stage = Stage.OFFLINE
var transport: NetTransport
var duel: Duel
var local_slot: int = DuelRules.SLOT_A
var remote_slot: int = DuelRules.SLOT_B

## Set by the scene: a Callable returning this frame's input bits for the local
## seat. Kept as an injected dependency so a test can drive a session with a
## scripted stream and no devices at all.
var local_input: Callable = func() -> int: return 0

## --- what the HUD shows -----------------------------------------------------
var rtt_ms := 0.0
var jitter_ms := 0.0
## Snapshots whose state disagreed with what we had predicted. Normal.
var corrections := 0
## Snapshots that disagreed with an authoritative replay. Not normal.
var desync_count := 0
## Snapshots the detector was actually able to check, having both the previous
## authoritative state and every authoritative input in between. Without this,
## a desync_count of zero would be indistinguishable from never having looked.
var verifications := 0
var last_desync_frame := -1
var last_desync_mine := 0
var last_desync_theirs := 0
## Frames the host had to guess the client's input because none had arrived.
var input_starved := 0
## Frames between the newest snapshot and where the client has predicted to.
var predicted_ahead := 0
var snapshots_sent := 0
var snapshots_received := 0
var status_detail := ""

var _frames := 0
var _handshake_frames := 0
var _ping_id := 0
var _pending_pings := {} # id -> sent usec
var _lead := MIN_LEAD
var _arena_hash := 0

## host: client input by frame, and the pairs applied since the last snapshot
var _remote_inputs := {} # frame -> int bits
var _last_remote_bits := 0
var _since_snapshot: Array[Vector2i] = []

## client: our own input by frame, the host's input by frame as we learn it,
## and the last authoritative state we were handed
var _local_inputs := {} # frame -> int bits
var _auth_inputs := {} # frame -> Vector2i(bits_a, bits_b)
var _predicted := {} # frame -> checksum we predicted, for counting corrections
var _auth_state := PackedByteArray()
var _auth_frame := -1
var _auth_checksum := 0
var _newest_snapshot_frame := -1
var _pending_snapshots: Array[Dictionary] = []
var _started := false


## --- lifecycle --------------------------------------------------------------

func start(net: NetTransport, fight: Duel, as_host: bool) -> void:
	transport = net
	duel = fight
	role = Role.HOST if as_host else Role.CLIENT
	# The host takes the left seat. Both sides agree on this without asking,
	# which keeps the handshake to one exchange.
	local_slot = DuelRules.SLOT_A if as_host else DuelRules.SLOT_B
	remote_slot = DuelRules.SLOT_B if as_host else DuelRules.SLOT_A
	_arena_hash = NetProtocol.arena_hash(fight.level.data)

	transport.received.connect(_on_received)
	transport.peer_joined.connect(_on_peer_joined)
	transport.peer_left.connect(_on_peer_left)
	transport.link_changed.connect(_on_link_changed)

	stage = Stage.WAITING
	status_detail = transport.detail
	if transport.has_peer():
		_on_peer_joined()


func shutdown() -> void:
	if transport != null and transport.has_peer():
		transport.send(NetProtocol.bye(NetProtocol.Bye.QUIT))
	stage = Stage.ENDED
	if transport != null:
		transport.close()


func is_running() -> bool:
	return stage == Stage.RUNNING


## --- the frame --------------------------------------------------------------

## Call once per physics frame, from the scene. Steps the duel zero, one or two
## frames depending on how the clocks line up.
func poll() -> void:
	if transport == null:
		return
	transport.poll()
	_frames += 1

	match stage:
		Stage.HANDSHAKE:
			_handshake_frames += 1
			if _handshake_frames > HANDSHAKE_TIMEOUT_FRAMES:
				_fail("the other side never answered the handshake")
			elif role == Role.CLIENT and _handshake_frames % HANDSHAKE_RETRY_FRAMES == 0:
				transport.send(NetProtocol.hello(NetProtocol.VERSION, "challenger"))
		Stage.RUNNING:
			if _frames % PING_INTERVAL == 0:
				_send_ping()
			if role == Role.HOST:
				_host_frame()
			else:
				_client_frame()
		_:
			pass


func _host_frame() -> void:
	var mine: int = local_input.call()
	var theirs: int = _last_remote_bits
	if _remote_inputs.has(duel.frame):
		theirs = int(_remote_inputs[duel.frame])
		_last_remote_bits = theirs
	else:
		# Nothing arrived for this frame. Repeating the last byte is the least
		# wrong guess: a held direction keeps running, a tap does not repeat.
		input_starved += 1

	var pair := _pair(mine, theirs)
	_since_snapshot.append(pair)
	duel.step(pair.x, pair.y)
	_trim(_remote_inputs, duel.frame - HISTORY)

	if duel.frame % SNAPSHOT_INTERVAL == 0:
		_send_snapshot()


func _client_frame() -> void:
	_absorb_snapshots()
	if not _started:
		# Nothing to predict from until the host has told us where we are.
		return

	var steps := _steps_this_frame()
	for i: int in steps:
		var mine: int = local_input.call()
		_local_inputs[duel.frame] = mine
		var theirs := _predicted_remote_bits(duel.frame)
		var at := duel.frame
		var pair := _pair(mine, theirs)
		duel.step(pair.x, pair.y)
		_predicted[at + 1] = duel.checksum()

	_send_input_window()
	_trim(_local_inputs, duel.frame - HISTORY)
	_trim(_auth_inputs, duel.frame - HISTORY)
	_trim(_predicted, duel.frame - HISTORY)
	predicted_ahead = duel.frame - _newest_snapshot_frame


## The client runs ahead of the newest snapshot by the one-way latency plus a
## little slack, so its input reaches the host before the host needs it. Drift
## is corrected a frame at a time rather than by jumping, which would be
## visible.
func _steps_this_frame() -> int:
	if _newest_snapshot_frame < 0:
		return 1
	var want := _newest_snapshot_frame + _lead
	if duel.frame < want - 1:
		return 2 # behind: catch up gently
	if duel.frame > want + 3:
		return 0 # too far ahead: let the host come to us
	return 1


func _predicted_remote_bits(at: int) -> int:
	if _auth_inputs.has(at):
		return int((_auth_inputs[at] as Vector2i)[remote_slot])
	if _auth_inputs.has(at - 1):
		return int((_auth_inputs[at - 1] as Vector2i)[remote_slot])
	return _last_remote_bits


## --- reconciliation ---------------------------------------------------------

func _absorb_snapshots() -> void:
	if _pending_snapshots.is_empty():
		return
	# Oldest first: each one's input history fills the gap for the next, which
	# is what makes the authoritative replay possible.
	var queue := _pending_snapshots
	_pending_snapshots = []
	for snapshot: Dictionary in queue:
		_apply_snapshot(snapshot)


func _apply_snapshot(snapshot: Dictionary) -> void:
	var at: int = int(snapshot["frame"])
	var checksum: int = int(snapshot["checksum"])
	var state: PackedByteArray = snapshot["state"]
	var pairs: Array[Vector2i] = snapshot["pairs"]

	# Record the host's input for the frames behind this snapshot.
	var first := at - pairs.size()
	for i: int in pairs.size():
		_auth_inputs[first + i] = pairs[i]
	if pairs.size() > 0:
		_last_remote_bits = int(pairs[pairs.size() - 1][remote_slot])

	# A snapshot older than the one we already trust tells us nothing.
	if at <= _auth_frame:
		return

	_verify_against_authority(at, checksum)

	var predicted_here: int = int(_predicted.get(at, -1))
	if predicted_here != -1 and predicted_here != checksum:
		corrections += 1

	# Land exactly on the host's state, then replay everything since.
	var resume_at := maxi(duel.frame, at)
	if not duel.read_state(state):
		_fail("a snapshot would not read back")
		return
	_replay_to(resume_at)

	_auth_state = state
	_auth_frame = at
	_auth_checksum = checksum
	_newest_snapshot_frame = at
	if not _started:
		_started = true
		_lead = _wanted_lead()
		_replay_to(at + _lead)


## The divergence test. Takes the LAST authoritative state and the
## authoritative inputs the host says it applied since, recomputes this
## snapshot's frame with no prediction anywhere, and compares. A mismatch here
## cannot be explained by a wrong guess.
func _verify_against_authority(at: int, checksum: int) -> void:
	if _auth_frame < 0 or at <= _auth_frame:
		return
	if at - _auth_frame > HISTORY:
		return # too far behind to replay; resync and say nothing
	for f: int in range(_auth_frame, at):
		if not _auth_inputs.has(f):
			return # a gap in the authoritative input: cannot conclude anything

	if not duel.read_state(_auth_state):
		return
	for f: int in range(_auth_frame, at):
		var pair: Vector2i = _auth_inputs[f]
		duel.step(pair.x, pair.y)

	var recomputed := duel.checksum()
	verifications += 1
	if recomputed == checksum:
		return

	desync_count += 1
	last_desync_frame = at
	last_desync_mine = recomputed
	last_desync_theirs = checksum
	desync_detected.emit(at, recomputed, checksum)
	# Tell the other side too, so a divergence is visible on both screens
	# rather than only on the one that happened to notice.
	transport.send(NetProtocol.desync(at, recomputed, checksum))


## Steps the duel forward from wherever it is to `target`, using our own
## recorded input and the best remote input we know for each frame.
func _replay_to(target: int) -> void:
	var guard := 0
	while duel.frame < target and guard < HISTORY * 2:
		guard += 1
		var at := duel.frame
		var pair: Vector2i
		if _auth_inputs.has(at):
			pair = _auth_inputs[at]
		else:
			pair = _pair(int(_local_inputs.get(at, 0)), _predicted_remote_bits(at))
		duel.step(pair.x, pair.y)
		_predicted[at + 1] = duel.checksum()


## --- sending ----------------------------------------------------------------

func _send_snapshot() -> void:
	if _since_snapshot.size() > 255:
		_since_snapshot = _since_snapshot.slice(_since_snapshot.size() - 255)
	transport.send(NetProtocol.snapshot(
		duel.frame, duel.checksum(), duel.write_state(), _since_snapshot
	))
	_since_snapshot = []
	snapshots_sent += 1


func _send_input_window() -> void:
	var first := maxi(0, duel.frame - INPUT_REDUNDANCY)
	var bits := PackedByteArray()
	for f: int in range(first, duel.frame):
		bits.append(int(_local_inputs.get(f, 0)) & 0xff)
	if bits.is_empty():
		return
	transport.send(NetProtocol.input_window(first, bits))


func _send_ping() -> void:
	_ping_id += 1
	var now := Time.get_ticks_usec()
	_pending_pings[_ping_id] = now
	if _pending_pings.size() > 16:
		_pending_pings.erase(_pending_pings.keys()[0])
	transport.send(NetProtocol.ping(_ping_id, now))


## --- receiving --------------------------------------------------------------

func _on_received(bytes: PackedByteArray) -> void:
	var message := NetProtocol.decode(bytes)
	if message.has("error"):
		status_detail = "ignored a bad message: %s" % message["error"]
		if message.has("version"):
			_fail("the other player is running a different build (protocol %d, ours %d)"
				% [message["version"], NetProtocol.VERSION])
		return

	match int(message["type"]):
		NetProtocol.Type.HELLO:
			if role == Role.HOST:
				transport.send(NetProtocol.welcome(
					DuelRules.SLOT_B, duel.rounds_to_win, _arena_hash
				))
				_begin_running()

		NetProtocol.Type.WELCOME:
			if role == Role.CLIENT:
				local_slot = int(message["slot"])
				remote_slot = 1 - local_slot
				if int(message["arena_hash"]) != _arena_hash:
					_fail("the two sides are not fighting in the same arena")
					return
				duel.rounds_to_win = maxi(1, int(message["rounds_to_win"]))
				_begin_running()

		NetProtocol.Type.INPUT:
			if role == Role.HOST:
				var first: int = int(message["first_frame"])
				var bits: PackedByteArray = message["bits"]
				for i: int in bits.size():
					var at := first + i
					# Never overwrite a frame already simulated, and never
					# accept input for a frame long gone.
					if at >= duel.frame:
						_remote_inputs[at] = bits[i]

		NetProtocol.Type.SNAPSHOT:
			if role == Role.CLIENT:
				snapshots_received += 1
				_newest_snapshot_frame = maxi(
					_newest_snapshot_frame, int(message["frame"])
				)
				_pending_snapshots.append(message)

		NetProtocol.Type.PING:
			transport.send(NetProtocol.pong(
				int(message["id"]), int(message["sent_usec"])
			))

		NetProtocol.Type.PONG:
			_record_round_trip(int(message["id"]))

		NetProtocol.Type.DESYNC:
			# The other side noticed first. Count it once, from whichever side.
			if int(message["frame"]) != last_desync_frame:
				desync_count += 1
				last_desync_frame = int(message["frame"])
				last_desync_mine = int(message["theirs"])
				last_desync_theirs = int(message["mine"])
				desync_detected.emit(
					last_desync_frame, last_desync_mine, last_desync_theirs
				)

		NetProtocol.Type.BYE:
			stage = Stage.ENDED
			status_detail = "the other player left"
			peer_departed.emit()


func _record_round_trip(id: int) -> void:
	if not _pending_pings.has(id):
		return
	var sent: int = _pending_pings[id]
	_pending_pings.erase(id)
	var sample := float(Time.get_ticks_usec() - sent) / 1000.0
	var previous := rtt_ms
	rtt_ms = sample if previous <= 0.0 else lerpf(previous, sample, 0.25)
	jitter_ms = (
		absf(sample - previous) if previous <= 0.0
		else lerpf(jitter_ms, absf(sample - previous), 0.25)
	)
	if role == Role.CLIENT:
		_lead = _wanted_lead()


func _wanted_lead() -> int:
	var one_way_frames := int(ceil((rtt_ms * 0.5 + jitter_ms) / (DuelRules.DT * 1000.0)))
	return clampi(one_way_frames + LEAD_SLACK, MIN_LEAD, MAX_LEAD)


## --- link -------------------------------------------------------------------

func _on_peer_joined() -> void:
	if stage == Stage.RUNNING:
		return
	stage = Stage.HANDSHAKE
	_handshake_frames = 0
	# The guest speaks first; the host answers with the seating.
	if role == Role.CLIENT:
		transport.send(NetProtocol.hello(NetProtocol.VERSION, "challenger"))


func _on_peer_left() -> void:
	if stage == Stage.ENDED:
		return
	stage = Stage.WAITING
	status_detail = "the other player disconnected"
	peer_departed.emit()


func _on_link_changed(link: NetTransport.Link, detail: String) -> void:
	status_detail = detail
	if link == NetTransport.Link.FAILED:
		_fail(detail)


func _begin_running() -> void:
	if stage == Stage.RUNNING:
		return
	stage = Stage.RUNNING
	status_detail = "connected"
	handshake_complete.emit(local_slot)


func _fail(reason: String) -> void:
	if stage == Stage.ENDED:
		return
	stage = Stage.ENDED
	status_detail = reason
	link_failed.emit(reason)


## --- helpers ----------------------------------------------------------------

## Orders a local/remote pair of input bytes into (slot A, slot B).
func _pair(mine: int, theirs: int) -> Vector2i:
	return (
		Vector2i(mine, theirs) if local_slot == DuelRules.SLOT_A
		else Vector2i(theirs, mine)
	)


static func _trim(history: Dictionary, before: int) -> void:
	if before <= 0:
		return
	for key: int in history.keys():
		if key < before:
			history.erase(key)


## One line for the HUD. Deliberately blunt about a desync: a match that has
## drifted should say so rather than quietly disagree with itself.
func status_line() -> String:
	if desync_count > 0:
		return "DESYNC x%d @ %d  ·  %d MS" % [desync_count, last_desync_frame, int(rtt_ms)]
	match stage:
		Stage.OFFLINE:
			return "OFFLINE"
		Stage.WAITING:
			return status_detail.to_upper() if status_detail != "" else "WAITING"
		Stage.HANDSHAKE:
			return "CONNECTING"
		Stage.ENDED:
			return status_detail.to_upper() if status_detail != "" else "ENDED"
		_:
			pass
	var seat := "HOST" if role == Role.HOST else "GUEST"
	if role == Role.HOST:
		return "%s  ·  %d MS  ·  %d STARVED" % [seat, int(rtt_ms), input_starved]
	return "%s  ·  %d MS  ·  %d CORR  ·  +%d" % [
		seat, int(rtt_ms), corrections, predicted_ahead,
	]
