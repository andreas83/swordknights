extends GutTest
## The roll against the foes, played: what goes over the tuck and what does
## not, and what is on the far side of it (docs/character.md, "The roll").
##
## - **The sentinel.** Rolled at on sight of his raise, the prince comes up
##   behind him before the cut, and the cut goes on into empty air; rolled
##   late, into the live cut, the window carries him through it. Either way
##   his back is there to be cut in his recovery.
## - **The Bastion, in the two-tile corridor.** The owner's Chapter II stuck
##   point: from the front he is a wall, and walking into him only ever
##   pushes the prince back. A roll goes under the shield's face and under
##   the shove, comes up behind him, and his back is open -- through the
##   whole of his 30-frame turn.
## - **What a roll does not go under**, by rule: a Caracal's claws, the
##   King's slam, anything in flight.

const GAME_SCENE := "res://scenes/game.tscn"
const R := PlayerInput.BIT_RIGHT
const L := PlayerInput.BIT_LEFT
const D := PlayerInput.BIT_DOWN
const J := PlayerInput.BIT_JUMP
const A := PlayerInput.BIT_ATTACK

## The prince facing right, a sentinel three tiles off walking at him.
const SENTINEL := """; Sentinel








    @  p                 D
##########################
##########################
"""

## The Chapter II corridor: two tiles of headroom, the Bastion posted in it
## facing the way the prince comes.
const CORRIDOR := """; Corridor







##########################
##########################

    @         w          D
##########################
##########################
"""


class ScriptedInput extends PlayerInput:
	var bits := 0

	func poll() -> void:
		apply_bits(bits)


var _game: Game
var _input: ScriptedInput


func _play(text: String) -> void:
	var data := AsciiLevel.new()
	data.parse(text)
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Game
	_game.level_source = data
	add_child_autofree(_game)
	_input = ScriptedInput.new()
	_game.player.input = _input
	for _frame: int in 30:
		await wait_physics_frames(1)
		if _game.player.state == Player.State.IDLE and _game.player.is_grounded():
			break


func _p() -> Player:
	return _game.player


func _foe(kind: Variant) -> Node:
	for node: Node in _game.get_node("Entities").get_children():
		if is_instance_of(node, kind) and not node.is_queued_for_deletion():
			return node
	return null


func _until(done: Callable, frames: int) -> bool:
	for _frame: int in frames:
		if bool(done.call()):
			return true
		await wait_physics_frames(1)
	return bool(done.call())


func _press(bits: int) -> void:
	_input.bits = bits
	await wait_physics_frames(1)
	_input.bits = 0
	await wait_physics_frames(1)


## Rolls, holding the stick toward `turn` through the rise so he comes up
## facing back the way he came.
func _roll_and_turn(turn: int) -> void:
	await _press(D | J)
	await _until(func() -> bool: return _p().state_time >= Tuning.ROLL_TUCK, 40)
	_input.bits = turn
	await _until(func() -> bool: return _p().state != Player.State.ROLL, 30)
	_input.bits = 0
	await wait_physics_frames(1)


func test_rolled_at_on_sight_of_the_raise_he_comes_up_behind_the_sentinel() -> void:
	await _play(SENTINEL)
	var guard := _foe(Patrol) as Patrol
	assert_true(await _until(func() -> bool: return guard.state == Patrol.State.WINDUP, 180),
		"the sentinel raises")
	await _roll_and_turn(L)
	assert_gt(_p().position.x, guard.position.x, "the roll came up behind him")
	assert_eq(_p().facing, -1, "turned in the rise to face his back")
	await _until(func() -> bool: return guard.state == Patrol.State.RECOVER, 40)
	await _press(A)
	await _until(func() -> bool: return guard.health < Patrol.MAX_HEALTH, 30)
	assert_eq(guard.health, Patrol.MAX_HEALTH - 1, "and his back is cut in his recovery")
	assert_eq(_p().health, Tuning.MAX_HEALTH, "the cut went into the air the prince left")


func test_rolled_into_the_live_cut_the_window_carries_him_through() -> void:
	await _play(SENTINEL)
	var guard := _foe(Patrol) as Patrol
	await _until(func() -> bool: return guard.state == Patrol.State.WINDUP, 180)
	# Late: the blade comes down a few frames into the tuck, over him.
	await _until(func() -> bool: return guard.state_time >= guard.windup_time() - 0.1, 40)
	_input.bits = D | J
	await wait_physics_frames(1)
	_input.bits = 0
	var cut_over := [false]
	await _until(func() -> bool:
		if guard.state == Patrol.State.STRIKE \
				and guard.strike_rect().intersects(_p().body_rect()):
			cut_over[0] = true
		return _p().state != Player.State.ROLL, 60)
	assert_true(cut_over[0], "the live cut was where his standing body would have been")
	assert_eq(_p().health, Tuning.MAX_HEALTH, "and went over the tuck")


func test_walking_into_the_corridor_bastion_never_gets_past_him() -> void:
	await _play(CORRIDOR)
	var bastion := _foe(Bastion) as Bastion
	_input.bits = R
	var past := [false]
	await _until(func() -> bool:
		past[0] = past[0] or _p().position.x > bastion.position.x
		return false, 240)
	_input.bits = 0
	assert_false(past[0], "from the front, on foot, his shield is a wall")


func test_a_roll_goes_under_the_corridor_bastion_and_his_back_is_open_in_the_turn() -> void:
	await _play(CORRIDOR)
	var bastion := _foe(Bastion) as Bastion
	_input.bits = R
	await _until(func() -> bool: return bastion.gap_to(_p().body_rect()) <= Bastion.SHOVE_GAP + 2.0,
		200)
	_input.bits = 0
	await _until(func() -> bool: return absf(_p().velocity.x) < 1.0, 30)
	await _roll_and_turn(L)
	assert_gt(_p().position.x, bastion.position.x, "under the shield and out behind him")
	assert_eq(_p().health, Tuning.MAX_HEALTH, "neither the face nor the shove touched him")
	assert_true(await _until(func() -> bool: return bastion.state == Bastion.State.TURN, 180),
		"he hears the prince at his back and turns")
	await _press(A)
	await _until(func() -> bool: return bastion.health < Bastion.MAX_HEALTH, 20)
	assert_eq(bastion.health, Bastion.MAX_HEALTH - 1, "a cut in his turn wounds his back")
	assert_eq(bastion.state, Bastion.State.STAGGER, "inside the turn's thirty frames")


## --- what does not go under ----------------------------------------------------------

func test_bodies_and_shots_are_not_rolled_under_by_the_window() -> void:
	var cat := Caracal.new()
	add_child_autofree(cat)
	cat.state = Caracal.State.POUNCE
	assert_false(cat.dangers()[0].rollable, "a cat's claws come down on a tucked body")
	var shot := FoeProjectile.new()
	add_child_autofree(shot)
	assert_false(shot.danger().rollable, "a shot is passed by height or not at all")


func test_blades_and_shields_set_against_a_standing_man_are() -> void:
	var guard := Patrol.new()
	add_child_autofree(guard)
	guard.state = Patrol.State.STRIKE
	assert_true(guard.dangers()[0].rollable, "a sentinel's cut")
	var bastion := Bastion.new()
	add_child_autofree(bastion)
	bastion.state = Bastion.State.SHOVE
	for danger: FoeDanger in bastion.dangers():
		assert_true(danger.rollable, "a Bastion's shove and shield face")
