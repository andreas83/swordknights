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
## Cell -> "false" | "cracked": the seals of secret rooms (Tiles.SEAL_LEGEND).
## The grid holds what each seal is in play; this remembers that it is one.
var seals: Dictionary = {}
## The secret rooms, left to right. Each is
## `{kind, seal: Array[Vector2i], room: Array[Vector2i], cells: Array[Vector2i]}`
## where `cells` is seal and room together: everything drawn as stone until
## the secret is found. See _find_secrets().
var secrets: Array[Dictionary] = []
## Index of a secret -> true once it has been opened in play.
var opened: Dictionary = {}

var _grid: PackedInt32Array = PackedInt32Array()
var _secret_of: Dictionary = {}


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
	seals.clear()

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

			if Tiles.SEAL_LEGEND.has(glyph):
				var seal := String(Tiles.SEAL_LEGEND[glyph])
				seals[Vector2i(x, y)] = seal
				_grid[y * cols + x] = Tiles.SEAL_KIND[seal]
				continue

			if Tiles.LEGEND.has(glyph):
				_grid[y * cols + x] = Tiles.LEGEND[glyph]

	_find_secrets()


## True if the line contains a character that is neither a tile nor an entity
## mark — i.e. it is prose rather than level geometry.
static func _has_unknown_glyphs(line: String) -> bool:
	for i: int in line.length():
		var glyph := line[i]
		if not (Tiles.LEGEND.has(glyph)
				or Tiles.ENTITY_LEGEND.has(glyph)
				or Tiles.DECOR_LEGEND.has(glyph)
				or Tiles.SEAL_LEGEND.has(glyph)):
			return true
	return false


## --- secrets ----------------------------------------------------------------
##
## A secret is a seal and the room behind it, and the ASCII only marks the
## seal. The room is found by flooding out from the seal through BACKDROP and
## entity marks, never through open air: a room is drawn as background masonry
## with its prize in it, exactly as an author would draw a niche, and the
## flood stops at the stone around it. That keeps the format to two new glyphs
## and makes a room impossible to forget to mark.
##
## Seals that touch, or share a room, are one secret: a wall two cells tall is
## one door, and a room with two ways in is still one room. The entity cells a
## room swallows become BACKDROP so its back wall is unbroken behind the prize.
func _find_secrets() -> void:
	secrets.clear()
	opened.clear()
	_secret_of.clear()
	var marked := {}
	for mark: Dictionary in entities:
		marked[mark["cell"]] = true

	var starts: Array = seals.keys()
	starts.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x or (a.x == b.x and a.y < b.y))
	for start: Vector2i in starts:
		if _secret_of.has(start):
			continue
		var index := secrets.size()
		var seal: Array[Vector2i] = []
		var room: Array[Vector2i] = []
		var queue: Array[Vector2i] = [start]
		_secret_of[start] = index
		while not queue.is_empty():
			var cell: Vector2i = queue.pop_back()
			if seals.has(cell):
				seal.append(cell)
			else:
				room.append(cell)
				if marked.has(cell):
					_grid[cell.y * cols + cell.x] = Tiles.Kind.BACKDROP
			for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var next := cell + step
				if _secret_of.has(next) or not _in_room(next, marked):
					continue
				_secret_of[next] = index
				queue.append(next)
		var kind := "false"
		for cell: Vector2i in seal:
			if String(seals[cell]) == "cracked":
				kind = "cracked"
		var cells: Array[Vector2i] = seal.duplicate()
		cells.append_array(room)
		secrets.append({"kind": kind, "seal": seal, "room": room, "cells": cells})


func _in_room(cell: Vector2i, marked: Dictionary) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= cols or cell.y >= rows:
		return false
	if seals.has(cell):
		return true
	var kind := kind_at(cell.x, cell.y)
	return kind == Tiles.Kind.BACKDROP or (kind == Tiles.Kind.EMPTY and marked.has(cell))


## The secret a cell belongs to, seal or room, or -1.
func secret_at(cell: Vector2i) -> int:
	return int(_secret_of.get(cell, -1))


## Opens a secret in play: a cracked seal stops being stone. A false one was
## never stone, so for it this only records that it has been found.
func open_secret(index: int) -> void:
	if index < 0 or index >= secrets.size() or opened.has(index):
		return
	opened[index] = true
	for cell: Vector2i in secrets[index]["seal"]:
		set_kind(cell.x, cell.y, Tiles.Kind.BACKDROP)


## A copy with every secret either opened (its seal gone) or shut (its seal
## solid stone, false or not). `open` maps secret index -> true. This is the
## hypothetical the reachability proof plays: the level as it is for someone
## who has found exactly these secrets and walked past the rest.
func with_secrets(open: Dictionary) -> AsciiLevel:
	var out := copy()
	for index: int in secrets.size():
		for cell: Vector2i in secrets[index]["seal"]:
			out.set_kind(cell.x, cell.y,
				Tiles.Kind.BACKDROP if open.has(index) else Tiles.Kind.SOLID)
	return out


## A copy that looks the way the level does before anything is found: every
## secret not yet opened is solid stone, seal and room alike. The renderer
## builds the picture from this, so a wall with a room in it is drawn — and
## dressed, and casts its shadow — as the wall it pretends to be.
func facade() -> AsciiLevel:
	var out := copy()
	for index: int in secrets.size():
		if opened.has(index):
			continue
		for cell: Vector2i in secrets[index]["cells"]:
			out.set_kind(cell.x, cell.y, Tiles.Kind.SOLID)
	return out


func copy() -> AsciiLevel:
	var out := AsciiLevel.new()
	out.cols = cols
	out.rows = rows
	out.spawn_point = spawn_point
	out.entities = entities.duplicate(true)
	out.decorations = decorations.duplicate(true)
	out.name = name
	out.seals = seals.duplicate()
	out.secrets = secrets.duplicate(true)
	out.opened = opened.duplicate()
	out._grid = _grid.duplicate()
	out._secret_of = _secret_of.duplicate()
	return out


func set_kind(x: int, y: int, kind: Tiles.Kind) -> void:
	if x < 0 or y < 0 or x >= cols or y >= rows:
		return
	_grid[y * cols + x] = kind


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

	var seal_glyph := {}
	for glyph: String in Tiles.SEAL_LEGEND:
		seal_glyph[String(Tiles.SEAL_LEGEND[glyph])] = glyph

	var out := PackedStringArray()
	for y: int in rows:
		var line := ""
		for x: int in cols:
			var cell := Vector2i(x, y)
			var k := kind_at(x, y)
			if seals.has(cell) and not opened.has(secret_at(cell)):
				line += String(seal_glyph[seals[cell]])
			elif k == Tiles.Kind.EMPTY and decor_glyph.has(cell):
				line += String(decor_glyph[cell])
			else:
				line += " " if k == Tiles.Kind.EMPTY else String(glyph_for[k])
		out.append(line.rstrip(" "))
	return "\n".join(out)
