extends GutTest
## The duel's jump forgives what the adventure's does (scripts/duel/fighter.gd,
## DuelTuning's jump windows; docs/duel-combat.md, "The jump").
##
## The owner, on a phone: jumping felt better in the adventure than in the
## duel. Measured frame by frame, the held arcs were not the difference -- the
## duel's is the spec's, two tiles in 21 frames -- the edges were. A thumb's tap
## of one frame rose 8 px (the cut was live from the first frame), a press one
## frame after the feet left an edge or one frame before they landed did
## nothing at all. The prince has a minimum hold, coyote time and a jump
## buffer, and so now has the fighter, counted in frames and carried in the
## snapshot.
##
## The coyote and buffer windows are measured here on BOTH characters, the same
## way, so "as forgiving as the adventure" is a number this file holds, not a
## claim. Seen to fail with the three windows set to nothing (jump_min_hold 0,
## coyote_frames 0, jump_buffer 1, which is the old fighter exactly): every
## test but the arc's and the dive kick's goes red; and with the counters
## left out of the flags word, the snapshot test.
##
## Real bodies on real tiles, stepped inside a physics frame.

const GAME_SCENE := "res://scenes/game.tscn"
const FIGHTER_SCENE := "res://scenes/fighter.tscn"
const DT := 1.0 / 60.0
const JUMP := PlayerInput.BIT_JUMP
const RIGHT := PlayerInput.BIT_RIGHT
const DOWN := PlayerInput.BIT_DOWN

## A ledge four tiles high and a floor beyond it, for both characters.
const PRINCE_LEDGE := """; A ledge








   @
##############
##############
##############
##############
##########################################
"""
const FIGHTER_LEDGE := """........................................
........................................
........................................
........................................
........................................
........................................
........................................
........................................
#.......................................
#.......................................
###############.........................
###############.........................
###############.........................
########################################"""
## Where the fighter stands on top of its ledge, and on the floor below it.
const TOP := Vector2(48.0, 160.0)
const LOW_FLOOR := Vector2(300.0, 208.0)

var _level: Level
var _fighter: Fighter
var _game: Game
var _player: Player
var _prince_input: PlayerInput
var _prince_top := 0.0


func after_each() -> void:
	if _level != null:
		_level.free()
		_level = null
	if _game != null:
		_game.free()
		_game = null


## --- the tap ------------------------------------------------------------------

## A tap of one to four frames is the same hop: two thirds of a full jump, as
## the prince's tap is two thirds of his. It used to rise 8, 13, 18 and 22 px.
func test_a_tap_is_a_hop_and_not_a_twitch() -> void:
	await _stage()
	var full := _fighter_apex(99)
	var hop := _fighter_apex(_fighter.tuning.jump_min_hold)
	for hold: int in range(1, _fighter.tuning.jump_min_hold + 1):
		assert_almost_eq(_fighter_apex(hold), hop, 0.01, "a %d-frame tap is the hop" % hold)
	assert_gt(hop, full * 0.6, "the hop is most of a jump (%.1f of %.1f px)" % [hop, full])
	assert_lt(hop, full * 0.75, "and still short of it: holding is the way up two tiles")
	assert_gt(_fighter_apex(6), hop, "a longer hold rises higher")


## The forgiveness changed no held arc: apex, airtime and reach are the
## profile DuelTuning derives, so no strip's gap or ledge moved.
func test_the_held_arc_is_unchanged() -> void:
	await _stage()
	var tuning := _fighter.tuning
	_reset(TOP)
	var y0 := _fighter.position.y
	var top := y0
	var air := 0
	for f: int in 120:
		_step(JUMP)
		top = minf(top, _fighter.position.y)
		air += 1
		if f > 0 and _fighter.grounded:
			break
	assert_almost_eq(y0 - top, tuning.jump_rise(), 1.0, "the apex is jump_rise()")
	assert_true(absi(air - tuning.jump_frames()) <= 1, "the airtime is jump_frames()")


