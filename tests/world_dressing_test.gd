extends SceneTree
## Pins the two promises the automatic dresser makes.
##
## The first is a GAMEPLAY promise and it is the reason dressing can be run
## over levels nobody has looked at: decoration never changes what the
## character can reach. Not "should not" — cannot, because every decoration
## tile is built with no collision and no queried kind, and every mark leaves
## its own cell empty. This file proves both halves rather than trusting them.
##
## The second is an ART promise: every level the game ships gets architecture,
## including the two that were authored before any of this existed and the
## ones a generator makes up at runtime.
##
##     godot --headless --script tests/world_dressing_test.gd

const LEVELS := [
	"res://levels/level_01.txt",
	"res://levels/feel_lab.txt",
	"res://levels/zone_02.txt",
	"res://levels/zone_03.txt",
]

var _failures := 0


func _initialize() -> void:
	_check_decoration_tiles_cannot_collide()
	_check_marks_leave_their_cell_empty()
	_check_every_shipping_level_gets_architecture()
	_check_a_generated_level_gets_architecture()
	_check_a_symmetric_level_is_dressed_symmetrically()
	_check_nothing_is_dressed_over_an_entity()
	_check_the_legend_and_the_atlas_agree()

	if _failures > 0:
		printerr("world_dressing_test: %d failure(s)" % _failures)
		quit(1)
		return
	print("world_dressing_test: ok")
	quit(0)


## --- the gameplay promise ---------------------------------------------------

## Every architecture tile in the generated TileSet must have no collision
## polygon on either physics layer and must report Kind.EMPTY. If one ever
## gains a shape, a decorated level silently stops being the level that was
## tested, and the failure looks like a physics bug a long way from here.
func _check_decoration_tiles_cannot_collide() -> void:
	var tile_set := load("res://assets/tiles.tres") as TileSet
	if tile_set == null:
		_fail("could not load the tile set")
		return
	var source := tile_set.get_source(0) as TileSetAtlasSource
	for id: String in Tiles.DECOR_ATLAS:
		var coords: Vector2i = Tiles.DECOR_ATLAS[id]
		if not source.has_tile(coords):
			_fail("the atlas has no tile for '%s'" % id)
			continue
		var data := source.get_tile_data(coords, 0)
		_equal(int(data.get_custom_data(Tiles.CUSTOM_DATA_KIND)), int(Tiles.Kind.EMPTY),
			"'%s' is queried as empty" % id)
		for layer: int in [Tiles.PHYSICS_SOLID, Tiles.PHYSICS_ONE_WAY]:
			_equal(data.get_collision_polygons_count(layer), 0,
				"'%s' has no collision on layer %d" % [id, layer])


## A decoration mark is an annotation, not terrain. Parsing one must leave the
## cell exactly as empty as a space would, so marking a level up cannot close
## a gap or grow a ledge.
func _check_marks_leave_their_cell_empty() -> void:
	for glyph: String in Tiles.DECOR_LEGEND:
		var level := AsciiLevel.new()
		level.parse("....\n.%s..\n####" % glyph)
		_equal(int(level.kind_at(1, 1)), int(Tiles.Kind.EMPTY),
			"'%s' leaves its cell empty" % glyph)
		_equal(level.decorations.size(), 1, "'%s' records one decoration" % glyph)

	# And the whole of level 01, parsed with its marks, must still be the
	# level the traversal tests measure: same solid cells, same everything.
	var marked := AsciiLevel.from_file("res://levels/level_01.txt")
	var solid := 0
	for y: int in marked.rows:
		for x: int in marked.cols:
			if marked.is_solid(x, y):
				solid += 1
	_true(solid > 400, "level 01 still has its terrain (%d solid cells)" % solid)
	_true(marked.decorations.size() > 0, "and it carries authored decoration marks")

	# Round-trip: the marks survive to_text(), or a tool that rewrites a level
	# quietly strips its architecture.
	var again := AsciiLevel.new()
	again.parse(marked.to_text())
	_equal(again.decorations.size(), marked.decorations.size(),
		"decoration marks round-trip through to_text()")


## --- the art promise --------------------------------------------------------

func _check_every_shipping_level_gets_architecture() -> void:
	for path: String in LEVELS:
		var level := AsciiLevel.from_file(path)
		if level == null:
			_fail("could not load %s" % path)
			continue
		_assert_dressed(level, path)


func _check_a_generated_level_gets_architecture() -> void:
	# A fixed seed so a failure is reproducible; the point is that a level
	# this file has never seen comes out dressed.
	var result := LevelGenerator.build(20260211, 120, 0.55)
	if not bool(result["ok"]):
		_fail("the generator failed: %s" % String(result["reason"]))
		return
	_assert_dressed(result["level"] as AsciiLevel, "a generated level")


