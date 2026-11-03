class_name LevelGrammar
extends RefCounted
## The segment vocabulary the generator chains together.
##
## A segment is a parameterised ASCII stamp modelled on one of level 01's
## beats. Each one declares an entry height, an exit height, a width and a
## difficulty weight, so segments chain without a seam: the next segment's
## entry height is the previous one's exit height, and because every segment
## fills its own ground from its surface row down to the bedrock, the terrain
## is continuous by construction.
##
## Heights are measured in tiles above a shared base floor, so "entry height 3"
## means the walkable surface is three tiles higher than the lowest ground the
## generator ever emits. The vertical spacing between those heights is NOT a
## free choice — it comes out of scripts/core/tuning.gd:
##
##   hop_rise()   a plain hop                   Tuning.hop_tiles()
##   step_rise()  needs a one-way platform      Tuning.platform_step_tiles()
##   grab_rise()  needs a ledge grab            Tuning.grab_tiles()
##
## Retuning the character moves those numbers and the grammar follows, which is
## the whole point of reading them from Tuning rather than writing 2/3/4 here.
##
## Nothing in this file is random: the generator resolves every parameter into
## a spec dictionary first (see `instantiate`), then `stamp` renders that spec
## deterministically. That split is what makes a level replayable from a seed
## and a stamped segment testable on its own.


## --- the ASCII legend, mirrored from scripts/world/tiles.gd ----------------
## tests/level_envelope_test.gd asserts these still mean what we think they do.

const SOLID := "#"
const PLATFORM := "="
const SPIKES := "^"
const WATER := "~"
const LADDER := "H"
const BACKDROP := ":"
const EMPTY := " "
const SEAL_FALSE := "%"
const SEAL_CRACKED := "&"

const SPAWN := "@"
const RELIC := "*"
const EXIT := "D"
const TORCH := "t"
const PATROL := "p"


## --- vertical layout -------------------------------------------------------
## Rows are fixed so every segment can fill its ground to the same bedrock and
## the camera sees a consistent amount of sky.

const SKY_ROWS := 5          ## Headroom above the highest possible surface.
const MAX_HEIGHT := 9        ## Highest terrain height the chain may reach.
const PIT_DEPTH := 4         ## Deepest a cistern or basin may be carved.
const BEDROCK_ROWS := 2      ## Solid rows kept under the deepest pit.

## Row of the topmost solid tile of ground at height 0.
const BASE_ROW := SKY_ROWS + MAX_HEIGHT

const ROWS := BASE_ROW + PIT_DEPTH + BEDROCK_ROWS + 1


## Row of the topmost solid tile of ground at `height`.
static func surface_row(height: int) -> int:
	return BASE_ROW - height


## Row of the cell a character stands in when standing on ground at `height`.
static func stand_row(height: int) -> int:
	return BASE_ROW - height - 1


## --- the traversal grammar, derived from Tuning ----------------------------

## The tallest rise a plain hop lands on top of.
static func hop_rise() -> int:
	return Tuning.hop_tiles()


## The rise that needs a one-way platform as an intermediate step.
static func step_rise() -> int:
	return Tuning.platform_step_tiles()


## The tallest rise a ledge grab can still catch.
static func grab_rise() -> int:
	return Tuning.grab_tiles()


## The widest level gap a running jump can cross, in empty tiles.
##
## Delegates to Tuning: the airtime integration and the takeoff/landing
## geometry are properties of the character, not of level generation, and two
## copies of the same derivation is exactly how grab_tiles() drifted a tile
## away from what the character could do.
static func max_gap_tiles() -> int:
	return Tuning.gap_tiles()


## The widest gap the generator authors unprompted. One tile inside the
## envelope, because the outermost tile of the envelope wants a full-speed
## takeoff from the very lip of the ledge — difficulty 0.85 and up opens it
## again, and LevelReachability has the final say either way.
static func safe_gap_tiles() -> int:
	return maxi(1, max_gap_tiles() - 1)


