class_name ReachSearch
extends RefCounted
## The reachability proof for a level with mechanisms: LevelReachability's
## search and survey again, over (cell, mode, channel mask).
##
## Kept out of scripts/levels/reachability.gd on purpose. A level without a
## mechanism has an empty ReachModel and never reaches this file, so its proof
## is exactly the code it always was -- which is what lets the Sun Terrace,
## every generated ruin, the secret audit and the checkpoint proof go on
## meaning what they meant (tests/unit/test_reach_guard_rail.gd).
##
## How a mask works is ReachModel's business (scripts/levels/reach_model.gd).
## Here it is only carried: a full state is `(mask << MASK_SHIFT) | cell key`,
## and before a state is expanded the solver's tile flags are swapped for its
## mask's, so every movement primitive -- the arcs, the grab probe, the
## ladders -- sees the level as that state has it. Arriving somewhere can set
## bits (a plate), and a stand state reached under a new mask is checked again
## under it: a latch that takes the floor takes the prince with it.

const MASK_SHIFT := LevelReachability.Solver.MASK_SHIFT
const LOW_MASK := LevelReachability.Solver.LOW_MASK


## Greedy best-first toward `exits` (and the cell above each), like
## Solver.search(). An exit counts under any mask; a `proved` cell only with
## every wire off, because that is the state it was proved in
## (Game.checkpoint_cells()).
static func search(solver: LevelReachability.Solver, start: Vector2i,
		exits: Array[Vector2i], proved: Array[Vector2i]) -> Dictionary:
	var exit_keys := _keys(solver, exits)
	var proved_keys := _keys(solver, proved)
	var goals: Array[Vector2i] = exits.duplicate()
	goals.append_array(proved)

	var span := solver.cols + solver.rows + 2
	var buckets: Array[Array] = []
	buckets.resize(span)
	for i: int in span:
		buckets[i] = []
	var visited := {}
	var lowest := span
	var starts: Array[int] = []
	arrive(solver, solver.cell_key(LevelReachability.MODE_STAND, start.x, start.y), 0, starts)
	for full: int in starts:
		if exit_keys.has(full & LOW_MASK) or proved_keys.has(full):
			return {"ok": true, "reason": "spawn is already at the exit", "explored": 0}
		visited[full] = true
		var first := _priority(solver, full, goals, span)
		buckets[first].append(full)
		lowest = mini(lowest, first)

	var explored := 0
	var neighbours: Array[int] = []
	var arrivals: Array[int] = []
	while lowest < span:
		if buckets[lowest].is_empty():
			lowest += 1
			continue
		var key: int = buckets[lowest].pop_back()
		explored += 1
		if explored > LevelReachability.MAX_STATES:
			return {"ok": false, "explored": explored, "reason":
				"search budget of %d states exhausted" % LevelReachability.MAX_STATES}
		_expand(solver, key, neighbours)
		for next: int in neighbours:
			arrivals.clear()
			arrive(solver, next, key >> MASK_SHIFT, arrivals)
			for full: int in arrivals:
				if visited.has(full):
					continue
				visited[full] = true
				if exit_keys.has(full & LOW_MASK) or proved_keys.has(full):
					return {"ok": true, "reason": "exit reached", "explored": explored,
						"states": visited.size()}
				var priority := _priority(solver, full, goals, span)
				buckets[priority].append(full)
				if priority < lowest:
					lowest = priority

	return {"ok": false, "reason": "exit is not reachable from the spawn",
		"explored": explored, "states": visited.size()}


## Solver.survey() over masks. A cell is reached if any of its states is, and
## stranded if any reached state of it cannot reach the exit -- a player can
## be in any of them. `stranded_states` lists those states themselves.
static func survey(solver: LevelReachability.Solver, start: Vector2i,
		goals: Array[Vector2i]) -> Dictionary:
	var goal_keys := _keys(solver, goals)
	var incoming := {}
	var queue: Array[int] = []
	var starts: Array[int] = []
	arrive(solver, solver.cell_key(LevelReachability.MODE_STAND, start.x, start.y), 0, starts)
	for full: int in starts:
		if not incoming.has(full):
			incoming[full] = []
			queue.append(full)
	var head := 0
	var neighbours: Array[int] = []
	var arrivals: Array[int] = []
	while head < queue.size():
		var key: int = queue[head]
		head += 1
		if head > LevelReachability.MAX_STATES:
			return {"ok": false, "reason": "search budget of %d states exhausted"
				% LevelReachability.MAX_STATES, "reached": {}, "stranded": {},
				"stranded_states": {}, "states": head}
		_expand(solver, key, neighbours)
		for next: int in neighbours:
			arrivals.clear()
			arrive(solver, next, key >> MASK_SHIFT, arrivals)
			for full: int in arrivals:
				if not incoming.has(full):
					incoming[full] = []
					queue.append(full)
				(incoming[full] as Array).append(key)

	var home := {}
	var back: Array[int] = []
	for key: int in queue:
		if goal_keys.has(key & LOW_MASK):
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
	var stranded_states := {}
	for key: int in queue:
		var low := key & LOW_MASK
		if low & 1 != LevelReachability.MODE_STAND:
			continue
		var cell := Vector2i((low >> 1) % solver.cols, (low >> 1) / solver.cols)
		reached[cell] = true
		if not home.has(key):
			stranded[cell] = true
			stranded_states[key] = true
	var ok := not back.is_empty()
	return {
		"ok": ok,
		"reason": "exit reached" if ok else "exit is not reachable from the spawn",
		"reached": reached,
		"stranded": stranded,
		"stranded_states": stranded_states,
		"states": queue.size(),
	}


## Arriving in cell key `low` from a state with `mask`, appending the full
## states the prince ends up in. Standing somewhere can set bits; under the
## new mask he may not be standing any more, and then he falls from there and
## arrives wherever that leaves him. Bits are only ever set, so this recurses
## at most once per channel.
static func arrive(solver: LevelReachability.Solver, low: int, mask: int,
		out: Array[int], depth: int = 0) -> void:
	if low & 1 != LevelReachability.MODE_STAND:
		out.append((mask << MASK_SHIFT) | low)
		return
	var cell := Vector2i((low >> 1) % solver.cols, (low >> 1) / solver.cols)
	var after := solver.model().after_standing(mask, cell)
	if after == mask:
		out.append((mask << MASK_SHIFT) | low)
		return
	solver.use_mask(after)
	if solver.is_stand(cell.x, cell.y):
		out.append((after << MASK_SHIFT) | low)
		return
	if depth >= ReachModel.MAX_CHANNELS:
		return
	var landed: Array[int] = []
	solver.drop(cell, landed)
	for next: int in landed:
		arrive(solver, next, after, out, depth + 1)


## The neighbours of full state `key`, with its mask's flags in place.
static func _expand(solver: LevelReachability.Solver, key: int, out: Array[int]) -> void:
	solver.use_mask(key >> MASK_SHIFT)
	solver.expand(key & LOW_MASK, out)


## Standing and ladder cell keys for every cell in `cells`.
static func _keys(solver: LevelReachability.Solver, cells: Array[Vector2i]) -> Dictionary:
	var out := {}
	for cell: Vector2i in cells:
		out[solver.cell_key(LevelReachability.MODE_STAND, cell.x, cell.y)] = true
		out[solver.cell_key(LevelReachability.MODE_LADDER, cell.x, cell.y)] = true
	return out


static func _priority(solver: LevelReachability.Solver, full: int,
		goals: Array[Vector2i], span: int) -> int:
	var index := (full & LOW_MASK) >> 1
	return solver.priority(index % solver.cols, index / solver.cols, goals, span)
