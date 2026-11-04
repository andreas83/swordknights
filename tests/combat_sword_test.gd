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
	_an_empty_hand_catches_a_thrown_sword()
	_a_high_throw_is_caught_high()
	_a_low_throw_cannot_be_caught()
	_an_armed_fighter_deflects_or_dies_and_never_catches()
	_a_catch_beats_a_kill_on_the_same_frame()
	_a_blade_from_behind_kills_whatever_the_hands_do()
	_a_cut_on_the_same_frame_beats_the_catch()

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
	var duck := Support.stance_bits(Support.DUCKED)
	stage.run(1, Support.UP | Support.THROW, duck)
	stage.run(14, 0, duck)
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


## --- the catch --------------------------------------------------------------
##
## An empty hand can take a thrown sword out of the air: THROW with nothing to
## throw opens the hands (a snatch), and a blade flying into them while they
## are open is caught. tests/fighter_frames_test.gd pins the window frame by
## frame; these are the outcomes, and the ties.

## Disarms B and waits out the flinch, so B stands empty-handed and free with
## its own sword on the floor behind it.
func _unarmed_b(gap: float) -> Support.Stage:
	var stage := Support.build(root)
	stage.place(gap)
	stage.b.disarm(0)
	stage.run(stage.tuning.disarmed_frames + 2, 0, 0)
	stage.events.clear()
	return stage


func _event(stage: Support.Stage, kind: String) -> Dictionary:
	for event: Dictionary in stage.events:
		if event.get("kind", "") == kind:
			return event
	return {}


## A throws across THROW_GAP; B, empty-handed, snatches the frame after. The
## blade reaches B's hands a frame later, well inside the window.
func _an_empty_hand_catches_a_thrown_sword() -> void:
	var stage := _unarmed_b(THROW_GAP)
	var b_old := stage.b.blade
	var thrown := stage.a.blade
	stage.run(1, Support.THROW, 0)
	stage.run(1, 0, Support.THROW)
	_s.equal(stage.b.state, Fighter.State.SNATCH, "B's empty hand turned THROW into a snatch")
	var settled_in := -1
	for frame: int in 10:
		stage.run(1, 0, 0)
		if stage.b.is_armed():
			settled_in = frame
			break
	_s.check(settled_in >= 0, "B caught the sword in flight")
	_s.check(stage.b.is_alive() and stage.a.is_alive(), "and nobody died")
	_s.equal(stage.b.state, Fighter.State.CATCH, "the catch is its own pose")
	_s.equal(stage.b.stance, DuelTuning.Stance.MID, "held at the height it came in at")
	_s.check(stage.b.blade == thrown, "B holds the very sword A threw")
	_s.check(not stage.a.is_armed(), "the thrower stays empty-handed")
	_s.check(stage.a.blade == b_old and b_old.is_loose(),
		"and keeps the record of B's old sword, still on the floor: two swords, always")
	var event := _event(stage, "catch")
	_s.equal(event.get("by", -1), 1, "the catch is reported, by B")
	_s.equal(event.get("from", -1), 0, "from A's throw")
	_s.check(stage.b.blade_rect().size == Vector2.ZERO,
		"the caught blade is not up to parry with while the hands close on it")

	stage.run(stage.tuning.catch_settle, 0, 0)
	_s.check(stage.b.is_free(), "after catch_settle frames B is free")
	_s.check(stage.b.blade_rect().size.x > 0.0, "and the blade is up")
	stage.dispose()


func _a_high_throw_is_caught_high() -> void:
	var stage := _unarmed_b(THROW_GAP)
	stage.run(1, Support.UP | Support.THROW, 0)
	stage.run(1, 0, Support.THROW)
	for frame: int in 8:
		stage.run(1, 0, 0)
		if stage.saw("catch"):
			break
	_s.check(stage.saw("catch"), "a rising high throw is caught")
	_s.equal(stage.b.stance, DuelTuning.Stance.HIGH, "and held HIGH, where it came in")
	# Once the hands have closed on it, the stance is the buttons' again: zero
	# frames of lock in the free states, catch or no catch.
	stage.run(stage.tuning.catch_settle + 1, 0, 0)
	_s.equal(stage.b.stance, DuelTuning.Stance.MID, "and free again, it follows the buttons")
	stage.dispose()


## The hands reach from the face down to the bottom of MID. A LOW throw goes
## under them into the legs: the thrower's answer to open hands, and the
## catcher's reason to jump instead.
func _a_low_throw_cannot_be_caught() -> void:
	var stage := _unarmed_b(THROW_GAP)
	stage.run(1, Support.DOWN | Support.THROW, 0)
	_s.equal(stage.a.blade.stance, DuelTuning.Stance.LOW, "A threw from LOW")
	stage.run(1, 0, Support.THROW)
	stage.run(10, 0, 0)
	_s.check(not stage.saw("catch"), "nothing catches a LOW throw")
	_s.check(not stage.b.is_alive(), "it goes under the open hands and kills")
	stage.dispose()


