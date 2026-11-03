extends SceneTree
## The four windows the duel is actually played in, frame by frame.
##
##     godot --headless --script tests/fighter_frames_test.gd
##
##   * the thrust: 14 frames, lethal on 1 to 4, recovering and vulnerable after
##   * the roll: 25 frames, compressed to under a third of standing height,
##     with NO invulnerability — a LOW thrust kills a rolling fighter
##   * the disarm: a read that only pays inside the opening frames of the
##     opponent's thrust, and never pays against someone who is not attacking
##   * the catch: an empty hand's snatch is open for its first six frames, and
##     the edges of when a snatch takes a thrown sword are played, not assumed
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
	_the_snatch_opens_the_hands_for_its_first_frames()
	_the_catch_window_edges()

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


## --- the catch --------------------------------------------------------------

## Far enough that a throw takes a few frames to reach the hands, so a snatch
## can be early, on time or late; the same gap combat_sword_test throws across.
const CATCH_GAP := 40.0


## THROW with an empty hand is a snatch: open hands on frames 1..catch_window,
## then recovery to snatch_frames, then free. With a sword in hand the same
## button throws it, and never opens the hands.
func _the_snatch_opens_the_hands_for_its_first_frames() -> void:
	var stage := Support.build(root)
	stage.place(CLEAR)
	var tuning := stage.tuning
	var fighter := stage.a
	fighter.disarm(1)
	stage.run(tuning.disarmed_frames + 2, 0, 0)
	_s.check(fighter.is_free() and not fighter.is_armed(), "A is free and empty-handed")
	_s.check(
		tuning.catch_window < tuning.snatch_frames,
		"the snatch is longer than its window (%d of %d)"
			% [tuning.catch_window, tuning.snatch_frames]
	)

	stage.run(1, Support.THROW, 0)
	for frame: int in range(1, tuning.snatch_frames + 1):
		if frame > 1:
			stage.run(1, 0, 0)
		var open := frame <= tuning.catch_window
		_s.equal(fighter.state, Fighter.State.SNATCH, "frame %d is still the snatch" % frame)
		_s.equal(fighter.state_frame, frame, "the snatch is on frame %d" % frame)
		_s.equal(fighter.hands_open(), open, "frame %d: the hands are open: %s" % [frame, open])
		_s.equal(
			fighter.catch_rect().size.x > 0.0, open,
			"frame %d: the hands %s" % [frame, "reach" if open else "reach nothing"]
		)
	stage.run(1, 0, 0)
	_s.equal(
		fighter.state, Fighter.State.IDLE,
		"the %dth frame is free again" % (tuning.snatch_frames + 1)
	)

	stage.run(1, 0, Support.THROW)
	_s.check(stage.b.state != Fighter.State.SNATCH, "an armed fighter's THROW never snatches")
	_s.equal(stage.b.blade.mode, DuelBlade.Mode.FLYING, "it throws")
	_s.check(not stage.b.hands_open(), "and its hands are not open")
	stage.dispose()


## The edges of the catch, by playing them. A throws across CATCH_GAP on frame
## 0; B, empty-handed, snatches on frame `press`; every press from too early to
## too late is tried in a fresh stage.
##
## First a run with no snatch says where the window has to sit: on which frame
## the blade first touches the hands' rect, and on which it reaches the body and
## kills. Then the rule, derived rather than chosen:
##
##   * the hands are open on frames press .. press + catch_window - 1
##   * they catch if they are open on any frame the blade is in them, up to and
##     including the frame it reaches the body -- the tie goes to the hands
##
## so the presses that catch are exactly first_hands - catch_window + 1 through
## first_body. One earlier and the hands have closed before the blade arrives,
## and the fighter dies in the recovery; one later and the fighter is dead.
func _the_catch_window_edges() -> void:
	var tuning := DuelTuning.new()
	var control := _catch_run(9999)
	var first_hands := int(control["hands"])
	var first_body := int(control["body"])
	_s.check(first_hands > 0, "the blade reaches the hands' rect in flight (frame %d)"
		% first_hands)
	_s.check(first_body > first_hands, "and the body after it (frame %d)" % first_body)
	_s.check(bool(control["dead"]), "with no snatch the throw kills")

	var earliest := first_hands - tuning.catch_window + 1
	var latest := first_body
	var wrong: Array[String] = []
	var caught := 0
	for press: int in range(earliest - 3, latest + 3):
		var run := _catch_run(press)
		var expected := press >= earliest and press <= latest
		if bool(run["caught"]):
			caught += 1
		if bool(run["caught"]) != expected:
			wrong.append("press %d caught=%s" % [press, run["caught"]])
		elif not expected and not bool(run["dead"]):
			wrong.append("press %d neither caught nor died" % press)
	_s.equal(wrong, [] as Array[String], "every press from frame %d to %d catches, no other"
		% [earliest, latest])
	_s.equal(caught, latest - earliest + 1, "the catching presses are one unbroken run")
	_s.equal(
		caught, first_body - first_hands + tuning.catch_window,
		"as wide as the window plus the frames the blade spends in the hands"
	)

	var early := _catch_run(earliest - 1)
	_s.check(
		bool(early["dead"]) and not bool(early["caught"]),
		"one frame early: the hands closed before it came, and the snatch's recovery dies"
	)
	var tie := _catch_run(latest)
	_s.check(
		bool(tie["caught"]) and not bool(tie["dead"]),
		"on the very frame it reaches the body the open hands still take it"
	)


## One throw at an empty-handed B who snatches on frame `press` (never, for a
## press past the end). Returns the frame the blade first touched the hands'
## rect, the frame B died (-1 if not), whether B caught it, and whether B died.
func _catch_run(press: int) -> Dictionary:
	var stage := Support.build(root)
	stage.place(CATCH_GAP)
	stage.b.disarm(0)
	stage.run(stage.tuning.disarmed_frames + 2, 0, 0)
	var hands_rect := stage.tuning.catch_rect(stage.b.position, stage.b.facing)
	var out := {"hands": -1, "body": -1, "caught": false, "dead": false}
	for frame: int in range(mini(press, 0), 30):
		stage.step(
			Support.THROW if frame == 0 else 0, Support.THROW if frame == press else 0
		)
		if frame < 0:
			continue
		var blade := stage.a.blade
		var touching := blade.mode != DuelBlade.Mode.HELD \
			and blade.rect(stage.tuning).intersects(hands_rect)
		if int(out["hands"]) < 0 and (touching or stage.saw("catch")):
			out["hands"] = frame
		if not stage.b.is_alive() and int(out["body"]) < 0:
			out["body"] = frame
	out["caught"] = stage.saw("catch")
	out["dead"] = not stage.b.is_alive()
	stage.dispose()
	return out
