extends SceneTree
## The duel movement profile: the numbers every frame count is judged against.
##
##     godot --headless --script tests/fighter_profile_test.gd
##
## The spec asks for the opposite of the adventure character: "maximum speed
## within 1-2 frames", "releasing the input stops the fighter within 2-3
## frames", "gravity: very high, no floaty moon jumps". Those are claims about
## behaviour, so they are measured by simulating a fighter rather than by
## reading the constants back — a retune that breaks the feel fails here and
## says by how much.
##
## It also pins the two things that keep the duel and the adventure apart: the
## fighter reads DuelTuning and never scripts/core/tuning.gd, and the stance
## bands are cut so that the combat matrix's duck and roll columns fall out of
## the geometry.

const Support := preload("res://tests/fighter_support.gd")

## Far enough apart that neither fighter can touch the other.
const CLEAR := 120.0

var _s := Support.new()
var _warm := 0


func _physics_process(_delta: float) -> bool:
	_warm += 1
	if _warm < 2:
		return false

	_top_speed_arrives_in_one_or_two_frames()
	_the_stop_takes_two_or_three_frames()
	_gravity_is_high_and_the_jump_is_not_floaty()
	_the_derived_helpers_match_the_simulation()
	_the_fighter_never_reads_the_adventure_tuning()
	_the_stance_bands_produce_the_matrix_geometry()

	quit(_s.report("fighter_profile"))
	return true


func _top_speed_arrives_in_one_or_two_frames() -> void:
	var stage := Support.build(root)
	stage.place(CLEAR)
	var frames := 0
	for _frame: int in 10:
		stage.run(1, Support.RIGHT, 0)
		frames += 1
		if is_equal_approx(stage.a.velocity.x, stage.tuning.run_speed):
			break
	_s.check(frames >= 1 and frames <= 2, "top speed in 1 to 2 frames (took %d)" % frames)
	_s.equal(
		frames, stage.tuning.frames_to_top_speed(),
		"and the profile's own arithmetic agrees"
	)
	stage.dispose()


func _the_stop_takes_two_or_three_frames() -> void:
	var stage := Support.build(root)
	stage.place(CLEAR)
	stage.run(6, Support.RIGHT, 0)
	_s.check(
		is_equal_approx(stage.a.velocity.x, stage.tuning.run_speed), "running flat out first"
	)
	var frames := 0
	for _frame: int in 10:
		stage.run(1, 0, 0)
		frames += 1
		if is_zero_approx(stage.a.velocity.x):
			break
	_s.check(frames >= 2 and frames <= 3, "stopped in 2 to 3 frames (took %d)" % frames)
	_s.equal(frames, stage.tuning.frames_to_stop(), "and the profile's own arithmetic agrees")
	stage.dispose()


func _gravity_is_high_and_the_jump_is_not_floaty() -> void:
	var stage := Support.build(root)
	stage.place(CLEAR)
	var tuning := stage.tuning
	_s.check(
		tuning.gravity > Tuning.GRAVITY * 2.0,
		"duel gravity (%.0f) is far above the adventure's (%.0f)"
			% [tuning.gravity, Tuning.GRAVITY]
	)

	stage.run(1, Support.JUMP, 0)
	var apex := 0.0
	var airtime := 1
	for _frame: int in 120:
		stage.run(1, Support.JUMP, 0)
		airtime += 1
		apex = minf(apex, stage.a.position.y - stage.ground_y())
		if stage.a.grounded:
			break
	_s.check(airtime <= 24, "a jump is over in under 0.4s (%d frames)" % airtime)
	_s.check(
		-apex > 28.0 and -apex < 42.0,
		"the apex is about two tiles, not a moon hop (%.1f px)" % -apex
	)
	_s.check(
		airtime < 60.0 * Tuning.jump_airtime(),
		"and the duel's jump is shorter than the adventure's"
	)
	stage.dispose()


func _the_derived_helpers_match_the_simulation() -> void:
	var stage := Support.build(root)
	stage.place(CLEAR)
	stage.run(1, Support.JUMP, 0)
	var airtime := 1
	for _frame: int in 120:
		stage.run(1, Support.JUMP, 0)
		airtime += 1
		if stage.a.grounded:
			break
	# One frame of slack: jump_frames() integrates from the ground, while the
	# fighter also has to collide with it to know it has landed.
	_s.check(
		absi(airtime - stage.tuning.jump_frames()) <= 1,
		"jump_frames() is %d and the fighter took %d" % [stage.tuning.jump_frames(), airtime]
	)
	stage.dispose()


## The whole reason DuelTuning exists. The adventure's grammar — 2-tile hop,
## 3-tile step, 4-tile grab, 3-tile gap — is pinned by other tests and every
## level depends on it, so the duel must not be able to retune it by accident.
func _the_fighter_never_reads_the_adventure_tuning() -> void:
	for path: String in [
		"res://scripts/duel/fighter.gd",
		"res://scripts/duel/duel_tuning.gd",
		"res://scripts/duel/combat.gd",
		"res://scripts/duel/combat_blade.gd",
	]:
		var file := FileAccess.open(path, FileAccess.READ)
		if not _s.check(file != null, "%s can be read" % path):
			continue
		var text := file.get_as_text()
		file.close()
		# Every legitimate mention is of DuelTuning; strip those and nothing
		# that reaches into Tuning may be left.
		var stripped := text.replace("DuelTuning", "").replace("duel_tuning", "")
		_s.check(
			not stripped.contains("Tuning."),
			"%s does not reach into the adventure's Tuning" % path
		)


## The matrix's duck and roll columns are geometry, not special cases: the
## bands are cut so a 13px duck is already under HIGH and a 7px roll is already
## under HIGH and MID. If these stop holding, tests/combat_matrix_test.gd stops
## testing the table and starts testing a coincidence.
func _the_stance_bands_produce_the_matrix_geometry() -> void:
	var tuning := DuelTuning.default()
	var feet := Vector2(100.0, 100.0)
	var postures := {
		"standing": tuning.body_height, "ducking": tuning.duck_height,
		"rolling": tuning.roll_height,
	}
	var reachable := {
		"standing": ["HIGH", "MID", "LOW"], "ducking": ["MID", "LOW"], "rolling": ["LOW"],
	}
	for posture: String in postures:
		var height: float = postures[posture]
		var body := Rect2(feet.x - 4.5, feet.y - height, 9.0, height)
		for stance: int in [
			DuelTuning.Stance.HIGH, DuelTuning.Stance.MID, DuelTuning.Stance.LOW
		]:
			var names: Array[String] = ["HIGH", "MID", "LOW"]
			var label := names[stance]
			var blade := tuning.blade_rect(feet, 1, stance, tuning.blade_reach)
			# Same x as the body, so only the heights decide.
			blade.position.x = body.position.x
			var hits: bool = blade.intersects(body)
			_s.equal(
				hits, reachable[posture].has(label),
				"a %s blade %s reach a %s fighter" % [
					label, "does" if reachable[posture].has(label) else "does not", posture
				]
			)
	_s.check(
		tuning.roll_height / tuning.body_height < 0.36,
		"the roll really is about a third of standing height"
	)
