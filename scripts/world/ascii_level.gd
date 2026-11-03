class_name AsciiLevel
extends RefCounted
## Parses an ASCII level into a tile grid plus entity spawn marks.
##
## The format stays human-editable on purpose: a level is reviewable in a diff
## and a generator can emit one without touching the engine.
##
## Comments start with ';' and nothing else. '#' is deliberately NOT a comment
## marker even though it reads like one: '#' is a solid tile, so a grid row
## whose first tile is solid and whose second is blank ("#  ###") would be
## swallowed as a comment and every row below it would silently shift up by
## one. That is invisible in a diff and moves the floor out from under the
## player, so the ambiguity is removed rather than documented.

var cols: int = 0
var rows: int = 0
var spawn_point: Vector2i = Vector2i(2, 2)
## Array of { kind: String, cell: Vector2i }
var entities: Array[Dictionary] = []
## Array of { id: String, cell: Vector2i }. Architecture the author placed by
## hand. WorldDresser merges these with the rules it applies automatically, so
## a level can be decorated, left alone, or anything in between.
var decorations: Array[Dictionary] = []
var name: String = "Untitled"

var _grid: PackedInt32Array = PackedInt32Array()


static func from_file(path: String) -> AsciiLevel:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("could not open level %s (%d)" % [path, FileAccess.get_open_error()])
		return null
	var text := file.get_as_text()
	file.close()
	var level := AsciiLevel.new()
	level.parse(text)
	# parse() picks the title out of the leading comment block; fall back to the
	# file name only when the level carries no title of its own.
	if level.name == "Untitled":
		level.name = path.get_file().get_basename()
	return level


const COMMENT_MARKER := ";"


static func is_comment(line: String) -> bool:
	return line.begins_with(COMMENT_MARKER)


func parse(text: String) -> void:
	var lines: Array[String] = []
	for raw: String in text.split("\n", true):
		var line := raw.trim_suffix("\r")

		# Catch files still using the old '#' header. Tested by content rather
		# than by position: "#  ###" is a legitimate first row, while
		# "# The Sun Terrace" contains glyphs no tile uses.
		if line.begins_with("#") and _has_unknown_glyphs(line):
			push_warning(
				"'#' is a solid tile, not a comment — use ';' for headers: %s" % line
			)

		if is_comment(line):
			var stripped := line.lstrip("; ").strip_edges()
			if name == "Untitled" and stripped != "":
				name = stripped
			continue
		lines.append(line)

	# Trim trailing blank lines but keep leading ones: they are sky headroom.
	while lines.size() > 0 and lines[lines.size() - 1].strip_edges() == "":
		lines.resize(lines.size() - 1)

	rows = lines.size()
	cols = 0
	for line: String in lines:
		cols = maxi(cols, line.length())

	_grid = PackedInt32Array()
	_grid.resize(cols * rows)
	_grid.fill(Tiles.Kind.EMPTY)
	entities.clear()
	decorations.clear()

	for y: int in rows:
		var line: String = lines[y]
		for x: int in line.length():
			var glyph := line[x]

			if Tiles.ENTITY_LEGEND.has(glyph):
				var kind: String = Tiles.ENTITY_LEGEND[glyph]
				if kind == "spawn":
					spawn_point = Vector2i(x, y)
				else:
					entities.append({"kind": kind, "cell": Vector2i(x, y)})
				continue

			# Architecture leaves the cell empty, exactly like an entity mark.
			# That is the whole safety property: decorating a level cannot
			# move a wall or close a gap.
			if Tiles.DECOR_LEGEND.has(glyph):
				decorations.append({
					"id": String(Tiles.DECOR_LEGEND[glyph]), "cell": Vector2i(x, y),
				})
				continue

			if Tiles.LEGEND.has(glyph):
				_grid[y * cols + x] = Tiles.LEGEND[glyph]


## True if the line contains a character that is neither a tile nor an entity
## mark — i.e. it is prose rather than level geometry.
static func _has_unknown_glyphs(line: String) -> bool:
	for i: int in line.length():
		var glyph := line[i]
		if not (Tiles.LEGEND.has(glyph)
				or Tiles.ENTITY_LEGEND.has(glyph)
				or Tiles.DECOR_LEGEND.has(glyph)):
			return true
	return false


func kind_at(x: int, y: int) -> Tiles.Kind:
	if y < 0 or y >= rows:
		return Tiles.Kind.EMPTY
	if x < 0 or x >= cols:
		# Walls on the sides keep the player inside the level; open above and below.
		return Tiles.Kind.SOLID
	return _grid[y * cols + x] as Tiles.Kind


func is_solid(x: int, y: int) -> bool:
	return kind_at(x, y) == Tiles.Kind.SOLID


## Which atlas tile a cell should use. Solid blocks are capped with gold when
## they face the sky, and get a lit left edge when nothing abuts them there —
## which is why this is computed from neighbours rather than stored.
func atlas_for(x: int, y: int) -> Vector2i:
	var kind := kind_at(x, y)
	match kind:
		Tiles.Kind.SOLID:
			var capped := kind_at(x, y - 1) != Tiles.Kind.SOLID
			var lit_left := kind_at(x - 1, y) != Tiles.Kind.SOLID
			if capped:
				return Tiles.ATLAS_SOLID_CAPPED_LIT if lit_left else Tiles.ATLAS_SOLID_CAPPED
			return Tiles.ATLAS_SOLID_BURIED_LIT if lit_left else Tiles.ATLAS_SOLID_BURIED
		Tiles.Kind.PLATFORM:
			return Tiles.ATLAS_PLATFORM
		Tiles.Kind.SPIKES:
			return Tiles.ATLAS_SPIKES
		Tiles.Kind.WATER:
			return Tiles.ATLAS_WATER
		Tiles.Kind.LADDER:
			return Tiles.ATLAS_LADDER
		Tiles.Kind.BACKDROP:
			return Tiles.ATLAS_BACKDROP
		_:
			return Vector2i(-1, -1)


func to_text() -> String:
	## Round-trips the grid back to ASCII. Used by the level tools and tests.
	## Decoration marks round-trip too: they sit in empty cells, so there is
	## never a glyph to choose between terrain and architecture.
	var glyph_for := {}
	for glyph: String in Tiles.LEGEND:
		var k: int = Tiles.LEGEND[glyph]
		if k != Tiles.Kind.EMPTY and not glyph_for.has(k):
			glyph_for[k] = glyph

	var glyph_of_id := {}
	for glyph: String in Tiles.DECOR_LEGEND:
		glyph_of_id[String(Tiles.DECOR_LEGEND[glyph])] = glyph

	var decor_glyph := {}
	for mark: Dictionary in decorations:
		var id := String(mark["id"])
		if glyph_of_id.has(id):
			decor_glyph[mark["cell"]] = glyph_of_id[id]

	var out := PackedStringArray()
	for y: int in rows:
		var line := ""
		for x: int in cols:
			var cell := Vector2i(x, y)
			var k := kind_at(x, y)
			if k == Tiles.Kind.EMPTY and decor_glyph.has(cell):
				line += String(decor_glyph[cell])
			else:
				line += " " if k == Tiles.Kind.EMPTY else String(glyph_for[k])
		out.append(line.rstrip(" "))
	return "\n".join(out)
