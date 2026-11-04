extends GutTest
## The duel's fairness at the blade: a LOW guard you can hold standing still,
## footwork that gives ground without turning, a duck that is a dodge and not
## a stance to stab from, a roll that costs something, and a dive kick that
## buys a reset rather than a kill (scripts/duel/fighter.gd, combat.gd,
## duel_tuning.gd; docs/duel-combat.md, "Stance, footwork and the duck" and
## "The roll and the dive kick").
##
## Each was a dominant line before: a bot that only ever thrust LOW beat EASY
## 24 times in 24, because down on the spot was a duck and a duck dies to LOW;
## two rolls chained kept a fighter 7 px tall for 116 frames in 120; and a dive
## kick put its target down for 45 frames while the kicker got up in 10, so
## the LOW thrust after it killed every time.
##
## Played out on the real fighter on the flat stage of tests/fighter_support.gd,
## inside a physics frame (await one, then run), because move_and_collide()
## only answers inside one.

const Support := preload("res://tests/fighter_support.gd")

const HIGH := DuelTuning.Stance.HIGH
const MID := DuelTuning.Stance.MID
const LOW := DuelTuning.Stance.LOW
const DUCK := Support.DOWN | Support.WALK
## A thrust reaches a body at 27 px between the feet and a resting blade at
## 34: at 20 it can kill, at 30 only the blades meet.
const BODY_GAP := 20.0
const BLADE_GAP := 30.0


## --- the LOW guard ------------------------------------------------------------

## Down standing still is the LOW guard: it parries a LOW thrust, from either
## side. It used to be the duck, which the matrix kills with LOW.
func test_down_standing_still_parries_a_low_thrust() -> void:
	await wait_physics_frames(1)
	for mirrored: bool in [false, true]:
		var stage := Support.build(get_tree().root)
		stage.place(BODY_GAP)
		var attacker := stage.b if mirrored else stage.a
		var defender := stage.a if mirrored else stage.b
		_feed(stage, mirrored, 3, Support.DOWN, Support.DOWN)
		var label := " (mirrored)" if mirrored else ""
		assert_eq(defender.state, Fighter.State.IDLE, "standing, not ducking" + label)
		assert_eq(defender.posture(), LOW, "holding LOW" + label)
		assert_eq(defender.hurt_rect().size.y, stage.tuning.body_height, "at full height" + label)
		_feed(stage, mirrored, 1, Support.DOWN | Support.ATTACK, Support.DOWN)
		_feed(stage, mirrored, 6, Support.DOWN, Support.DOWN)
		assert_true(defender.is_alive() and attacker.is_alive(), "nobody dies" + label)
		assert_true(stage.saw("clash"), "the LOW thrust is parried" + label)
		stage.dispose()


## The read, at LOW: a blade dropped into a LOW thrust in its opening frames
## takes the attacker's sword, from a standstill.
func test_dropping_into_a_low_thrust_disarms_it() -> void:
	await wait_physics_frames(1)
	var stage := Support.build(get_tree().root)
	stage.place(BLADE_GAP)
	stage.run(3, 0, 0)
	stage.run(1, Support.DOWN | Support.ATTACK, 0)
	stage.run(1, Support.DOWN, Support.DOWN)
	assert_false(stage.a.is_armed(), "the attacker lost the sword")
	assert_eq(stage.a.state, Fighter.State.DISARMED, "and reels")
	assert_true(stage.b.is_alive(), "the reader stands")
	assert_eq(stage.b.state, Fighter.State.IDLE, "on its feet, not in a duck")
	stage.dispose()


## Standing up out of a duck into LOW is the blade arriving at LOW as surely as
## pressing down is: a duck holds no height at all. So it reads too.
func test_rising_from_a_duck_into_low_is_a_read() -> void:
	await wait_physics_frames(1)
	var stage := Support.build(get_tree().root)
	stage.place(BLADE_GAP)
	stage.run(3, 0, DUCK)
	stage.run(1, Support.DOWN | Support.ATTACK, DUCK)
	stage.run(1, Support.DOWN, Support.DOWN)
	assert_false(stage.a.is_armed(), "coming up into the LOW thrust disarms it")
	stage.dispose()


## --- WALK ---------------------------------------------------------------------

