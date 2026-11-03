extends GutTest
## Level directives (`;!` lines) and declared marks (scripts/world/ascii_level.gd).
##
## A directive is a comment first. The two things the ASCII format has been
## burned by are a comment that ate a row of geometry and a header that moved
## the floor, so the first tests are that a directive can do neither: the
## grid is the same with and without them, and none is ever the title. The
## rest pin `;! mark` -- a declared glyph's connected run is one entity at its
## bottom-left, with its parameters, in reading order -- and that every
## malformed line is a problem the author is told about rather than nothing.

const PLAIN := """; Wired Hall
; A test level.



  @   1        D
 #######  2 ####
 #######  2 ####
###############
"""

const WIRED := """;! time dusk
; Wired Hall
;! mark 1 plate channel=west
; A test level.
;! mark 2 gate channel=west width=2



  @   1        D
 #######  2 ####
 #######  2 ####
###############
"""


func _parse(text: String) -> AsciiLevel:
	var level := AsciiLevel.new()
	level.parse(text)
	return level


func _marks(level: AsciiLevel, kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for mark: Dictionary in level.entities:
		if String(mark["kind"]) == kind:
			out.append(mark)
	return out


func test_a_directive_never_moves_a_tile_and_is_never_the_title() -> void:
	var plain := _parse(PLAIN)
	var wired := _parse(WIRED)
	assert_eq(wired.name, "Wired Hall", "the title is the first plain comment")
	assert_eq([wired.cols, wired.rows], [plain.cols, plain.rows], "the same size")
	assert_eq(wired.spawn_point, plain.spawn_point, "the same spawn")
	for y: int in plain.rows:
		for x: int in plain.cols:
			if plain.kind_at(x, y) != wired.kind_at(x, y):
				fail_test("cell (%d, %d) changed under a directive" % [x, y])
				return
	pass_test("every cell is what it was without the directives")


func test_directives_are_kept_in_order_with_their_words() -> void:
	var wired := _parse(WIRED)
	var names: Array[String] = []
	for directive: Dictionary in wired.directives:
		names.append(String(directive["name"]))
	assert_eq(names, ["time", "mark", "mark"] as Array[String])
	var time := wired.directive("time")
	assert_eq(time["args"], PackedStringArray(["dusk"]), "plain words are arguments")
	var gate := wired.directives[2]
	assert_eq(gate["params"], {"channel": "west", "width": "2"}, "key=value words are params")
	assert_eq(wired.directive("nothing"), {}, "an absent directive is empty")


func test_a_declared_glyph_places_one_entity_per_connected_run() -> void:
	var wired := _parse(WIRED)
	var plates := _marks(wired, "plate")
	var gates := _marks(wired, "gate")
	assert_eq(plates.size(), 1, "one plate")
	assert_eq(gates.size(), 1, "one gate, though two cells: they touch")
	if plates.size() != 1 or gates.size() != 1:
		return
	assert_eq(plates[0]["cell"], Vector2i(6, 3))
	assert_eq(plates[0]["params"], {"channel": "west"}, "the declaration's params")
	assert_eq(gates[0]["cells"], [Vector2i(10, 4), Vector2i(10, 5)] as Array[Vector2i],
		"every cell of the run, in reading order")
	assert_eq(gates[0]["cell"], Vector2i(10, 5), "anchored at the bottom: where it stands")
	for cell: Vector2i in gates[0]["cells"]:
		assert_eq(wired.kind_at(cell.x, cell.y), Tiles.Kind.EMPTY,
			"a mark leaves its cell empty, like every entity mark")


func test_runs_that_do_not_touch_are_separate_entities_in_reading_order() -> void:
	var level := _parse(""";! mark 1 plate channel=a
; Two Plates


 1 @ D 1
#########
""")
	var kinds: Array[String] = []
	var cells: Array[Vector2i] = []
	for mark: Dictionary in level.entities:
		kinds.append(String(mark["kind"]))
		cells.append(mark["cell"])
	assert_eq(kinds, ["plate", "exit", "plate"] as Array[String],
		"declared marks sit in reading order among the legend's")
	assert_eq(cells, [Vector2i(1, 2), Vector2i(5, 2), Vector2i(7, 2)] as Array[Vector2i])


func test_every_malformed_line_is_a_problem_and_breaks_nothing() -> void:
	var level := _parse(""";! mark # wall
;! mark 12 gate
;! mark 3
;! mark 4 gate stray
;! mark 5 gate
;! mark 5 lift
;! tiem dusk
;!
; Problems


 @  ?  D
#########
""")
	var joined := "\n".join(level.problems)
	for expected: String in [
		"'#' already means something in the legend",
		"one character, not '12'",
		"a mark needs a glyph and a kind",
		"'stray' is not key=value",
		"'5' is declared twice",
		"there is no directive 'tiem'",
		"a directive with nothing in it",
		"'?' is in no legend and not declared",
	]:
		assert_string_contains(joined, expected)
	assert_eq(level.declared.get("5", {}).get("kind", ""), "lift", "the last one wins")
	assert_eq(level.spawn_point, Vector2i(1, 2), "and the level is still parsed")
	assert_eq(level.kind_at(0, 3), Tiles.Kind.SOLID, "'#' in a mark line stays a tile")


func test_a_copy_keeps_the_directives() -> void:
	var wired := _parse(WIRED)
	var copied := wired.copy()
	assert_eq(copied.directives, wired.directives)
	assert_eq(copied.declared, wired.declared)
	assert_eq(_marks(copied, "gate"), _marks(wired, "gate"), "and the marks they placed")


func test_a_hash_line_is_still_not_a_comment() -> void:
	var level := _parse("""; Hash Row
;! time dusk


 @    D
#  ####
#######
""")
	assert_eq(level.rows, 5, "'#  ####' is a row of the level, directive or no")
	assert_eq(level.kind_at(0, 3), Tiles.Kind.SOLID)


func test_the_shipping_levels_have_no_problems() -> void:
	var checked := 0
	for name: String in DirAccess.get_files_at("res://levels"):
		# The duel's strip is ZoneStrip's own format (zone headers inside it).
		if name.get_extension() != "txt" or name == "duel_zones.txt":
			continue
		var level := AsciiLevel.from_file("res://levels".path_join(name))
		assert_eq(level.problems, PackedStringArray(), "%s parses clean" % name)
		checked += 1
	assert_gt(checked, 1, "found the levels")
