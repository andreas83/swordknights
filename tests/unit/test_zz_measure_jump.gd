extends GutTest
## TEMPORARY measurement, not committed.

const GAME_SCENE := "res://scenes/game.tscn"
const DT := 1.0 / 60.0
const FIGHTER_SCENE := "res://scenes/fighter.tscn"

const PRINCE_LEDGE := """; Ledge








   @
##############
##############
##############
##############
##########################################
"""

var _game: Game
var _player: Player
var _input: PlayerInput


func _prince() -> void:
	var data := AsciiLevel.new()
	data.parse(PRINCE_LEDGE)
	var packed := load(GAME_SCENE) as PackedScene
	_game = packed.instantiate() as Game
	_game.level_source = data
	add_child(_game)
	await wait_physics_frames(3)
	_game.set_physics_process(false)
	_player = _game.player
	_player.set_physics_process(false)
	_input = PlayerInput.new()
	_player.input = _input
	_pstep(0, 20)


func _pstep(bits: int, frames: int = 1) -> void:
	for _f: int in frames:
		_input.apply_bits(bits)
		_player._physics_process(DT)


func _reset_prince(x: float) -> void:
	_player.position = Vector2(x, _floor_y())
	_player.velocity = Vector2.ZERO
	_pstep(0, 30)


var _top_y := 0.0


func _floor_y() -> float:
	return _top_y


func test_prince() -> void:
	await _prince()
	var floor_y := _player.position.y
	_top_y = floor_y
	gut.p("prince floor y %.2f grounded %s" % [floor_y, _player.is_grounded()])
	# held jump standing
	_reset_prince(48.0)
	var res := _arc_prince(0, 99)
	gut.p("PRINCE held standing: %s" % str(res))
	for k: int in [1, 2, 3, 4, 5, 6, 8, 10]:
		_reset_prince(48.0)
		gut.p("PRINCE tap %d: %s" % [k, str(_arc_prince(0, k))])
	# running jump on the lower floor: start at x 260, run right
	_player.position = Vector2(240.0, _top_y + 64.0)
	_player.velocity = Vector2.ZERO
	_pstep(0, 30)
	_pstep(PlayerInput.BIT_RIGHT, 40)
	gut.p("PRINCE run vx %.1f" % _player.velocity.x)
	gut.p("PRINCE running held: %s" % str(_arc_prince(PlayerInput.BIT_RIGHT, 99)))
	# coyote: run off the ledge (ledge ends at x=14*16=224)
	for late: int in range(0, 10):
		_player.position = Vector2(140.0, _floor_y())
		_player.velocity = Vector2.ZERO
		_pstep(0, 20)
		var off := -1
		for f: int in 200:
			_pstep(PlayerInput.BIT_RIGHT)
			if not _player.is_grounded():
				off = f
				break
		# `late` more frames airborne, then press
		_pstep(PlayerInput.BIT_RIGHT, late)
		_pstep(PlayerInput.BIT_RIGHT | PlayerInput.BIT_JUMP)
		gut.p("PRINCE coyote late=%d vy=%.1f jumped=%s" % [
			late, _player.velocity.y, _player.velocity.y < -150.0])
	for early: int in range(0, 14):
		_reset_prince(48.0)
		var land := -1
		for f: int in 120:
			_pstep(PlayerInput.BIT_JUMP if f < 4 else 0)
			if f > 2 and _player.is_grounded():
				land = f
				break
		_reset_prince(48.0)
		var jumped := false
		for f: int in land + 6:
			var bits := PlayerInput.BIT_JUMP if f < 4 or f == land - early else 0
			_pstep(bits)
			if f > land - early and f > 8 and _player.velocity.y < -150.0:
				jumped = true
		gut.p("PRINCE buffer press %d steps before the landing step (%d): jumped=%s" % [early, land, jumped])
	_game.free()
	assert_true(true)


## Holds jump for `hold` frames (with `dir_bits`), then nothing but dir. Returns
## latency (frames from press to feet up), apex height, frames to apex, airtime,
## horizontal distance.
func _arc_prince(dir_bits: int, hold: int) -> Dictionary:
	var y0 := _player.position.y
	var x0 := _player.position.x
	var top := y0
	var apex_f := -1
	var left := -1
	var air := 0
	for f: int in 200:
		var bits := dir_bits | (PlayerInput.BIT_JUMP if f < hold else 0)
		_pstep(bits)
		if left < 0 and _player.position.y < y0 - 0.01:
			left = f + 1
		if _player.position.y < top:
			top = _player.position.y
			apex_f = f + 1
		if left > 0:
			air += 1
		if left > 0 and _player.is_grounded():
			break
	return {"latency": left, "apex": snappedf(y0 - top, 0.1), "apex_f": apex_f, "air": air,
		"dx": snappedf(_player.position.x - x0, 0.1)}


