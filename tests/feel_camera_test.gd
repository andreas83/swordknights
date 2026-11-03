extends SceneTree
## Pins the camera's framing rules and the budget they are allowed to spend.
##
## The rules are static functions on `GameCamera` precisely so they can be
## checked here without building a level and a physics world just to get a
## character to fall off something. The integration half below drives the
## camera's `_physics_process` by hand for the same reason: a headless run
## paces physics against idle frames however it likes, and a camera test that
## depends on that is a camera test that fails on a loaded CI machine.
##
##     godot --headless --script tests/feel_camera_test.gd

const DT := 1.0 / 60.0

var _failures := 0


func _initialize() -> void:
	_check_lead()
	_check_fall_lead()
	_check_anchor()
	_check_budget()
	_check_no_zoom()
	_check_held_frame()

	if _failures > 0:
		printerr("feel_camera_test: %d failure(s)" % _failures)
		quit(1)
		return
	print("feel_camera_test: ok")
	quit(0)


## Drift ahead when running, hold still when idle.
func _check_lead() -> void:
	_true(GameCamera.lead_scale(0.0, false) == 0.0,
		"standing still, the frame does not lead at all")
	_true(is_equal_approx(GameCamera.lead_scale(Tuning.RUN_SPEED, false), 1.0),
		"at a full run it leads by the whole look-ahead")
	_true(is_equal_approx(GameCamera.lead_scale(-Tuning.RUN_SPEED, false), 1.0),
		"and the same running the other way — direction comes from facing")
	_true(GameCamera.lead_scale(Tuning.RUN_SPEED * 4.0, false) <= 1.0,
		"a knockback cannot push the lead past the look-ahead")
	_true(GameCamera.lead_scale(Tuning.WALK_SPEED, false)
			< GameCamera.lead_scale(Tuning.RUN_SPEED, false),
		"a walk leads less than a run")

	# Tighten on a ledge grab: most of the lead comes off, but not all of it.
	var hanging := GameCamera.lead_scale(Tuning.RUN_SPEED, true)
	_true(hanging < 0.5, "hanging, the frame stops leading (%.2f)" % hanging)
	_true(hanging > 0.0, "but keeps a sliver, so the intent still reads")


## Lead a long fall, so the ground arrives before the player does.
func _check_fall_lead() -> void:
	_true(GameCamera.fall_lead(Tuning.MAX_FALL_SPEED, true, false) == 0.0,
		"standing on the floor, there is no fall to lead")
	_true(GameCamera.fall_lead(Tuning.MAX_FALL_SPEED, false, true) == 0.0,
		"nor while hanging off a ledge")
	_true(GameCamera.fall_lead(0.0, false, false) == 0.0, "nor on the way up")

	# An ordinary jump must not reframe anything: that is the whole reason the
	# threshold sits where it does.
	var jump_arc := Tuning.flat_jump_land_speed() * 0.45
	_true(GameCamera.fall_lead(jump_arc, false, false) == 0.0,
		"the arc of a plain hop is not a fall")

	var terminal := GameCamera.fall_lead(Tuning.MAX_FALL_SPEED, false, false)
	_true(is_equal_approx(terminal, GameCamera.FALL_LEAD_MAX),
		"terminal velocity spends the whole fall-lead budget")
	var middling := GameCamera.fall_lead(Tuning.HARD_LAND_SPEED, false, false)
	_true(middling > 0.0 and middling < terminal,
		"and a two-tile drop spends some of it (%.1f px)" % middling)
	_true(GameCamera.fall_lead(Tuning.MAX_FALL_SPEED * 3.0, false, false) <= terminal,
		"nothing spends more than the budget")


## Where the frame rests, and the one direction it refuses to go.
func _check_anchor() -> void:
	_true(GameCamera.anchor_for(0.0, 120.0, 0.0, true, false) == 120.0,
		"grounded, the frame rests on the floor underfoot")

	# Jumping must not pan the view — this is the behaviour the camera has
	# always had and the reframing must not have cost us.
	var held := GameCamera.anchor_for(120.0, 60.0, -Tuning.JUMP_SPEED, false, false)
	_true(held == 120.0, "jumping does not pan the frame up")

	var falling := GameCamera.anchor_for(120.0, 160.0, 200.0, false, false)
	_true(falling > 120.0 and falling < 160.0,
		"falling, the frame follows down but lags behind (%.1f)" % falling)
	_true(GameCamera.anchor_for(120.0, 124.0, 200.0, false, false) == 120.0,
		"a short drop stays inside the slack and moves nothing")

	var lifted := GameCamera.anchor_for(120.0, 120.0, 0.0, false, true)
	_true(lifted < 120.0, "hanging, the frame lifts onto the ledge being taken")
	_true(is_equal_approx(120.0 - lifted, GameCamera.GRAB_LIFT),
		"by exactly GRAB_LIFT")

	# A fall followed by a recovery must not snap back: the anchor only ever
	# descends while airborne.
	var walked := 120.0
	for i: int in 30:
		walked = GameCamera.anchor_for(walked, 120.0 + float(i) * 4.0, 200.0, false, false)
	for i: int in 30:
		walked = GameCamera.anchor_for(walked, 120.0, -200.0, false, false)
	_true(walked >= 120.0, "the frame never climbs back up on its own")


