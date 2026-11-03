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
##
## ## Directives
##
## A comment that starts `;!` is a directive: an instruction about the level
## rather than a row of it (docs/world.md, "Directives and wiring"). It is a
## comment first -- the geometry parser skips it like any `;` line, so a
## directive can never move a tile, and it is never taken for the title:
##
##     ;! time golden               the hour the level is set at
##     ;! horizon 32                no sun below this row
##     ;! channel 2 hold 4.0        what wire 2 does: latch, hold S, beat P
##     ;! checkpoints route         order torches along the proved route
##     ;! mark k plate channel=a    glyph k places a "plate", on wire a
##
## ## Wiring
##
## Mechanisms (Tiles.MECHANISM_LEGEND) are wired by mason's marks: a digit
## cut in a stone cell -- solid, like the stone around it -- carries a
## channel and wires the one mechanism it touches. Same mark, same wire. A
## mark that touches no mechanism, or two, is a problem with its cell named.
## Every connected run of one kind's glyphs is ONE mechanism, so a gate three
## cells tall is one gate. `mark` binds a glyph no legend uses to any kind for
## one level, with parameters, which is how a test or a one-off kind is
## placed; it is wired by `channel=`.
##
## Problems -- a malformed directive, a stray mark, a glyph in no legend --
## are collected in `problems` rather than raised: Game warns about them on
## load, and a test refuses a shipping level that has any.

const DIRECTIVE_MARKER := ";!"
## Directive names something reads. A name not here is reported, so a typo in
## a header is a problem and not silently nothing. Add a name when you add its
## reader.
const DIRECTIVES: Array[String] = ["mark", "time", "channel", "horizon", "checkpoints"]
## The modes a channel can be given (ChannelBus).
const CHANNEL_MODES: Array[String] = ["momentary", "latch", "hold", "beat"]

var cols: int = 0
var rows: int = 0
var spawn_point: Vector2i = Vector2i(2, 2)
## Array of { kind: String, cell: Vector2i }, in reading order. A mark placed
## by a declared glyph also carries `cells` (its whole run), `params` and
## `glyph`, and its `cell` is the run's bottom-left: where it stands.
var entities: Array[Dictionary] = []
## Every `;!` line, in order: `{name, args: PackedStringArray, params:
## Dictionary, line: int}`, where `params` are its `key=value` words.
var directives: Array[Dictionary] = []
## Glyph -> `{kind, params}`: what this level's `;! mark` lines declared.
var declared: Dictionary = {}
## Cell -> digit: the mason's marks, each solid stone in the grid.
var masons_marks: Dictionary = {}
## Cell -> the glyph that put a mechanism there. One kind can have several
## glyphs whose places differ: a lift's `[ ]` is its home stop and its `'` its
## travel, which is how it knows which way it goes. Also on each mechanism
## mark, as `glyphs`, for its reach hook.
var mechanism_glyphs: Dictionary = {}
## Channel -> `{mode, seconds, phase, period}` from `;! channel` lines.
var channels: Dictionary = {}
## What is wrong with the text, for whoever wrote it. Never an error in play.
var problems: PackedStringArray = PackedStringArray()
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


static func is_directive(line: String) -> bool:
	return line.begins_with(DIRECTIVE_MARKER)


func parse(text: String) -> void:
	var lines: Array[String] = []
	directives.clear()
	declared.clear()
	problems.clear()
	masons_marks.clear()
	mechanism_glyphs.clear()
	channels.clear()
	var number := 0
	for raw: String in text.split("\n", true):
		var line := raw.trim_suffix("\r")
		number += 1

		# Catch files still using the old '#' header. Tested by content rather
		# than by position: "#  ###" is a legitimate first row, while
		# "# The Sun Terrace" contains glyphs no tile uses.
		if line.begins_with("#") and _has_unknown_glyphs(line):
			push_warning(
				"'#' is a solid tile, not a comment — use ';' for headers: %s" % line
			)

		if is_directive(line):
			_read_directive(line, number)
			continue
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
	var runs := {}
	var mechanisms := {}

	for y: int in rows:
		var line: String = lines[y]
		for x: int in line.length():
			var glyph := line[x]

			# A declared glyph is an entity mark too, and leaves its cell empty.
			if declared.has(glyph):
				if not runs.has(glyph):
					runs[glyph] = []
				(runs[glyph] as Array).append(Vector2i(x, y))
				continue

			# A mechanism: grouped by kind, so `[` and `]` can be one lift.
			var mechanism := Tiles.mechanism_kind(glyph)
			if mechanism != "":
				if not mechanisms.has(mechanism):
					mechanisms[mechanism] = []
				(mechanisms[mechanism] as Array).append(Vector2i(x, y))
				mechanism_glyphs[Vector2i(x, y)] = glyph
				_grid[y * cols + x] = Tiles.mechanism_terrain(glyph)
				continue

			if Tiles.is_masons_mark(glyph):
				masons_marks[Vector2i(x, y)] = glyph
				_grid[y * cols + x] = Tiles.Kind.SOLID
				continue

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
			else:
				problems.append("row %d, column %d: '%s' is in no legend and not declared"
					% [y, x, glyph])

	_place_runs(runs, mechanisms)
	_find_secrets()


