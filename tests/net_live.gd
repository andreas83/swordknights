extends SceneTree
## One peer of a real, two-process networked duel.
##
## Driven by tests/net_live.sh, which starts a relay and two of these and then
## judges what they wrote. Unlike tests/net_desync_test.gd — where the host is a
## recording so that everything is deterministic — this one goes through real
## sockets between real operating-system processes, which is the only way to
## find out whether WsTransport, the relay and the handshake actually work.
##
##     godot --headless --path . --script tests/net_live.gd -- \
##       --mode room-host --url ws://127.0.0.1:45678 --frames 300 \
##       --report /tmp/host.txt --code-out /tmp/code.txt
##
## Modes: direct-host, direct-guest, room-host, room-guest.
##
## `--sim match` (the default) plays the tug-of-war match on the real fighter,
## which is what the online duel runs; `--sim round` plays the earlier round
## duel.
##
## Runs at real time on purpose: no --fixed-fps. Two processes talking over a
## socket have to agree about how fast a second is.

const Support := preload("res://tests/duel_support.gd")

var mode := "direct-host"
var sim_kind := "match"
var url := "ws://127.0.0.1:45678"
var port := 45678
var code := ""
var want_frames := 300
var report_path := ""
var code_out := ""
## Give up if nothing ever connects, so a failed run ends rather than hangs.
var patience_frames := 1800

var _duel: DuelSim
var _transport: WsTransport
var _session: NetSession
var _stream: Array[Vector2i]
var _warm := 0
var _waited := 0
var _ran := 0
var _done := false
var _note := ""


func _initialize() -> void:
	_parse_args()
	_stream = Support.input_stream(want_frames + 600, 0xc0ffee)


func _physics_process(_delta: float) -> bool:
	_warm += 1
	if _warm < 2:
		return false
	if _warm == 2:
		_open()
		return false
	if _done:
		return true

	if _session == null:
		# Relay mode: the room has not been assigned yet, so there is no
		# session to pump the transport. Pump it here instead.
		_transport.poll()
		_waited += 1
		if _waited > patience_frames:
			return _finish("no room: %s" % _transport.detail)
		return false

	_session.poll()

	if _session.is_running():
		_ran += 1
		if _ran >= want_frames:
			return _finish("ran %d frames" % _ran)
	else:
		_waited += 1
		if _ran > 0:
			# We duelled and the other side has gone. That is a finish, not a
			# failure: whichever peer hits its frame budget first leaves.
			return _finish("peer left after %d frames" % _ran)
		if _session.stage == NetSession.Stage.ENDED:
			return _finish("session ended early: %s" % _session.status_detail)
		if _waited > patience_frames:
			return _finish("gave up waiting: %s" % _session.status_detail)

	return false


## --- setting up -------------------------------------------------------------

func _open() -> void:
	if sim_kind == "match":
		var fight := DuelMatch.new()
		fight.name = "Match"
		fight.fighter_scene = load("res://scenes/fighter.tscn")
		root.add_child(fight)
		if not fight.build(ZoneStrip.from_manifest("res://levels/duel_zones.txt")):
			_finish("the match would not build")
			return
		_duel = fight
	else:
		_duel = Support.spawn_duel(root)
	_transport = WsTransport.new()
	_transport.room_assigned.connect(_on_room_assigned)

	var as_host := mode.ends_with("-host")
	var err := OK
	match mode:
		"direct-host":
			err = _transport.host(port)
		"direct-guest":
			err = _transport.join(url)
		"room-host":
			err = _transport.join_room(url, "")
		"room-guest":
			err = _transport.join_room(url, code)
		_:
			push_error("unknown mode %s" % mode)
			_finish("bad mode")
			return

	if err != OK:
		_finish("could not open transport: %s" % _transport.detail)
		return

	# A relayed peer is told which seat it has when the room opens; a direct
	# one knows already.
	if mode.begins_with("direct"):
		_start_session(as_host)
	print("[%s] opened: %s" % [mode, _transport.describe()])


func _on_room_assigned(room_code: String, as_host: bool) -> void:
	print("[%s] room %s, host=%s" % [mode, room_code, as_host])
	if code_out != "":
		var file := FileAccess.open(code_out, FileAccess.WRITE)
		if file != null:
			file.store_line(room_code)
			file.close()
	if _session == null:
		_start_session(as_host)


func _start_session(as_host: bool) -> void:
	_session = NetSession.new()
	var stream := _stream
	var duel := _duel
	_session.local_input = func() -> int:
		var at: int = duel.frame
		if at < 0 or at >= stream.size():
			return 0
		var pair: Vector2i = stream[at]
		return pair.x if as_host else pair.y
	_session.desync_detected.connect(
		func(frame: int, mine: int, theirs: int) -> void:
			print("[%s] DESYNC frame %d: %08x vs %08x" % [mode, frame, mine, theirs])
	)
	_session.start(_transport, _duel, as_host)


## --- finishing --------------------------------------------------------------

func _finish(note: String) -> bool:
	_done = true
	_note = note
	var lines := PackedStringArray([
		"mode=%s" % mode,
		"note=%s" % note,
		"stage=%d" % (_session.stage if _session != null else -1),
		"running=%s" % (_session != null and _session.is_running()),
		"frames=%d" % (_duel.frame if _duel != null else -1),
		"ran=%d" % _ran,
		"sim=%s" % sim_kind,
		"outcome=%s" % _outcome(),
		"snapshots_sent=%d" % (_session.snapshots_sent if _session != null else 0),
		"snapshots_received=%d" % (_session.snapshots_received if _session != null else 0),
		"corrections=%d" % (_session.corrections if _session != null else 0),
		"verifications=%d" % (_session.verifications if _session != null else 0),
		"desyncs=%d" % (_session.desync_count if _session != null else -1),
		"starved=%d" % (_session.input_starved if _session != null else 0),
		"rtt_ms=%.1f" % (_session.rtt_ms if _session != null else -1.0),
		"transport=%s" % (_transport.describe() if _transport != null else "none"),
	])
	var text := "\n".join(lines)
	print("[%s] %s" % [mode, note])
	print(text)
	if report_path != "":
		var file := FileAccess.open(report_path, FileAccess.WRITE)
		if file != null:
			file.store_string(text + "\n")
			file.close()
	if _session != null:
		_session.shutdown()
	return true


## What the duel came to, in the sim's own terms: kills in the match, round and
## score in the round duel.
func _outcome() -> String:
	var fight := _duel as DuelMatch
	if fight != null:
		return "kills %d,%d leader %d" % [fight.kills[0], fight.kills[1], fight.leader_slot()]
	var duel := _duel as Duel
	if duel != null:
		return "round %d scores %d,%d" % [duel.round_index, duel.scores[0], duel.scores[1]]
	return "none"


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var key: String = args[i]
		var value: String = args[i + 1] if i + 1 < args.size() else ""
		match key:
			"--mode":
				mode = value
				i += 2
			"--sim":
				sim_kind = value
				i += 2
			"--url":
				url = value
				i += 2
			"--port":
				port = int(value)
				i += 2
			"--code":
				code = value.strip_edges().to_upper()
				i += 2
			"--frames":
				want_frames = maxi(1, int(value))
				i += 2
			"--report":
				report_path = value
				i += 2
			"--code-out":
				code_out = value
				i += 2
			"--patience":
				patience_frames = maxi(60, int(value))
				i += 2
			_:
				i += 1
