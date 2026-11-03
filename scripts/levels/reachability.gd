class_name LevelReachability
extends RefCounted
## Proves that a level's exit can actually be reached from its spawn.
##
## This is the part that makes a generated level trustworthy. It is not a
## heuristic and not a tile-distance estimate: it is a search over the
## character's real movement primitives, where every primitive is produced by
## stepping the same arithmetic scripts/player/player.gd steps — the two-phase
## gravity of `_apply_gravity`, the `move_toward` air control of
## `_free_movement`, the one-way platform layer, and the hand probe of
## `_try_grab_ledge` with its hang-rect and stand-rect clearance checks.
##
## Nothing here hardcodes a jump height, a gap width or a grab reach. The reach
## envelope falls out of scripts/core/tuning.gd through the simulation, which
## is why `measure_reach()` exists: it probes synthetic levels and reports the
## rises the simulation actually clears, and tests/level_envelope_test.gd pins
## those measurements against Tuning.hop_tiles(), Tuning.platform_step_tiles()
## and Tuning.grab_tiles(). A retune that moves those helpers has to move the
## measured envelope with it or the suite fails.
##
## The search is deliberately conservative — where a real player has an option
## this model does not reproduce (coyote jumps, releasing the stick mid-arc,
## jumping off a ladder, wall-sliding to a lower ledge, crouch-walking under a
## one-tile ceiling), the edge is simply not offered. So "verified" means
## "reachable even by this reduced character", never "reachable if you are
## perfect". Erring the other way would make the proof worthless.

## Tile flags, cached off AsciiLevel.kind_at once per verification.
const F_SOLID := 1
const F_PLATFORM := 2
const F_HAZARD := 4
const F_LADDER := 8

const MODE_STAND := 0
const MODE_LADDER := 1

## Physics is stepped at Godot's fixed 60 Hz, same as _physics_process.
const DT := 1.0 / 60.0
## Long enough for a fall from the top of a level to the void below it.
const MAX_ARC_FRAMES := 240
## A budget so an unsolvable level fails instead of hanging the generator.
const MAX_STATES := 200000


## Verifies a parsed level end to end. Returns
## `{ok, reason, explored, goal, spawn}`.
static func verify(level: AsciiLevel) -> Dictionary:
	if level == null:
		return _fail("no level data", 0)
	return verify_from(level, level.spawn_point)


## The same proof from somewhere other than the spawn: can a character standing
## in `start` still reach the exit?
##
## This is what makes a checkpoint safe to respawn on. A place the player has
## stood is reachable by definition, but nothing guarantees the exit is
## reachable *from* it — a dead-end pit with a torch in it would turn every
## death into a return to the same pit. `Game` adopts a torch as a checkpoint
## only when this says yes, so a respawn can never be a soft lock.
##
## `proved` is cells already shown to reach the exit. Arriving at one of them
## is as good as arriving at the door, because reachability is transitive, and
## it turns a search across the whole level into a search to the next torch:
## proving ten torches costs about what proving one used to.
static func verify_from(level: AsciiLevel, start: Vector2i,
		proved: Array[Vector2i] = []) -> Dictionary:
	if level == null:
		return _fail("no level data", 0)

	var exits: Array[Vector2i] = []
	for mark: Dictionary in level.entities:
		if String(mark["kind"]) == "exit":
			exits.append(mark["cell"])
	if exits.is_empty():
		return _fail("level has no exit door", 0)

	var solver := Solver.new(level)

	var spawn := start
	if not solver.is_stand(spawn.x, spawn.y):
		return _fail("spawn %s is not standing on clear solid ground" % str(spawn), 0)

	var goals: Array[Vector2i] = []
	var grounded_exit := false
	for cell: Vector2i in exits:
		if solver.is_stand(cell.x, cell.y):
			grounded_exit = true
		# The door's trigger box is two tiles tall (ExitDoor.bounds), so
		# arriving in the cell above it counts as touching it.
		goals.append(cell)
		goals.append(cell + Vector2i.UP)
	if not grounded_exit:
		return _fail("exit door %s is not standing on clear solid ground" % str(exits[0]), 0)
	goals.append_array(proved)

	var report := solver.search(spawn, goals)
	report["spawn"] = spawn
	report["goal"] = exits[0]
	return report