## --- directives -------------------------------------------------------------

## The last directive called `directive_name`, or an empty Dictionary.
func directive(directive_name: String) -> Dictionary:
	for i: int in range(directives.size() - 1, -1, -1):
		if String(directives[i]["name"]) == directive_name:
			return directives[i]
	return {}


## One `;!` line: its name, its plain words and its `key=value` words.
func _read_directive(line: String, number: int) -> void:
	var words := line.substr(DIRECTIVE_MARKER.length()).replace("\t", " ").split(" ", false)
	if words.is_empty():
		problems.append("line %d: a directive with nothing in it" % number)
		return
	var directive_name := words[0].to_lower()
	var args := PackedStringArray()
	var params := {}
	for i: int in range(1, words.size()):
		var word := words[i]
		var equals := word.find("=")
		if equals > 0:
			params[word.substr(0, equals)] = word.substr(equals + 1)
		else:
			args.append(word)
	directives.append({"name": directive_name, "args": args, "params": params, "line": number})
	if not DIRECTIVES.has(directive_name):
		problems.append("line %d: there is no directive '%s'" % [number, directive_name])
		return
	match directive_name:
		"mark":
			_declare(args, params, number)
		"channel":
			_read_channel(args, params, number)
		"horizon":
			if args.size() != 1 or not args[0].is_valid_int():
				problems.append("line %d: a horizon is one row number" % number)
		"checkpoints":
			if args.size() != 1 or not args[0] in ["x", "route"]:
				problems.append("line %d: checkpoints are ordered by 'x' or 'route'" % number)
		"time":
			if args.size() != 1:
				problems.append("line %d: a time is one stop or one number" % number)
			elif not TimeOfDay.is_valid(args[0]):
				problems.append("line %d: there is no time '%s': a stop (%s) or 0 to 1"
					% [number, args[0], ", ".join(TimeOfDay.STOPS)])


## `;! channel <name> <mode> [seconds | phase] [period=frames]`.
func _read_channel(args: PackedStringArray, params: Dictionary, number: int) -> void:
	if args.size() < 2:
		problems.append("line %d: a channel needs a name and a mode" % number)
		return
	var mode := args[1].to_lower()
	if not CHANNEL_MODES.has(mode):
		problems.append("line %d: a channel's mode is %s, not '%s'"
			% [number, "/".join(CHANNEL_MODES), mode])
		return
	var spec := {"mode": mode}
	if mode == "hold":
		if args.size() < 3 or not args[2].is_valid_float() or float(args[2]) <= 0.0:
			problems.append("line %d: a hold needs its seconds" % number)
			return
		spec["seconds"] = float(args[2])
	elif mode == "beat":
		var period := String(params.get("period", "100"))
		if args.size() < 3 or not args[2].is_valid_int() or not period.is_valid_int() \
				or int(period) <= 0:
			problems.append("line %d: a beat needs its phase in frames" % number)
			return
		spec["phase"] = int(args[2])
		spec["period"] = int(period)
	if channels.has(args[0]):
		problems.append("line %d: channel %s is set twice; the last one wins" % [number, args[0]])
	channels[args[0]] = spec


## `;! mark <glyph> <kind> [key=value ...]`: the glyph places that kind.
func _declare(args: PackedStringArray, params: Dictionary, number: int) -> void:
	if args.size() < 2:
		problems.append("line %d: a mark needs a glyph and a kind" % number)
		return
	var glyph := args[0]
	if glyph.length() != 1:
		problems.append("line %d: a mark's glyph is one character, not '%s'" % [number, glyph])
		return
	if glyph == COMMENT_MARKER or _in_a_legend(glyph):
		problems.append("line %d: '%s' already means something in the legend" % [number, glyph])
		return
	if Tiles.is_masons_mark(glyph):
		problems.append("line %d: '%s' is a mason's mark, not a glyph to declare" % [number, glyph])
		return
	for extra: String in args.slice(2):
		problems.append("line %d: '%s' is not key=value" % [number, extra])
	if declared.has(glyph):
		problems.append("line %d: '%s' is declared twice; the last one wins" % [number, glyph])
	declared[glyph] = {"kind": args[1], "params": params}


