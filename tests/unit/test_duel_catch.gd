extends GutTest
## The catch's invariants that need no physics frame
## (scripts/duel/duel_tuning.gd, fighter.gd, combat.gd).
##
## The catch is played out frame by frame in tests/fighter_frames_test.gd and
## tests/combat_sword_test.gd, which have to step fighters inside a physics
## frame. What is here is what can be said without stepping anything: where
## the hands reach, that a blade cannot skip over them between two frames, that
## the snapshot's state numbers did not move, and that two blades caught on the
## same frame are both resolved whichever fighter is seat A. DuelCombat.resolve
## moves nothing, so it can be called on fighters put into a state by hand.

const FIGHTER_SCENE := preload("res://scenes/fighter.tscn")
const FEET := Vector2(200.0, 160.0)

var _tuning := DuelTuning.new()


## The one inequality that makes a frame-sampled catch honest: in one frame a
## throw moves less than the hands are deep, so a blade coming at the front of
## a body is inside the hands on at least one frame before it is inside the
## body. Without it the "catch wins the tie" rule would be a coin toss on the
## gap between the fighters.
func test_a_throw_cannot_step_over_the_hands_in_one_frame() -> void:
	var per_frame := _tuning.throw_speed / 60.0
	assert_true(_tuning.catch_reach >= per_frame,
		"catch_reach %.1f px against %.1f px of throw per frame"
			% [_tuning.catch_reach, per_frame])


func test_the_hands_reach_a_high_and_a_mid_throw_and_not_a_low_one() -> void:
	var hands := _tuning.catch_rect(FEET, -1)
	var from := FEET + Vector2(hands.position.x - FEET.x - 1.0, 0.0)
	for stance: int in [DuelTuning.Stance.HIGH, DuelTuning.Stance.MID]:
		var blade := _blade_at_height(stance, from)
		assert_true(blade.intersects(hands), "a %s throw meets the hands"
			% DuelTuning.Stance.keys()[stance])
	var low := _blade_at_height(DuelTuning.Stance.LOW, from)
	assert_false(low.intersects(hands), "a LOW throw passes under them")


func test_the_hands_are_in_front_and_only_in_front() -> void:
	var right := _tuning.catch_rect(FEET, 1)
	var left := _tuning.catch_rect(FEET, -1)
	var half := _tuning.body_width * 0.5
	assert_almost_eq(right.position.x, FEET.x + half, 0.001, "facing right, they start at the body")
	assert_almost_eq(left.end.x, FEET.x - half, 0.001, "facing left, they end at it")
	assert_almost_eq(right.size.x, _tuning.catch_reach, 0.001, "catch_reach deep")


func test_a_caught_blade_is_held_high_or_mid() -> void:
	assert_eq(_tuning.catch_stance(_tuning.band_high_bottom + 1.0), DuelTuning.Stance.HIGH)
	assert_eq(_tuning.catch_stance(_tuning.band_high_bottom - 1.0), DuelTuning.Stance.MID)
	assert_eq(_tuning.catch_stance(2.0), DuelTuning.Stance.MID, "never LOW")


## The state travels in the snapshot as its ordinal. The two catch states were
## appended so that every older state kept its number; a build that sorted them
## in among the unarmed states would change what every snapshot byte means.
func test_the_catch_states_were_appended_and_moved_no_one() -> void:
	assert_eq(int(Fighter.State.DOWNED), 10)
	assert_eq(int(Fighter.State.DEAD), 11)
	assert_eq(int(Fighter.State.SNATCH), 12)
	assert_eq(int(Fighter.State.CATCH), 13)
	assert_eq(Fighter.state_bytes(), 100, "and the fighter's block is the same 100 bytes")


func test_closed_hands_reach_nothing() -> void:
	var fighter := _fighter(0, FEET, 1)
	assert_eq(fighter.catch_rect(), Rect2(), "standing")
	fighter.blade.drop(FEET, DuelTuning.Stance.MID, -1, _tuning)
	fighter.state = Fighter.State.SNATCH
	fighter.state_frame = _tuning.catch_window
	assert_ne(fighter.catch_rect(), Rect2(), "open on the last frame of the window")
	fighter.state_frame = _tuning.catch_window + 1
	assert_eq(fighter.catch_rect(), Rect2(), "closed on the frame after it")


## Both fighters threw at each other, both snatched, and both blades arrive in
## the open hands on the same frame. Each catch swaps records between the two
## seats, so a resolver that walked the seats would find the second blade moved
## into a seat it had already visited and leave it in the air for a frame. Both
## must be caught, in either seat order.
func test_two_blades_crossing_into_two_pairs_of_hands_are_both_caught() -> void:
	for order: int in 2:
		var a := _fighter(0, FEET, 1)
		var b := _fighter(1, FEET + Vector2(60.0, 0.0), -1)
		# Both swords leave both hands first: open hands are empty hands.
		for thrower: Fighter in [a, b]:
			thrower.blade.mode = DuelBlade.Mode.FLYING
			thrower.blade.thrown_by = thrower.id
			thrower.blade.stance = DuelTuning.Stance.MID
			thrower.blade.velocity = Vector2(thrower.facing * _tuning.throw_speed, 0.0)
			thrower.state = Fighter.State.SNATCH
			thrower.state_frame = 1
		for pair: Array in [[a, b], [b, a]]:
			var thrower: Fighter = pair[0]
			var catcher: Fighter = pair[1]
			var hands := catcher.catch_rect()
			assert_ne(hands, Rect2(), "order %d: seat %d's hands are open" % [order, catcher.id])
			thrower.blade.position = hands.get_center()
		var events := DuelCombat.resolve(a, b) if order == 0 else DuelCombat.resolve(b, a)
		var caught := events.filter(func(e: Dictionary) -> bool: return e["kind"] == "catch")
		assert_eq(caught.size(), 2, "order %d: both blades caught on the frame" % order)
		assert_true(a.is_armed() and b.is_armed(), "order %d: both fighters armed" % order)
		assert_eq(a.state, Fighter.State.CATCH, "order %d: A in the catch" % order)
		assert_eq(b.state, Fighter.State.CATCH, "order %d: B in the catch" % order)
		assert_ne(a.blade, b.blade, "order %d: two swords, not one in two hands" % order)


func _blade_at_height(stance: int, at: Vector2) -> Rect2:
	var hand := _tuning.hand_position(FEET, 1, stance)
	return _tuning.loose_blade_rect(Vector2(at.x, hand.y))


func _fighter(seat: int, feet: Vector2, facing: int) -> Fighter:
	var fighter := FIGHTER_SCENE.instantiate() as Fighter
	add_child_autofree(fighter)
	fighter.setup(seat, _tuning)
	fighter.respawn_at(feet, facing)
	return fighter
