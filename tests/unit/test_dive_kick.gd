extends GutTest
## The dive kick: down + JUMP in the air. A straight line, heel first, that
## rocks what it reaches and wounds nothing, springs the prince back off it,
## and plants him when it meets stone instead.
##
## Held to three things. It adds no reach: never faster across than a run and
## never slower down than the hardest fall, so it lands nearer than the same
## jump left alone. It costs what the plunge costs when it misses. And every
## foe answers it as docs/character.md says -- the sentinel reels, the
## Bastion's shield goes wide and a blade from the front then wounds him, the
## Caracal is bowled into its opening -- with no heart lost by any of them.
## The unarmed sweep is the other half of the feet, and is here too: it
## breaks a sentinel's raise, and clangs off a Bastion's shield.

const GAME_SCENE := "res://scenes/game.tscn"
const R := PlayerInput.BIT_RIGHT
const D := PlayerInput.BIT_DOWN
const J := PlayerInput.BIT_JUMP
const A := PlayerInput.BIT_ATTACK
const T := PlayerInput.BIT_THROW

const OPEN := """; Open








   @                     D
##########################
##########################
"""

## A sentinel, a Bastion and a cat, each with room to be kicked.
const GUARD := """; Guard








   @         p           D
##########################
##########################
"""

## A sentinel five tiles off, with room behind the prince to throw into.
const GUARD_NEAR := """; Guard Near








         @    p           D
##########################
##########################
"""

const BASTION := """; Bastion








   @         w           D
##########################
##########################
"""