## The computer's feet predict the jump the fighter makes. DuelFeet.leap()
## flies a one-frame hold as the min-hold one, as the fighter does, so the
## computer does not plan an 8 px twitch that comes out a 22 px hop.
func test_the_feet_predict_the_tap() -> void:
	await _stage()
	var tuning := _fighter.tuning
	var strip := DuelStrips.open(DuelStrips.TUG)
	var me := DuelView.Body.new()
	me.position = strip.start_position(0)
	me.velocity = Vector2.ZERO
	me.grounded = true
	var tap := DuelFeet.leap(strip, tuning, me, 0, true, 1)
	var hop := DuelFeet.leap(strip, tuning, me, 0, true, tuning.jump_min_hold)
	assert_true(bool(tap["landed"]), "the predicted tap lands")
	assert_eq(int(tap["frames"]), int(hop["frames"]), "a tap is predicted as the hop")
	_reset(TOP)
	var frames := 0
	for f: int in 120:
		_step(JUMP if f == 0 else 0)
		frames += 1
		if f > 0 and _fighter.grounded:
			break
	assert_true(absi(int(tap["frames"]) + 1 - frames) <= 1,
		"leap() lands on frame %d, the fighter on %d" % [int(tap["frames"]) + 1, frames])


## --- the edges, against the adventure -------------------------------------------

## Off an edge, JUMP still jumps for as many frames as it does for the prince.
func test_the_coyote_window_is_the_adventures() -> void:
	await _stage()
	var duel := _fighter_coyote_presses()
	_level.free()
	_level = null
	await _prince_stage()
	var adventure := _prince_coyote_presses()
	assert_gt(adventure, 0, "the prince forgives a late press at all")
	assert_eq(duel, adventure, "the fighter forgives as many late frames as the prince")
	assert_eq(duel, _fighter_tuning().coyote_frames - 1, "which is coyote_frames less one")


## A press before the feet land jumps on landing, as far ahead as the prince's.
func test_the_buffer_is_the_adventures() -> void:
	await _stage()
	var duel := _fighter_buffered_presses()
	_level.free()
	_level = null
	await _prince_stage()
	var adventure := _prince_buffered_presses()
	assert_gt(adventure, 1, "the prince keeps an early press")
	assert_eq(duel, adventure, "the fighter keeps it exactly as long")


## A JUMP pressed in the rise at the end of a roll -- a commitment that reads no
## input -- jumps on the first free frame instead of being eaten.
func test_a_jump_pressed_while_rising_fires_when_free() -> void:
	await _stage()
	_reset(LOW_FLOOR)
	_step(DOWN | JUMP)
	assert_eq(_fighter.state, Fighter.State.ROLLING, "down + JUMP rolls")
	while _fighter.state == Fighter.State.ROLLING:
		_step(0)
	assert_eq(_fighter.state, Fighter.State.RISING, "and the roll rises")
	_step(JUMP)
	var jumped := false
	for f: int in _fighter.tuning.roll_recover + 2:
		_step(JUMP)
		if _fighter.velocity.y < 0.0:
			jumped = true
			break
	assert_true(jumped, "the press made in the rise jumps once the fighter is free")


## Down + JUMP is chosen on its frame: in the air it is a dive kick at once,
## and pressed in a commitment it is not queued as a roll for later.
func test_down_and_jump_is_never_queued() -> void:
	await _stage()
	_reset(LOW_FLOOR)
	_step(JUMP)
	_step(0, 3)
	_step(DOWN | JUMP)
	assert_eq(_fighter.state, Fighter.State.DIVEKICK, "down + JUMP in the air kicks")
	_reset(LOW_FLOOR)
	_step(DOWN | JUMP)
	while _fighter.state == Fighter.State.ROLLING:
		_step(0)
	_step(DOWN | JUMP)
	for f: int in 20:
		_step(DOWN)
		assert_ne(_fighter.state, Fighter.State.ROLLING, "no second roll comes out of the rise")


## The three windows are snapshot state: a fighter restored from a snapshot
## taken with a press waiting in the buffer jumps on the same frame, to the
## same byte, as the one that was never restored.
func test_the_windows_survive_a_snapshot() -> void:
	await _stage()
	var land := _landing_step(4)
	_reset(TOP)
	for f: int in land - 5:
		_step(JUMP if f < 4 else 0)
	_step(JUMP)
	var bytes := PackedByteArray()
	bytes.resize(Fighter.state_bytes())
	_fighter.write_state(bytes, 0)
	var straight := _trace(12)
	_fighter.read_state(bytes, 0)
	var restored := _trace(12)
	assert_eq(restored, straight, "the restored fighter takes the same frames")
	assert_true(straight.has(true), "and the buffered press did jump in them")


## --- the fighter ----------------------------------------------------------------

