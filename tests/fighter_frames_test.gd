extends SceneTree
## The three windows the duel is actually played in, frame by frame.
##
##     godot --headless --script tests/fighter_frames_test.gd
##
##   * the thrust: 14 frames, lethal on 1 to 4, recovering and vulnerable after
##   * the roll: 25 frames, compressed to under a third of standing height,
##     with NO invulnerability — a LOW thrust kills a rolling fighter
##   * the disarm: a read that only pays inside the opening frames of the
##     opponent's thrust, and never pays against someone who is not attacking
##
## These are closed intervals over Fighter.state_frame, which is why they can
## be asserted at all: the physics tick is a fixed 60 Hz, so one frame is one
## simulation step and the spec's numbers are literal.

const Support := preload("res://tests/fighter_support.gd")

## Far enough apart that nothing either fighter does can reach the other.
const CLEAR := 120.0
## Between body range (~27px) and blade range (~34px): the blades can meet but
## the thrust cannot reach the body. This is where a disarm read happens, and
## it has to be, because at body range the first frame of a thrust has already
## killed anyone standing at a different height.
const BLADE_GAP := 31.0

var _s := Support.new()
var _warm := 0


func _physics_process(_delta: float) -> bool:
	_warm += 1
	if _warm < 2:
		return false

	_the_thrust_is_active_on_its_first_four_frames()
	_the_thrust_locks_its_stance_for_the_whole_swing()
	_the_roll_is_compressed_for_twenty_five_frames()
	_the_roll_goes_under_high_and_mid_and_not_under_low()
	_the_disarm_window_is_the_opening_of_the_thrust()
	_a_held_stance_parries_where_a_changed_one_disarms()
	_an_opponent_who_is_not_attacking_cannot_be_disarmed()

	quit(_s.report("fighter_frames"))
	return true


## --- the thrust -------------------------------------------------------------

func _the_thrust_is_active_on_its_first_four_frames() -> void:
	var stage := Support.build(root)
	stage.place(CLEAR)
	var fighter := stage.a
	var tuning := stage.tuning

	_s.check(
		tuning.thrust_frames >= 12 and tuning.thrust_frames <= 15,
		"the thrust is 12 to 15 frames (%d)" % tuning.thrust_frames
	)
	stage.run(1, Support.ATTACK, 0)
	for frame: int in range(1, tuning.thrust_frames + 1):
		if frame > 1:
			stage.run(1, 0, 0)
		var active := frame <= tuning.thrust_active
		_s.equal(fighter.state, Fighter.State.THRUSTING, "frame %d is still the thrust" % frame)
		_s.equal(fighter.state_frame, frame, "the thrust is on frame %d" % frame)
		_s.equal(fighter.is_attacking(), active, "frame %d: attacking is %s" % [frame, active])
		_s.equal(
			fighter.blade_rect().size.x > 0.0, active,
			"frame %d: the blade is %s" % [frame, "extended" if active else "out of position"]
		)
		if active:
			_s.equal(
				fighter.blade_rect().size.x, tuning.blade_reach,
				"frame %d reaches the full thrust" % frame
			)

	stage.run(1, 0, 0)
	_s.equal(
		fighter.state, Fighter.State.IDLE,
		"the %dth frame is free again" % (tuning.thrust_frames + 1)
	)
	stage.dispose()


## Zero frames of animation lock belongs to the free states. A thrust is a
## commitment: if its height could still be changed, one button would sweep an
## active blade through all three bands and the disarm read below would be
## meaningless.
func _the_thrust_locks_its_stance_for_the_whole_swing() -> void:
	var stage := Support.build(root)
	stage.place(CLEAR)
	stage.run(1, Support.UP | Support.ATTACK, 0)
	_s.equal(stage.a.stance, DuelTuning.Stance.HIGH, "the thrust went out HIGH")
	stage.run(4, Support.DOWN, 0)
	_s.equal(stage.a.stance, DuelTuning.Stance.HIGH, "holding down does not lower a live blade")
	_s.check(not stage.a.stance_changed, "and no stance change is reported during a thrust")

	# Out of the thrust, the stance follows the button again immediately.
	stage.run(tuning_frames(stage) + 1, Support.DOWN, 0)
	_s.equal(stage.a.stance, DuelTuning.Stance.LOW, "the stance is free again the moment it is")
	stage.dispose()


func tuning_frames(stage: Support.Stage) -> int:
	return stage.tuning.thrust_frames


## --- the roll ---------------------------------------------------------------