## --- secrets ---------------------------------------------------------------
##
## A secret room (docs/world.md, "Secrets") is only a gift if it is never the
## way and never a hole. `audit_secrets()` proves both, over every combination
## of found and unfound secrets, because the player can be anywhere in that
## lattice — found the first, walked past the second:
##
## - **Never required.** With every seal shut (false walls included: the
##   hypothesis is a player who never noticed one), the exit is reachable.
## - **Actually secret.** With every seal shut, every room is walled in: each
##   cell of it touches only its own room, its own seal or stone. The search
##   moves a body that collides per axis against solid cells, so nothing it
##   does can put any part of the character inside a walled room; checking the
##   walls is the same claim as flooding the level, at none of the cost. A
##   room the main line can already reach is a niche, not a secret.
## - **Findable.** With its own seal open, each room has a cell the character
##   can stand in. A prize nobody can reach is a promise broken.
## - **Never a trap.** For every subset of opened secrets, no cell the
##   character can reach is stranded — cut off from the exit — unless it was
##   already reachable and already stranded with every seal shut. Opening a
##   secret may not add a single dead end, which covers a room with no way
##   out, a broken floor that was the only bridge and a hole over a pit alike.
##
## The last is why the survey below is a flood rather than the greedy search:
## "every reachable state can still reach the door" is a question about all of
## them at once, answered by walking the explored edges backwards from the
## door — one pass however many cells there are. The shut level is only
## surveyed cell by cell, for a stranded cell an open one turns up: none of
## the shipping or generated levels has one, so the usual cost is one flood
## per subset and a greedy search, which is what lets the generator run this
## on every ruin it carves a secret into.
##
## With up to MAX_SUBSETS_FOR secrets every subset is played; past that, each
## secret alone and all of them together.
const MAX_SUBSETS_FOR := 4


## `{ok, reason, secrets, states}`; `ok` with no secrets is trivially true.
static func audit_secrets(level: AsciiLevel) -> Dictionary:
	if level == null:
		return _fail("no level data", 0)
	var count := level.secrets.size()
	if count == 0:
		return {"ok": true, "reason": "no secrets", "secrets": 0, "states": 0}

	var shut := level.with_secrets({})
	var base := verify(shut)
	if not bool(base["ok"]):
		return _fail("with every secret shut the exit is out of reach (%s): a secret "
			% String(base["reason"]) + "may never be the way", 0)
	var states := int(base.get("states", 0))

	for index: int in count:
		var breach := _breach(shut, level.secrets[index])
		if breach.x >= 0:
			return _fail("secret %d's room opens onto %s without its seal: it is not "
				% [index, str(breach)] + "hidden", states)

	for open: Dictionary in _openings(count):
		var played := survey(level.with_secrets(open))
		states += int(played["states"])
		var which := str(open.keys())
		if not bool(played["ok"]):
			return _fail("opening secrets %s cuts the way to the exit (%s)"
				% [which, String(played["reason"])], states)
		var stranded: Dictionary = played["stranded"]
		for cell: Vector2i in stranded:
			if not _stranded_anyway(shut, cell):
				return _fail("with secrets %s open, standing at %s the exit is gone"
					% [which, str(cell)], states)
		if open.size() == 1:
			var index: int = open.keys()[0]
			var reached: Dictionary = played["reached"]
			var inside := false
			for cell: Vector2i in level.secrets[index]["room"]:
				inside = inside or reached.has(cell)
			if not inside:
				return _fail("secret %d's room cannot be stood in even once it is open"
					% index, states)

	return {"ok": true, "reason": "%d secret(s): never required, never a trap" % count,
		"secrets": count, "states": states}


## The first cell outside `secret` that one of its room cells touches and that
## is not stone in `shut`, or (-1, -1) when the room is walled in.
static func _breach(shut: AsciiLevel, secret: Dictionary) -> Vector2i:
	var own := {}
	for cell: Vector2i in secret["cells"]:
		own[cell] = true
	for cell: Vector2i in secret["room"]:
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := cell + step
			if not own.has(next) and not shut.is_solid(next.x, next.y):
				return next
	return Vector2i(-1, -1)


