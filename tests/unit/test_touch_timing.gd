extends GutTest
## A press is honoured whenever it is made, however short it is.
##
## A thumb on glass taps: the button is down for three or four frames, often
## one, and the press lands a little early or a little late. Two things in the
## character punished that, and these tests pin both fixes:
##
## - **The jump cut applied from the first frame.** Releasing jump multiplies
##   upward speed by JUMP_CUT_MULTIPLIER on every frame it is released, so a
##   one-frame tap rose about 7 px, and a jump buffered before landing and
##   released before touching down — the classic early tap — was cut on the
##   frame it fired and rose about 2 px: a jump that did not happen. Now the
##   cut waits for Tuning.MIN_JUMP_HOLD, so a tap is a short hop, not a twitch.
## - **A sword press outside a free ground state was dropped.** In the air, in
##   a turn, in a landing or in the tail of a swing, pressing attack did
##   nothing at all. It is now buffered for Tuning.ATTACK_BUFFER, exactly as
##   jump is.
##
## The character is stepped by hand, one `_physics_process()` per 60 Hz
## frame with the engine's own stepping switched off, so the frame a button
## goes down and up is exact.

const GAME_SCENE := "res://scenes/game.tscn"
const DT := 1.0 / 60.0

const FLAT := """; Flat








       @          D
###################
###################
"""

var _game: Game
var _player: Player
var _input: PlayerInput


func before_each() -> void:
	var data := AsciiLevel.new()
	data.parse(FLAT)
	var packed := load(GAME_SCENE) as PackedScene
	_game = packed.instantiate() as Game
	_game.level_source = data
	add_child_autofree(_game)
	# Let the tile collision reach the physics server, then take the clock.
	await wait_physics_frames(3)
	_game.set_physics_process(false)
	_player = _game.player
	_player.set_physics_process(false)
	_input = PlayerInput.new()
	_player.input = _input
	_step(0, 20)
	assert_true(_player.is_grounded(), "the prince starts on the floor")


func _step(bits: int, frames: int = 1) -> void:
	for _frame: int in frames:
		_input.apply_bits(bits)
		_player._physics_process(DT)


## Steps with no buttons until the prince is back on the floor; returns how far
## above where he started the feet went.
func _rise_until_landed(floor_y: float, frames: int = 120) -> float:
	var top := floor_y
	for _frame: int in frames:
		_step(0)
		top = minf(top, _player.position.y)
		if _player.is_grounded() and _player.velocity.y >= 0.0:
			break
	return floor_y - top


func test_a_one_frame_tap_is_a_hop_not_a_twitch() -> void:
	var floor_y := _player.position.y
	_step(PlayerInput.BIT_JUMP)
	var rise := _rise_until_landed(floor_y)
	assert_gte(rise, Tuning.TILE, "a tap clears a tile; it rose %.1f px" % rise)
	assert_lt(rise, Tuning.max_jump_rise() - 4.0,
		"and is still shorter than a held jump: the cut still means something")


func test_an_early_tap_buffered_before_landing_still_jumps() -> void:
	var floor_y := _player.position.y
	# Up off the floor with a full jump...
	_step(PlayerInput.BIT_JUMP, 30)
	# ...fall until a few frames above the floor, tap, and let go in the air.
	var tapped := false
	for _frame: int in 120:
		if not tapped and _player.velocity.y > 0.0 and _player.position.y > floor_y - 10.0:
			_step(PlayerInput.BIT_JUMP)
			tapped = true
			continue
		_step(0)
		if tapped and _player.is_grounded():
			break
	assert_true(tapped, "the tap was made in the air, released before landing")
	var rise := _rise_until_landed(floor_y)
	assert_gte(rise, Tuning.TILE, "the buffered jump fired as a hop: %.1f px" % rise)


func test_holding_jump_still_reaches_full_height() -> void:
	var floor_y := _player.position.y
	var top := floor_y
	for _frame: int in 30:
		_step(PlayerInput.BIT_JUMP)
		top = minf(top, _player.position.y)
	var rise := maxf(floor_y - top, _rise_until_landed(floor_y))
	assert_gte(rise, float(Tuning.hop_tiles()) * Tuning.TILE,
		"a held jump still clears the hop rise: %.1f px" % rise)


func test_a_sword_press_just_before_landing_swings_on_landing() -> void:
	var floor_y := _player.position.y
	_step(PlayerInput.BIT_JUMP, 30)
	var pressed := false
	var swung := false
	for _frame: int in 120:
		if not pressed and _player.velocity.y > 0.0 and _player.position.y > floor_y - 10.0:
			_step(PlayerInput.BIT_ATTACK)
			pressed = true
			continue
		_step(0)
		swung = swung or _player.state == Player.State.ATTACK
		if swung:
			break
	assert_true(pressed, "the press was made in the air")
	assert_true(swung, "and the sword came out when the feet touched down")


func test_a_sword_press_during_a_turn_swings_after_it() -> void:
	_step(PlayerInput.BIT_RIGHT, 30)
	_step(PlayerInput.BIT_LEFT)
	assert_eq(_player.state, Player.State.TURN, "running, then reversing, is a turn")
	_step(PlayerInput.BIT_LEFT | PlayerInput.BIT_ATTACK)
	var swung := false
	for _frame: int in 20:
		_step(0)
		if _player.state == Player.State.ATTACK:
			swung = true
			break
	assert_true(swung, "the press made mid-turn was kept, not eaten")
	assert_eq(_player.facing, -1, "and the swing faces the new way")


func test_a_stale_sword_press_does_not_fire_later() -> void:
	_step(PlayerInput.BIT_JUMP, 12)
	assert_false(_player.is_grounded(), "the prince is in the air")
	# Still rising, a long way above the floor.
	_step(PlayerInput.BIT_JUMP | PlayerInput.BIT_ATTACK)
	var swung := false
	for _frame: int in 120:
		_step(0)
		swung = swung or _player.state == Player.State.ATTACK
		if _player.is_grounded():
			break
	_step(0, 3)
	swung = swung or _player.state == Player.State.ATTACK
	assert_false(swung, "a press long before landing is forgotten, not hoarded")