## WALK gives ground facing the opponent, slowly; a run turns round. Backing off
## with WALK, a MID guard still parries the MID thrust that follows it.
func test_walk_backs_off_without_turning_and_keeps_the_guard() -> void:
	await wait_physics_frames(1)
	var stage := Support.build(get_tree().root)
	stage.place(BODY_GAP)
	var from := stage.b.position.x
	stage.run(3, 0, Support.RIGHT | Support.WALK)
	assert_eq(stage.b.facing, -1, "still facing the opponent")
	assert_gt(stage.b.position.x, from, "and further away")
	assert_almost_eq(absf(stage.b.velocity.x), stage.tuning.walk_speed, 0.5, "at walk_speed")
	stage.run(1, Support.ATTACK, Support.RIGHT | Support.WALK)
	stage.run(5, 0, Support.RIGHT | Support.WALK)
	assert_true(stage.b.is_alive(), "the guard is still toward the thrust")
	assert_true(stage.saw("clash"), "and turns it aside")
	stage.dispose()

	stage = Support.build(get_tree().root)
	stage.place(BODY_GAP)
	stage.run(2, 0, Support.RIGHT)
	assert_eq(stage.b.facing, 1, "without WALK the same direction turns the back")
	stage.run(1, Support.ATTACK, Support.RIGHT)
	stage.run(4, 0, Support.RIGHT)
	assert_false(stage.b.is_alive(), "and a back is cut")
	stage.dispose()


## --- the duck -----------------------------------------------------------------

## The duck is down with WALK: planted, 13 px tall, under a HIGH thrust.
func test_the_duck_is_down_with_walk_and_goes_under_high() -> void:
	await wait_physics_frames(1)
	var stage := Support.build(get_tree().root)
	stage.place(BODY_GAP)
	stage.run(3, 0, DUCK | Support.LEFT)
	assert_eq(stage.b.state, Fighter.State.DUCKING, "DUCKING")
	assert_eq(stage.b.posture(), DuelTuning.DUCKED, "the matrix's fourth column")
	assert_eq(stage.b.velocity.x, 0.0, "planted, whatever the stick says")
	stage.run(1, Support.UP | Support.ATTACK, DUCK)
	stage.run(5, Support.UP, DUCK)
	assert_true(stage.b.is_alive(), "the HIGH thrust passes over")
	assert_false(stage.saw("clash"), "touching nothing")
	stage.dispose()


## A thrust is made standing: out of a duck the body comes up into it. So a
## thrust from a duck against a HIGH thrust on the same frame is two thrusts at
## different heights -- both land -- and two of them are a clash. The duck used
## to persist into the thrust: it beat the HIGH thrust outright and two of them
## double-killed.
func test_a_thrust_out_of_a_duck_is_made_standing() -> void:
	await wait_physics_frames(1)
	var stage := Support.build(get_tree().root)
	stage.place(BODY_GAP)
	stage.run(3, 0, DUCK)
	stage.run(1, Support.UP | Support.ATTACK, DUCK | Support.ATTACK)
	stage.run(5, 0, 0)
	assert_false(stage.a.is_alive(), "the ducker's LOW blade lands")
	assert_false(stage.b.is_alive(), "and so does the HIGH one: it stood up into it")
	stage.dispose()

	stage = Support.build(get_tree().root)
	stage.place(BODY_GAP)
	stage.run(3, DUCK, DUCK)
	stage.run(1, DUCK | Support.ATTACK, DUCK | Support.ATTACK)
	assert_eq(stage.a.hurt_rect().size.y, stage.tuning.body_height, "standing in the thrust")
	stage.run(5, 0, 0)
	assert_true(stage.a.is_alive() and stage.b.is_alive(), "two of them clash, nobody dies")
	assert_true(stage.saw("clash"), "a clash")
	stage.dispose()


## --- the roll -----------------------------------------------------------------

## A roll ends in roll_recover frames of RISING: standing height, no blade up,
## no input read. Then the fighter is free.
func test_a_roll_ends_in_recovery() -> void:
	await wait_physics_frames(1)
	var stage := Support.build(get_tree().root)
	var tuning := stage.tuning
	assert_between(tuning.roll_recover, 6, 8, "six to eight frames of recovery")
	stage.place(200.0)
	stage.run(1, Support.DOWN | Support.JUMP, 0)
	stage.run(tuning.roll_frames, 0, 0)
	for frame: int in range(1, tuning.roll_recover + 1):
		assert_eq(stage.a.state, Fighter.State.RISING, "frame %d of the rise" % frame)
		assert_eq(stage.a.hurt_rect().size.y, tuning.body_height, "standing height")
		assert_eq(stage.a.blade_rect(), Rect2(), "no blade up")
		if frame < tuning.roll_recover:
			# Presses into the rise: each one a fresh edge, every one ignored.
			stage.run(1, Support.ATTACK if frame % 2 == 1 else 0, 0)
	stage.run(1, 0, 0)
	assert_true(stage.a.is_free(), "free after the rise")
	assert_ne(stage.a.state, Fighter.State.THRUSTING, "and nothing pressed in it happened")
	stage.dispose()


