extends GutTest
## The prince's idle: when it starts, what stops it, and that it is only ever a
## picture.
##
## The ladder is checked on a bare IdleArt clock, which needs no scene. The
## rest plays the real game scene on a flat floor with the prince stepped by
## hand -- one `_physics_process()` and then one IdleArt `_process()` per 60 Hz
## frame, the order Godot runs them in -- so "the same frame" means exactly
## that, and the simulation can be traced frame by frame.

const GAME_SCENE := "res://scenes/game.tscn"
const FIGHTER_SCENE := "res://scenes/fighter.tscn"
const DT := 1.0 / 60.0
## A spell whose first eight bits include all five, so the trace sees each.
const SPELL := 1

const FLAT := """; Flat








       @          D
###################
###################
"""

## Every button on the wire, one at a time.
const BUTTONS: Array[int] = [
	PlayerInput.BIT_LEFT, PlayerInput.BIT_RIGHT, PlayerInput.BIT_UP, PlayerInput.BIT_DOWN,
	PlayerInput.BIT_JUMP, PlayerInput.BIT_ATTACK, PlayerInput.BIT_WALK, PlayerInput.BIT_THROW,
]

var _game: Game
var _player: Player
var _idle: IdleArt
var _art: PlayerArt
var _input: PlayerInput
var _start := Vector2.ZERO
var _played := {}


## A fresh clock, outside any scene.
func _clock(spell: int) -> IdleArt:
	var idle: IdleArt = autofree(IdleArt.new())
	idle.spell_seed = spell
	return idle


func _scene() -> void:
	var data := AsciiLevel.new()
	data.parse(FLAT)
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Game
	_game.level_source = data
	add_child_autofree(_game)
	await wait_physics_frames(3)
	_game.set_physics_process(false)
	_player = _game.player
	_player.set_physics_process(false)
	_input = PlayerInput.new()
	_player.input = _input
	_art = _player.get_node("PlayerArt") as PlayerArt
	_idle = _art.idle_art
	assert_not_null(_idle, "the prince's art gives him an idle")
	_idle.set_process(false)
	_settle()
	_start = _player.position


## One 60 Hz frame in engine order: the simulation, then the idle's clock.
func _frame(bits: int, idle_on: bool = true) -> void:
	_input.apply_bits(bits)
	_player._physics_process(DT)
	if idle_on:
		_idle._process(DT)


## Nothing pressed until he is standing on the floor again.
func _settle() -> void:
	for _f: int in 180:
		_frame(0)
		if _player.state == Player.State.IDLE and _player.is_grounded():
			return


## Quiet frames until a long bit is playing.
func _into_a_bit() -> void:
	for _f: int in roundi((IdleArt.BIT_AFTER + 0.5) / DT):
		_frame(0)


func _guard_at(offset: Vector2) -> Patrol:
	var guard := Patrol.new()
	guard.position = _player.position + offset
	_game.get_node("Entities").add_child(guard)
	guard.set_physics_process(false)
	return guard


## --- the ladder --------------------------------------------------------------

func test_the_ladder_escalates_from_nothing_to_fidgets_to_bits() -> void:
	var idle := _clock(7)
	var first_fidget := -1.0
	var first_bit := -1.0
	var longs: Array[IdleArt.Bit] = []
	var last := IdleArt.Bit.NONE
	for frame: int in roundi(80.0 / DT):
		idle.advance(DT, true)
		var t := float(frame + 1) * DT
		if idle.bit == IdleArt.Bit.NONE:
			last = IdleArt.Bit.NONE
			continue
		if t < IdleArt.FIDGET_AFTER:
			fail_test("something played %.2f s in, before FIDGET_AFTER" % t)
			return
		if first_fidget < 0.0:
			first_fidget = t
		if IdleArt.LONG.has(idle.bit):
			if first_bit < 0.0:
				first_bit = t
			if idle.bit != last:
				longs.append(idle.bit)
		elif t < IdleArt.BIT_AFTER:
			assert_has(IdleArt.SUBTLE, idle.bit, "only fidgets before BIT_AFTER")
		last = idle.bit
	assert_almost_eq(first_fidget, IdleArt.FIDGET_AFTER, DT * 1.5, "the first fidget is on time")
	assert_almost_eq(first_bit, IdleArt.BIT_AFTER, DT * 1.5, "the first bit is on time")
	assert_gte(longs.size(), 6, "a bit every CYCLE: %s" % [longs])
	var kinds := {}
	for i: int in longs.size():
		kinds[longs[i]] = true
		if i > 0:
			assert_ne(longs[i], longs[i - 1], "never the same bit twice running: %s" % [longs])
	assert_gte(kinds.size(), 3, "at least three different bits: %s" % [longs])


