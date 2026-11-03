extends GutTest
## The count of secrets found: the banner when one is found, the tally on the
## complete screen, and a restart that seals them all again.
##
## A count is only worth showing if it cannot drift: found twice is still
## once, a level without secrets does not grow a "SECRETS 0/0", and replaying
## a level does not start it with its secrets already open.

const GAME_SCENE := "res://scenes/game.tscn"

## Two blocks four tiles tall, each with a room in its foot: a false doorway
## in the first and a cracked one in the second. The exit is behind the spawn.
const TWO_ROOMS := """; Two Rooms


       #####     #####
       #####     #####
       %:::#     &:::#
 D @   %::*#     &::*#
#######################
#######################
"""

const NO_ROOMS := """; No Rooms




 D @
#######
#######
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
	await wait_physics_frames(4)


## Stands the character just outside a seal's doorway, facing it.
func _stand_before(column: int) -> void:
	_game.player.respawn(_game.level.entity_world_position(Vector2i(column - 1, 5)))
	_game.player.facing = 1
	await wait_physics_frames(2)


func _walk_in() -> void:
	_input.bits = PlayerInput.BIT_RIGHT
	await wait_physics_frames(40)
	_input.bits = 0
	await wait_physics_frames(2)


func _swing() -> void:
	_input.bits = PlayerInput.BIT_ATTACK
	await wait_physics_frames(1)
	_input.bits = 0
	await wait_physics_frames(20)


func test_each_secret_counts_once_and_says_so() -> void:
	await _play(TWO_ROOMS)
	assert_eq(_game.secrets.total, 2, "two secrets in the level")
	assert_eq(_game.secrets.count, 0, "none found yet")

	await _stand_before(7)
	await _walk_in()
	assert_eq(_game.secrets.count, 1, "the false doorway is found")
	assert_string_contains(_game.hud._secret_text, "1 OF 2", false)

	# Out and back in again: the room is the same room.
	await _stand_before(7)
	await _walk_in()
	assert_eq(_game.secrets.count, 1, "walking into a found room again counts nothing")

	await _stand_before(17)
	await _swing()
	assert_eq(_game.secrets.count, 2, "the cracked doorway is found")
	assert_string_contains(_game.hud._secret_text, "2 OF 2", false)


func test_the_complete_screen_counts_secrets_where_there_are_any() -> void:
	await _play(TWO_ROOMS)
	await _stand_before(7)
	await _walk_in()
	_game._complete()
	assert_string_contains(_game._overlay_subtitle(), "SECRETS 1/2", false)

	await _play(NO_ROOMS)
	_game._complete()
	assert_eq(_game._overlay_subtitle().find("SECRETS"), -1,
		"a level without secrets does not count them")


func test_a_restart_seals_every_secret_again() -> void:
	await _play(TWO_ROOMS)
	await _stand_before(17)
	await _swing()
	assert_eq(_game.secrets.count, 1, "the cracked doorway is open")
	assert_false(_game.level.data.is_solid(17, 5), "and is not stone")

	_game._restart()
	await wait_physics_frames(2)
	assert_eq(_game.secrets.count, 0, "a restart forgets what was found")
	assert_true(_game.level.data.is_solid(17, 5), "and the cracked wall is a wall again")
	var hidden := 0
	for node: Node in _game.get_node("Entities").get_children():
		if node is Relic and not node.is_queued_for_deletion() and not (node as Relic).visible:
			hidden += 1
	assert_eq(hidden, 2, "both prizes are back behind their stone")