static func gap_limit(difficulty: float) -> int:
	return max_gap_tiles() if difficulty >= 0.85 else safe_gap_tiles()


## --- the segment catalogue -------------------------------------------------

## `difficulty` is the segment's intrinsic hardness on the same 0..1 scale the
## generator is asked for; `ascent` is a hint for the chainer, not a promise.
static func templates() -> Array[Dictionary]:
	return [
		{"id": "terrace", "difficulty": 0.00, "ascent": 0,
			"teaches": "run and jump"},
		{"id": "relic_alcove", "difficulty": 0.15, "ascent": 0,
			"teaches": "an optional prize off the main path"},
		{"id": "gap", "difficulty": 0.30, "ascent": 0,
			"teaches": "a committed running jump over a chasm"},
		{"id": "cistern", "difficulty": 0.20, "ascent": 0,
			"teaches": "climbing — a safe failure"},
		{"id": "platform_stair", "difficulty": 0.35, "ascent": 1,
			"teaches": "a one-way platform as a step"},
		{"id": "guard_post", "difficulty": 0.45, "ascent": 0,
			"teaches": "the sword"},
		{"id": "spike_pit", "difficulty": 0.55, "ascent": 0,
			"teaches": "a gap that punishes a short jump"},
		{"id": "water_basin", "difficulty": 0.65, "ascent": 0,
			"teaches": "a wide committed jump"},
		{"id": "grab_wall", "difficulty": 0.75, "ascent": 1,
			"teaches": "the ledge grab"},
	]


## True when a segment of this kind can be placed at `entry` without running
## out of sky. Checked before any random draw so the generator's rng stream
## does not depend on which candidates were rejected.
static func fits(id: String, entry: int) -> bool:
	if entry < 0 or entry > MAX_HEIGHT:
		return false
	match id:
		"grab_wall":
			return entry + grab_rise() <= MAX_HEIGHT
		"platform_stair":
			return entry + step_rise() <= MAX_HEIGHT
		"relic_alcove":
			return entry + hop_rise() <= MAX_HEIGHT
		_:
			return true