const CAT := """; Cat








   @         j           D
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


## Puts the prince in the air over and in front of `foe`, falling, and kicks.
func _kick_at(foe: Node2D) -> void:
	var p := _p()
	p.facing = 1
	p.position = foe.position + Vector2(-14.0, -30.0)
	p.velocity = Vector2.ZERO
	p._enter(Player.State.FALL)
	# One frame for the body to learn it is off the floor, and the coyote
	# time that frame grants spent, so the press is a kick and not a late jump.
	await wait_physics_frames(1)
	p._coyote = 0.0
	await _press(D | J)


## Runs right, jumps at a full run, and returns the x the feet land at. With
## `kick`, the dive kick is thrown at the apex.
func _jump_lands_at(kick: bool) -> float:
	await _play(OPEN)
	_input.bits = R
	await _until(func() -> bool: return absf(_p().velocity.x) >= Tuning.RUN_SPEED - 1.0, 40)
	_input.bits = R | J
	await _until(func() -> bool: return _p().velocity.y >= 0.0 and not _p().is_grounded(), 60)
	_input.bits = R
	if kick:
		await _press(R | D | J)
		_input.bits = R
	await _until(func() -> bool: return _p().is_grounded(), 90)
	_input.bits = 0
	return _p().position.x


## --- the numbers -------------------------------------------------------------------

func test_it_is_never_faster_across_than_a_run_nor_slower_down_than_a_fall() -> void:
	assert_lte(Tuning.DIVE_KICK_DRIFT, Tuning.RUN_SPEED, "across: no faster than a run")
	assert_gte(Tuning.DIVE_KICK_DROP, Tuning.MAX_FALL_SPEED, "down: as fast as anything falls")


func test_a_kick_from_the_apex_lands_nearer_than_the_jump_left_alone() -> void:
	var plain := await _jump_lands_at(false)
	var kicked := await _jump_lands_at(true)
	assert_lt(kicked, plain, "the kick cuts a jump short; it never stretches one")


func test_a_kick_that_misses_cannot_be_swung_out_of_before_a_guards_cut() -> void:
	var answer := Tuning.DIVE_KICK_RECOVER + Tuning.ATTACK_TIME * 0.25
	assert_gt(answer, Patrol.WINDUP_TIME, "the plunge's price (test_specials.gd)")
	await _play(OPEN)
	_input.bits = J
	await _until(func() -> bool: return _p().velocity.y > 0.0, 60)
	_input.bits = 0
	await wait_physics_frames(1)
	await _press(D | J)
	await _until(func() -> bool: return _p().state == Player.State.KICK_LAND, 60)
	await _press(A)
	assert_eq(_p().state, Player.State.KICK_LAND, "planted: a swing does not come out")


## --- the foes ------------------------------------------------------------------------

func test_a_kicked_sentinel_reels_unwounded_and_the_prince_springs_back() -> void:
	await _play(GUARD)
	var guard := _foe(Patrol) as Patrol
	await _kick_at(guard)
	assert_true(await _until(func() -> bool: return guard.state == Patrol.State.STAGGER, 20),
		"the heel found him and he reels")
	assert_eq(guard.stagger_length, Patrol.KICKED_TIME, "for a kick's reel")
	assert_eq(guard.health, Patrol.MAX_HEALTH, "and loses nothing: the feet do not wound")
	assert_eq(_p().state, Player.State.JUMP, "the prince is sprung back up off him")
	assert_lt(_p().velocity.x, 0.0, "and back the way he came")


func test_a_kick_opens_the_bastions_shield_and_a_blade_from_the_front_wounds() -> void:
	await _play(BASTION)
	var bastion := _foe(Bastion) as Bastion
	await _kick_at(bastion)
	assert_true(await _until(func() -> bool: return bastion.state == Bastion.State.OPENED, 20),
		"the shield is knocked wide")
	assert_eq(bastion.health, Bastion.MAX_HEALTH, "by a kick that wounds nothing")
	assert_false(bastion.is_dangerous(), "his front is no wall while it is open")
	await _until(func() -> bool: return _p().is_grounded(), 60)
	_input.bits = R
	await _until(func() -> bool: return bastion.gap_to(_p().body_rect()) <= 4.0, 60)
	_input.bits = 0
	await _press(A)
	await _until(func() -> bool: return bastion.health < Bastion.MAX_HEALTH, 20)
	assert_eq(bastion.health, Bastion.MAX_HEALTH - 1, "a swing from the front wounds him")


func test_a_kicked_cat_is_bowled_into_its_opening() -> void:
	await _play(CAT)
	var cat := _foe(Caracal) as Caracal
	await _kick_at(cat)
	assert_true(await _until(func() -> bool:
		return cat.state == Caracal.State.SKID or cat.state == Caracal.State.FALL, 20),
		"bowled over")
	assert_true(cat.is_alive(), "and alive: its one heart is not the feet's to take")
	assert_false(cat.is_dangerous(), "with its claws spent")


func test_an_unarmed_sweep_breaks_a_sentinels_raise_and_wounds_nothing() -> void:
	await _play(GUARD_NEAR)
	var guard := _foe(Patrol) as Patrol
	# Thrown the other way, so it is gone and the sentinel is whole.
	await _press(PlayerInput.BIT_LEFT)
	await _press(T)
	await _until(func() -> bool: return _p().state == Player.State.IDLE, 30)
	await _press(R)
	assert_false(_p().moves.armed(), "the sword is gone: the feet are what is left")
	await _until(func() -> bool: return guard.state == Patrol.State.WINDUP, 240)
	await _press(A)
	assert_eq(_p().state, Player.State.SWEEP, "SWORD with no sword sweeps")
	assert_true(await _until(func() -> bool: return guard.state == Patrol.State.STAGGER, 20),
		"the leg takes his feet out of the raise")
	assert_eq(guard.health, Patrol.MAX_HEALTH, "and takes no heart")
	assert_eq(_p().health, Tuning.MAX_HEALTH, "and his cut never came")


func test_the_bastion_answers_each_of_the_duels_blows() -> void:
	var outcomes := {}
	for case: Array in [
		["kick front", Foe.Blow.KICK, -1.0], ["kick back", Foe.Blow.KICK, 1.0],
		["sweep front", Foe.Blow.SWEEP, -1.0], ["sweep back", Foe.Blow.SWEEP, 1.0],
		["thrown front", Foe.Blow.THROWN, -1.0], ["thrown back", Foe.Blow.THROWN, 1.0],
	]:
		var bastion: Bastion = autofree(Bastion.new())
		bastion.position = Vector2(100.0, 100.0)
		bastion.facing = -1
		outcomes[case[0]] = bastion.take_blow(case[1], 100.0 + float(case[2]) * 20.0)
	assert_eq(outcomes["kick front"], Foe.Outcome.STAGGERED, "a kick opens the shield")
	assert_eq(outcomes["kick back"], Foe.Outcome.STAGGERED, "from either side")
	assert_eq(outcomes["sweep front"], Foe.Outcome.BLOCKED, "a sweep rings off the pavise")
	assert_eq(outcomes["sweep back"], Foe.Outcome.STAGGERED, "and rocks his back")
	assert_eq(outcomes["thrown front"], Foe.Outcome.BLOCKED, "a thrown blade off the face")
	assert_eq(outcomes["thrown back"], Foe.Outcome.WOUNDED, "into his back, a wound")
