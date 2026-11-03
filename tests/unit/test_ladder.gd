extends GutTest
## A ladder is climbed at a pace worth taking, and can be jumped off.
##
## Both were reported from a phone. The climb ran at three tiles a second, so
## the feel lab's seven-tile ladder took longer than crossing the whole lab on
## foot. And a jump on the ladder did leave it -- for one frame: the stick is
## almost always still pushed up or down when the thumb taps JUMP, and the
## next frame's free movement saw a vertical input over a ladder and put the
## prince straight back on the rungs.
##
## Plays the real game scene with the real physics. The climb speed is
## measured, not read off the constant, so a ladder that stalls on something
## (a collision, a state that keeps dropping out) fails as well.

const GAME_SCENE := "res://scenes/game.tscn"
const FRAME := 1.0 / 60.0

## A ladder at column 5, seven rungs tall, open air on both sides of it. The
## prince spawns at its foot.
const SHAFT := """; Shaft


     H
     H
     H
     H
     H
     H
     H
     @          D
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
	data.parse(SHAFT)
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Game
	_game.level_source = data
	add_child_autofree(_game)
	_input = ScriptedInput.new()
	_game.player.input = _input
	await wait_physics_frames(4)


func _player() -> Player:
	return _game.player


## Up until the prince is on the ladder and a few rungs clear of the floor.
func _get_on() -> void:
	_input.bits = PlayerInput.BIT_UP
	for _frame: int in 40:
		await wait_physics_frames(1)
		if _player().state == Player.State.LADDER and _player().position.y < 150.0:
			break


## Tiles per second while holding `bits` on the ladder, over `frames` frames.
func _climb_rate(bits: int, frames: int) -> float:
	_input.bits = bits
	await wait_physics_frames(2)
	var from := _player().position.y
	var start := Engine.get_physics_frames()
	await wait_physics_frames(frames)
	var tiles := absf(_player().position.y - from) / Tuning.TILE
	return tiles / (float(Engine.get_physics_frames() - start) * FRAME)


func test_the_climb_is_quick_both_ways() -> void:
	await _get_on()
	assert_eq(_player().state, Player.State.LADDER, "on the ladder")
	var up := await _climb_rate(PlayerInput.BIT_UP, 20)
	var down := await _climb_rate(PlayerInput.BIT_DOWN, 20)
	gut.p("ladder: %.2f tiles/s up, %.2f tiles/s down" % [up, down])
	# Three tiles a second was the complaint. Five is a run's pace, near enough.
	assert_gte(up, 5.0, "climbing up runs at five tiles a second or better")
	assert_gte(down, 5.0, "and so does climbing down")
	assert_almost_eq(up, Tuning.LADDER_SPEED / Tuning.TILE, 0.3,
		"and the measured pace is the tuned one: nothing on the ladder stalls it")


func test_a_jump_with_a_direction_leaps_off_sideways() -> void:
	await _get_on()
	var start := _player().position
	_input.bits = PlayerInput.BIT_UP | PlayerInput.BIT_RIGHT | PlayerInput.BIT_JUMP
	await wait_physics_frames(1)
	var left_ladder := true
	for _frame: int in 18:
		await wait_physics_frames(1)
		left_ladder = left_ladder and _player().state != Player.State.LADDER
	assert_true(left_ladder, "the stick still pushed up does not put him back on")
	assert_gt(_player().position.x - start.x, Tuning.TILE,
		"he is more than a tile clear of the ladder, to the side he pushed")
	assert_eq(_player().facing, 1, "and faces the way he leapt")


func test_a_jump_straight_up_does_not_regrab_at_once() -> void:
	await _get_on()
	var start := _player().position
	# Jump held, so the hop is a whole one rather than a cut tap.
	_input.bits = PlayerInput.BIT_UP | PlayerInput.BIT_JUMP
	# Counted off the engine, not off the waits: a wait can span more than one
	# physics frame, and the regrab time is a number of frames.
	var leapt := Engine.get_physics_frames()
	var rose := 0.0
	for _wait: int in 60:
		await wait_physics_frames(1)
		rose = maxf(rose, start.y - _player().position.y)
		if _player().state == Player.State.LADDER:
			break
	var frames_off := Engine.get_physics_frames() - leapt
	assert_gt(rose, Tuning.TILE, "the jump rose off the rungs")
	assert_gte(frames_off, roundi(Tuning.LADDER_REGRAB_TIME / FRAME) - 1,
		"the hands stay off the ladder for the regrab time")
	assert_eq(_player().state, Player.State.LADDER, "and then take it again, with up held")
	# A catch in mid-air has to hold and climb, not slide: the reachability
	# proof routes through exactly that move.
	var caught_at := _player().position.y
	await wait_physics_frames(10)
	assert_eq(_player().state, Player.State.LADDER, "the catch holds")
	assert_lt(_player().position.y, caught_at - Tuning.TILE * 0.5, "and climbs")
