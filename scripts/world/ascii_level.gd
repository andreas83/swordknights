class_name AsciiLevel
extends RefCounted
## Parses an ASCII level into a tile grid plus entity spawn marks.
##
## The format stays human-editable on purpose: a level is reviewable in a diff
## and a generator can emit one without touching the engine. Lines starting
## with '#' at column 0 followed by a space, or with ';', are comments — note
## that a bare '#' is a solid tile, so the comment marker is '# ' or ';'.

var cols: int = 0
var rows: int = 0
var spawn_point: Vector2i = Vector2i(2, 2)
## Array of { kind: String, cell: Vector2i }
var entities: Array[Dictionary] = []
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


static func is_comment(line: String) -> bool:
	return line.begins_with(";") or line.begins_with("# ") or line == "#"


func parse(text: String) -> void:
	var lines: Array[String] = []
	for raw: String in text.split("\n", true):
		var line := raw.trim_suffix("\r")
		if is_comment(line):
			var stripped := line.lstrip("#; ").strip_edges()
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

			if Tiles.LEGEND.has(glyph):
				_grid[y * cols + x] = Tiles.LEGEND[glyph]


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
	var glyph_for := {}
	for glyph: String in Tiles.LEGEND:
		var k: int = Tiles.LEGEND[glyph]
		if k != Tiles.Kind.EMPTY and not glyph_for.has(k):
			glyph_for[k] = glyph

	var out := PackedStringArray()
	for y: int in rows:
		var line := ""
		for x: int in cols:
			var k := kind_at(x, y)
			line += " " if k == Tiles.Kind.EMPTY else String(glyph_for[k])
		out.append(line.rstrip(" "))
	return "\n".join(out)