## Only an empty hand catches. An armed fighter has the deflect, as before, and
## a sword arriving at one that does nothing kills it -- it is not handed a
## second sword. Its THROW, pressed as the blade arrives, throws its own.
func _an_armed_fighter_deflects_or_dies_and_never_catches() -> void:
	var stage := Support.build(root)
	stage.place(THROW_GAP)
	var own := stage.b.blade
	stage.run(1, Support.THROW, 0)
	for frame: int in 12:
		var arriving := stage.a.blade.mode == DuelBlade.Mode.FLYING \
			and absf(stage.a.blade.position.x - stage.b.position.x) < 24.0
		stage.run(1, 0, Support.ATTACK if arriving and stage.b.is_free() else 0)
	_s.check(stage.saw("deflect"), "an armed fighter's thrust deflects the throw")
	_s.check(not stage.saw("catch"), "and does not catch it")
	_s.check(stage.b.blade == own and own.is_held(), "B still holds its own sword")
	_s.check(stage.a.blade.is_loose(), "A's sword is knocked to the floor")
	stage.dispose()

	stage = Support.build(root)
	stage.place(THROW_GAP)
	stage.run(1, Support.THROW, 0)
	stage.run(12, 0, 0)
	_s.check(not stage.saw("catch"), "an armed fighter standing in front of a throw")
	_s.check(not stage.b.is_alive(), "is killed by it, not handed it")
	stage.dispose()

	stage = Support.build(root)
	stage.place(THROW_GAP)
	stage.run(1, Support.THROW, 0)
	stage.run(1, 0, Support.THROW)
	_s.check(stage.b.state != Fighter.State.SNATCH, "an armed fighter's THROW is no snatch")
	_s.equal(stage.b.blade.thrown_by, 1, "it throws its own sword instead")
	stage.run(12, 0, 0)
	_s.check(not stage.saw("catch"), "nobody caught anything")
	_s.check(not stage.b.is_alive(), "and A's throw still landed")
	stage.dispose()


## THE TIE. A throws point-blank into B's open hands: the blade appears already
## touching both the hands' rect and B's body. The blade is flying into the
## hands, which stand in front of the body on its path, so the catch wins --
## as a parry wins over a cut on the diagonal. With the hands closed the same
## frame is a kill.
func _a_catch_beats_a_kill_on_the_same_frame() -> void:
	var stage := _unarmed_b(12.0)
	var tuning := stage.tuning
	var spawn := tuning.loose_blade_rect(
		tuning.hand_position(stage.a.position, stage.a.facing, stage.a.stance))
	var both := spawn.intersects(tuning.catch_rect(stage.b.position, stage.b.facing)) \
		and spawn.intersects(stage.b.hurt_rect())
	_s.check(both, "the case is a tie: the throw appears inside B's hands and body")
	stage.run(1, Support.THROW, Support.THROW)
	_s.check(stage.saw("catch"), "open hands win the tie")
	_s.check(not stage.saw("kill") and stage.b.is_alive(), "and B is not killed")
	_s.check(stage.b.is_armed() and not stage.a.is_armed(), "B holds A's sword")
	stage.dispose()

	stage = _unarmed_b(12.0)
	stage.run(1, Support.THROW, 0)
	_s.check(not stage.b.is_alive(), "with the hands closed the same throw kills")
	_s.check(not stage.saw("catch"), "and nothing is caught")
	stage.dispose()


## The tie goes to the hands only because the blade has to pass them to reach
## the body. A blade overtaking B from behind reaches the back first: open hands
## facing the other way catch nothing, even on a frame the blade touches them.
func _a_blade_from_behind_kills_whatever_the_hands_do() -> void:
	var stage := _unarmed_b(12.0)
	stage.b.facing = 1
	var tuning := stage.tuning
	var spawn := tuning.loose_blade_rect(
		tuning.hand_position(stage.a.position, stage.a.facing, stage.a.stance))
	_s.check(
		spawn.intersects(tuning.catch_rect(stage.b.position, 1))
			and spawn.intersects(stage.b.hurt_rect()),
		"the throw appears inside B's back and B's forward-facing hands"
	)
	stage.run(1, Support.THROW, Support.THROW)
	_s.equal(stage.b.state, Fighter.State.DEAD, "a blade in the back kills, hands open or not")
	_s.check(not stage.saw("catch"), "and nothing is caught")
	stage.dispose()


## The other tie: B's hands would take a blade on the same frame that A's
## thrust cuts B down. Blades on bodies are resolved before blades in flight,
## so the cut lands first and a dead fighter catches nothing. The blade here is
## B's own record, sent flying at B as a catch-swap can leave it, so that A can
## be armed and thrusting while a sword is in the air. A thrusts HIGH, over the
## flying blade, so a deflect cannot be what saves anyone.
func _a_cut_on_the_same_frame_beats_the_catch() -> void:
	for thrusting: bool in [false, true]:
		var stage := _unarmed_b(20.0)
		var record := stage.b.blade
		record.mode = DuelBlade.Mode.FLYING
		record.thrown_by = 0
		record.stance = DuelTuning.Stance.MID
		record.position = stage.tuning.hand_position(
			stage.b.position + Vector2(-30.0, 0.0), 1, DuelTuning.Stance.MID)
		record.velocity = Vector2(stage.tuning.throw_speed, 0.0)
		var bits_a := Support.UP | Support.ATTACK if thrusting else 0
		stage.run(1, bits_a, Support.THROW)
		if not thrusting:
			_s.check(stage.saw("catch"), "unopposed, B's hands take the blade on that frame")
			stage.dispose()
			continue
		_s.check(not stage.b.is_alive(), "A's thrust cuts B down on the same frame")
		_s.equal(_event(stage, "kill").get("killer", -2), 0, "credited to the thrust")
		_s.check(not stage.saw("catch"), "and the dead hands catch nothing")
		_s.check(not stage.saw("deflect"), "nor was the blade deflected")
		stage.dispose()
