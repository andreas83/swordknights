extends GutTest
## One swing of the sword takes one of a guard's hearts, never two.
##
## The sword's hit rect is live for about eight frames, and `Game` resolves
## interactions on every one of them. A hit staggers the guard and knocks him
## back about two pixels a frame, which is not enough to leave a fourteen-pixel
## blade, so the next live frame hit him again: one swing spent both of his
## hearts and his health was decoration. `IMPACT_COOLDOWN` only ever rationed
## the hitstop, not the wound.
##
## Plays the real game scene: the prince a tile from a guard, one press.

const GAME_SCENE := "res://scenes/game.tscn"
const DeathWatch := preload("res://tests/death_watch.gd")

## The prince at column 4 facing right, a guard at column 5: 16 px apart,
## inside the sword's reach.
const FLOOR := """; One Swing








    @p            D
###################
###################
"""


class ScriptedInput extends PlayerInput:
	var bits := 0

	func poll() -> void:
		apply_bits(bits)


var _game: Game
var _input: ScriptedInput


func before_each() -> void:
	var data := AsciiLevel.new()
	data.parse(FLOOR)
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Game
	_game.level_source = data
	add_child_autofree(_game)
	_input = ScriptedInput.new()
	_game.player.input = _input
	# Standing, and not held by a hitstop left over from another test.
	for _frame: int in 30:
		await wait_physics_frames(1)
		if _game.player.state == Player.State.IDLE and not Flow.is_hitstopped():
			break


func _guard() -> Patrol:
	for node: Node in _game.get_node("Entities").get_children():
		if node is Patrol and not node.is_queued_for_deletion():
			return node as Patrol
	return null


func _swing() -> void:
	_input.bits = PlayerInput.BIT_ATTACK
	await wait_physics_frames(1)
	_input.bits = 0
	# Out the far side of the swing, its hitstop and the guard's stagger.
	await wait_physics_frames(30)


func test_one_swing_takes_one_heart() -> void:
	var guard := _guard()
	assert_not_null(guard, "the level has a guard")
	assert_eq(guard.health, Patrol.MAX_HEALTH, "at full health")
	await _swing()
	assert_true(is_instance_valid(guard), "a guard with two hearts survives one swing")
	if is_instance_valid(guard):
		assert_true(guard.is_alive(), "and is still standing")
		assert_eq(guard.health, Patrol.MAX_HEALTH - 1, "one swing, one heart")


func test_the_next_swing_takes_the_next_heart() -> void:
	var guard := _guard()
	await _swing()
	# Close in on wherever the knock-back left him, then cut again.
	_input.bits = PlayerInput.BIT_RIGHT
	for _frame: int in 60:
		await wait_physics_frames(1)
		if absf(guard.global_position.x - _game.player.position.x) < 18.0:
			break
	_input.bits = 0
	await _swing()
	assert_true(not is_instance_valid(guard) or not guard.is_alive(),
		"a second swing is a second wound, and two finish him")

	# A death after that returns the prince to a checkpoint; the guard he cut
	# down must not be standing there again.
	DeathWatch.expect_deaths(1)
	_game.player.kill()
	for _frame: int in 120:
		await wait_physics_frames(1)
		if _game.phase == Game.Phase.PLAYING and _game.player.is_alive():
			break
	await wait_physics_frames(2)
	var back := _guard()
	assert_true(back == null or not back.is_alive(), "a guard cut down stays down")
