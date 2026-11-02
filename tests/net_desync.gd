extends SceneTree
## Prediction, reconciliation, and the divergence detector.
##
##     godot --headless --script tests/net_desync.gd
##
## HOW A HOST IS FAKED WITHOUT A SECOND PROCESS
## Two duels cannot coexist in one world — see tests/duel_support.gd for why —
## so the host is recorded rather than run alongside. Pass one steps a single
## duel through a scripted input stream and writes down the exact SNAPSHOT
## messages a host would have sent. That duel is then freed, a client duel is
## built in its place, and the recorded snapshots are played back to a real
## NetSession over a LoopbackTransport. The client is therefore talking to a
## genuine, self-consistent host; it just happens to be a recording.
##
## FOUR CLAIMS
## 1. A client that mispredicts converges anyway, and reports no desync. This is
##    the half that matters most: a detector that fires on ordinary
##    misprediction is one nobody will believe. `verifications` proves the
##    detector really looked rather than staying quiet by never running.
## 2. The detector fires when the host asserts a frame the client cannot
##    reproduce from authoritative state and authoritative input — which is what
##    nondeterministic physics across two platforms would look like.
## 3. Losing snapshots is survivable: no false desync, and the duel still
##    tracks the host.
## 4. Latency and jitter do not break it either.

const Support := preload("res://tests/duel_support.gd")
const Loopback := preload("res://scripts/net/loopback_transport.gd")

const FRAMES := 300
## Which recorded snapshot gets its state and checksum swapped for another
## frame's, so the host is asserting something real but unreachable.
const TAMPER_INDEX := 40

enum Stage { RECORD, CLEAN, TAMPERED, LOSSY, LAGGY, DONE }

var _s := Support.new()
var _stream: Array[Vector2i]
var _snapshots: Array[Dictionary] = [] # {frame, bytes, checksum}
var _host_checksums := PackedInt64Array()
var _warm := 0
var _stage: Stage = Stage.RECORD
var _run: Dictionary = {}


func _initialize() -> void:
	_stream = Support.input_stream(FRAMES, 0xd0d9e)


func _physics_process(_delta: float) -> bool:
	_warm += 1
	if _warm < 3:
		return false

	match _stage:
		Stage.RECORD:
			_record_a_host()
			_stage = Stage.CLEAN

		Stage.CLEAN:
			if _drive("clean", _snapshots, 0, 0, 0.0):
				var session: NetSession = _run["session"]
				# A verification is a frame the client recomputed from the
				# host's own state and the host's own input and got the host's
				# own checksum. Many of those with no failures IS the statement
				# that the client converged — there is nothing stronger to say.
				_s.check(
					session.verifications > _snapshots.size() / 2,
					"the client reproduced the host's state exactly, %d times"
						% session.verifications
				)
				_s.equal(session.desync_count, 0, "a clean host produces no desync")
				_s.check(
					session.corrections > 0,
					"the client did mispredict and correct (%d times)" % session.corrections
				)
				_s.check(
					session.is_running(), "the session is still running at the end"
				)
				_finish_run()
				_stage = Stage.TAMPERED

		Stage.TAMPERED:
			if _drive("tampered", _tampered_snapshots(), 0, 0, 0.0):
				var session: NetSession = _run["session"]
				_s.check(
					session.desync_count > 0,
					"a host asserting an unreachable frame is detected as a desync"
				)
				_s.equal(
					int((_run["desync_signalled_box"] as Array)[1]),
					int(_snapshots[TAMPER_INDEX]["frame"]),
					"the desync is reported against the frame that diverged"
				)
				_s.check(
					bool((_run["desync_signalled_box"] as Array)[0]),
					"desync_detected fires, so the HUD can say so"
				)
				_s.check(
					session.last_desync_mine != session.last_desync_theirs,
					"the report carries two different checksums"
				)
				_finish_run()
				_stage = Stage.LOSSY

		Stage.LOSSY:
			# A quarter of the host's snapshots never arrive.
			if _drive("lossy", _snapshots, 0, 0, 0.25):
				var session: NetSession = _run["session"]
				_s.equal(
					session.desync_count, 0,
					"losing snapshots is not a desync"
				)
				_s.check(
					session.snapshots_received < _snapshots.size(),
					"snapshots really were lost (%d of %d arrived)"
						% [session.snapshots_received, _snapshots.size()]
				)
				_s.check(
					session.is_running(), "the session survives packet loss"
				)
				_finish_run()
				_stage = Stage.LAGGY

		Stage.LAGGY:
			# 100 ms each way with 50 ms of jitter, which also reorders.
			if _drive("laggy", _snapshots, 6, 3, 0.0):
				var session: NetSession = _run["session"]
				_s.equal(session.desync_count, 0, "latency and jitter are not a desync")
				_s.check(
					session.corrections > 0,
					"lag makes the client mispredict more, and it still corrects"
				)
				_s.check(session.is_running(), "the session survives lag and jitter")
				_finish_run()
				_stage = Stage.DONE

		Stage.DONE:
			quit(_s.report("net_desync"))
			return true

	return false


## --- recording the host -----------------------------------------------------

## Steps one duel through the stream and writes down the SNAPSHOT messages a
## host would have sent, with the same cadence NetSession uses.
func _record_a_host() -> void:
	var duel := Support.spawn_duel(root)
	var since: Array[Vector2i] = []
	_snapshots.clear()
	_host_checksums = PackedInt64Array()

	for pair: Vector2i in _stream:
		since.append(pair)
		duel.step(pair.x, pair.y)
		_host_checksums.append(duel.checksum())
		if duel.frame % NetSession.SNAPSHOT_INTERVAL == 0:
			_snapshots.append({
				"frame": duel.frame,
				"checksum": duel.checksum(),
				"state": duel.write_state(),
				"pairs": since.duplicate(),
			})
			since = []

	duel.free()
	_s.check(_snapshots.size() > TAMPER_INDEX + 10, "enough snapshots were recorded")
	_s.equal(
		_host_checksums.size(), FRAMES, "a host checksum was recorded for every frame"
	)


