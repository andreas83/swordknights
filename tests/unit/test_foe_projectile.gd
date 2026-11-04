extends GutTest
## A foe's projectile (scripts/entities/foe_projectile.gd): a danger in its
## own right once it leaves the hand, and the prince's once a parry sends it
## back.
##
## Played through the real game scene with an archer that exists only here,
## so what is held is Game's half of the arrangement: an arrow that reaches
## him hurts him and is spent; one he parries goes back and wounds the archer
## who loosed it, as `Foe.Blow.SHOT`; stone stops one; and a respawn at a
## torch does not hand him back the arrow that killed him.

const GAME_SCENE := "res://scenes/game.tscn"
const DeathWatch := preload("res://tests/death_watch.gd")
const ARCHER := "test_archer"
## Two pixels a frame: slow enough to parry by the frame, fast enough to land
## inside a test's patience.
const SPEED := 120.0

## The prince at column 4 facing right; the archer goes at column 12.
const RANGE := """; Archery Range








    @                D
######################
######################
"""

## The same, with a pillar between them.
const PILLAR := """; Pillar







        #
    @   #            D
######################
######################
"""


class Archer extends Foe:
	var health := 2
	var blows: Array[int] = []

	func bounds() -> Rect2:
		return Rect2(global_position - Vector2(5.0, 20.0), Vector2(10.0, 20.0))

	func is_alive() -> bool:
		return health > 0

	func hit(_from_x: float) -> bool:
		health -= 1
		if health <= 0:
			defeated.emit()
			return true
		return false

	func take_blow(blow: Blow, from_x: float) -> Outcome:
		blows.append(blow)
		return super(blow, from_x)

	## An arrow at chest height, westward.
	func loose() -> FoeProjectile:
		var arrow := FoeProjectile.new()
		arrow.position = global_position + Vector2(-8.0, -12.0)
		arrow.velocity = Vector2(-SPEED, 0.0)
		launch(arrow)
		return arrow


class ScriptedInput extends PlayerInput:
	var bits := 0

	func poll() -> void:
		apply_bits(bits)


var _game: Game
var _input: ScriptedInput


func before_all() -> void:
	EntityRegistry.add_for_test(ARCHER, Archer)


func after_all() -> void:
	EntityRegistry.remove_for_test(ARCHER)


func _play(text: String) -> void:
	var data := AsciiLevel.new()
	data.parse(text)
	data.entities.append({"kind": ARCHER, "cell": Vector2i(12, 8)})
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Game
	_game.level_source = data
	add_child_autofree(_game)
	_input = ScriptedInput.new()
	_game.player.input = _input
	for _frame: int in 30:
		await wait_physics_frames(1)
		if _game.player.state == Player.State.IDLE and _game.player.is_grounded() \
				and not Flow.is_hitstopped():
			break


func _archer() -> Archer:
	for node: Node in _game.get_node("Entities").get_children():
		if node is Archer and not node.is_queued_for_deletion():
			return node as Archer
	return null


func _arrows() -> int:
	var count := 0
	for node: Node in _game.get_node("Entities").get_children():
		if node is FoeProjectile and not node.is_queued_for_deletion():
			count += 1
	return count


## Waits until the arrow is spent, or `frames` run out.
func _until_spent(arrow: FoeProjectile, frames: int) -> void:
	for _frame: int in frames:
		if not is_instance_valid(arrow) or arrow.is_spent():
			return
		await wait_physics_frames(1)


func test_an_arrow_that_reaches_him_hurts_him_and_is_spent() -> void:
	await _play(RANGE)
	var arrow := _archer().loose()
	await wait_physics_frames(1)
	assert_eq(_arrows(), 1, "the arrow is the level's now")
	await _until_spent(arrow, 120)
	assert_eq(_game.player.health, Tuning.MAX_HEALTH - 1, "it landed")
	assert_eq(_arrows(), 0, "and was spent on him")


func test_a_parried_arrow_goes_back_and_wounds_its_archer() -> void:
	await _play(RANGE)
	var archer := _archer()
	var arrow := archer.loose()
	for _frame: int in 120:
		await wait_physics_frames(1)
		if arrow.global_position.x - _game.player.position.x < 18.0:
			break
	_input.bits = PlayerInput.BIT_UP | PlayerInput.BIT_ATTACK
	await wait_physics_frames(1)
	_input.bits = 0
	for _frame: int in 20:
		await wait_physics_frames(1)
		if arrow.reflected:
			break
	assert_true(arrow.reflected, "the parry turned it")
	assert_gt(arrow.velocity.x, SPEED, "back the way it came, faster")
	assert_eq(_game.player.health, Tuning.MAX_HEALTH, "and it never touched him")
	await _until_spent(arrow, 120)
	assert_eq(archer.blows, [Foe.Blow.SHOT] as Array[int], "it reached the archer as a shot")
	assert_eq(archer.health, 1, "and wounded him")
	assert_eq(_arrows(), 0, "spent on him")


func test_stone_stops_an_arrow() -> void:
	await _play(PILLAR)
	var arrow := _archer().loose()
	await _until_spent(arrow, 120)
	assert_true(not is_instance_valid(arrow) or arrow.is_spent(), "the pillar took it")
	assert_eq(_game.player.health, Tuning.MAX_HEALTH, "so it never reached him")


func test_a_respawn_does_not_hand_him_back_the_arrow_in_flight() -> void:
	await _play(RANGE)
	_archer().loose()
	await wait_physics_frames(2)
	assert_eq(_arrows(), 1, "an arrow is in the air")
	DeathWatch.expect_deaths(1)
	_game.player.kill()
	for _frame: int in 120:
		await wait_physics_frames(1)
		if _game.phase == Game.Phase.PLAYING and _game.player.is_alive():
			break
	await wait_physics_frames(2)
	assert_eq(_arrows(), 0, "the respawn cleared it")
	assert_not_null(_archer(), "and put the archer back at his post")
