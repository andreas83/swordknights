extends GutTest
## The two seals, played through the real game scene: a false wall the body
## walks through, a cracked wall that holds until the sword finds it, and a
## cracked floor the plunge goes through.
##
## Everything is driven by the scripted stick and buttons, so these pass only
## if the character can really do it: a false wall that still collides, a
## cracked wall whose collision outlives the reveal, or a plunge that lands on
## the floor it opened would each leave the character outside the room.

const GAME_SCENE := "res://scenes/game.tscn"

## The exit is behind the spawn, so the room is never the way. The seal is the
## two `%` cells in column 7; the room is the background masonry behind it.
const FALSE_WALL := """; False Wall


       #####
       #####
       %:::#
 D @   %::*#
############
############
"""

## The floor of the same corridor is cracked over a cellar three rows deep: a
## ledge grab back out of the hole it leaves.
const CRACKED_FLOOR := """; Cracked Floor



 D @
#####&&#####
####::::####
####::::####
####::*:####
############
############
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
		if _game.player.state == Player.State.IDLE and _game.player.is_grounded() \
				and not Flow.is_hitstopped():
			break


func _relic_in_room() -> Relic:
	for node: Node in _game.get_node("Entities").get_children():
		if node is Relic:
			return node as Relic
	return null


func _hold(bits: int, frames: int) -> void:
	_input.bits = bits
	await wait_physics_frames(frames)
	_input.bits = 0


func _tap(bits: int) -> void:
	_input.bits = bits
	await wait_physics_frames(1)
	_input.bits = 0


func _seal_x() -> float:
	return 7.0 * Tuning.TILE


func test_a_false_wall_lets_the_body_through_and_is_found() -> void:
	await _play(FALSE_WALL)
	assert_eq(_game.secrets.total, 1, "the level has one secret")
	assert_false(_relic_in_room().visible, "the prize is hidden behind the stone")

	await _hold(PlayerInput.BIT_RIGHT, 90)

	assert_gt(_game.player.position.x, _seal_x() + Tuning.TILE,
		"the body walked through the seal into the room")
	assert_eq(_game.secrets.count, 1, "and walking into it found it")
	assert_true(_game.level.data.opened.has(0), "the level knows it is open")
	assert_true(_relic_in_room().visible or _relic_in_room().is_taken(),
		"the prize is out from behind the stone")


func test_a_cracked_wall_holds_until_the_sword_opens_it() -> void:
	await _play(FALSE_WALL.replace("%", "&"))
	await _hold(PlayerInput.BIT_RIGHT, 60)
	assert_lt(_game.player.position.x, _seal_x(), "a cracked wall is a wall")
	assert_eq(_game.secrets.count, 0, "and pressing into it finds nothing")
	assert_true(_game.level.data.is_solid(7, 5), "it is still stone")

	await _tap(PlayerInput.BIT_ATTACK)
	for _frame: int in 20:
		await wait_physics_frames(1)
		if _game.secrets.count > 0:
			break
	assert_eq(_game.secrets.count, 1, "one swing at it opens it")
	assert_false(_game.level.data.is_solid(7, 5), "the seal is gone from the level")

	for _frame: int in 30:
		await wait_physics_frames(1)
		if not Flow.is_hitstopped() and _game.player.state != Player.State.ATTACK:
			break
	await _hold(PlayerInput.BIT_RIGHT, 60)
	assert_gt(_game.player.position.x, _seal_x() + Tuning.TILE,
		"and its collision went with it: the body walks in")


func test_a_cracked_floor_opens_under_a_plunge_and_not_under_a_fall() -> void:
	await _play(CRACKED_FLOOR)
	var over_crack := 6.0 * Tuning.TILE
	var floor_y := 4.0 * Tuning.TILE

	# A plain drop onto it from height is luck, not looking: it holds.
	_game.player.position = Vector2(over_crack, floor_y - 70.0)
	_game.player.velocity = Vector2.ZERO
	for _frame: int in 60:
		await wait_physics_frames(1)
		if _game.player.is_grounded():
			break
	await wait_physics_frames(4)
	assert_almost_eq(_game.player.position.y, floor_y, 0.5, "a fall lands on the crack")
	assert_eq(_game.secrets.count, 0, "and does not open it")

	# Up, and down again point first.
	_game.player.position = Vector2(over_crack, floor_y - 40.0)
	_game.player.velocity = Vector2.ZERO
	await wait_physics_frames(3)
	await _tap(PlayerInput.BIT_DOWN | PlayerInput.BIT_ATTACK)
	var bit_the_crack := false
	for _frame: int in 60:
		await wait_physics_frames(1)
		var at_floor := absf(_game.player.position.y - floor_y) < 0.5
		if at_floor and _game.player.state == Player.State.PLUNGE_LAND:
			bit_the_crack = true
		if _game.player.position.y > floor_y + 2.0 * Tuning.TILE:
			break
	assert_eq(_game.secrets.count, 1, "the plunge's point opened the floor")
	assert_false(bit_the_crack,
		"before the feet reached it: the point goes through, it does not land and then fall")
	assert_gt(_game.player.position.y, floor_y + 2.0 * Tuning.TILE,
		"and on into the cellar")