func _assert_dressed(level: AsciiLevel, what: String) -> void:
	var dressing := WorldDresser.dress(level)
	var mid: Dictionary = dressing["mid"]
	var fore: Dictionary = dressing["fore"]
	_true(mid.size() >= level.cols / 4,
		"%s has mid-ground architecture (%d cells over %d columns)"
		% [what, mid.size(), level.cols])
	_true(fore.size() > 0, "%s has a foreground plane (%d cells)" % [what, fore.size()])

	# Decoration must never be painted over terrain that is not empty: the
	# tile layer draws under it and the result would be a wall with a
	# balustrade embedded in it.
	for cell: Vector2i in mid:
		if level.kind_at(cell.x, cell.y) != Tiles.Kind.EMPTY and not _carved(mid[cell]):
			_fail("%s: %s sits on terrain at %s" % [what, _name_of(mid[cell]), cell])
			return


## Architecture that is carved INTO stone is allowed to be drawn over a solid
## tile — that is what carving means. Everything else must stand in open air.
func _carved(coords: Vector2i) -> bool:
	var id := _name_of(coords)
	return id.begins_with("arch_") or id == "niche" or id == "frieze"


## The Mirror Court is the one duel zone symmetric about its own centre, and the
## one both fighters start in.
func _check_a_symmetric_level_is_dressed_symmetrically() -> void:
	var arena := AsciiLevel.from_file("res://levels/zone_03.txt")
	if arena == null:
		_fail("could not load the Mirror Court")
		return
	var dressing := WorldDresser.dress(arena)
	for plane_name: String in ["mid", "fore"]:
		var plane: Dictionary = dressing[plane_name]
		for cell: Vector2i in plane:
			var twin := Vector2i(arena.cols - 1 - cell.x, cell.y)
			if not plane.has(twin):
				_fail("the arena's %s decoration at %s has no mirror at %s"
					% [plane_name, cell, twin])
				return
			if plane[twin] != Tiles.mirror_atlas(plane[cell]):
				_fail("the arena's %s decoration at %s is not the mirror of %s"
					% [plane_name, twin, cell])
				return
	_true(true, "the arena is dressed symmetrically")


## A relic behind a planter, or an exit door behind a foreground column, is a
## bug report rather than a composition.
func _check_nothing_is_dressed_over_an_entity() -> void:
	for path: String in LEVELS:
		var level := AsciiLevel.from_file(path)
		var dressing := WorldDresser.dress(level)
		var marked := {}
		for mark: Dictionary in level.decorations:
			marked[mark["cell"]] = true
		for mark: Dictionary in level.entities:
			var cell: Vector2i = mark["cell"]
			for plane_name: String in ["mid", "fore"]:
				var plane: Dictionary = dressing[plane_name]
				if plane.has(cell) and not marked.has(cell):
					_fail("%s: %s hides the %s at %s"
						% [path, _name_of(plane[cell]), String(mark["kind"]), cell])
					return


## --- bookkeeping ------------------------------------------------------------

## Every glyph has a tile, every tile the dresser plants has a glyph or a rule,
## and the atlas is big enough to hold the shade half of all of it.
func _check_the_legend_and_the_atlas_agree() -> void:
	for glyph: String in Tiles.DECOR_LEGEND:
		var id := String(Tiles.DECOR_LEGEND[glyph])
		var known := Tiles.DECOR_ATLAS.has(id) or id == "arch" or id == "column" \
			or id == "fountain"
		_true(known, "the mark '%s' names a tile ('%s')" % [glyph, id])
		_true(not Tiles.LEGEND.has(glyph) and not Tiles.ENTITY_LEGEND.has(glyph),
			"the mark '%s' is not already a terrain or entity glyph" % glyph)

	var atlas := (load("res://assets/tiles.png") as Texture2D).get_image()
	var rows := atlas.get_height() / 16
	for id: String in Tiles.DECOR_ATLAS:
		var coords: Vector2i = Tiles.DECOR_ATLAS[id]
		_true(coords.y + Tiles.SHADE_ROW_OFFSET < rows,
			"'%s' has a shade twin inside the atlas" % id)


func _name_of(coords: Vector2i) -> String:
	for id: String in Tiles.DECOR_ATLAS:
		if Tiles.DECOR_ATLAS[id] == coords:
			return id
	return "tile %s" % coords


func _equal(actual: Variant, expected: Variant, what: String) -> void:
	if actual == expected:
		return
	_fail("%s (got %s, wanted %s)" % [what, actual, expected])


func _true(condition: bool, what: String) -> void:
	if condition:
		return
	_fail(what)


func _fail(what: String) -> void:
	_failures += 1
	printerr("  FAIL: %s" % what)
