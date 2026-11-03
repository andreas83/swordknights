extends SceneTree
## One peer of a real, two-process networked match.
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
## Modes: direct-host, direct-guest, room-host, room-guest. Both peers play the
## tug-of-war match on the real fighter, which is what Duel Online runs.
##
## `--look figure=heroine,outfit=wine,...` is the look this peer sends in the
## handshake, as CharacterLook ids; `--look none` sends no look block at all,
## which is byte for byte what a build from before the looks sent. The report
## says what was sent (`sent_look`) and what came back from the other side,
## read the way match_online.gd reads it (`got_look`), so the script can check
## a chosen look really crossed the socket and the relay.
##
## Runs at real time on purpose: no --fixed-fps. Two processes talking over a
## socket have to agree about how fast a second is.

const Support := preload("res://tests/duel_support.gd")

var mode := "direct-host"
var url := "ws://127.0.0.1:45678"
var port := 45678
var code := ""
var want_frames := 300
var report_path := ""
var code_out := ""
## Give up if nothing ever connects, so a failed run ends rather than hangs.
var patience_frames := 1800
## The look sent in the handshake, as ids. Empty sends none.
var look_ids := {}

var _duel: DuelMatch
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
	_duel = Support.spawn_match(root)
	if _duel == null:
		_finish("the match would not build")
		return
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
	_session.local_look = look_ids
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
		"outcome=%s" % _outcome(),
		"snapshots_sent=%d" % (_session.snapshots_sent if _session != null else 0),
		"snapshots_received=%d" % (_session.snapshots_received if _session != null else 0),
		"corrections=%d" % (_session.corrections if _session != null else 0),
		"verifications=%d" % (_session.verifications if _session != null else 0),
		"desyncs=%d" % (_session.desync_count if _session != null else -1),
		"starved=%d" % (_session.input_starved if _session != null else 0),
		"rtt_ms=%.1f" % (_session.rtt_ms if _session != null else -1.0),
		"transport=%s" % (_transport.describe() if _transport != null else "none"),
		"sent_look=%s" % _look_text(look_ids),
		"got_fields=%d" % (_session.remote_look.size() if _session != null else -1),
		"got_look=%s" % _look_text(
			CharacterLook.from_ids(_session.remote_look).to_ids() if _session != null else {}),
		"look_error=%s" % (_session.remote_look_error if _session != null else ""),
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


## A look as one line, "figure=heroine,outfit=wine,...", in the wardrobe's
## field order; "none" for no look at all.
static func _look_text(ids: Dictionary) -> String:
	if ids.is_empty():
		return "none"
	var parts := PackedStringArray()
	for field: String in CharacterLook.FIELDS:
		parts.append("%s=%s" % [field, ids.get(field, "")])
	return ",".join(parts)


## The inverse of _look_text, for --look.
static func _parse_look(text: String) -> Dictionary:
	var ids := {}
	if text == "none":
		return ids
	for part: String in text.split(",", false):
		var pair := part.split("=")
		if pair.size() == 2:
			ids[pair[0].strip_edges()] = pair[1].strip_edges()
	return ids


## What the match came to: kills, and who held the initiative at the end.
func _outcome() -> String:
	if _duel == null:
		return "none"
	return "kills %d,%d leader %d" % [_duel.kills[0], _duel.kills[1], _duel.leader_slot()]


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
			"--look":
				look_ids = _parse_look(value)
				i += 2
			_:
				i += 1