func test_bits_are_longer_than_fidgets_and_every_bit_comes_up() -> void:
	for fidget: IdleArt.Bit in IdleArt.SUBTLE:
		for bit: IdleArt.Bit in IdleArt.LONG:
			assert_gt(float(IdleArt.LENGTH[bit]), 2.0 * float(IdleArt.LENGTH[fidget]),
				"a bit is a different scale of thing from a fidget")
			assert_lt(float(IdleArt.LENGTH[bit]), IdleArt.CYCLE_FIDGET_AT,
				"and is over before the cycle's fidget")
	var seen := {}
	for spell: int in 30:
		var idle := _clock(spell)
		for cycle: int in 4:
			seen[idle.long_bit(cycle)] = true
	assert_eq(seen.size(), IdleArt.LONG.size(), "every bit is reachable")


func test_anything_but_calm_starts_the_ladder_again() -> void:
	var idle := _clock(3)
	for _f: int in roundi((IdleArt.BIT_AFTER + 1.0) / DT):
		idle.advance(DT, true)
	assert_has(IdleArt.LONG, idle.bit, "deep in a bit")
	idle.advance(DT, false)
	assert_eq(idle.bit, IdleArt.Bit.NONE, "dropped on the frame")
	assert_eq(idle.still, 0.0, "and the clock is back at zero")
	for _f: int in roundi((IdleArt.FIDGET_AFTER - 0.1) / DT):
		idle.advance(DT, true)
		assert_eq(idle.bit, IdleArt.Bit.NONE, "a whole quiet spell again before anything")


## --- cancelling ------------------------------------------------------------

func test_every_button_cancels_the_bit_on_the_frame_it_goes_down() -> void:
	await _scene()
	for button: int in BUTTONS:
		_settle()
		_into_a_bit()
		assert_has(IdleArt.LONG, _idle.bit, "a bit is playing before %d" % button)
		var rest := {"marker": true}
		_frame(button)
		assert_eq(_idle.bit, IdleArt.Bit.NONE, "button %d drops the bit on its frame" % button)
		assert_same(_idle.pose(rest), rest, "and the figure is in its own pose that frame")
		_frame(0)


func test_no_state_but_idle_is_calm() -> void:
	await _scene()
	assert_true(IdleArt.is_calm(_player), "standing still on an empty floor")
	for state: int in Player.State.values():
		if state == Player.State.IDLE:
			continue
		_player.state = state as Player.State
		assert_false(IdleArt.is_calm(_player),
			"no idle in %s" % Player.State.keys()[state])
	_player.state = Player.State.IDLE


## --- guards ----------------------------------------------------------------

func test_no_idle_with_a_guard_in_frame() -> void:
	await _scene()
	var guard := _guard_at(Vector2(IdleArt.GUARD_NEAR.x - 2.0, 0.0))
	for _f: int in roundi(30.0 / DT):
		_frame(0)
		if _idle.bit != IdleArt.Bit.NONE or _idle.still > 0.0:
			fail_test("idled with a guard %.0f px away" % (IdleArt.GUARD_NEAR.x - 2.0))
			return
	pass_test("thirty seconds beside a guard and not a fidget")

	guard.position = _player.position + Vector2(-IdleArt.GUARD_NEAR.x - 2.0, 0.0)
	_into_a_bit()
	assert_has(IdleArt.LONG, _idle.bit, "a guard just out of frame does not stop it")

	guard.position = _player.position + Vector2(0.0, IdleArt.GUARD_NEAR.y + 2.0)
	_frame(0)
	assert_true(IdleArt.is_calm(_player), "nor one on a floor out of frame")

	guard.position = _player.position + Vector2(-IdleArt.GUARD_NEAR.x + 2.0, 0.0)
	_frame(0)
	assert_eq(_idle.bit, IdleArt.Bit.NONE, "a guard walking into frame ends the bit at once")


func test_a_guard_in_its_raise_holds_the_idle_from_anywhere() -> void:
	await _scene()
	var guard := _guard_at(Vector2(IdleArt.GUARD_NEAR.x * 3.0, 0.0))
	assert_true(IdleArt.is_calm(_player), "a walking guard far off is not a threat")
	for state: Patrol.State in [Patrol.State.WINDUP, Patrol.State.STRIKE,
			Patrol.State.RECOVER]:
		guard.state = state
		assert_false(IdleArt.is_calm(_player), "but one in %s is" % Patrol.State.keys()[state])
	guard.state = Patrol.State.DYING
	guard.position = _player.position + Vector2(20.0, 0.0)
	assert_true(IdleArt.is_calm(_player), "and a dying one, however close, is scenery")


## --- only a picture ---------------------------------------------------------