## True when `cell` was a dead end before any secret was opened: reachable with
## every seal shut, and no way from it to the exit even then.
static func _stranded_anyway(shut: AsciiLevel, cell: Vector2i) -> bool:
	var goals: Array[Vector2i] = [cell]
	if not bool(reaches(shut, goals)["ok"]):
		return false
	return not bool(verify_from(shut, cell)["ok"])


## The subsets of `count` secrets the audit plays, each as index -> true.
static func _openings(count: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if count <= MAX_SUBSETS_FOR:
		for mask: int in range(1, 1 << count):
			var open := {}
			for index: int in count:
				if mask & (1 << index) != 0:
					open[index] = true
			out.append(open)
		return out
	var every := {}
	for index: int in count:
		out.append({index: true})
		every[index] = true
	out.append(every)
	return out


## Every standing cell reachable from the spawn, and which of them can no
## longer reach the exit. `{ok, reason, reached, stranded, states}`, where
## `reached` and `stranded` map a cell to true and `ok` says the exit itself
## was reached.
static func survey(level: AsciiLevel) -> Dictionary:
	var empty := {"reached": {}, "stranded": {}, "states": 0}
	if level == null:
		return _fail("no level data", 0).merged(empty)
	var goals: Array[Vector2i] = []
	for mark: Dictionary in level.entities:
		if String(mark["kind"]) == "exit":
			goals.append(mark["cell"])
			goals.append(mark["cell"] + Vector2i.UP)
	if goals.is_empty():
		return _fail("level has no exit door", 0).merged(empty)
	var solver := Solver.new(level)
	if not solver.is_stand(level.spawn_point.x, level.spawn_point.y):
		return _fail("spawn is not standing on clear solid ground", 0).merged(empty)
	return solver.survey(level.spawn_point, goals)


## Runs the same search toward arbitrary goal cells. Used by `measure_reach()`
## and handy for diagnosing a level by hand.
static func reaches(level: AsciiLevel, goals: Array[Vector2i]) -> Dictionary:
	if level == null:
		return _fail("no level data", 0)
	var solver := Solver.new(level)
	if not solver.is_stand(level.spawn_point.x, level.spawn_point.y):
		return _fail("spawn is not standing on clear solid ground", 0)
	return solver.search(level.spawn_point, goals)


## The authoring envelope, for documentation and for the CLI's banner. The
## numbers the *verifier* uses are not read from here — they emerge from the
## simulation — but these are what the grammar is allowed to assume.
static func envelope() -> Dictionary:
	return {
		"hop_tiles": Tuning.hop_tiles(),
		"platform_step_tiles": Tuning.platform_step_tiles(),
		"grab_tiles": Tuning.grab_tiles(),
		"max_jump_rise_px": Tuning.max_jump_rise(),
		"jump_airtime_s": Tuning.jump_airtime(),
		"max_gap_tiles": LevelGrammar.max_gap_tiles(),
		"authored_gap_tiles": LevelGrammar.safe_gap_tiles(),
	}


## Measures the envelope by simulation instead of by arithmetic: how high a
## plain hop actually lands, how high a ledge grab actually catches, and how
## wide a gap a running jump actually crosses. Each probe is a synthetic level
## built for exactly one question.
static func measure_reach() -> Dictionary:
	return {
		"hop": _measure(1, 8, _probe_platform),
		"grab": _measure(1, 8, _probe_wall),
		"gap": _measure(1, 8, _probe_gap),
	}


## --- probes ----------------------------------------------------------------

## The largest `n` in [lo, hi] for which `builder` yields a solvable probe.
## Scans upward and stops at the first failure, so a non-monotonic envelope
## reports the first plateau rather than a misleading maximum.
static func _measure(lo: int, hi: int, builder: Callable) -> int:
	var best := 0
	for n: int in range(lo, hi + 1):
		var probe: Dictionary = builder.call(n)
		var level := AsciiLevel.new()
		level.parse(probe["text"])
		var goals: Array[Vector2i] = [probe["goal"]]
		if not bool(reaches(level, goals)["ok"]):
			break
		best = n
	return best


const _PROBE_COLS := 16
const _PROBE_ROWS := 14
const _PROBE_SURFACE := 10   ## Row of the probe's ground surface.


## A one-way platform `rise` tiles above the ground. A platform is not solid,
## so `_try_grab_ledge` cannot catch it — this isolates the plain hop.
static func _probe_platform(rise: int) -> Dictionary:
	var grid := _probe_canvas()
	var row := _PROBE_SURFACE - rise
	for x: int in range(7, 10):
		grid.set_cell(x, row, LevelGrammar.PLATFORM)
	return {
		"text": _probe_text(grid),
		"goal": Vector2i(8, row - 1),
	}


## A solid wall `rise` tiles tall. Hops handle the low ones, the ledge grab the
## tall ones, so the largest solvable rise is the grab reach.
static func _probe_wall(rise: int) -> Dictionary:
	var grid := _probe_canvas()
	for x: int in range(8, _PROBE_COLS):
		grid.fill_column(x, _PROBE_SURFACE - rise, _PROBE_ROWS - 1, LevelGrammar.SOLID)
	return {
		"text": _probe_text(grid),
		"goal": Vector2i(11, _PROBE_SURFACE - rise - 1),
	}


## Two terraces with `span` bottomless columns between them.
static func _probe_gap(span: int) -> Dictionary:
	var grid := _probe_canvas()
	for i: int in span:
		grid.fill_column(6 + i, 0, _PROBE_ROWS - 1, LevelGrammar.EMPTY)
	return {
		"text": _probe_text(grid),
		"goal": Vector2i(6 + span + 1, _PROBE_SURFACE - 1),
	}


static func _probe_canvas() -> LevelGrammar.Canvas:
	var grid := LevelGrammar.Canvas.new(_PROBE_COLS, _PROBE_ROWS)
	for x: int in _PROBE_COLS:
		grid.fill_column(x, _PROBE_SURFACE, _PROBE_ROWS - 1, LevelGrammar.SOLID)
	return grid


static func _probe_text(grid: LevelGrammar.Canvas) -> String:
	grid.set_cell(2, _PROBE_SURFACE - 1, LevelGrammar.SPAWN)
	return "\n".join(grid.to_lines())


static func _fail(reason: String, explored: int) -> Dictionary:
	return {"ok": false, "reason": reason, "explored": explored}


## --- the search ------------------------------------------------------------

class Solver extends RefCounted:
	var cols: int
	var rows: int
	var flags: PackedByteArray = PackedByteArray()

	var _half: float
	var _body: float
	var _tile: float

	func _init(level: AsciiLevel) -> void:
		cols = maxi(level.cols, 1)
		rows = maxi(level.rows, 1)
		_half = Tuning.BODY_WIDTH * 0.5
		_body = Tuning.BODY_HEIGHT
		_tile = Tuning.TILE

		flags.resize(cols * rows)
		for y: int in rows:
			for x: int in cols:
				var flag := 0
				match level.kind_at(x, y):
					Tiles.Kind.SOLID:
						flag = F_SOLID
					Tiles.Kind.PLATFORM:
						flag = F_PLATFORM
					Tiles.Kind.SPIKES, Tiles.Kind.WATER:
						flag = F_HAZARD
					Tiles.Kind.LADDER:
						flag = F_LADDER
					_:
						flag = 0
				flags[y * cols + x] = flag

	## Mirrors AsciiLevel.kind_at: the sides are walls, above and below is open.
	func at(x: int, y: int) -> int:
		if y < 0 or y >= rows:
			return 0
		if x < 0 or x >= cols:
			return F_SOLID
		return flags[y * cols + x]

	func _key(mode: int, x: int, y: int) -> int:
		return ((y * cols + x) << 1) | mode

	## --- body queries ------------------------------------------------------

	## OR of the flags of every cell the body overlaps, with the body's origin
	## at its feet. The rounding matches Level.rect_has_kind exactly, because
	## that is what decides a hazard or a wall at runtime.
	func rect_flags(cx: float, feet: float) -> int:
		var x0 := floori((cx - _half) / _tile)
		var x1 := floori((cx + _half - 0.001) / _tile)
		var y0 := floori((feet - _body) / _tile)
		var y1 := floori((feet - 0.001) / _tile)
		var out := 0
		for y: int in range(y0, y1 + 1):
			for x: int in range(x0, x1 + 1):
				out |= at(x, y)
		return out

	## True when a character can stand upright in cell (x, y): the body fits
	## without touching solid or a hazard, and something holds it up.
	func is_stand(x: int, y: int) -> bool:
		if y < 0 or y >= rows or x < 0 or x >= cols:
			return false
		var cx := float(x) * _tile + _tile * 0.5
		var feet := float(y + 1) * _tile
		if rect_flags(cx, feet) & (F_SOLID | F_HAZARD) != 0:
			return false
		return at(x, y + 1) & (F_SOLID | F_PLATFORM) != 0

	## True when the body overlaps a ladder it could be hanging on.
	func is_ladder(x: int, y: int) -> bool:
		if y < 0 or y >= rows or x < 0 or x >= cols:
			return false
		var cx := float(x) * _tile + _tile * 0.5
		var feet := float(y + 1) * _tile
		var f := rect_flags(cx, feet)
		if f & (F_SOLID | F_HAZARD) != 0:
			return false
		return f & F_LADDER != 0

	func _column_has_solid(column: int, row0: int, row1: int) -> bool:
		for y: int in range(row0, row1 + 1):
			if at(column, y) & F_SOLID != 0:
				return true
		return false

	func _row_has(row: int, col0: int, col1: int, mask: int) -> bool:
		for x: int in range(col0, col1 + 1):
			if at(x, row) & mask != 0:
				return true
		return false

	## --- search ------------------------------------------------------------

	## Greedy best-first over movement primitives. The queue is bucketed by
	## manhattan distance to the nearest goal, which finds a route through a
	## long level without flooding it, and is exhaustive — so an unreachable
	## exit still reports unreachable rather than timing out.
	func search(start: Vector2i, goals: Array[Vector2i]) -> Dictionary:
		var goal_keys := {}
		for cell: Vector2i in goals:
			goal_keys[_key(MODE_STAND, cell.x, cell.y)] = true
			goal_keys[_key(MODE_LADDER, cell.x, cell.y)] = true

		var start_key := _key(MODE_STAND, start.x, start.y)
		if goal_keys.has(start_key):
			return {"ok": true, "reason": "spawn is already at the exit", "explored": 0}

		var span := cols + rows + 2
		var buckets: Array[Array] = []
		buckets.resize(span)
		for i: int in span:
			buckets[i] = []

		var visited := {}
		visited[start_key] = true
		var lowest := _priority(start.x, start.y, goals, span)
		buckets[lowest].append(start_key)

		var explored := 0
		var neighbours: Array[int] = []

		while lowest < span:
			if buckets[lowest].is_empty():
				lowest += 1
				continue
			var key: int = buckets[lowest].pop_back()
			explored += 1
			if explored > MAX_STATES:
				return {
					"ok": false,
					"reason": "search budget of %d states exhausted" % MAX_STATES,
					"explored": explored,
				}

			var mode := key & 1
			var index := key >> 1
			var x := index % cols
			var y := index / cols

			neighbours.clear()
			if mode == MODE_STAND:
				_expand_stand(x, y, neighbours)
			else:
				_expand_ladder(x, y, neighbours)

			for next: int in neighbours:
				if visited.has(next):
					continue
				visited[next] = true
				if goal_keys.has(next):
					return {
						"ok": true,
						"reason": "exit reached",
						"explored": explored,
						"states": visited.size(),
					}
				var nindex := next >> 1
				var priority := _priority(nindex % cols, nindex / cols, goals, span)
				buckets[priority].append(next)
				if priority < lowest:
					lowest = priority

		return {
			"ok": false,
			"reason": "exit is not reachable from the spawn",
			"explored": explored,
			"states": visited.size(),
		}

	## Floods every state reachable from `start`, keeping each edge, then walks
	## the edges backwards from the goal states. A stand state the backward walk
	## never reaches is stranded: the character can get there and not out.
	func survey(start: Vector2i, goals: Array[Vector2i]) -> Dictionary:
		var goal_keys := {}
		for cell: Vector2i in goals:
			goal_keys[_key(MODE_STAND, cell.x, cell.y)] = true
			goal_keys[_key(MODE_LADDER, cell.x, cell.y)] = true

		var start_key := _key(MODE_STAND, start.x, start.y)
		var incoming := {start_key: []}
		var queue: Array[int] = [start_key]
		var head := 0
		var neighbours: Array[int] = []
		while head < queue.size():
			var key: int = queue[head]
			head += 1
			if head > MAX_STATES:
				return {"ok": false, "reason": "search budget of %d states exhausted"
					% MAX_STATES, "reached": {}, "stranded": {}, "states": head}
			var index := key >> 1
			neighbours.clear()
			if key & 1 == MODE_STAND:
				_expand_stand(index % cols, index / cols, neighbours)
			else:
				_expand_ladder(index % cols, index / cols, neighbours)
			for next: int in neighbours:
				if not incoming.has(next):
					incoming[next] = []
					queue.append(next)
				(incoming[next] as Array).append(key)

		var home := {}
		var back: Array[int] = []
		for key: int in queue:
			if goal_keys.has(key):
				home[key] = true
				back.append(key)
		var cursor := 0
		while cursor < back.size():
			for previous: int in incoming[back[cursor]]:
				if not home.has(previous):
					home[previous] = true
					back.append(previous)
			cursor += 1

		var reached := {}
		var stranded := {}
		for key: int in queue:
			if key & 1 != MODE_STAND:
				continue
			var cell := Vector2i((key >> 1) % cols, (key >> 1) / cols)
			reached[cell] = true
			if not home.has(key):
				stranded[cell] = true
		var ok := not back.is_empty()
		return {
			"ok": ok,
			"reason": "exit reached" if ok else "exit is not reachable from the spawn",
			"reached": reached,
			"stranded": stranded,
			"states": queue.size(),
		}

	func _priority(x: int, y: int, goals: Array[Vector2i], span: int) -> int:
		var best := span - 1
		for cell: Vector2i in goals:
			best = mini(best, absi(cell.x - x) + absi(cell.y - y))
		return clampi(best, 0, span - 1)

	## --- primitives --------------------------------------------------------

	func _offer_stand(x: int, y: int, out: Array[int]) -> void:
		if is_stand(x, y):
			out.append(_key(MODE_STAND, x, y))

	func _offer_ladder(x: int, y: int, out: Array[int]) -> void:
		if is_ladder(x, y):
			out.append(_key(MODE_LADDER, x, y))

	func _expand_stand(x: int, y: int, out: Array[int]) -> void:
		# walk — a one-tile step up or down needs a hop, so this is flat only
		_offer_stand(x - 1, y, out)
		_offer_stand(x + 1, y, out)

		# grab onto a ladder the body is already overlapping
		_offer_ladder(x, y, out)

		for dir: int in [-1, 1]:
			# A single walkable cell behind is enough to reach RUN_SPEED:
			# GROUND_ACCEL covers it in well under half a tile.
			var runway := is_stand(x - dir, y)
			if runway:
				_trace(x, y, true, dir, dir, Tuning.RUN_SPEED, 0.0, 0, out)
			# A standing-start jump lands shorter, which is what reaches a
			# narrow ledge the running jump would sail over.
			_trace(x, y, true, dir, dir, 0.0, 0.0, 0, out)
			# Straight up, facing `dir`: the only way to grab the wall you are
			# already pressed against.
			_trace(x, y, true, 0, dir, 0.0, 0.0, 0, out)

			var ahead_open := not is_stand(x + dir, y) and at(x + dir, y) & F_SOLID == 0
			if ahead_open:
				# Jumping from the lip rather than the middle of the tile. The
				# takeoff sits exactly on the tile boundary, so half the body
				# is still over solid ground — a position anyone reaches by
				# walking to the edge, and worth half a tile of gap. The real
				# character can lean another 4 px out over the drop; that part
				# is given up rather than claimed.
				if runway:
					_trace(x, y, true, dir, dir, Tuning.RUN_SPEED,
						Tuning.TILE * 0.5 * float(dir), 0, out)
				# Walking off an edge, which is a different arc from jumping.
				_trace(x, y, false, dir, dir,
					Tuning.RUN_SPEED if runway else Tuning.WALK_SPEED, 0.0, 0, out)

		# Drop through a one-way platform: Player sets _drop_through for 0.25s,
		# which is simply ignoring the one-way layer for that many frames.
		var below := at(x, y + 1)
		if below & F_PLATFORM != 0 and below & F_SOLID == 0:
			_trace(x, y, false, 0, 1, 0.0, 0.0, int(0.25 / DT), out)

	func _expand_ladder(x: int, y: int, out: Array[int]) -> void:
		_offer_ladder(x, y - 1, out)
		_offer_ladder(x, y + 1, out)
		# Stepping off: Player._update_ladder moves horizontally at half walk
		# speed and drops out of LADDER state as soon as the body leaves it.
		_offer_stand(x, y, out)
		_offer_stand(x - 1, y, out)
		_offer_stand(x + 1, y, out)

	## Steps one arc of the character's physics from standing in cell
	## (sx, sy) and appends every state it proves reachable.
	##
	## `jump` starts the arc with a jump impulse; otherwise the arc begins
	## grounded and walks until it runs out of floor. `dir` is the horizontal
	## input held for the whole arc, `facing` is what the grab probe uses when
	## `dir` is zero, `offset` shifts the takeoff away from the middle of the
	## tile, and `ignore_platforms` is the drop-through window in frames.
	func _trace(sx: int, sy: int, jump: bool, dir: int, facing: int, v0: float,
			offset: float, ignore_platforms: int, out: Array[int]) -> void:
		var cx := float(sx) * _tile + _tile * 0.5 + offset
		var feet := float(sy + 1) * _tile
		var vx := v0 * float(dir)
		var vy := -Tuning.JUMP_SPEED if jump else 0.0
		var grounded := not jump
		var floor_limit := float(rows) * _tile + 64.0

		# An arc may only start somewhere the body could actually be.
		if rect_flags(cx, feet) & (F_SOLID | F_HAZARD) != 0:
			return

		for frame: int in MAX_ARC_FRAMES:
			# 1. horizontal control, exactly as Player._free_movement
			var accel := Tuning.GROUND_ACCEL if grounded else Tuning.AIR_ACCEL
			var friction := Tuning.GROUND_FRICTION if grounded else Tuning.AIR_FRICTION
			if dir != 0:
				vx = move_toward(vx, float(dir) * Tuning.RUN_SPEED, accel * DT)
			else:
				vx = move_toward(vx, 0.0, friction * DT)

			# 2. gravity, with the reduced apex pull of Player._apply_gravity
			if not grounded:
				var near_apex := absf(vy) < Tuning.APEX_THRESHOLD
				var scale := Tuning.APEX_GRAVITY_SCALE if near_apex else 1.0
				vy = minf(vy + Tuning.GRAVITY * scale * DT, Tuning.MAX_FALL_SPEED)

			# 3. horizontal move, sliding along walls like move_and_slide
			if not is_zero_approx(vx):
				var nx := cx + vx * DT
				var row0 := floori((feet - _body) / _tile)
				var row1 := floori((feet - 0.001) / _tile)
				if vx > 0.0:
					var column := floori((nx + _half - 0.001) / _tile)
					if _column_has_solid(column, row0, row1):
						nx = float(column) * _tile - _half
						vx = 0.0
				else:
					var column := floori((nx - _half) / _tile)
					if _column_has_solid(column, row0, row1):
						nx = float(column + 1) * _tile + _half
						vx = 0.0
				cx = nx

			# 4. vertical move
			var landed := false
			if grounded:
				# Still walking: the arc leaves the ground when the floor does.
				# During the drop-through window the one-way layer is switched
				# off, so a platform stops holding the body up — which is the
				# whole mechanism, not just a collision detail.
				var support := F_SOLID if frame < ignore_platforms else (F_SOLID | F_PLATFORM)
				if at(floori(cx / _tile), floori(feet / _tile)) & support == 0:
					grounded = false
			else:
				var ny := feet + vy * DT
				var col0 := floori((cx - _half) / _tile)
				var col1 := floori((cx + _half - 0.001) / _tile)
				if vy > 0.0:
					var row := floori((ny - 0.001) / _tile)
					if _row_has(row, col0, col1, F_SOLID):
						ny = float(row) * _tile
						landed = true
					elif frame >= ignore_platforms:
						# One-way: it only stops the body whose feet cross its
						# top edge while descending.
						var crossed := _platform_crossing(feet, ny, col0, col1)
						if crossed >= 0:
							ny = float(crossed) * _tile
							landed = true
				elif vy < 0.0:
					var head := floori((ny - _body) / _tile)
					if _row_has(head, col0, col1, F_SOLID):
						ny = float(head + 1) * _tile + _body
						vy = 0.0
				feet = ny
				if landed:
					vy = 0.0
					grounded = true

			# 5. what this frame proves — or costs
			if rect_flags(cx, feet) & F_HAZARD != 0:
				return # spikes or water: the arc kills the player
			if feet - _body > floor_limit:
				return # fell out of the world

			# Catching a ladder mid-arc. Player._update_free() holds a catch
			# made in the air; tests/unit/test_ladder.gd plays it.
			if rect_flags(cx, feet) & F_LADDER != 0:
				_offer_ladder(floori(cx / _tile), floori((feet - 0.001) / _tile), out)

			if not grounded and vy > 0.0 and vy <= Tuning.MAX_GRAB_FALL_SPEED:
				_probe_ledge(cx, feet, dir if dir != 0 else facing, out)

			if landed:
				_offer_stand(floori(cx / _tile), floori(feet / _tile) - 1, out)
				return

			if grounded and is_zero_approx(vx) and dir == 0:
				return # standing still on the ground: nothing more to learn

	## The row of the one-way platform the feet cross between `feet0` and
	## `feet1`, or -1. Frame moves are under 6 px so at most one row is crossed.
	func _platform_crossing(feet0: float, feet1: float, col0: int, col1: int) -> int:
		var first := floori(feet0 / _tile)
		var last := floori((feet1 - 0.001) / _tile)
		for row: int in range(first, last + 1):
			var top := float(row) * _tile
			if top >= feet0 and top <= feet1 and _row_has(row, col0, col1, F_PLATFORM):
				return row
		return -1

	## Player._try_grab_ledge, step for step: the hand probe at hand height in
	## the facing direction, a solid cell with nothing solid on top of it, a
	## hang position clear of walls, and room to stand up after the mantle.
	func _probe_ledge(cx: float, feet: float, dir: int, out: Array[int]) -> void:
		if dir == 0:
			return
		var hand_x := cx + (_half + Tuning.GRAB_REACH) * float(dir)
		var probe_y := feet - _body + Tuning.GRAB_PROBE_Y
		var cell_x := floori(hand_x / _tile)
		var cell_y := floori(probe_y / _tile)

		if at(cell_x, cell_y) & F_SOLID == 0:
			return
		if at(cell_x, cell_y - 1) & F_SOLID != 0:
			return

		var ledge_top := float(cell_y) * _tile
		var hang_feet := ledge_top - Tuning.GRAB_PROBE_Y + _body
		var hang_x := (
			float(cell_x) * _tile - _half if dir > 0
			else float(cell_x + 1) * _tile + _half
		)
		if rect_flags(hang_x, hang_feet) & F_SOLID != 0:
			return # Player bails out of the grab rather than clipping in

		# Player._update_hang mantles half a tile across onto the ledge top.
		var target_x := hang_x + _tile * 0.5 * float(dir)
		if rect_flags(target_x, ledge_top) & F_SOLID != 0:
			return # no room to stand up: the grab is a dead end

		_offer_stand(floori(target_x / _tile), cell_y - 1, out)
