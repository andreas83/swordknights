extends GutTest
## Level directives (`;!` lines), mason's marks and declared marks
## (scripts/world/ascii_level.gd).
##
## A directive is a comment first. The two things the ASCII format has been
## burned by are a comment that ate a row of geometry and a header that moved
## the floor, so the first tests are that a directive can do neither: the
## grid is the same with and without them, and none is ever the title. Then
## the wiring the campaign is drafted in: a digit is a mason's mark, solid
## stone that wires the one mechanism it touches, and a mark that wires
## nothing, or two, is a problem with its cell named. Then `;! mark`, the
## per-level glyph, and `;! channel`, what a wire does. Every malformed line
## is a problem the author is told about rather than nothing.

## Test-only mechanism glyphs, the campaign's proposed two: a plate that is a
## floor stone, and a portcullis.
const PLATE := "o"
const GATE := "!"

const PLAIN := """; Wired Hall
; A test level.



  @   k        D
 #######  m ####
 #######  m ####
###############
"""

const WIRED := """;! time dusk
; Wired Hall
;! mark k plate channel=west
; A test level.
;! mark m gate channel=west width=2



  @   k        D
 #######  m ####
 #######  m ####
###############
"""

## A plate wired by the mark under it, a gate by the mark over it: the
## campaign's drafts, in miniature.
const MASONS := """;! channel 1 latch
; Masons




 ######1#####
       !
  @    !    D
###o#########
###1#########
"""


func before_all() -> void:
	Tiles.add_mechanism_for_test(PLATE, "plate", Tiles.Kind.SOLID)
	Tiles.add_mechanism_for_test(GATE, "gate")


func after_all() -> void:
	Tiles.remove_mechanism_for_test(PLATE)
	Tiles.remove_mechanism_for_test(GATE)


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


## --- directives ---------------------------------------------------------------

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


func test_a_hash_line_is_still_not_a_comment() -> void:
	var level := _parse("""; Hash Row
;! time dusk


 @    D
#  ####
#######
""")
	assert_eq(level.rows, 5, "'#  ####' is a row of the level, directive or no")
	assert_eq(level.kind_at(0, 3), Tiles.Kind.SOLID)


## --- mason's marks --------------------------------------------------------------

func test_a_mark_is_stone_that_wires_the_one_mechanism_it_touches() -> void:
	var level := _parse(MASONS)
	assert_eq(level.problems, PackedStringArray(), "the miniature is wired clean")
	var plates := _marks(level, "plate")
	var gates := _marks(level, "gate")
	assert_eq([plates.size(), gates.size()], [1, 1], "one plate, one gate")
	if plates.size() != 1 or gates.size() != 1:
		return
	assert_eq(plates[0]["params"].get("channel", ""), "1", "the plate carries its mark's digit")
	assert_eq(plates[0]["mark"], Vector2i(3, 8), "from the stone under it")
	assert_eq(gates[0]["params"].get("channel", ""), "1",
		"and so does the gate: same mark, same wire")
	assert_eq(gates[0]["mark"], Vector2i(7, 4), "from the lintel over it")
	assert_eq(gates[0]["cells"], [Vector2i(7, 5), Vector2i(7, 6)] as Array[Vector2i],
		"a portcullis two cells tall is one gate")
	for at: Vector2i in [Vector2i(3, 8), Vector2i(7, 4)]:
		assert_eq(level.kind_at(at.x, at.y), Tiles.Kind.SOLID, "a mark is stone at %s" % at)
	assert_eq(level.kind_at(3, 7), Tiles.Kind.SOLID, "the plate is a floor stone")
	assert_eq(level.kind_at(7, 6), Tiles.Kind.EMPTY, "the gate brings its own stone")
	assert_eq(level.channels, {"1": {"mode": "latch"}}, "and wire 1 latches")


func test_a_mark_that_wires_nothing_or_two_is_a_problem_with_its_cell() -> void:
	var level := _parse("""; Stray Marks


   2
  @ !!o5    D
###3###o#####
#############
""")
	var joined := "\n".join(level.problems)
	assert_string_contains(joined, "mason's mark '2' at column 3, row 2 touches 0 mechanisms")
	assert_string_contains(joined, "mason's mark '5' at column 7, row 3 touches 2 mechanisms")
	assert_string_contains(joined, "mason's mark '3' at column 3, row 4 touches 0 mechanisms")