## Resolves a template into a concrete segment spec. Every random choice this
## grammar makes happens here, in a fixed order, so the same rng state and the
## same arguments always yield the same spec.
##
## Returns an empty dictionary when the segment cannot be placed at `entry`.
static func instantiate(id: String, entry: int, difficulty: float,
		rng: RandomNumberGenerator) -> Dictionary:
	if not fits(id, entry):
		return {}

	var difficulty_of := {}
	for template: Dictionary in templates():
		difficulty_of[String(template["id"])] = float(template["difficulty"])

	var params := {}
	var exit := entry
	var width := 0

	match id:
		"terrace":
			var tail := _pick(rng, 2, 4, difficulty)
			var body := _pick(rng, 2, 5, 1.0 - difficulty)
			# A terrace is the grammar's only descent: stepping down is free,
			# so this is what keeps the chain from ratcheting up to MAX_HEIGHT.
			var drop := 0
			if entry > 0:
				drop = mini(entry, _pick(rng, 0, mini(entry, grab_rise()), difficulty))
			exit = entry - drop
			width = body + tail
			# The torch belongs on the part of the terrace that is still at the
			# entry height — the tail may have stepped down out from under it.
			params = {"tail": tail, "torch": _maybe_torch(rng, body)}

		"gap":
			var left := _pick(rng, 2, 4, 1.0 - difficulty)
			var span := _pick(rng, 1, gap_limit(difficulty), difficulty)
			var right := _pick(rng, 3, 5, 1.0 - difficulty)
			width = left + span + right
			params = {"left": left, "span": span, "right": right,
				"torch": _maybe_torch(rng, left)}

		"cistern":
			var left := _pick(rng, 3, 4, 1.0 - difficulty)
			var pit := _pick(rng, 2, gap_limit(difficulty), difficulty)
			var right := _pick(rng, 3, 5, 1.0 - difficulty)
			var depth := _pick(rng, 2, PIT_DEPTH, difficulty)
			width = left + pit + right
			params = {"left": left, "pit": pit, "right": right, "depth": depth,
				"torch": _maybe_torch(rng, left)}

		"spike_pit":
			var left := _pick(rng, 3, 4, 1.0 - difficulty)
			var span := _pick(rng, 1, gap_limit(difficulty), difficulty)
			var right := _pick(rng, 3, 5, 1.0 - difficulty)
			var depth := _pick(rng, 1, 2, difficulty)
			width = left + span + right
			params = {"left": left, "span": span, "right": right, "depth": depth,
				"torch": _maybe_torch(rng, left)}

		"water_basin":
			var left := _pick(rng, 3, 5, 1.0 - difficulty)
			var span := _pick(rng, 2, gap_limit(difficulty), difficulty)
			var right := _pick(rng, 3, 5, 1.0 - difficulty)
			var depth := _pick(rng, 2, PIT_DEPTH, difficulty)
			width = left + span + right
			params = {"left": left, "span": span, "right": right, "depth": depth,
				"torch": _maybe_torch(rng, left)}

		"grab_wall":
			var left := _pick(rng, 3, 5, 1.0 - difficulty)
			var right := _pick(rng, 3, 5, 1.0 - difficulty)
			exit = entry + grab_rise()
			width = left + right
			params = {"left": left, "right": right, "torch": _maybe_torch(rng, left)}

		"platform_stair":
			var max_steps := 1
			if entry + step_rise() * 2 <= MAX_HEIGHT:
				max_steps = 2
			var steps := _pick(rng, 1, max_steps, difficulty)
			var run := _pick(rng, 4, 5, 1.0 - difficulty)
			var plat := _pick(rng, 2, 3, 1.0 - difficulty)
			var tail := _pick(rng, 3, 4, 1.0 - difficulty)
			exit = entry + step_rise() * steps
			width = steps * run + tail
			params = {"steps": steps, "run": run, "plat": plat, "tail": tail,
				"torch": _maybe_torch(rng, run)}

		"guard_post":
			var body := _pick(rng, 6, 9, difficulty)
			width = body
			params = {"torch": _maybe_torch(rng, width)}

		"relic_alcove":
			var left := _pick(rng, 2, 3, 1.0 - difficulty)
			var pedestal := _pick(rng, 2, 3, 1.0 - difficulty)
			var right := _pick(rng, 2, 3, 1.0 - difficulty)
			width = left + pedestal + right
			params = {"left": left, "pedestal": pedestal, "right": right,
				"torch": _maybe_torch(rng, left)}

		_:
			return {}

	if exit < 0 or exit > MAX_HEIGHT:
		return {}

	return {
		"id": id,
		"width": width,
		"entry": entry,
		"exit": exit,
		"difficulty": float(difficulty_of.get(id, 0.0)),
		"params": params,
	}


## A flat terrace of an exact width — the generator uses this for the opening
## and closing beats, which have to be long enough to hold the spawn and the
## exit door with runway around them.
static func flat_terrace(entry: int, width: int, torch_at: int = -1) -> Dictionary:
	return {
		"id": "terrace",
		"width": maxi(width, 3),
		"entry": entry,
		"exit": entry,
		"difficulty": 0.0,
		"params": {"tail": 1, "torch": torch_at},
	}


## --- stamping --------------------------------------------------------------

