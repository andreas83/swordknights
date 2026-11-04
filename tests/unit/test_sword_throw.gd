extends GutTest
## The sword throw: THROW, and the blade flies level, wounds the first foe it
## reaches, and lies where it lands until the prince stoops for it -- or until
## it comes back to his hand by itself, which is the rule that keeps a throw
## from ever costing the game (PrinceBlade argues it).
##
## Played: a throw at a sentinel wounds him and the blade lies by him; down
## over it takes it back; left alone it flies home after RECALL_TIME and not
## before; thrown into spikes it is home after RECALL_LOST; a death gives it
## back with the respawn. Against the bestiary: off a Bastion's shield it
## clangs and drops, into his back it wounds; over a prowling cat it flies on,
## because a blade at chest height is higher than a cat; and into a cracked
## wall it opens the secret, as a swing would.

const GAME_SCENE := "res://scenes/game.tscn"
const DeathWatch := preload("res://tests/death_watch.gd")
const R := PlayerInput.BIT_RIGHT
const D := PlayerInput.BIT_DOWN
const T := PlayerInput.BIT_THROW
const FRAME := 1.0 / 60.0

const GUARD := """; Guard








   @    p                D
##########################
##########################
"""

const OPEN := """; Open








   @                     D
##########################
##########################
"""

## Spikes from column 6 on: whatever is thrown lands in them.
const SPIKES := """; Spikes








   @                     D
######^^^^^^^^^^^^^#######
##########################
"""

## A Bastion facing the prince; turned round, his back is to him.
const BASTION_FRONT := """; Front








   @     w               D
##########################
##########################
"""

const CAT := """; Cat








   @   j                 D
##########################
##########################
"""

## A cracked wall four tiles ahead, sealing a room with the door behind the
## prince, so the room is never the way.
const CRACKED := """; Cracked



            #####
            #####
            &:::#
 D     @    &::*#
#################
#################
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


func _blade() -> PrinceBlade:
	return _game.player.moves.blade


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


## Throws, and waits for the blade to stop flying.
func _throw() -> void:
	await _press(T)
	await _until(func() -> bool: return not _p().moves.armed(), 20)
	await _until(func() -> bool: return not _blade().is_flying(), 60)


func test_a_thrown_sword_wounds_the_first_foe_and_lies_by_him() -> void:
	await _play(GUARD)
	var guard := _foe(Patrol) as Patrol
	await _throw()
	assert_eq(guard.health, Patrol.MAX_HEALTH - 1, "the blade wounded him")
	assert_false(_p().moves.armed(), "and the prince's hand is empty")
	await _until(func() -> bool: return _blade().resting, 90)
	assert_true(_blade().resting, "the blade lies on the floor")
	assert_lt(absf(_blade().position.x - guard.position.x), 2.0 * Tuning.TILE,
		"where it struck him, not where it would have flown")


func test_down_over_the_blade_takes_it_back() -> void:
	await _play(OPEN)
	await _throw()
	await _until(func() -> bool: return _blade().resting, 90)
	_input.bits = R
	await _until(func() -> bool:
		return _p().body_rect().grow(2.0).intersects(_blade().rect()), 120)
	_input.bits = 0
	var back := [0]
	_p().rearmed.connect(func() -> void: back[0] += 1)
	await _press(D)
	assert_true(_p().moves.armed(), "down, over it, and it is in the hand")
	assert_eq(back[0], 1, "and says so once")


func test_left_lying_it_flies_home_after_the_recall_and_not_before() -> void:
	await _play(OPEN)
	await _throw()
	await _until(func() -> bool: return _blade().resting, 90)
	var lying := _blade().idle
	await wait_physics_frames(roundi((Tuning.RECALL_TIME - lying) / FRAME) - 10)
	assert_false(_p().moves.armed(), "still lying a moment before the recall")
	assert_true(await _until(func() -> bool: return _p().moves.armed(), 90),
		"and back in the hand after it, though he never went for it")


func test_thrown_into_spikes_it_is_home_after_the_short_recall() -> void:
	await _play(SPIKES)
	await _throw()
	assert_true(await _until(func() -> bool: return _blade().lost, 90),
		"the blade is lost in the spikes")
	var waited := [0]
	await _until(func() -> bool:
		waited[0] += 1
		return _p().moves.armed(), roundi(Tuning.RECALL_TIME / FRAME))
	assert_true(_p().moves.armed(), "it came home")
	assert_lt(float(waited[0]) * FRAME, Tuning.RECALL_TIME * 0.5,
		"on the short recall, not the long one")


func test_a_respawn_always_gives_the_sword_back() -> void:
	DeathWatch.expect_deaths(1)
	await _play(OPEN)
	await _throw()
	assert_false(_p().moves.armed(), "thrown")
	_p().kill()
	await _until(func() -> bool: return _game.phase == Game.Phase.PLAYING and _p().is_alive(),
		240)
	assert_true(_p().is_alive(), "back at the checkpoint")
	assert_true(_p().moves.armed(), "with the sword in his hand")
	assert_true(_blade().is_held(), "and no second blade lying anywhere")


func test_off_a_bastions_shield_it_clangs_and_into_his_back_it_wounds() -> void:
	await _play(BASTION_FRONT)
	var front := _foe(Bastion) as Bastion
	await _throw()
	assert_eq(front.health, Bastion.MAX_HEALTH, "the shield turns it")
	assert_lt(_blade().position.x, front.position.x, "and it drops at his feet, in front")
	await _play(BASTION_FRONT)
	var back := _foe(Bastion) as Bastion
	back.facing = 1
	await _throw()
	assert_eq(back.health, Bastion.MAX_HEALTH - 1, "his back takes it")


func test_it_flies_over_a_prowling_cat() -> void:
	await _play(CAT)
	var cat := _foe(Caracal) as Caracal
	await _press(T)
	var passed := [false]
	await _until(func() -> bool:
		if _blade().is_flying() and _blade().position.x > cat.position.x + Caracal.BODY.x:
			passed[0] = true
		return passed[0] or (not _blade().is_flying() and not _p().moves.armed()), 60)
	assert_true(passed[0], "the blade went on past the cat")
	assert_true(cat.is_alive(), "over its back: a cat is lower than a man's chest")


func test_a_thrown_sword_opens_a_cracked_wall() -> void:
	await _play(CRACKED)
	assert_eq(_game.secrets.count, 0, "sealed")
	await _press(T)
	assert_true(await _until(func() -> bool: return _game.secrets.count > 0, 60),
		"the point went into the crack and opened it")