func test_a_mechanism_touching_two_different_marks_is_a_problem() -> void:
	var level := _parse("""; Crossed Wires


     1
  @  !     D
#####2#####
""")
	assert_string_contains("\n".join(level.problems),
		"mason's mark '2' at column 5, row 4: the gate it touches already carries mark '1'")


## --- declared marks ---------------------------------------------------------------

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
	var level := _parse(""";! mark k plate channel=a
; Two Plates


 k @ D k
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


func test_a_copy_keeps_the_directives_and_the_wiring() -> void:
	var wired := _parse(WIRED)
	var copied := wired.copy()
	assert_eq(copied.directives, wired.directives)
	assert_eq(copied.declared, wired.declared)
	assert_eq(_marks(copied, "gate"), _marks(wired, "gate"), "and the marks they placed")
	var masons := _parse(MASONS)
	assert_eq(masons.copy().masons_marks, masons.masons_marks, "and the mason's marks")
	assert_eq(masons.copy().channels, masons.channels, "and the channels")


## --- channels --------------------------------------------------------------------

func test_a_channel_line_says_what_its_wire_does() -> void:
	var level := _parse(""";! channel 1 latch
;! channel 2 hold 4.0
;! channel 4 beat 0
;! channel 5 beat 50 period=120
;! channel west momentary
; Channels


 @ D
#####
""")
	assert_eq(level.problems, PackedStringArray())
	assert_eq(level.channels["1"], {"mode": "latch"})
	assert_eq(level.channels["2"], {"mode": "hold", "seconds": 4.0})
	assert_eq(level.channels["4"], {"mode": "beat", "phase": 0, "period": 100},
		"a beat's period is the campaign's 100 frames unless it says")
	assert_eq(level.channels["5"], {"mode": "beat", "phase": 50, "period": 120})
	assert_eq(level.channels["west"], {"mode": "momentary"})


## --- problems -------------------------------------------------------------------

func test_every_malformed_line_is_a_problem_and_breaks_nothing() -> void:
	var level := _parse(""";! mark # wall
;! mark 12 gate
;! mark 7 gate
;! mark k
;! mark u gate stray
;! mark q gate
;! mark q lift
;! tiem dusk
;! channel 3 stay
;! channel 3 hold
;! channel 6 beat
;! horizon high
;! checkpoints down
;! time
;!
; Problems


 @  ?  D
#########
""")
	var joined := "\n".join(level.problems)
	for expected: String in [
		"'#' already means something in the legend",
		"one character, not '12'",
		"'7' is a mason's mark, not a glyph to declare",
		"a mark needs a glyph and a kind",
		"'stray' is not key=value",
		"'q' is declared twice",
		"there is no directive 'tiem'",
		"not 'stay'",
		"a hold needs its seconds",
		"a beat needs its phase in frames",
		"a horizon is one row number",
		"checkpoints are ordered by 'x' or 'route'",
		"a time is one stop or one number",
		"a directive with nothing in it",
		"'?' is in no legend and not declared",
	]:
		assert_string_contains(joined, expected)
	assert_eq(level.declared.get("q", {}).get("kind", ""), "lift", "the last one wins")
	assert_eq(level.spawn_point, Vector2i(1, 2), "and the level is still parsed")
	assert_eq(level.kind_at(0, 3), Tiles.Kind.SOLID, "'#' in a mark line stays a tile")


func test_the_shipping_levels_have_no_problems() -> void:
	var checked := 0
	for name: String in DirAccess.get_files_at("res://levels"):
		# The duel's strip is ZoneStrip's manifest, a list of files.
		if name.get_extension() != "txt" or name == "duel_zones.txt":
			continue
		var level := AsciiLevel.from_file("res://levels".path_join(name))
		assert_eq(level.problems, PackedStringArray(), "%s parses clean" % name)
		assert_eq(EntityRegistry.problems_in(level), PackedStringArray(),
			"and every mark in it is a registered kind")
		checked += 1
	assert_gt(checked, 1, "found the levels")