## "Subtle" is a number or it is nothing. Everything the camera is allowed to
## move the frame by, added up, is under half the height of the viewport.
func _check_budget() -> void:
	var vertical := GameCamera.FALL_LEAD_MAX + GameCamera.GRAB_LIFT + GameCamera.SETTLE_MAX
	_true(vertical <= 48.0,
		"all vertical reframing together is %.0f px of a 180 px frame (<= 48)" % vertical)
	_true(GameCamera.SETTLE_MAX <= 6.0,
		"the hardest landing dips the frame %.0f px (<= 6)" % GameCamera.SETTLE_MAX)
	_true(GameCamera.FALL_LEAD_MAX <= 2.5 * Tuning.TILE,
		"the fall lead is %.1f tiles (<= 2.5)" % (GameCamera.FALL_LEAD_MAX / Tuning.TILE))
	_true(GameCamera.GRAB_LIFT < Tuning.BODY_HEIGHT,
		"the grab lift is less than the character is tall")
	_true(GameCamera.LOOK_BEHIND_SMOOTHING < 6.0,
		"the lead retracts slower than it extends, so stopping settles")


## No zoom, deliberately: see the class docs on game_camera.gd. A non-integer
## zoom resamples the tilemap and softens every shadow edge in the frame, which
## is the one thing docs/art-direction.md does not allow. Checked in the source
## because the point is that nobody adds one later.
func _check_no_zoom() -> void:
	var file := FileAccess.open("res://scripts/render/game_camera.gd", FileAccess.READ)
	if file == null:
		_fail("cannot read game_camera.gd")
		return
	for line: String in file.get_as_text().split("\n"):
		var code := line.strip_edges()
		if code.begins_with("#") or code.begins_with("##"):
			continue
		_true(not code.begins_with("zoom") and not code.contains(" zoom ="),
			"the camera never writes zoom: %s" % code)


## A held frame is held. During a hitstop the camera must not move, must not
## re-roll its shake, and must not quietly accumulate the frames it missed.
func _check_held_frame() -> void:
	var host := Node2D.new()
	root.add_child(host)
	var scene := load("res://scenes/player.tscn") as PackedScene
	if scene == null:
		_fail("cannot load player.tscn")
		return
	var player := scene.instantiate() as Player
	var camera := GameCamera.new()
	host.add_child(player)
	host.add_child(camera)
	# Both are driven by hand below; the engine must not also step them.
	player.set_physics_process(false)
	camera.set_physics_process(false)

	player.position = Vector2(160.0, 120.0)
	player.facing = 1
	camera.setup(player, Vector2(640.0, 360.0))
	for i: int in 40:
		camera._physics_process(DT)
	_true(camera.zoom == Vector2.ONE, "the camera is at 1:1 and stays there")

	var settled := camera.global_position
	var flow := Flow.install(host)
	_true(flow != null, "the test has a Flow to hold the frame with")
	if flow == null:
		return

	Flow.hitstop(host, Flow.HIT_FRAMES * Flow.FRAME)
	camera.shake(3.0, 0.3)
	player.position += Vector2(64.0, 48.0)
	var offset_before := camera.offset
	for i: int in Flow.HIT_FRAMES:
		camera._physics_process(DT)
	_true(camera.global_position == settled,
		"the frame does not move while it is held")
	_true(camera.offset == offset_before,
		"and the shake does not re-roll inside it")

	for i: int in Flow.HIT_FRAMES:
		flow._physics_process(DT)
	_true(not Flow.is_hitstopped(), "the hold expires")
	for i: int in 3:
		camera._physics_process(DT)
	_true(camera.global_position != settled,
		"and the camera picks the character up again afterwards")

	# The settle is an impulse that decays; it must not leave the frame low.
	camera.shake(0.0, 0.0)
	camera.settle(1.0)
	for i: int in 60:
		camera._physics_process(DT)
	_true(camera.offset == Vector2.ZERO,
		"a settle returns the frame to where it was (offset %s)" % camera.offset)
	_true(camera.offset == camera.offset.round(),
		"and every offset is a whole pixel, because the art is")

	# The Flow is parented deferred and the flush happens on the way out, so
	# leave it alone: freeing it here would hand add_child a dead object.
	host.free()


func _true(condition: bool, what: String) -> void:
	if not condition:
		_fail(what)


func _fail(message: String) -> void:
	_failures += 1
	printerr("  FAIL  " + message)