## --- fighter ---

const F_LEDGE := """
........................................
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
########################################
"""

var _level: Level
var _f: Fighter


func _fighter_stage() -> void:
	_level = Level.new()
	add_child(_level)
	var ascii := AsciiLevel.new()
	ascii.parse(F_LEDGE.strip_edges())
	_level.build(ascii)
	_level.tilemap.update_internals()
	var packed := load(FIGHTER_SCENE) as PackedScene
	_f = packed.instantiate() as Fighter
	_level.add_child(_f)
	_f.world = LevelWorld.new(_level)
	_f.setup(0, DuelTuning.new())


func _fstep(bits: int, frames: int = 1) -> void:
	for _i: int in frames:
		_f.input.apply_bits(bits)
		_f.simulate(DT)


func _reset_f(at: Vector2) -> void:
	_f.respawn_at(at, 1)
	_fstep(0, 10)


func test_fighter_before() -> void:
	await _fighter_run(true)


func test_fighter_after() -> void:
	await _fighter_run(false)


func _fighter_run(before: bool) -> void:
	await wait_physics_frames(2)
	_fighter_stage()
	if before:
		_f.tuning.jump_min_hold = 0
		_f.tuning.coyote_frames = 0
		_f.tuning.jump_buffer = 1
	gut.p("FIGHTER %s" % ("BEFORE" if before else "AFTER"))
	await wait_physics_frames(2)
	var top := Vector2(48.0, 10.0 * 16.0)
	_reset_f(top)
	gut.p("FIGHTER grounded %s y %.2f" % [_f.grounded, _f.position.y])
	gut.p("FIGHTER held standing: %s" % str(_arc_f(0, 99)))
	for k: int in [1, 2, 3, 4, 5, 6, 8, 10]:
		_reset_f(top)
		gut.p("FIGHTER tap %d: %s" % [k, str(_arc_f(0, k))])
	_reset_f(Vector2(300.0, 13.0 * 16.0))
	_fstep(PlayerInput.BIT_RIGHT, 20)
	gut.p("FIGHTER run vx %.1f" % _f.velocity.x)
	gut.p("FIGHTER running held: %s" % str(_arc_f(PlayerInput.BIT_RIGHT, 99)))
	for late: int in range(0, 8):
		_reset_f(Vector2(150.0, 10.0 * 16.0))
		for i: int in 200:
			_fstep(PlayerInput.BIT_RIGHT)
			if not _f.grounded:
				break
		_fstep(PlayerInput.BIT_RIGHT, late)
		_fstep(PlayerInput.BIT_RIGHT | PlayerInput.BIT_JUMP)
		gut.p("FIGHTER coyote late=%d vy=%.1f jumped=%s" % [
			late, _f.velocity.y, _f.velocity.y < -150.0])
	for early: int in range(0, 14):
		_reset_f(top)
		var land := -1
		for f: int in 120:
			_fstep(PlayerInput.BIT_JUMP if f < 4 else 0)
			if f > 2 and _f.grounded:
				land = f
				break
		_reset_f(top)
		var jumped := false
		for f: int in land + 6:
			var bits := PlayerInput.BIT_JUMP if f < 4 or f == land - early else 0
			_fstep(bits)
			if f > land - early and f > 8 and _f.velocity.y < -150.0:
				jumped = true
		gut.p("FIGHTER buffer press %d steps before the landing step (%d): jumped=%s" % [early, land, jumped])
	# down+jump while running: roll
	_reset_f(Vector2(300.0, 13.0 * 16.0))
	_fstep(PlayerInput.BIT_RIGHT, 10)
	_fstep(PlayerInput.BIT_RIGHT | PlayerInput.BIT_DOWN | PlayerInput.BIT_JUMP)
	gut.p("FIGHTER run+down+jump -> state %s" % Fighter.State.keys()[_f.state])
	_level.free()
	assert_true(true)


func _arc_f(dir_bits: int, hold: int) -> Dictionary:
	var y0 := _f.position.y
	var x0 := _f.position.x
	var top := y0
	var apex_f := -1
	var left := -1
	var air := 0
	for f: int in 200:
		var bits := dir_bits | (PlayerInput.BIT_JUMP if f < hold else 0)
		_fstep(bits)
		if left < 0 and _f.position.y < y0 - 0.01:
			left = f + 1
		if _f.position.y < top:
			top = _f.position.y
			apex_f = f + 1
		if left > 0:
			air += 1
		if left > 0 and _f.grounded:
			break
	return {"latency": left, "apex": snappedf(y0 - top, 0.1), "apex_f": apex_f, "air": air,
		"dx": snappedf(_f.position.x - x0, 0.1)}