## Renders `spec` into `canvas` with its left edge at column `x0` and returns
## the entity anchors it offers, each `{kind: String, cell: Vector2i}`. The
## generator decides which anchors to honour; a segment only says where a
## relic, a guard or a torch would sit well.
static func stamp(canvas: Canvas, x0: int, spec: Dictionary) -> Array[Dictionary]:
	var marks: Array[Dictionary] = []
	match String(spec["id"]):
		"terrace":
			marks = _stamp_terrace(canvas, x0, spec)
		"gap":
			marks = _stamp_gap(canvas, x0, spec)
		"cistern":
			marks = _stamp_cistern(canvas, x0, spec)
		"spike_pit":
			marks = _stamp_spike_pit(canvas, x0, spec)
		"water_basin":
			marks = _stamp_water_basin(canvas, x0, spec)
		"grab_wall":
			marks = _stamp_grab_wall(canvas, x0, spec)
		"platform_stair":
			marks = _stamp_platform_stair(canvas, x0, spec)
		"guard_post":
			marks = _stamp_guard_post(canvas, x0, spec)
		"relic_alcove":
			marks = _stamp_relic_alcove(canvas, x0, spec)
		_:
			push_error("unknown segment id '%s'" % str(spec.get("id", "?")))
	return marks


static func _stamp_terrace(canvas: Canvas, x0: int, spec: Dictionary) -> Array[Dictionary]:
	var width: int = spec["width"]
	var entry: int = spec["entry"]
	var exit: int = spec["exit"]
	var tail: int = clampi(int(spec["params"]["tail"]), 1, width - 1)
	for i: int in width:
		_ground(canvas, x0 + i, entry if i < width - tail else exit)
	return _torch_marks(canvas, spec, x0, entry)


static func _stamp_gap(canvas: Canvas, x0: int, spec: Dictionary) -> Array[Dictionary]:
	var entry: int = spec["entry"]
	var left: int = spec["params"]["left"]
	var span: int = spec["params"]["span"]
	var right: int = spec["params"]["right"]

	for i: int in left:
		_ground(canvas, x0 + i, entry)
	# A bottomless chasm rather than a floor: falling in costs a life instead of
	# stranding the player somewhere they cannot climb out of.
	for i: int in span:
		canvas.fill_column(x0 + left + i, 0, ROWS - 1, EMPTY)
	for i: int in right:
		_ground(canvas, x0 + left + span + i, entry)
	return _torch_marks(canvas, spec, x0, entry)


static func _stamp_cistern(canvas: Canvas, x0: int, spec: Dictionary) -> Array[Dictionary]:
	var entry: int = spec["entry"]
	var left: int = spec["params"]["left"]
	var pit: int = spec["params"]["pit"]
	var right: int = spec["params"]["right"]
	var depth: int = spec["params"]["depth"]

	for i: int in left:
		_ground(canvas, x0 + i, entry)

	var pit_x := x0 + left
	var top := surface_row(entry)
	var floor_row := top + depth
	for i: int in pit:
		_ground(canvas, pit_x + i, entry)
		canvas.fill_column(pit_x + i, top, floor_row - 1, EMPTY)
	# The ladder stands in the pit's first column and reaches the terrace's own
	# standing row, so stepping sideways off the top lands on the terrace.
	canvas.fill_column(pit_x, stand_row(entry), floor_row - 1, LADDER)

	for i: int in right:
		_ground(canvas, pit_x + pit + i, entry)
	return _torch_marks(canvas, spec, x0, entry)


static func _stamp_spike_pit(canvas: Canvas, x0: int, spec: Dictionary) -> Array[Dictionary]:
	var entry: int = spec["entry"]
	var left: int = spec["params"]["left"]
	var span: int = spec["params"]["span"]
	var right: int = spec["params"]["right"]
	var depth: int = spec["params"]["depth"]

	for i: int in left:
		_ground(canvas, x0 + i, entry)

	var top := surface_row(entry)
	for i: int in span:
		var x := x0 + left + i
		_ground(canvas, x, entry)
		canvas.fill_column(x, top, top + depth - 1, EMPTY)
		canvas.set_cell(x, top + depth - 1, SPIKES)

	for i: int in right:
		_ground(canvas, x0 + left + span + i, entry)
	return _torch_marks(canvas, spec, x0, entry)