static func _in_a_legend(glyph: String) -> bool:
	return (Tiles.LEGEND.has(glyph) or Tiles.ENTITY_LEGEND.has(glyph)
		or Tiles.DECOR_LEGEND.has(glyph) or Tiles.SEAL_LEGEND.has(glyph)
		or Tiles.mechanism_kind(glyph) != "")


## Every connected run of a declared glyph, and of a mechanism kind, becomes
## one mark, anchored at its bottom-left cell -- where a thing that stands,
## stands. The mechanisms are wired by the mason's marks touching them. Then
## every mark goes back in reading order with the rest, which is the order
## Game places and meets them in.
func _place_runs(declared_runs: Dictionary, mechanism_runs: Dictionary) -> void:
	var wired: Array[Dictionary] = []
	if declared_runs.is_empty() and mechanism_runs.is_empty():
		_wire(wired)
		return
	for glyph: String in declared_runs:
		var spec: Dictionary = declared[glyph]
		for run: Array[Vector2i] in _connected(declared_runs[glyph]):
			var mark := _run_mark(String(spec["kind"]), run,
				(spec["params"] as Dictionary).duplicate())
			mark["glyph"] = glyph
			entities.append(mark)
	for kind: String in mechanism_runs:
		for run: Array[Vector2i] in _connected(mechanism_runs[kind]):
			var mark := _run_mark(kind, run, {})
			var glyphs := {}
			for cell: Vector2i in run:
				glyphs[cell] = mechanism_glyphs[cell]
			mark["glyphs"] = glyphs
			entities.append(mark)
			wired.append(mark)
	_wire(wired)
	entities.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var p: Vector2i = a["cell"]
		var q: Vector2i = b["cell"]
		return p.y < q.y or (p.y == q.y and p.x < q.x))


static func _run_mark(kind: String, run: Array[Vector2i], params: Dictionary) -> Dictionary:
	var anchor := run[0]
	for cell: Vector2i in run:
		if cell.y > anchor.y or (cell.y == anchor.y and cell.x < anchor.x):
			anchor = cell
	return {"kind": kind, "cell": anchor, "cells": run, "params": params}


## Each mason's mark gives its digit, as `params.channel`, to the one
## mechanism it touches. A mark touching none, or two, or a mechanism touching
## two different marks, is a problem with the cell named: a wire to nothing is
## a gate that never opens, and nobody sees it until they are standing there.
func _wire(mechanisms: Array[Dictionary]) -> void:
	if masons_marks.is_empty():
		return
	var owner := {}
	for i: int in mechanisms.size():
		for cell: Vector2i in mechanisms[i]["cells"]:
			owner[cell] = i
	var marks: Array = masons_marks.keys()
	marks.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x))
	for at: Vector2i in marks:
		var digit := String(masons_marks[at])
		var named := "mason's mark '%s' at column %d, row %d" % [digit, at.x, at.y]
		var touching := {}
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if owner.has(at + step):
				touching[owner[at + step]] = true
		if touching.size() != 1:
			problems.append("%s touches %d mechanisms: a mark wires exactly one"
				% [named, touching.size()])
			continue
		var mark: Dictionary = mechanisms[int(touching.keys()[0])]
		var params: Dictionary = mark["params"]
		if params.has("channel") and String(params["channel"]) != digit:
			problems.append("%s: the %s it touches already carries mark '%s'"
				% [named, mark["kind"], params["channel"]])
			continue
		params["channel"] = digit
		mark["mark"] = at


## `cells` split into 4-connected runs, each in reading order.
static func _connected(cells: Array) -> Array[Array]:
	var left := {}
	for cell: Vector2i in cells:
		left[cell] = true
	var out: Array[Array] = []
	for start: Vector2i in cells:
		if not left.has(start):
			continue
		var run: Array[Vector2i] = []
		var queue: Array[Vector2i] = [start]
		left.erase(start)
		while not queue.is_empty():
			var cell: Vector2i = queue.pop_back()
			run.append(cell)
			for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if left.has(cell + step):
					left.erase(cell + step)
					queue.append(cell + step)
		run.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return a.y < b.y or (a.y == b.y and a.x < b.x))
		out.append(run)
	return out


## True if the line contains a character that is neither a tile nor an entity
## mark — i.e. it is prose rather than level geometry.
static func _has_unknown_glyphs(line: String) -> bool:
	for i: int in line.length():
		var glyph := line[i]
		if not (_in_a_legend(glyph) or Tiles.is_masons_mark(glyph)):
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
		for cell: Vector2i in mark.get("cells", [mark["cell"]]):
			marked[cell] = true

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
	out.directives = directives.duplicate(true)
	out.declared = declared.duplicate(true)
	out.masons_marks = masons_marks.duplicate()
	out.channels = channels.duplicate(true)
	out.problems = problems.duplicate()
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