func _stage() -> void:
	await wait_physics_frames(1)
	_level = Level.new()
	add_child(_level)
	var ascii := AsciiLevel.new()
	ascii.parse(FIGHTER_LEDGE)
	_level.build(ascii)
	_level.tilemap.update_internals()
	_fighter = (load(FIGHTER_SCENE) as PackedScene).instantiate() as Fighter
	_level.add_child(_fighter)
	_fighter.world = LevelWorld.new(_level)
	_fighter.setup(0, DuelTuning.new())
	await wait_physics_frames(1)


func _fighter_tuning() -> DuelTuning:
	return DuelTuning.new()


func _step(bits: int, frames: int = 1) -> void:
	for _f: int in frames:
		_fighter.input.apply_bits(bits)
		_fighter.simulate(DT)


func _reset(at: Vector2) -> void:
	_fighter.respawn_at(at, 1)
	_step(0, 10)


func _fighter_apex(hold: int) -> float:
	_reset(TOP)
	var y0 := _fighter.position.y
	var top := y0
	for f: int in 120:
		_step(JUMP if f < hold else 0)
		top = minf(top, _fighter.position.y)
		if f > 0 and _fighter.grounded:
			break
	return y0 - top


## Frames until the feet are down again, with jump held `hold` frames.
func _landing_step(hold: int) -> int:
	_reset(TOP)
	for f: int in 120:
		_step(JUMP if f < hold else 0)
		if f > 2 and _fighter.grounded:
			return f
	return -1


## How many frames after the feet leave the ledge a press still jumps.
func _fighter_coyote_presses() -> int:
	var count := 0
	for late: int in 12:
		_reset(Vector2(150.0, TOP.y))
		for _f: int in 200:
			_step(RIGHT)
			if not _fighter.grounded:
				break
		_step(RIGHT, late)
		_step(RIGHT | JUMP)
		if _fighter.velocity.y < 0.0:
			count += 1
		else:
			break
	return count


## How many frames before the landing frame -- that frame included -- a press
## still jumps on landing.
func _fighter_buffered_presses() -> int:
	var land := _landing_step(4)
	var count := 0
	for early: int in 16:
		_reset(TOP)
		var jumped := false
		for f: int in land + 6:
			_step(JUMP if f < 4 or f == land - early else 0)
			if f > land - early and f > 8 and _fighter.velocity.y < 0.0:
				jumped = true
		if not jumped:
			break
		count += 1
	return count


## Whether the fighter is rising, frame by frame, with nothing pressed -- and
## its position, so a restored fighter must match it to the byte.
func _trace(frames: int) -> Array:
	var out := []
	for _f: int in frames:
		_step(0)
		out.append(_fighter.velocity.y < 0.0)
		out.append(_fighter.position)
	return out


## --- the prince -------------------------------------------------------------------

func _prince_stage() -> void:
	var data := AsciiLevel.new()
	data.parse(PRINCE_LEDGE)
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Game
	_game.level_source = data
	add_child(_game)
	await wait_physics_frames(3)
	_game.set_physics_process(false)
	_player = _game.player
	_player.set_physics_process(false)
	_prince_input = PlayerInput.new()
	_player.input = _prince_input
	_prince_step(0, 20)
	_prince_top = _player.position.y


func _prince_step(bits: int, frames: int = 1) -> void:
	for _f: int in frames:
		_prince_input.apply_bits(bits)
		_player._physics_process(DT)


func _prince_reset(x: float) -> void:
	_player.position = Vector2(x, _prince_top)
	_player.velocity = Vector2.ZERO
	_prince_step(0, 30)


func _prince_coyote_presses() -> int:
	var count := 0
	for late: int in 12:
		_prince_reset(140.0)
		for _f: int in 200:
			_prince_step(RIGHT)
			if not _player.is_grounded():
				break
		_prince_step(RIGHT, late)
		_prince_step(RIGHT | JUMP)
		if _player.velocity.y < 0.0:
			count += 1
		else:
			break
	return count


func _prince_buffered_presses() -> int:
	_prince_reset(48.0)
	var land := -1
	for f: int in 120:
		_prince_step(JUMP if f < 4 else 0)
		if f > 2 and _player.is_grounded():
			land = f
			break
	var count := 0
	for early: int in 16:
		_prince_reset(48.0)
		var jumped := false
		for f: int in land + 6:
			_prince_step(JUMP if f < 4 or f == land - early else 0)
			if f > land - early and f > 8 and _player.velocity.y < 0.0:
				jumped = true
		if not jumped:
			break
		count += 1
	return count