static func _stamp_water_basin(canvas: Canvas, x0: int, spec: Dictionary) -> Array[Dictionary]:
	var entry: int = spec["entry"]
	var left: int = spec["params"]["left"]
	var span: int = spec["params"]["span"]
	var right: int = spec["params"]["right"]
	var depth: int = spec["params"]["depth"]

	for i: int in left:
		_ground(canvas, x0 + i, entry)

	var top := surface_row(entry)
	for i: int in span:
		var x := x0 + left + i
		_ground(canvas, x, entry)
		# Brim-full, like level 01's basin: the surface is level with the
		# terrace, so there is no lip to scramble onto.
		canvas.fill_column(x, top, top + depth - 1, WATER)

	for i: int in right:
		_ground(canvas, x0 + left + span + i, entry)
	return _torch_marks(canvas, spec, x0, entry)


static func _stamp_grab_wall(canvas: Canvas, x0: int, spec: Dictionary) -> Array[Dictionary]:
	var entry: int = spec["entry"]
	var exit: int = spec["exit"]
	var left: int = spec["params"]["left"]
	var right: int = spec["params"]["right"]

	for i: int in left:
		_ground(canvas, x0 + i, entry)
	for i: int in right:
		_ground(canvas, x0 + left + i, exit)
	# The torch goes on the upper terrace, which is where the player arrives.
	return _torch_marks(canvas, spec, x0, entry)


static func _stamp_platform_stair(canvas: Canvas, x0: int, spec: Dictionary) -> Array[Dictionary]:
	var steps: int = spec["params"]["steps"]
	var run: int = spec["params"]["run"]
	var plat: int = spec["params"]["plat"]
	var tail: int = spec["params"]["tail"]

	var height: int = spec["entry"]
	var x := x0
	for _step: int in steps:
		for i: int in run:
			_ground(canvas, x + i, height)
		# The platform floats hop_rise() above the lower ground, in the columns
		# just short of the riser: hop onto the platform, then step up again.
		var platform_row := surface_row(height) - hop_rise()
		var plat_w := mini(plat, run - 1)
		for i: int in plat_w:
			canvas.set_cell(x + run - plat_w + i, platform_row, PLATFORM)
		x += run
		height += step_rise()

	for i: int in tail:
		_ground(canvas, x + i, height)
	return _torch_marks(canvas, spec, x0, spec["entry"])


static func _stamp_guard_post(canvas: Canvas, x0: int, spec: Dictionary) -> Array[Dictionary]:
	var width: int = spec["width"]
	var entry: int = spec["entry"]
	for i: int in width:
		_ground(canvas, x0 + i, entry)

	var marks := _torch_marks(canvas, spec, x0, entry)
	# The guard turns at walls and at drops, so it wants room either side.
	marks.append({"kind": "patrol", "cell": Vector2i(x0 + width / 2, stand_row(entry))})
	return marks


static func _stamp_relic_alcove(canvas: Canvas, x0: int, spec: Dictionary) -> Array[Dictionary]:
	var entry: int = spec["entry"]
	var left: int = spec["params"]["left"]
	var pedestal: int = spec["params"]["pedestal"]
	var right: int = spec["params"]["right"]

	for i: int in left:
		_ground(canvas, x0 + i, entry)

	var shelf := entry + hop_rise()
	var pedestal_x := x0 + left
	for i: int in pedestal:
		_ground(canvas, pedestal_x + i, shelf)
	for i: int in right:
		_ground(canvas, pedestal_x + pedestal + i, entry)

	# Backdrop never collides, so the niche behind the prize is pure dressing.
	var niche_row := stand_row(shelf)
	for y: int in range(niche_row, stand_row(entry) + 1):
		canvas.set_cell(pedestal_x - 1, y, BACKDROP)
		canvas.set_cell(pedestal_x + pedestal, y, BACKDROP)

	var marks := _torch_marks(canvas, spec, x0, entry)
	marks.append({"kind": "relic", "cell": Vector2i(pedestal_x, niche_row)})
	return marks


## --- stamping helpers ------------------------------------------------------