## The recorded stream with one snapshot's state and checksum replaced by a
## later frame's. The host is now claiming a state that is real but cannot be
## reached from the previous snapshot by the inputs it says it applied — which
## is exactly the shape of two machines whose physics disagree.
func _tampered_snapshots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in _snapshots.size():
		var snapshot := (_snapshots[i] as Dictionary).duplicate()
		if i == TAMPER_INDEX:
			var elsewhere: Dictionary = _snapshots[i + 5]
			snapshot["state"] = elsewhere["state"]
			snapshot["checksum"] = elsewhere["checksum"]
		out.append(snapshot)
	return out


## --- driving a client -------------------------------------------------------

## Runs one scenario. Returns true when it has finished; call once per physics
## frame until then, because the duel has to step inside a physics frame.
func _drive(
	label: String, snapshots: Array[Dictionary],
	latency: int, jitter: int, loss: float
) -> bool:
	if _run.is_empty():
		_begin_run(label, snapshots, latency, jitter, loss)
		return false

	var session: NetSession = _run["session"]
	var duel: Duel = _run["duel"]
	var host_end: LoopbackTransport = _run["host_end"]
	var queue: Array[Dictionary] = _run["snapshots"]
	var cursor: int = _run["cursor"]

	# The host is "behind" the client by construction: it releases the snapshot
	# for frame F once the client has predicted past F.
	host_end.poll()
	# One snapshot of slack, so the very first one is released while the client
	# is still on frame 0 and has nothing to predict from yet.
	while cursor < queue.size() \
			and int(queue[cursor]["frame"]) <= duel.frame + NetSession.SNAPSHOT_INTERVAL:
		var snapshot: Dictionary = queue[cursor]
		host_end.send(NetProtocol.snapshot(
			int(snapshot["frame"]), int(snapshot["checksum"]),
			snapshot["state"], snapshot["pairs"]
		))
		cursor += 1
	_run["cursor"] = cursor

	session.poll()
	_run["ticks"] = int(_run["ticks"]) + 1
	if int(_run["ticks"]) % 150 == 0:
		print("    %s tick=%d frame=%d cursor=%d/%d stage=%d snaps=%d" % [
			label, _run["ticks"], duel.frame, cursor, queue.size(),
			session.stage, session.snapshots_received,
		])

	var done := cursor >= queue.size() and duel.frame >= int(queue[queue.size() - 1]["frame"])
	if not done and int(_run["ticks"]) < FRAMES * 4:
		return false

	_run["final_frame"] = duel.frame
	_run["final_checksum"] = duel.checksum()
	_s.check(
		duel.frame >= int(queue[queue.size() - 1]["frame"]),
		"%s: the client reached the host's last snapshot frame" % label
	)
	return true


func _begin_run(
	label: String, snapshots: Array[Dictionary],
	latency: int, jitter: int, loss: float
) -> void:
	var ends := Loopback.pair(0xbeef)
	var host_end: LoopbackTransport = ends[0]
	var client_end: LoopbackTransport = ends[1]
	host_end.latency_frames = latency
	host_end.jitter_frames = jitter
	host_end.drop_rate = loss
	client_end.latency_frames = latency
	client_end.jitter_frames = jitter

	var duel := Support.spawn_duel(root)
	var session := NetSession.new()

	# The client's own input is the one the recorded host applied for its seat,
	# so any correction comes from mispredicting the HOST's input — which is the
	# only thing a client can actually get wrong.
	var stream := _stream
	session.local_input = func() -> int:
		var at: int = duel.frame
		if at < 0 or at >= stream.size():
			return 0
		return (stream[at] as Vector2i)[DuelRules.SLOT_B]

	# Remember the FIRST frame reported. A host asserting an unreachable state
	# also poisons the next verification, which replays from that same state, so
	# one divergence legitimately reports twice; the first one is the real one.
	var signalled := [false, -1]
	session.desync_detected.connect(
		func(frame: int, _mine: int, _theirs: int) -> void:
			signalled[0] = true
			if int(signalled[1]) < 0:
				signalled[1] = frame
	)

	# Stand in for the host's side of the handshake.
	var arena_hash := NetProtocol.arena_hash(duel.level.data)
	host_end.received.connect(func(bytes: PackedByteArray) -> void:
		var message := NetProtocol.decode(bytes)
		if message.has("error"):
			return
		if int(message["type"]) == NetProtocol.Type.HELLO:
			host_end.send(NetProtocol.welcome(
				DuelRules.SLOT_B, DuelRules.ROUNDS_TO_WIN, arena_hash
			))
	)

	session.start(client_end, duel, false)

	_run = {
		"label": label, "session": session, "duel": duel,
		"host_end": host_end, "client_end": client_end,
		"snapshots": snapshots, "cursor": 0, "ticks": 0,
		"desync_signalled_box": signalled,
	}


func _finish_run() -> void:
	var session: NetSession = _run["session"]
	var duel: Duel = _run["duel"]
	print("  %-9s frame=%d snapshots=%d corrections=%d verifications=%d desync=%d" % [
		_run["label"], duel.frame, session.snapshots_received,
		session.corrections, session.verifications, session.desync_count,
	])
	session.shutdown()
	duel.free()
	_run = {}
