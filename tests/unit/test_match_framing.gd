extends GutTest
## How close the duel's camera stands (scripts/duel/match_framing.gd), as a
## model: no window, no match, a display frame at a time.
##
## Held here: the levels on the screens that matter -- far is the old fixed
## framing, close the adventure's scale; the frame comes in as the two close
## and goes out as they part, and rests on a whole pixel per texel; a fencing
## exchange at the edge of a threshold does not pump it; a kill holds it; and,
## over a minute of two fighters running about the window at full speed, it
## never once frames them out. That last one is what the mode cannot lose.

const DT := 1.0 / 60.0
## A phone held sideways: 2400 x 1080, the canvas 400 x 180, six pixels a unit.
const PHONE := Vector2(2400.0, 1080.0)
## Where the window is, for the walks: one zone, 480 wide.
const WINDOW := Vector2(960.0, 1440.0)
const FLOOR := 300.0


func _framing(screen: Vector2 = PHONE, per_unit: float = 6.0) -> MatchFraming:
	var framing := MatchFraming.new()
	framing.screen = screen
	framing.per_unit = per_unit
	framing.body = DuelTuning.default().body_height
	return framing


func _pair(gap: float, middle: float = 1200.0) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(middle - gap * 0.5, FLOOR), Vector2(middle + gap * 0.5, FLOOR)])


func _run(framing: MatchFraming, subjects: PackedVector2Array, seconds: float,
		together: bool = true) -> void:
	for _frame: int in roundi(seconds / DT):
		framing.update(DT, subjects, together)


func test_far_is_the_old_framing_and_close_is_the_adventures() -> void:
	# [screen, pixels per unit, far, close]
	var screens: Array = [
		[Vector2(1920, 1080), 6.0, 4, 6],
		[PHONE, 6.0, 4, 6],
		[Vector2(2532, 1170), 6.5, 5, 6],
		[Vector2(3200, 1440), 8.0, 6, 8],
		[Vector2(1280, 720), 4.0, 3, 4],
	]
	for screen: Array in screens:
		var framing := _framing(screen[0], screen[1])
		assert_eq(framing.far_level(), int(screen[2]), "far at %s" % screen[0])
		assert_eq(framing.close_level(), int(screen[3]), "close at %s" % screen[0])
		var body_share := framing.body * framing.far_level() / (screen[0] as Vector2).y
		assert_almost_eq(body_share, MatchFraming.FIGHTER_SHARE, 0.013,
			"a fighter is 8-9%% of the screen at the far level, %s" % screen[0])
		assert_lte(float(framing.close_level()), float(screen[1]) + 0.001,
			"never closer than the adventure, %s" % screen[0])


func test_it_comes_in_as_they_close_and_goes_out_as_they_part() -> void:
	var framing := _framing()
	framing.reset(_pair(440.0), true)
	assert_eq(framing.level, framing.far_level(), "apart: the far level")
	_run(framing, _pair(60.0), 4.0)
	assert_eq(framing.level, framing.close_level(), "together: the adventure's scale")
	assert_true(framing.at_rest(), "and at rest on it")
	assert_eq(framing.shown, float(framing.close_level()), "a whole pixel per texel")
	_run(framing, _pair(440.0), 2.0)
	assert_eq(framing.level, framing.far_level(), "apart again: out")
	assert_eq(framing.shown, float(framing.far_level()), "and at rest there too")


func test_a_step_is_eased_never_cut() -> void:
	var framing := _framing()
	framing.reset(_pair(440.0), true)
	var last := framing.shown
	var biggest := 0.0
	for _frame: int in 240:
		framing.update(DT, _pair(60.0), true)
		biggest = maxf(biggest, absf(framing.shown - last))
		last = framing.shown
	assert_eq(framing.level, framing.close_level(), "it came in")
	# A cut would move a whole level in a frame; the ease's steepest frame,
	# smoothstep over EASE_CALM, is 1.5 / 36 of one.
	assert_lt(biggest, 0.1, "no frame moves the scale by more than a tenth of a level")


