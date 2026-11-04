extends SceneTree
## Pins the transition system, the hitstop budget, and the one rule that keeps
## hitstop out of the duel.
##
## The last of those is the reason this file exists. Hitstop in single-player is
## a real freeze: `Game` stops stepping its actors. That is fine there and
## fatal in a duel, where both peers must reach the same state from the same
## inputs on the same frame and a locally-detected sword hit is not something
## they agree on. The guard is a source scan, because the failure would not
## show up as a failing assertion anywhere — it would show up as a desync
## report in someone's third round.
##
##     godot --headless --script tests/feel_flow_test.gd

## Generous: the wipe is driven on the display clock and this asserts that it
## finishes, not how fast the machine is.
const FRAME_BUDGET := 600

var _failures := 0
var _host: Node
var _flow: Flow
var _covered_at_lead := -1.0
var _covered_calls := 0
var _frames := 0
var _wipe_started := false


func _initialize() -> void:
	_host = Node.new()
	_host.name = "FeelFlowTestHost"
	root.add_child(_host)

	_check_install()
	_check_hitstop_budget()
	_check_wipe_geometry()
	_check_haptics_setting()
	_check_duel_is_untouched()
	_check_hitstop_callers()


## The frame-driven half: the wipe is a state machine on the display clock, so
## it needs real frames rather than a hand-cranked loop.
func _process(_delta: float) -> bool:
	_frames += 1

	if not _wipe_started:
		if _flow == null or not _flow.is_inside_tree():
			# install() adds deferred, so the node arrives a frame or two in.
			return _give_up_if_stuck()
		_check_veil()
		_flow.start_wipe(_on_covered)
		_true(Flow.busy(), "a wipe that has just started owns the screen")
		_wipe_started = true
		return false

	if Flow.busy():
		return _give_up_if_stuck()

	_check_wipe_finished()
	_check_hitstop_clock()
	return _finish()


func _on_covered() -> void:
	_covered_calls += 1
	_covered_at_lead = _flow._lead


## --- static and structural checks -------------------------------------------

func _check_install() -> void:
	_flow = Flow.install(_host)
	_true(_flow != null, "install() returns a Flow")
	_true(Flow.install(_host) == _flow, "install() is idempotent — one Flow per tree")
	_true(_flow.layer == Flow.LAYER, "the veil sits above every other CanvasLayer")
	_true(not _flow.is_busy(), "a fresh Flow is idle")
	_true(not Flow.busy(), "and says so through the static predicate")
	_true(not Flow.is_hitstopped(), "and is not holding a frame")


## The budget, stated as arithmetic rather than measured, so it cannot drift
## without this failing.
func _check_hitstop_budget() -> void:
	_true(Flow.MAX_HITSTOP <= 7.0 * Flow.FRAME,
		"the hitstop ceiling is %.0f frames (<= 7)" % (Flow.MAX_HITSTOP / Flow.FRAME))
	var stops: Array[int] = [
		Flow.HIT_FRAMES, Flow.STOMP_FRAMES, Flow.HURT_FRAMES,
		Flow.PLUNGE_FRAMES, Flow.PARRY_FRAMES,
	]
	for frames: int in stops:
		_true(float(frames) * Flow.FRAME <= Flow.MAX_HITSTOP,
			"a %d-frame stop fits under the ceiling" % frames)
	_true(Flow.STOMP_FRAMES >= Flow.HIT_FRAMES,
		"a stomp weighs at least as much as a sword")
	_true(Flow.PLUNGE_FRAMES >= Flow.STOMP_FRAMES,
		"a plunge weighs at least as much as the stomp it contains")
	_true(Flow.HURT_FRAMES <= Flow.HIT_FRAMES,
		"taking a hit costs the player less time than landing one")

	# Taken with max(), never summed: three things connecting in one frame must
	# not stack into a stutter.
	Flow.hitstop(_host, Flow.HIT_FRAMES * Flow.FRAME)
	Flow.hitstop(_host, Flow.HURT_FRAMES * Flow.FRAME)
	_true(is_equal_approx(Flow.hitstop_remaining(), Flow.HIT_FRAMES * Flow.FRAME),
		"overlapping hitstops take the longest, not the sum")
	Flow.hitstop(_host, 10.0)
	_true(is_equal_approx(Flow.hitstop_remaining(), Flow.MAX_HITSTOP),
		"an absurd request is clamped to the ceiling")
	_true(Flow.is_hitstopped(), "and the frame is held while it lasts")
	_flow._hitstop = 0.0

	# The transition budget, likewise. A retry is the one transition the player
	# waits on rather than watches, so it has its own, shorter, number.
	var full := Flow.COVER_TIME + Flow.HOLD_TIME + Flow.UNCOVER_TIME
	_true(full <= 0.45, "a full wipe takes %.0f ms (<= 450)" % (full * 1000.0))
	_true(full * Flow.FAST_SCALE <= 0.26,
		"a fast wipe takes %.0f ms (<= 260)" % (full * Flow.FAST_SCALE * 1000.0))


## The wipe has to actually cover the screen at full extent, on every row. The
## edge is raked, so "it looked covered in the middle" is not good enough.
func _check_wipe_geometry() -> void:
	var view := Vector2(320.0, 180.0)
	for row: int in range(0, 181, 10):
		_true(Flow.covers_row(1.0, 0.0, view, float(row)),
			"row %d is covered at full extent" % row)
	_true(not Flow.covers_row(0.5, 0.0, view, 0.0), "half way across is not covered")
	_true(not Flow.covers_row(1.0, 1.0, view, 90.0), "a finished wipe covers nothing")
	# A tall phone in landscape is wider than the design viewport; the wipe must
	# still close over it.
	for row: int in range(0, 201, 25):
		_true(Flow.covers_row(1.0, 0.0, Vector2(480.0, 200.0), float(row)),
			"a 480x200 frame is covered at row %d" % row)


