extends GutTest
## The duel's stick holds a LOW guard against a wandering thumb, keeps the duck
## a lean away, and never turns a sagging run into down + JUMP's roll
## (scripts/ui/touch_controls.gd, "The duel's stick"; docs/duel-combat.md,
## "The stick").
##
## The owner, on a phone: the LOW guard was not clear. On the adventure's
## mapping, straight down was the guard only while the thumb stayed within
## seven units of the vertical -- under 3 mm on a phone -- and past that the
## stick pressed a direction and WALK too, which is the duck, which LOW kills.
## A thumb holding LOW flickered into the duck, and each flicker moved the
## posture. Seen to fail with stance_actions() reading the push as
## stick_actions(delta, false) does.

const LOW: Array[String] = ["move_down"]
const HIGH: Array[String] = ["move_up"]


## Straight down holds LOW and nothing else, however the thumb wobbles inside
## the lane -- and the lane widens with the push.
func test_straight_down_holds_low_through_a_wobble() -> void:
	for push: float in [16.0, 22.0, 30.0]:
		var wobble := push * TouchControls.STANCE_CONE * 0.95
		for side: float in [-wobble, -3.0, 0.0, 3.0, wobble]:
			var held := TouchControls.stance_actions(Vector2(side, push))
			assert_eq(held, LOW, "down %.0f, aside %.1f holds LOW" % [push, side])
			assert_eq(TouchControls.stance_word(held), "LOW", "and says so")
	# The wobble the adventure's stick turned into a duck.
	var drift := Vector2(8.0, 22.0)
	assert_true(TouchControls.stick_actions(drift).has("walk"),
		"on the adventure's mapping, that drift was a duck")
	assert_eq(TouchControls.stance_actions(drift), LOW, "on the duel's it is the guard")


## The duck is down and a lean, either way, near or far: down with a direction
## and WALK, which plants the fighter whatever the lean says.
func test_down_and_aside_ducks() -> void:
	for at: Vector2 in [Vector2(12.0, 20.0), Vector2(-12.0, 20.0), Vector2(20.0, 25.0),
			Vector2(-24.0, 26.0), Vector2(15.0, 16.0)]:
		var held := TouchControls.stance_actions(at)
		assert_true(held.has("move_down") and held.has("walk"), "%s ducks: %s" % [at, held])
		assert_eq(TouchControls.stance_word(held), "DUCK", "and says DUCK")


## A run whose thumb sags below the horizontal is a run: no down, so JUMP is a
## jump and not a roll, and the blade stays where it was.
func test_a_sagging_run_holds_no_down() -> void:
	for at: Vector2 in [Vector2(28.0, 16.0), Vector2(-28.0, 20.0), Vector2(34.0, 30.0)]:
		var held := TouchControls.stance_actions(at)
		assert_false(held.has("move_down"), "%s does not press down: %s" % [at, held])
		assert_false(held.has("walk"), "and runs")
		assert_true(held.has("move_right") or held.has("move_left"), "that way")


## Straight up is HIGH standing still, like straight down is LOW; a lean up is
## a shuffle at HIGH, a run up a run at HIGH; a small flat push walks.
func test_up_and_the_flat_are_the_adventures() -> void:
	assert_eq(TouchControls.stance_actions(Vector2(5.0, -22.0)), HIGH, "straight up: HIGH")
	assert_eq(TouchControls.stance_word(HIGH), "HIGH")
	var lean := TouchControls.stance_actions(Vector2(12.0, -20.0))
	assert_true(lean.has("move_up") and lean.has("walk"), "a lean up shuffles at HIGH")
	var run := TouchControls.stance_actions(Vector2(28.0, -20.0))
	assert_true(run.has("move_up") and not run.has("walk"), "a run up runs at HIGH")
	assert_eq(TouchControls.stance_actions(Vector2(10.0, 3.0)), ["move_right", "walk"],
		"a small flat push walks")
	assert_eq(TouchControls.stance_actions(Vector2(25.0, 3.0)), ["move_right"],
		"a full one runs")
	assert_eq(TouchControls.stance_word([] as Array[String]), "MID", "nothing is MID")


## The adventure's stick is untouched: its mapping is the old formula, push
## for push, and only the duel's scenes read the stick for stances.
func test_the_adventure_keeps_its_stick() -> void:
	for x: int in range(-34, 35, 3):
		for y: int in range(-34, 35, 3):
			var at := Vector2(x, y)
			assert_eq(TouchControls.stick_actions(at), _old(at), "the adventure at %s" % at)
	for path: String in ["res://scenes/game.tscn", "res://scenes/feel_lab.tscn"]:
		var scene := (load(path) as PackedScene).instantiate()
		var controls := TouchControls.of(scene)
		assert_false(controls.stance_stick, "%s reads the adventure's stick" % path)
		scene.free()
	for path: String in ["res://scenes/duel_match_cpu.tscn", "res://scenes/duel_match_online.tscn"]:
		var scene := (load(path) as PackedScene).instantiate()
		var controls := TouchControls.of(scene)
		assert_true(controls.stance_stick, "%s reads the duel's stick" % path)
		scene.free()


## The stick as it was before the duel had one of its own.
func _old(delta: Vector2) -> Array[String]:
	var wanted: Array[String] = []
	if delta.x < -7.0:
		wanted.append("move_left")
	elif delta.x > 7.0:
		wanted.append("move_right")
	if delta.y < -14.0:
		wanted.append("move_up")
	elif delta.y > 14.0:
		wanted.append("move_down")
	if absf(delta.x) > 7.0 and absf(delta.x) < 30.0 * 0.55:
		wanted.append("walk")
	return wanted