## Two fighters at the edge of reach, one lunging in and stepping back twice a
## second, with the gap astride the line where the frame would come in: it may
## step once, and must not pump.
func test_fencing_at_a_threshold_does_not_pump() -> void:
	var framing := _framing()
	var room := framing.room(float(framing.far_level() + 1)).x
	var line := room - (MatchFraming.SIDE + MatchFraming.HYSTERESIS) * 2.0
	framing.reset(_pair(line + 24.0), true)
	var changes := 0
	var was := framing.level
	for frame: int in 60 * 20:
		var lunge := 24.0 if (frame / 15) % 2 == 0 else -24.0
		framing.update(DT, _pair(line + lunge), true)
		if framing.level != was:
			changes += 1
			was = framing.level
	assert_lte(changes, 1, "%d changes of level in twenty seconds of fencing" % changes)


func test_a_kill_holds_the_frame_then_stands_back() -> void:
	var framing := _framing()
	framing.reset(_pair(60.0), true)
	assert_eq(framing.level, framing.close_level())
	framing.kill_beat()
	var one := PackedVector2Array([_pair(60.0)[0], _pair(60.0)[1]])
	_run(framing, one, MatchFraming.KILL_HOLD - 0.05, false)
	assert_eq(framing.level, framing.close_level(), "held through the kill")
	assert_eq(framing.shown, float(framing.close_level()), "not even eased")
	_run(framing, one, 1.0, false)
	assert_eq(framing.level, framing.far_level(),
		"then out to wait for the respawn, with one fighter down")


## A minute of two fighters running about one window at full speed, turning
## at random, jumping now and then, the frame updated every display frame:
## every frame, both are inside it with EDGE to spare.
func test_both_fighters_are_always_in_frame() -> void:
	for screen: Array in [[PHONE, 6.0], [Vector2(1920, 1080), 6.0], [Vector2(1280, 720), 4.0]]:
		var framing := _framing(screen[0], screen[1])
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var at := _pair(80.0)
		var heading := PackedFloat32Array([-1.0, 1.0])
		var air := PackedFloat32Array([0.0, 0.0])
		framing.reset(at, true)
		var worst := INF
		for _frame: int in 60 * 60:
			for i: int in 2:
				if rng.randf() < 0.02:
					heading[i] = -heading[i]
				if rng.randf() < 0.01 and air[i] <= 0.0:
					air[i] = 0.35
				var feet := at[i]
				feet.x = clampf(feet.x + heading[i] * 120.0 * DT, WINDOW.x + 7.0, WINDOW.y - 7.0)
				air[i] = maxf(0.0, air[i] - DT)
				feet.y = FLOOR - sin(air[i] / 0.35 * PI) * 33.0
				at[i] = feet
			var shown := framing.update(DT, at, true)
			worst = minf(worst, framing.fit_scale(at) - shown)
		assert_gte(worst, -0.0001,
			"never framed out at %s (closest margin %.4f of a level)" % [screen[0], worst])


## A 16:9 desktop is narrower than a zone at the far level: with the two at
## opposite walls the floor drops below it, a whole level, rather than lose one.
func test_a_narrow_screen_drops_below_far_rather_than_lose_one() -> void:
	var framing := _framing(Vector2(1280, 720), 4.0)
	var walls := _pair(466.0)
	framing.reset(_pair(100.0), true)
	_run(framing, walls, 1.0)
	assert_eq(framing.level, framing.far_level() - 1, "a level below far")
	assert_true(framing.fits(framing.shown, walls, MatchFraming.EDGE,
		MatchFraming.EDGE_UPRIGHT), "and both are on screen")
	_run(framing, _pair(200.0), 4.0)
	assert_gte(framing.level, framing.far_level(), "back when they close")
