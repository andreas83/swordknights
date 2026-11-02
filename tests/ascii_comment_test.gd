extends SceneTree
## Regression test for the ASCII comment marker.
##
## '#' is a solid tile. When it also acted as a comment marker, a grid row
## whose first tile was solid and whose second was blank ("#  ###") was
## silently swallowed and every row below it shifted up by one — invisible in
## a diff, and it moves the floor out from under the player.
##
##     godot --headless --script tests/ascii_comment_test.gd

var _failures := 0


func _initialize() -> void:
	_solid_row_starting_with_hash_survives()
	_semicolon_is_a_comment()
	_title_comes_from_the_header()
	_level_01_round_trips()

	if _failures > 0:
		printerr("ascii_comment_test: %d failure(s)" % _failures)
		quit(1)
		return
	print("ascii_comment_test: ok")
	quit(0)


func _solid_row_starting_with_hash_survives() -> void:
	var level := AsciiLevel.new()
	level.parse("#  ###\n######\n")
	_equal(level.rows, 2, "a '# ' row is tiles, not a comment")
	_true(level.is_solid(0, 0), "the leading '#' is a solid tile")
	_true(not level.is_solid(1, 0), "the blank after it is empty")
	_true(level.is_solid(3, 0), "the rest of the row survived")


func _semicolon_is_a_comment() -> void:
	var level := AsciiLevel.new()
	level.parse("; a header\n;\n####\n")
	_equal(level.rows, 1, "';' lines are dropped")
	_true(level.is_solid(0, 0), "the grid row survived")


func _title_comes_from_the_header() -> void:
	var level := AsciiLevel.new()
	level.parse("; The Sun Terrace\n####\n")
	_equal(level.name, "The Sun Terrace", "title read from the first comment")


## The shipped level must survive a parse -> text -> parse round trip with its
## row count intact; that is what the old bug broke.
func _level_01_round_trips() -> void:
	var first := AsciiLevel.from_file("res://levels/level_01.txt")
	if first == null:
		_fail("could not load level_01")
		return
	var second := AsciiLevel.new()
	second.parse(first.to_text())
	_equal(second.rows, first.rows, "level_01 row count survives a round trip")
	_equal(second.cols, first.cols, "level_01 column count survives a round trip")


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