func _the_roll_is_compressed_for_twenty_five_frames() -> void:
	var stage := Support.build(root)
	stage.place(CLEAR)
	var tuning := stage.tuning
	_s.equal(tuning.roll_frames, 25, "the roll is 25 frames")

	stage.run(1, Support.DOWN | Support.JUMP, 0)
	var ratio := stage.a.hurt_rect().size.y / tuning.body_height
	_s.check(
		ratio > 0.25 and ratio < 0.36,
		"the rolling hurtbox is about 30%% of standing height (%.0f%%)" % (ratio * 100.0)
	)
	for frame: int in range(1, tuning.roll_frames + 1):
		if frame > 1:
			stage.run(1, 0, 0)
		_s.equal(stage.a.state, Fighter.State.ROLLING, "frame %d is still the roll" % frame)
	stage.run(1, 0, 0)
	_s.check(stage.a.state != Fighter.State.ROLLING, "the 26th frame is out of the roll")
	stage.dispose()


func _the_roll_goes_under_high_and_mid_and_not_under_low() -> void:
	for spec: Array in [
		[DuelTuning.Stance.HIGH, true, "HIGH passes over a roll"],
		[DuelTuning.Stance.MID, true, "MID passes over a roll"],
		[DuelTuning.Stance.LOW, false, "LOW kills a rolling fighter"],
	]:
		var stage := Support.build(root)
		stage.place(20.0)
		var att_bits: int = Support.stance_bits(
			DuelTuning.DUCKED if spec[0] == DuelTuning.Stance.LOW else spec[0]
		)
		# B is already rolling when the thrust goes out, and rolls into it.
		stage.run(1, att_bits, Support.DOWN | Support.JUMP)
		_s.equal(stage.b.state, Fighter.State.ROLLING, "the defender is rolling")
		stage.run(1, att_bits | Support.ATTACK, 0)
		stage.run(4, att_bits, 0)
		_s.equal(stage.b.is_alive(), spec[1], spec[2])
		stage.dispose()


## --- the disarm -------------------------------------------------------------

## The spec's pseudocode gates a disarm on the defender changing stance and the
## attacker not — and never checks that the attacker is attacking at all, so as
## written you disarm a motionless opponent by waving your blade at their
## resting one. docs/duel-spec.md flags that; this is the resolution it
## proposes: the read only pays inside the opening frames of a real thrust.
func _the_disarm_window_is_the_opening_of_the_thrust() -> void:
	var window := 0
	for read_on: int in range(1, 9):
		var stage := Support.build(root)
		stage.place(BLADE_GAP)
		var expected := read_on <= stage.tuning.disarm_window
		# B holds HIGH, out of the way of a MID thrust and out of body reach,
		# then drops to MID on frame `read_on` of that thrust.
		stage.run(3, 0, Support.UP)
		if read_on == 1:
			# The read lands on the very frame the blade goes out.
			stage.run(1, Support.ATTACK, 0)
		else:
			stage.run(1, Support.ATTACK, Support.UP)
			if read_on > 2:
				stage.run(read_on - 2, 0, Support.UP)
			stage.run(1, 0, 0)

		var disarmed := not stage.a.is_armed()
		if disarmed:
			window = maxi(window, read_on)
		_s.equal(
			disarmed, expected,
			"a stance change on thrust frame %d %s disarm" % [
				read_on, "does" if expected else "does not"
			]
		)
		if expected:
			_s.equal(stage.a.state, Fighter.State.DISARMED, "frame %d: and it shows" % read_on)
			_s.check(stage.saw("disarm"), "frame %d: and it is reported" % read_on)
			_s.check(stage.a.is_alive(), "frame %d: a disarm is not a kill" % read_on)
		stage.dispose()
	_s.equal(window, 5, "the window is five frames wide")


## Same geometry, same stances, one difference: whether the defender's blade
## arrived this frame or was already there. That difference is the whole skill
## ceiling of the system.
func _a_held_stance_parries_where_a_changed_one_disarms() -> void:
	var stage := Support.build(root)
	stage.place(BLADE_GAP)
	stage.run(4, 0, 0) # B simply stands at MID
	stage.run(1, Support.ATTACK, 0)
	stage.run(1, 0, 0)
	_s.check(stage.a.is_armed(), "a stance that was already there does not disarm")
	_s.check(stage.saw("clash"), "it parries instead")
	stage.dispose()


func _an_opponent_who_is_not_attacking_cannot_be_disarmed() -> void:
	var stage := Support.build(root)
	stage.place(BLADE_GAP)
	# B cycles through every stance next to a motionless A for a full second.
	var cycle := [0, Support.UP, 0, Support.DOWN]
	for frame: int in 60:
		stage.run(1, 0, cycle[frame % cycle.size()])
	_s.check(stage.a.is_armed(), "waving a blade at a resting one disarms nobody")
	_s.check(stage.b.is_armed(), "and the waving fighter keeps its own sword")
	_s.check(not stage.saw("disarm"), "nothing was reported as a disarm")
	stage.dispose()
