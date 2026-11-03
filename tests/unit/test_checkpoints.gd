extends GutTest
## A death costs the stretch since the last torch, not the whole level.
##
## Plays the real game scene on a small level built for the question: walk past
## a torch, die, and see where the character comes back. Before checkpoints
## existed this put the player back on the spawn every time, which on a
## 170-column Endless ruin is two minutes of replay for one missed jump.
##
## The second half is the guard that makes the feature safe. A torch is only a
## checkpoint when the reachability proof routes from it to the exit, so a
## torch at the bottom of a dead-end pit can never turn every death into a
## return to the same pit.

const GAME_SCENE := "res://scenes/game.tscn"
## These tests kill the prince on purpose, and say so to the death watch.
const DeathWatch := preload("res://tests/death_watch.gd")

## Spawn at column 1, a torch at column 8, the exit at column 18.
const CORRIDOR := """; Checkpoint Corridor








 @      t         D
###################
###################
"""

## The torch at column 10 sits at the bottom of a pit seven tiles deep: far
## deeper than any grab, with no ladder out. Standing there, the exit is gone.
const SEALED := """; Sealed Pit




 @            D
#########  #####
#########  #####
#########  #####
#########  #####
#########  #####
#########  #####
######### t#####
################
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
	var packed := load(GAME_SCENE) as PackedScene
	_game = packed.instantiate() as Game
	_game.level_source = data
	add_child_autofree(_game)
	_input = ScriptedInput.new()
	_game.player.input = _input
	await wait_physics_frames(4)


func _torch_x() -> float:
	return 8.0 * Tuning.TILE + Tuning.TILE * 0.5


func _spawn_x() -> float:
	return 1.0 * Tuning.TILE + Tuning.TILE * 0.5


## Walks right until the feet are past `x`, then lets go of the stick.
func _walk_past(x: float) -> void:
	_input.bits = PlayerInput.BIT_RIGHT
	for _frame: int in 240:
		await wait_physics_frames(1)
		if _game.player.position.x > x:
			break
	_input.bits = 0
	await wait_physics_frames(20)


## Kills the character and waits out the death beat and the wipe.
func _die_and_return() -> void:
	_game.player.kill()
	for _frame: int in 120:
		await wait_physics_frames(1)
		if _game.phase == Game.Phase.PLAYING and _game.player.is_alive():
			break
	await wait_physics_frames(2)


func test_death_returns_to_the_last_torch_passed() -> void:
	await _play(CORRIDOR)
	await _walk_past(_torch_x() + 24.0)
	assert_gt(_game.player.position.x, _torch_x() + 16.0, "the walk got past the torch")

	DeathWatch.expect_deaths(1)
	await _die_and_return()

	assert_true(_game.player.is_alive(), "the character came back")
	assert_eq(_game.phase, Game.Phase.PLAYING, "and the game is running again")
	assert_almost_eq(_game.player.position.x, _torch_x(), 1.0,
		"the respawn is at the torch, not back at the spawn")


func test_death_before_any_torch_returns_to_the_spawn() -> void:
	await _play(CORRIDOR)
	await _walk_past(_spawn_x() + 20.0)
	DeathWatch.expect_deaths(1)
	await _die_and_return()
	assert_almost_eq(_game.player.position.x, _spawn_x(), 1.0,
		"no torch passed yet, so the spawn is still the checkpoint")


func test_a_checkpoint_respawn_keeps_the_clock_and_restores_health() -> void:
	await _play(CORRIDOR)
	await _walk_past(_torch_x() + 24.0)
	_game.player.damage(1)
	await wait_physics_frames(30)
	var clock := _game.elapsed
	assert_gt(clock, 0.0, "the clock has been running")

	DeathWatch.expect_deaths(1)
	await _die_and_return()

	assert_gte(_game.elapsed, clock, "a death costs time; it does not hand time back")
	assert_eq(_game.player.health, Tuning.MAX_HEALTH, "the character comes back whole")
	assert_gt(_game.player.invulnerable, 0.0, "with a moment's grace to read the room")
	assert_eq(_game.deaths, 1, "and the death is counted")


func test_a_torch_the_exit_cannot_be_reached_from_is_not_a_checkpoint() -> void:
	var data := AsciiLevel.new()
	data.parse(SEALED)
	assert_true(bool(LevelReachability.verify(data)["ok"]), "the level itself is solvable")
	assert_false(bool(LevelReachability.verify_from(data, Vector2i(10, 11))["ok"]),
		"and the pit is a dead end: the premise of this test")
	assert_eq(Game.checkpoint_cells(data), [] as Array[Vector2i],
		"so the torch in it is never offered as a checkpoint")


func test_every_torch_in_the_sun_terrace_is_a_checkpoint() -> void:
	var data := AsciiLevel.from_file("res://levels/level_01.txt")
	var torches := 0
	for mark: Dictionary in data.entities:
		if String(mark["kind"]) == "torch":
			torches += 1
	assert_gt(torches, 2, "the level has torches to rest at")
	assert_eq(Game.checkpoint_cells(data).size(), torches,
		"and each of them routes to the exit")
