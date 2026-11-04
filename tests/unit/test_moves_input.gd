extends GutTest
## Where the duel's moves sit on the prince's controls, and that nothing that
## was already there moved (scripts/player/prince_moves.gd argues the map).
##
## The risk in adding a move to a game with a frozen input program and a
## phone's stick is not the move -- it is the press that used to mean
## something else. So every pairing that touches a new move is played here
## from both sides: down + JUMP rolls on stone and still drops through a
## one-way floor and still jumps at a run; down + JUMP in the air kicks and
## still jumps in coyote time; down + SWORD still plunges, up + SWORD still
## parries, back + SWORD still steps back; THROW throws; and with the sword
## gone, SWORD sweeps and nothing else comes out of it.

const GAME_SCENE := "res://scenes/game.tscn"

const R := PlayerInput.BIT_RIGHT
const L := PlayerInput.BIT_LEFT
const U := PlayerInput.BIT_UP
const D := PlayerInput.BIT_DOWN
const J := PlayerInput.BIT_JUMP
const A := PlayerInput.BIT_ATTACK
const T := PlayerInput.BIT_THROW

## Open stone floor; the prince spawns facing right.
const STONE := """; Stone








      @                  D
##########################
##########################
"""

## The prince on a one-way floor three tiles over the stone.
const LEDGE := """; Ledge





      @
    ======



                         D
##########################
##########################
"""

## A ledge to run off: stone ends at column 12, and the floor is far below.
const LIP := """; Lip



   @
#############



                         D
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


func _state() -> String:
	return String(Player.State.find_key(_p().state))


## One press of `bits`, then a frame with nothing held, so the next tap is a
## press edge of its own.
func _tap(bits: int) -> void:
	_input.bits = bits
	await wait_physics_frames(1)
	_input.bits = 0
	await wait_physics_frames(1)


## Steps until `done` is true, at most `frames` frames. Returns `done`'s last.
func _until(done: Callable, frames: int) -> bool:
	for _frame: int in frames:
		if bool(done.call()):
			return true
		await wait_physics_frames(1)
	return bool(done.call())


func test_down_and_jump_on_stone_rolls_forward_along_the_floor() -> void:
	await _play(STONE)
	var start := _p().position
	var rolls := [0]
	_p().rolled.connect(func() -> void: rolls[0] += 1)
	await _tap(D | J)
	assert_eq(_state(), "ROLL", "down + JUMP on stone is a roll")
	assert_eq(rolls[0], 1, "and says so")
	var air := [false]
	await _until(func() -> bool:
		air[0] = air[0] or not _p().is_grounded()
		return _p().state != Player.State.ROLL, 60)
	assert_false(air[0], "the feet never left the floor")
	assert_almost_eq(_p().position.y, start.y, 0.5, "on the same floor")
	assert_almost_eq(_p().position.x - start.x, Tuning.roll_distance(), 3.0,
		"carried the roll's distance the way he faced")


func test_down_and_jump_on_a_one_way_floor_still_drops_through() -> void:
	await _play(LEDGE)
	var top := _p().position.y
	await _tap(D | J)
	assert_ne(_state(), "ROLL", "a one-way floor is not stone: no roll")
	await _until(func() -> bool: return _p().position.y > top + Tuning.TILE, 40)
	assert_gt(_p().position.y, top + Tuning.TILE, "the drop-through still drops")


func test_down_and_jump_at_a_run_is_still_the_jump() -> void:
	await _play(STONE)
	_input.bits = R
	await _until(func() -> bool: return absf(_p().velocity.x) >= Tuning.RUN_SPEED - 1.0, 40)
	await _tap(R | D | J)
	assert_eq(_state(), "JUMP", "at a run a drifting stick does not turn a jump into a roll")
	assert_lt(_p().velocity.y, 0.0, "going up")


func test_down_and_jump_in_the_air_is_a_dive_kick() -> void:
	await _play(STONE)
	_input.bits = J
	await _until(func() -> bool: return _p().velocity.y > 0.0, 60)
	_input.bits = 0
	await wait_physics_frames(1)
	await _tap(D | J)
	assert_eq(_state(), "DIVE_KICK", "down + JUMP in a fall is the dive kick")
	assert_eq(_p().velocity, Vector2(Tuning.DIVE_KICK_DRIFT, Tuning.DIVE_KICK_DROP),
		"a straight line, heel first")
	await _until(func() -> bool: return _p().state != Player.State.DIVE_KICK, 60)
	assert_eq(_state(), "KICK_LAND", "and the heel meeting stone plants him")


func test_a_late_jump_off_a_lip_keeps_its_press() -> void:
	await _play(LIP)
	_input.bits = R
	await _until(func() -> bool: return not _p().is_grounded(), 120)
	assert_false(_p().is_grounded(), "ran off the lip")
	await _tap(R | D | J)
	assert_eq(_state(), "JUMP", "in coyote time down + JUMP is the late jump, not a kick")


func test_the_plunge_the_parry_and_the_backstep_keep_their_inputs() -> void:
	await _play(STONE)
	await _tap(U | A)
	assert_eq(_state(), "PARRY", "up + SWORD parries")
	await _until(func() -> bool: return _p().state == Player.State.IDLE, 60)
	await _tap(L | A)
	assert_eq(_state(), "BACKSTEP", "back + SWORD steps back")
	await _until(func() -> bool: return _p().state == Player.State.IDLE, 60)
	_input.bits = J
	await _until(func() -> bool: return _p().velocity.y > 0.0, 60)
	_input.bits = 0
	await wait_physics_frames(1)
	await _tap(D | A)
	assert_eq(_state(), "PLUNGE", "down + SWORD in the air plunges")


func test_throw_throws_and_the_empty_hand_sweeps() -> void:
	await _play(STONE)
	await _tap(T)
	assert_eq(_state(), "THROW", "THROW throws")
	await _until(func() -> bool: return not _p().moves.armed(), 20)
	assert_true(_p().moves.blade.is_flying(), "the blade is in flight")
	await _until(func() -> bool: return _p().state == Player.State.IDLE, 30)
	await _tap(T)
	assert_eq(_state(), "IDLE", "with nothing in the hand THROW does nothing")
	await _tap(U | A)
	assert_eq(_state(), "IDLE", "nor does up + SWORD: there is no blade to parry with")
	await _tap(A)
	assert_eq(_state(), "SWEEP", "SWORD with no sword is the sweep")


func test_with_no_sword_there_is_no_plunge_or_slash() -> void:
	await _play(STONE)
	await _tap(T)
	await _until(func() -> bool: return _p().state == Player.State.IDLE, 40)
	assert_false(_p().moves.armed(), "thrown")
	_input.bits = J
	await _until(func() -> bool: return _p().velocity.y > 0.0, 60)
	_input.bits = 0
	await wait_physics_frames(1)
	await _tap(D | A)
	assert_eq(_state(), "FALL", "no plunge without a sword")
	await _tap(A)
	assert_eq(_state(), "FALL", "and no air slash")
	assert_eq(_p().attack_rect(), Rect2(), "and no blade anywhere")