## Rolls chained as fast as the buttons allow stand up for roll_recover frames
## between each, instead of the 116 frames in 120 at roll height a free roll
## allowed.
func test_chained_rolls_stand_up_between() -> void:
	await wait_physics_frames(1)
	var stage := Support.build(get_tree().root)
	var tuning := stage.tuning
	stage.place(40.0)
	stage.a.respawn_at(Vector2(Support.TILE * 2.0, stage.ground_y()), 1)
	stage.run(3, 0, 0)
	var low := 0
	var last := 0
	for _frame: int in 120:
		var bits := Support.RIGHT
		if stage.a.is_free() and (last & Support.JUMP) == 0:
			bits |= Support.DOWN | Support.JUMP
		stage.run(1, bits, 0)
		last = bits
		if stage.a.hurt_rect().size.y <= tuning.roll_height:
			low += 1
	@warning_ignore("integer_division")
	var standing := (120 / (tuning.roll_frames + tuning.roll_recover)) * tuning.roll_recover
	gut.p("chained rolls: %d of 120 frames at roll height" % low)
	assert_lte(low, 120 - standing, "standing up between rolls")
	assert_lt(low, 110, "not the 116 in 120 of a roll that cost nothing")
	stage.dispose()


## Into the rise, any height cuts: there is no blade up to parry with.
func test_a_thrust_into_the_rise_kills() -> void:
	await wait_physics_frames(1)
	for height: int in [HIGH, MID, LOW]:
		var stage := Support.build(get_tree().root)
		stage.place(BODY_GAP)
		var bits := Support.stance_bits(height)
		stage.run(3, bits, bits)
		stage.b.state = Fighter.State.RISING
		stage.b.state_frame = 1
		stage.run(1, bits | Support.ATTACK, bits)
		stage.run(3, bits, bits)
		assert_false(stage.b.is_alive(), "a %s thrust kills a rising fighter holding %s"
			% [DuelTuning.Stance.keys()[height], DuelTuning.Stance.keys()[height]])
		stage.dispose()


## --- the dive kick ------------------------------------------------------------

## A kicked fighter is up, blade raised, before the kicker can move: a LOW
## thrust on the kicker's first free frame meets a LOW guard, not a body on the
## floor. And the sweep -- the empty hand's way back -- keeps its long one.
func test_a_dive_kick_buys_a_reset_not_a_kill() -> void:
	await wait_physics_frames(1)
	var stage := Support.build(get_tree().root)
	var tuning := stage.tuning
	assert_lt(tuning.kick_downed_frames, tuning.divekick_recover,
		"the kick's knockdown is shorter than the kicker's landing")
	assert_gt(tuning.downed_frames, tuning.divekick_recover, "the sweep's is not")
	stage.place(46.0)
	var phase := 0
	var kicked := -1
	var b_up := -1
	var a_free := -1
	for frame: int in 160:
		var bits := 0
		match phase:
			0:
				bits = Support.RIGHT | Support.JUMP
				if frame > 0 and stage.a.velocity.y >= -20.0:
					phase = 1
			1:
				bits = Support.RIGHT
				phase = 2
			2:
				bits = Support.RIGHT | Support.DOWN | Support.JUMP
				phase = 3
			3:
				if kicked >= 0 and stage.a.is_free() and stage.a.grounded:
					a_free = frame
					var toward := Support.RIGHT if stage.b.position.x > stage.a.position.x \
						else Support.LEFT
					bits = toward if stage.a.facing != _sign(toward) else Support.DOWN | Support.ATTACK
					if bits & Support.ATTACK:
						phase = 4
			4:
				bits = Support.DOWN
		var guard := Support.DOWN if kicked >= 0 else 0
		stage.run(1, bits, guard)
		if kicked < 0 and stage.b.state == Fighter.State.DOWNED:
			kicked = frame
		if kicked >= 0 and b_up < 0 and stage.b.is_free():
			b_up = frame
		if phase == 4 and stage.a.state != Fighter.State.THRUSTING:
			break
	assert_gte(kicked, 0, "the kick landed")
	assert_gte(a_free, 0, "the kicker got up")
	assert_true(b_up >= 0 and b_up < a_free, "the kicked fighter was up first (%d, %d)"
		% [b_up, a_free])
	assert_true(stage.b.is_alive(), "and its LOW guard met the follow-up")
	stage.dispose()


func _feed(stage: Support.Stage, mirrored: bool, frames: int, att: int, def: int) -> void:
	if mirrored:
		stage.run(frames, def, att)
	else:
		stage.run(frames, att, def)


func _sign(direction_bits: int) -> int:
	return 1 if direction_bits == Support.RIGHT else -1
