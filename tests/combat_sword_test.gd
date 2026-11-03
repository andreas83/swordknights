extends SceneTree
## The sword as a thing in the world: thrown, deflected, dropped, picked up.
##
##     godot --headless --script tests/combat_sword_test.gd
##
## A duellist's sword is not a property of the duellist. It is in one of three
## places — in the hand, in the air, on the floor — and either fighter can pick
## up the one on the floor. There are never more than two of them, which is
## what lets the whole of the duel's sword state ride inside the two fighters'
## snapshots with nothing hiding in a third place.

const Support := preload("res://tests/fighter_support.gd")

## Far enough that a thrown sword takes a few frames to arrive, which is what
## makes deflecting one a decision rather than a reflex.
const THROW_GAP := 40.0

var _s := Support.new()
var _warm := 0


func _physics_process(_delta: float) -> bool:
	_warm += 1
	if _warm < 2:
		return false

	_a_throw_leaves_the_hand_and_kills()
	_up_and_throw_angles_the_blade_upward()
	_a_duck_goes_under_a_high_throw_and_a_roll_under_a_mid_one()
	_a_thrust_deflects_a_flying_blade()
	_a_flying_blade_ends_up_on_the_floor()
	_either_fighter_can_pick_up_the_other_ones_sword()
	_dying_drops_the_sword_where_you_fell()
	_respawning_comes_back_with_your_own_sword()

	quit(_s.report("combat_sword"))
	return true


func _a_throw_leaves_the_hand_and_kills() -> void:
	var stage := Support.build(root)
	stage.place(THROW_GAP)
	stage.run(1, Support.THROW, 0)
	_s.check(not stage.a.is_armed(), "the thrower is empty-handed at once")
	_s.equal(stage.a.blade.mode, DuelBlade.Mode.FLYING, "and the sword is in the air")
	_s.equal(stage.a.blade.thrown_by, 0, "the blade remembers who threw it")
	_s.check(
		is_zero_approx(stage.a.blade.velocity.y),
		"a plain throw is parallel to the ground"
	)

	stage.run(10, 0, 0)
	_s.check(not stage.b.is_alive(), "a thrown sword is lethal on contact")
	_s.check(stage.saw("kill"), "and the kill is reported")
	for event: Dictionary in stage.events:
		if event.get("kind", "") == "kill":
			_s.equal(event.get("killer", -2), 0, "credited to the thrower")
	stage.dispose()


func _up_and_throw_angles_the_blade_upward() -> void:
	var stage := Support.build(root)
	stage.place(THROW_GAP)
	stage.run(1, Support.UP | Support.THROW, 0)
	_s.check(stage.a.blade.velocity.y < 0.0, "up and throw angles the blade slightly up")
	var launched := stage.a.blade.position.y
	stage.run(3, 0, 0)
	_s.check(stage.a.blade.position.y < launched, "and it keeps rising")
	stage.dispose()


## The spec's counters to a thrown sword are ducking and rolling, and they work
## for the same reason they work against a thrust: the blade flies at the band
## it was thrown from, and a compressed hurtbox is below it.
func _a_duck_goes_under_a_high_throw_and_a_roll_under_a_mid_one() -> void:
	var stage := Support.build(root)
	stage.place(THROW_GAP)
	stage.run(1, Support.UP | Support.THROW, Support.DOWN)
	stage.run(14, 0, Support.DOWN)
	_s.check(stage.b.is_alive(), "a duck goes under a high throw")
	stage.dispose()

	stage = Support.build(root)
	stage.place(THROW_GAP)
	# The roll has to be running when the blade arrives, not when it is thrown.
	stage.run(1, Support.THROW, 0)
	stage.run(2, 0, Support.DOWN | Support.JUMP)
	_s.equal(stage.b.state, Fighter.State.ROLLING, "the defender is rolling")
	stage.run(10, 0, 0)
	_s.check(stage.b.is_alive(), "a roll goes under a mid throw")
	stage.dispose()

	# And standing up in front of one does not.
	stage = Support.build(root)
	stage.place(THROW_GAP)
	stage.run(1, Support.THROW, 0)
	stage.run(10, 0, 0)
	_s.check(not stage.b.is_alive(), "standing in front of it does not")
	stage.dispose()