func _check_haptics_setting() -> void:
	var had_file := FileAccess.file_exists(UserData.at(Flow.SETTINGS_PATH))
	var was := Flow.haptics_enabled()

	Flow.set_haptics_enabled(false)
	_true(not Flow.haptics_enabled(), "haptics can be switched off")
	# Nothing to observe from a buzz; what matters is that it is inert and does
	# not reach the platform when the setting says no.
	Flow.haptic(1.0)
	Flow.set_haptics_enabled(true)
	_true(Flow.haptics_enabled(), "and back on")
	Flow.haptic(0.0)
	Flow.haptic(2.0)

	Flow.set_haptics_enabled(was)
	if not had_file:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(UserData.at(Flow.SETTINGS_PATH)))


## The rule from docs/feel.md, enforced where it can be enforced: a duel never
## freezes a frame, and never reaches the single-player flow to ask it to.
func _check_duel_is_untouched() -> void:
	for directory: String in ["res://scripts/duel", "res://scripts/net"]:
		for path: String in _scripts_under(directory):
			var body := _read(path)
			_true(not body.contains("Flow."),
				"%s does not reach into Flow — a duel must not be wiped or frozen" % path)
			_true(not body.contains("hitstop"),
				"%s does not mention hitstop" % path)


## And the other half of the same rule: whatever does freeze a frame has to be
## something a reviewer can find. One caller, in the single-player scene.
func _check_hitstop_callers() -> void:
	var callers: Array[String] = []
	for directory: String in ["res://scripts"]:
		for path: String in _scripts_under(directory):
			if path.ends_with("/flow.gd"):
				continue
			if _read(path).contains("Flow.hitstop("):
				callers.append(path)
	callers.sort()
	_true(callers == ["res://scripts/core/game.gd"],
		"Flow.hitstop() is called from game.gd and nowhere else, not %s" % str(callers))


## --- frame-driven checks ----------------------------------------------------

func _check_veil() -> void:
	var veil := _flow.get_node_or_null("Veil") as Control
	_true(veil != null, "the Flow owns a veil to draw on")
	_true(_flow.process_mode == Node.PROCESS_MODE_ALWAYS,
		"the wipe keeps running while the scene under it is frozen")


func _check_wipe_finished() -> void:
	_true(_covered_calls == 1, "the caller's work ran exactly once, not %d times"
		% _covered_calls)
	_true(is_equal_approx(_covered_at_lead, 1.0),
		"it ran at full cover (lead was %.3f), so nobody saw it happen"
			% _covered_at_lead)
	_true(_flow._lead == 0.0 and _flow._trail == 0.0,
		"a finished wipe leaves nothing on screen")
	_true(not Flow.busy(), "and hands the screen back")

	# A second wipe asked for while one is running is dropped, not queued.
	_flow.start_wipe(Callable())
	_true(Flow.busy(), "a second wipe starts")
	var before := _flow._lead
	_flow.start_wipe(_on_covered)
	_true(_flow._lead == before and _covered_calls == 1,
		"and a third, asked for mid-wipe, is dropped rather than queued")
	_flow._stage = Flow.Stage.IDLE


## The clock is stepped by hand so this does not depend on how the engine
## happens to pace physics against idle frames in a headless run.
func _check_hitstop_clock() -> void:
	Flow.hitstop(_host, Flow.HIT_FRAMES * Flow.FRAME)
	var held := 0
	for i: int in 20:
		if not Flow.is_hitstopped():
			break
		held += 1
		_flow._physics_process(Flow.FRAME)
	_true(held == Flow.HIT_FRAMES,
		"a %d-frame hitstop holds for %d frames" % [Flow.HIT_FRAMES, held])
	_true(not Flow.is_hitstopped(), "and then lets go")


## --- plumbing ---------------------------------------------------------------

func _scripts_under(directory: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(directory)
	if dir == null:
		_fail("cannot open %s" % directory)
		return out
	for name: String in dir.get_files():
		# The engine serves .gd as .gd.remap in an export; from source it does
		# not, and these tests only ever run from source.
		if name.ends_with(".gd"):
			out.append(directory.path_join(name))
	for name: String in dir.get_directories():
		out.append_array(_scripts_under(directory.path_join(name)))
	return out


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("cannot read %s" % path)
		return ""
	return file.get_as_text()


func _give_up_if_stuck() -> bool:
	if _frames < FRAME_BUDGET:
		return false
	_fail("gave up after %d frames: stage %d, lead %.3f, trail %.3f"
		% [_frames, _flow._stage if _flow != null else -1,
			_flow._lead if _flow != null else -1.0,
			_flow._trail if _flow != null else -1.0])
	return _finish()


func _finish() -> bool:
	if _failures > 0:
		printerr("feel_flow_test: %d failure(s)" % _failures)
		quit(1)
		return true
	print("feel_flow_test: ok")
	quit(0)
	return true


func _true(condition: bool, what: String) -> void:
	if not condition:
		_fail(what)


func _fail(message: String) -> void:
	_failures += 1
	printerr("  FAIL  " + message)