## The simulation's whole visible state for one frame.
func _snapshot() -> Array:
	var shape := _player.get_node("CollisionShape2D") as CollisionShape2D
	var rect := shape.shape as RectangleShape2D
	return [
		_player.position - _start, _player.velocity, _player.state, _player.state_time,
		_player.facing, _player.health, _player.invulnerable, _player.is_grounded(),
		_player.collision_layer, _player.collision_mask, shape.position, rect.size,
		_player.body_rect().size, _player.attack_rect().size,
	]


## A hundred quiet seconds -- every fidget and every bit, with SPELL -- then a
## run, a jump, a swing and a crouch, as [buttons, frames].
const SCRIPT: Array[Vector2i] = [
	Vector2i(0, 6000), Vector2i(PlayerInput.BIT_RIGHT, 20),
	Vector2i(PlayerInput.BIT_RIGHT | PlayerInput.BIT_JUMP, 12), Vector2i(0, 50),
	Vector2i(PlayerInput.BIT_ATTACK, 1), Vector2i(0, 30),
	Vector2i(PlayerInput.BIT_DOWN, 12), Vector2i(0, 20),
]


## Plays SCRIPT in a fresh game scene, tracing the simulation every frame.
## Fresh rather than respawned, because move_and_slide() keeps engine-side
## state a respawn cannot reset. Nothing here awaits a frame: an engine
## physics step between two hand-stepped frames is a wall-clock accident, and
## it moved the prince by hundredths of a pixel between two runs with the idle
## off on both. So the idle's pose is asked for the way PlayerArt._draw() asks
## for it, every frame, and the props are left to the pose renderer.
func _play(idle_on: bool) -> Array:
	if _game != null:
		_game.free()
	await _scene()
	# The scene's first frames are stepped by the wall clock, so how long he
	# took to settle and the last thousandth of a pixel he settled at vary from
	# scene to scene. Put him back on the whole-pixel floor line with his
	# clocks at zero, so both runs start from the same numbers.
	_start = _player.position.round()
	_player.respawn(_start)
	_idle.spell_seed = SPELL
	var trace := []
	for step: Vector2i in SCRIPT:
		for _f: int in step.y:
			_frame(step.x, idle_on)
			# What PlayerArt._draw() asks for: the pose with the bit laid over.
			_art._posture()
			trace.append(_snapshot())
			_played[_idle.bit] = true
	return trace


func test_idle_never_touches_the_body_or_the_simulation() -> void:
	var without: Array = await _play(false)
	assert_eq(_played.keys(), [IdleArt.Bit.NONE], "the idle stayed off the first time")
	_played.clear()
	var with_idle: Array = await _play(true)

	assert_true(_played.has(IdleArt.SUBTLE[0]) or _played.has(IdleArt.SUBTLE[1]),
		"a fidget played")
	for bit: IdleArt.Bit in IdleArt.LONG:
		assert_true(_played.has(bit),
			"%s played: this test measures something" % IdleArt.Bit.keys()[bit])
	assert_eq(with_idle.size(), without.size(), "the same number of frames")
	for i: int in mini(with_idle.size(), without.size()):
		if with_idle[i] != without[i]:
			fail_test("frame %d differs with the idle on:\n  off %s\n  on  %s"
				% [i, without[i], with_idle[i]])
			return
	pass_test("the same simulation, frame for frame")


func test_drawing_every_bit_changes_nothing() -> void:
	await _scene()
	var before := _snapshot()
	var drawn := 0
	for bit: IdleArt.Bit in IdleArt.SUBTLE + IdleArt.LONG:
		var length := float(IdleArt.LENGTH[bit])
		for step: int in 8:
			_idle.pin(bit, length * float(step) / 8.0)
			_idle.queue_redraw()
			_art.queue_redraw()
			await wait_process_frames(1)
			drawn += 1
			assert_eq(_snapshot(), before, "drawing %s at step %d"
				% [IdleArt.Bit.keys()[bit], step])
	assert_eq(drawn, 8 * (IdleArt.SUBTLE.size() + IdleArt.LONG.size()), "drew every bit")


## --- the duel ----------------------------------------------------------------

func test_nobody_idles_in_a_duel() -> void:
	var fighter := (load(FIGHTER_SCENE) as PackedScene).instantiate() as Fighter
	add_child_autofree(fighter)
	fighter.setup(0, null)
	var art := FighterArt.dress(fighter, 0)
	await wait_process_frames(2)
	assert_true(art.is_inside_tree(), "the fighter is dressed")
	assert_null(art.idle_art, "FighterArt never attaches an idle")
	var idles := 0
	for node: Node in fighter.find_children("*", "", true, false):
		idles += 1 if node is IdleArt else 0
	assert_gt(fighter.find_children("*", "", true, false).size(), 0, "searched the fighter")
	assert_eq(idles, 0, "and there is no IdleArt anywhere under the fighter")
