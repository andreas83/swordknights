extends GutTest
## The sentinel's rules: harmless until it raises, dangerous only while it
## cuts, and always answerable in between.
##
## Driven through Patrol.tick(), which is a whole frame of decision without a
## physics world, so nothing here depends on a level or on timing. The prince
## is a rectangle, which is all the guard ever sees of him.

const FRAME := 1.0 / 60.0
## The prince's body as Player.body_rect() reports it while standing.
const PRINCE := Vector2(Tuning.BODY_WIDTH, Tuning.BODY_HEIGHT)


func _guard() -> Patrol:
	var guard := Patrol.new()
	guard.facing = 1
	guard.position = Vector2(100.0, 200.0)
	return autofree(guard)


## A prince standing on the guard's floor with `gap` pixels between the
## guard's front and his near side.
func _prince_ahead(guard: Patrol, gap: float) -> Rect2:
	var front := guard.position.x + Patrol.BODY.x * 0.5
	return Rect2(Vector2(front + gap, guard.position.y - PRINCE.y), PRINCE)


func _run(guard: Patrol, seconds: float) -> void:
	for _i: int in roundi(seconds / FRAME):
		guard.tick(FRAME, true)


func test_walking_guard_is_not_dangerous() -> void:
	var guard := _guard()
	guard.target_rect = _prince_ahead(guard, 60.0)
	_run(guard, 0.5)
	assert_eq(guard.state, Patrol.State.WALK)
	assert_false(guard.is_dangerous())
	assert_eq(guard.strike_rect(), Rect2(), "no blade while walking")


func test_a_prince_in_range_gets_the_raise_before_the_cut() -> void:
	var guard := _guard()
	var raised := [0]
	guard.alerted.connect(func() -> void: raised[0] += 1)
	guard.target_rect = _prince_ahead(guard, Patrol.ENGAGE_GAP - 1.0)
	guard.tick(FRAME, true)
	assert_eq(guard.state, Patrol.State.WINDUP)
	assert_eq(raised[0], 1, "alerted fires once, at the start of the raise")
	# Harmless for the whole raise.
	var frames := 1
	while guard.state == Patrol.State.WINDUP:
		assert_false(guard.is_dangerous(), "the raise must never hurt")
		guard.tick(FRAME, true)
		frames += 1
	assert_eq(guard.state, Patrol.State.STRIKE)
	assert_gte(frames, 24, "the telegraph is at least 24 frames long")
	assert_true(guard.is_dangerous())
	assert_true(guard.strike_rect().intersects(_prince_ahead(guard, Patrol.ENGAGE_GAP - 1.0)))


func test_cut_is_followed_by_an_opening() -> void:
	var guard := _guard()
	guard.target_rect = _prince_ahead(guard, 4.0)
	_run(guard, Patrol.WINDUP_TIME + Patrol.STRIKE_TIME + FRAME * 2.0)
	assert_eq(guard.state, Patrol.State.RECOVER)
	assert_false(guard.is_dangerous())


func test_a_hit_during_the_raise_staggers_it_out_of_the_cut() -> void:
	var guard := _guard()
	guard.target_rect = _prince_ahead(guard, 4.0)
	_run(guard, Patrol.WINDUP_TIME * 0.5)
	assert_eq(guard.state, Patrol.State.WINDUP)
	assert_false(guard.hit(guard.position.x - 10.0), "two hits to kill")
	assert_eq(guard.state, Patrol.State.STAGGER)
	_run(guard, Patrol.WINDUP_TIME)
	assert_ne(guard.state, Patrol.State.STRIKE, "a staggered raise does not cut")


## The fairness argument in numbers: when the raise starts, the prince's own
## sword already reaches the guard, and the guard's cut reaches a prince who
## does nothing, so the outcome is decided by who acts on the raise.
func test_reach_relationships() -> void:
	var guard := _guard()
	var prince := _prince_ahead(guard, Patrol.ENGAGE_GAP)
	var guard_front := guard.position.x + Patrol.BODY.x * 0.5
	var sword_tip := prince.position.x - Tuning.ATTACK_REACH
	assert_lte(sword_tip, guard_front, "the prince's sword reaches a guard that is raising")
	assert_gt(Patrol.REACH, Patrol.ENGAGE_GAP, "standing still in front of the raise is cut")
	assert_lt(Patrol.REACH, Patrol.ENGAGE_GAP + Tuning.TILE,
		"one tile of backing off escapes the cut")
	var sword_starts := Tuning.ATTACK_TIME * 0.25
	assert_lt(sword_starts, Patrol.WINDUP_TIME * 0.5,
		"a swing started halfway through the raise still lands first")


func test_prince_on_another_floor_is_ignored() -> void:
	var guard := _guard()
	var rect := _prince_ahead(guard, 4.0)
	rect.position.y -= Tuning.TILE * 2.0
	guard.target_rect = rect
	_run(guard, 0.3)
	assert_eq(guard.state, Patrol.State.WALK, "a prince on the terrace above is not engaged")


func test_prince_on_its_heels_is_heard() -> void:
	var guard := _guard()
	var back := guard.position.x - Patrol.BODY.x * 0.5
	guard.target_rect = Rect2(Vector2(back - PRINCE.x - 2.0, guard.position.y - PRINCE.y), PRINCE)
	_run(guard, Patrol.LOOK_TIME)
	assert_eq(guard.facing, -1, "it turns to face him")


func test_death_is_a_state_not_a_free() -> void:
	var guard := _guard()
	var deaths := [0]
	guard.defeated.connect(func() -> void: deaths[0] += 1)
	guard.hit(0.0)
	_run(guard, Patrol.STAGGER_TIME)
	assert_true(guard.hit(0.0), "second hit kills")
	assert_false(guard.is_alive())
	assert_false(guard.is_dangerous())
	assert_false(guard.hit(0.0), "a falling body cannot be killed twice")
	assert_eq(deaths[0], 1, "defeated fires exactly once")
	guard.target_rect = _prince_ahead(guard, 2.0)
	_run(guard, Patrol.DEATH_TIME * 0.8)
	assert_eq(guard.state, Patrol.State.DYING, "a dying guard never raises")


func test_art_attaches_itself() -> void:
	var guard := _guard()
	add_child(guard)
	var art := guard.get_node_or_null("Art")
	assert_not_null(art, "every guard everywhere is drawn")
	assert_true(art is PatrolArt)
