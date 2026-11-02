extends SceneTree
## Pins the traversal grammar to the jump arc.
##
## The levels — hand-authored and generated — assume a 2-tile rise is a hop, a
## 3-tile rise needs a one-way platform step and a 4-tile rise needs a ledge
## grab. Those are derived from Tuning, not chosen, so this test is what stops
## a retune from silently making level geometry unreachable.
##
##     godot --headless --script tests/tuning_grammar_test.gd

var _failures := 0


func _initialize() -> void:
	_check_grammar_constants()
	_check_level_01_matches_the_grammar()

	if _failures > 0:
		printerr("tuning_grammar_test: %d failure(s)" % _failures)
		quit(1)
		return
	print("tuning_grammar_test: ok")
	quit(0)


func _check_grammar_constants() -> void:
	_equal(Tuning.hop_tiles(), 2, "hop_tiles")
	_equal(Tuning.platform_step_tiles(), 3, "platform_step_tiles")
	_equal(Tuning.grab_tiles(), 4, "grab_tiles")

	# A hop must clear its own rise and fall short of the next one up.
	var rise := Tuning.max_jump_rise()
	_true(rise >= Tuning.hop_tiles() * Tuning.TILE,
		"a jump must actually clear hop_tiles (%.2f px)" % rise)
	_true(rise < (Tuning.hop_tiles() + 1) * Tuning.TILE,
		"a jump must NOT reach platform_step_tiles (%.2f px)" % rise)


## Level 01's ledge-grab wall is the canonical example: the terrace the player
## jumps from and the wall top they catch must be exactly grab_tiles() apart.
func _check_level_01_matches_the_grammar() -> void:
	var level := AsciiLevel.from_file("res://levels/level_01.txt")
	if level == null:
		_fail("could not load level_01")
		return

	var terrace_top := _first_solid_row(level, 5)
	var wall_top := _first_solid_row(level, 35)
	_true(terrace_top > 0 and wall_top > 0, "found both the terrace and the wall")
	_equal(terrace_top - wall_top, Tuning.grab_tiles(),
		"level 01's grab wall is grab_tiles() above the terrace")

	# And the spawn must sit on solid ground with headroom.
	var spawn := level.spawn_point
	_true(level.is_solid(spawn.x, spawn.y + 1), "spawn stands on solid ground")
	_true(not level.is_solid(spawn.x, spawn.y), "spawn cell itself is clear")


func _first_solid_row(level: AsciiLevel, column: int) -> int:
	for y: int in level.rows:
		if level.is_solid(column, y):
			return y
	return -1


func _equal(actual: Variant, expected: Variant, what: String) -> void:
	if actual == expected:
		return
	_fail("%s: expected %s, got %s" % [what, str(expected), str(actual)])


func _true(condition: bool, what: String) -> void:
	if not condition:
		_fail(what)


func _fail(message: String) -> void:
	_failures += 1
	printerr("  FAIL  " + message)