## Fills one column with ground: solid from its surface row to the bedrock.
static func _ground(canvas: Canvas, x: int, height: int) -> void:
	canvas.fill_column(x, surface_row(height), ROWS - 1, SOLID)


static func _maybe_torch(rng: RandomNumberGenerator, span: int) -> int:
	if span <= 0 or rng.randf() > 0.42:
		return -1
	return rng.randi_range(0, span - 1)


## A torch mark, if the segment drew one and the cell it asked for can really
## hold it: empty, with ground underneath. Checked here rather than trusted,
## because a segment computes the row from its *entry* height and parts of it
## may have been carved away or stepped down since.
static func _torch_marks(canvas: Canvas, spec: Dictionary, x0: int,
		height: int) -> Array[Dictionary]:
	var marks: Array[Dictionary] = []
	var at: int = int(spec["params"].get("torch", -1))
	if at < 0:
		return marks

	var cell := Vector2i(x0 + at, stand_row(height))
	if canvas.get_cell(cell.x, cell.y) != EMPTY:
		return marks
	var under := canvas.get_cell(cell.x, cell.y + 1)
	if under != SOLID and under != PLATFORM:
		return marks

	marks.append({"kind": "torch", "cell": cell})
	return marks


## Draws an integer from [lo, hi], biased toward `lo` when `difficulty` is low
## and toward `hi` when it is high. Always consumes exactly one rng draw so the
## stream stays predictable.
static func _pick(rng: RandomNumberGenerator, lo: int, hi: int, difficulty: float) -> int:
	var t := rng.randf()
	if hi <= lo:
		return lo
	var shaped := pow(t, 1.0 + (1.0 - clampf(difficulty, 0.0, 1.0)) * 1.8)
	return clampi(lo + int(shaped * float(hi - lo + 1)), lo, hi)


## --- the canvas ------------------------------------------------------------

## A mutable grid of ASCII glyphs. Kept here because segments are the only
## things that draw into it.
class Canvas extends RefCounted:
	const SPACE := 32

	var cols: int
	var rows: int

	var _cells: PackedByteArray = PackedByteArray()

	func _init(p_cols: int, p_rows: int) -> void:
		cols = maxi(p_cols, 1)
		rows = maxi(p_rows, 1)
		_cells.resize(cols * rows)
		_cells.fill(SPACE)

	func in_bounds(x: int, y: int) -> bool:
		return x >= 0 and x < cols and y >= 0 and y < rows

	func set_cell(x: int, y: int, glyph: String) -> void:
		if not in_bounds(x, y) or glyph.is_empty():
			return
		_cells[y * cols + x] = glyph.unicode_at(0)

	func get_cell(x: int, y: int) -> String:
		if not in_bounds(x, y):
			return " "
		return char(_cells[y * cols + x])

	## Inclusive in both rows.
	func fill_column(x: int, y0: int, y1: int, glyph: String) -> void:
		for y: int in range(mini(y0, y1), maxi(y0, y1) + 1):
			set_cell(x, y, glyph)

	func to_lines() -> PackedStringArray:
		var out := PackedStringArray()
		for y: int in rows:
			var line := ""
			for x: int in cols:
				line += char(_cells[y * cols + x])
			out.append(_round_trips(line.rstrip(" ")))
		return out

	## Guards the one way an ASCII grid row can be mistaken for prose.
	##
	## AsciiLevel.is_comment() treats a line of exactly "#" or one beginning
	## "# " as a comment, so a row whose first tile is solid and whose second
	## is blank disappears when the level is parsed back — quietly, taking its
	## row with it and shifting everything below. The legend maps "." to EMPTY
	## as well as " ", so writing that one blank as "." keeps the row readable,
	## hand-editable and immune. Only the first two columns can ever trigger
	## this, so at most one glyph changes.
	func _round_trips(line: String) -> String:
		if not AsciiLevel.is_comment(line):
			return line
		if line.length() < 2:
			return line + "."
		return line.substr(0, 1) + "." + line.substr(2)