func _a_thrust_deflects_a_flying_blade() -> void:
	var stage := Support.build(root)
	stage.place(THROW_GAP)
	stage.run(1, Support.THROW, Support.ATTACK)
	_s.check(stage.saw("deflect"), "a thrust knocks a flying blade out of the air")
	_s.equal(stage.a.blade.mode, DuelBlade.Mode.LOOSE, "the blade stops flying")
	stage.run(20, 0, 0)
	_s.check(stage.b.is_alive(), "and the fighter who deflected it is alive")
	_s.check(stage.a.blade.is_loose(), "with a sword on the floor between them")
	stage.dispose()


func _a_flying_blade_ends_up_on_the_floor() -> void:
	var stage := Support.build(root)
	stage.place(20.0)
	stage.a.facing = -1 # thrown at the far wall, away from the other fighter
	stage.run(1, Support.THROW, 0)
	stage.run(90, 0, 0)
	_s.check(stage.a.blade.is_loose(), "a throw that hits a wall stops being a throw")
	_s.check(stage.a.blade.velocity == Vector2.ZERO, "and comes to rest")
	_s.check(
		stage.a.blade.position.y > stage.ground_y() - 8.0,
		"on the floor, where it can be picked up (y=%.1f)" % stage.a.blade.position.y
	)
	_s.check(stage.b.is_alive(), "and it never went near the other fighter")
	stage.dispose()


## Swords are indistinguishable, so picking up the other fighter's dropped one
## swaps the two records. The count is what matters, and the count is two.
func _either_fighter_can_pick_up_the_other_ones_sword() -> void:
	var stage := Support.build(root)
	stage.place(20.0)
	# A is disarmed and its sword lies at its feet. B throws its own sword at
	# the far wall, so B is empty-handed too and B's record is somewhere else.
	stage.a.disarm(1)
	stage.b.facing = 1
	stage.run(1, 0, Support.THROW)
	stage.b.facing = -1
	stage.run(90, 0, 0)
	_s.check(not stage.a.is_armed() and not stage.b.is_armed(), "both are empty-handed")
	var far := stage.b.blade.position

	# B walks left onto the sword on the floor and presses down.
	var armed_after := 0
	for frame: int in 30:
		stage.run(1, 0, Support.LEFT | Support.DOWN)
		if stage.b.is_armed():
			armed_after = frame + 1
			break
	_s.check(armed_after > 0, "B picked the sword up by standing on it and pressing down")
	_s.check(stage.b.blade.is_held(), "B's record now holds the sword in B's hand")
	_s.check(stage.a.blade.is_loose(), "A's record holds the one still on the floor")
	_s.check(
		stage.a.blade.position.distance_to(far) < 1.0,
		"which is the far one: the records were swapped, not duplicated"
	)
	_s.check(stage.saw("pickup"), "and the pickup is reported")
	stage.dispose()


func _dying_drops_the_sword_where_you_fell() -> void:
	var stage := Support.build(root)
	stage.place(20.0)
	var where := stage.b.position
	stage.b.kill(0)
	_s.check(not stage.b.is_armed(), "a dead fighter is not holding anything")
	_s.check(stage.b.blade.is_loose(), "the sword fell out of the hand")
	stage.run(20, 0, 0)
	_s.check(
		absf(stage.b.blade.position.x - where.x) < 24.0,
		"and landed near where its owner fell"
	)
	stage.dispose()


## There is no sword economy to manage: a fighter always comes back with its
## own record's blade, wherever that blade was lying, so the arena can never
## accumulate swords and can never run out of them.
func _respawning_comes_back_with_your_own_sword() -> void:
	var stage := Support.build(root)
	stage.place(20.0)
	stage.a.disarm(1)
	stage.run(5, 0, 0)
	_s.check(stage.a.blade.is_loose(), "the sword is on the floor")
	stage.a.respawn_at(Vector2(Support.LEFT_X, stage.ground_y()), 1)
	_s.check(stage.a.is_armed(), "a respawn comes back armed")
	_s.equal(stage.a.blade.position, Vector2.ZERO, "and the loose record was cleared")
	_s.check(stage.b.is_armed(), "the other fighter still has its own")
	stage.dispose()
