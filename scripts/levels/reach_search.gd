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
##
## ## Checkpoints keep their latches
##
## A checkpoint respawn keeps what was latched (Game._respawn()), so a torch
## is proved from every mask the prince can be standing on it under, not just
## from the authored state (prove_checkpoints()). That set, with the traps put
## back, is the set he can respawn under, because every other bit in a mask is
## a latch: ReachModel has no other way to set one. A latch that drops the floor
## between a torch and the door therefore costs the torch its checkpoint,
## rather than making a respawn a soft lock.
##
## ## Floors that give way
##
## A transient stand (ReachModel.fuse_on_stand(): crumbling stone) is
## expanded under the mask it was reached with, and everything it leads to
## arrives under the mask with its fuse burnt (_leaving()). A move whose
## landing that took away is re-checked where it arrives and falls from there
## if it no longer stands. Waiting needs no move of its own: the jump straight
## up comes down where the slab was, with it gone, and falls through -- which
## is what a slab does to anyone who stays on it. A model with no fuses leaves
## every mask as it was, and none of this runs.
##
## A respawn puts traps back (ReachModel.resets_on_respawn()), so a torch is
## proved under each mask it is stood on with, as the respawn leaves it.

const MASK_SHIFT := LevelReachability.Solver.MASK_SHIFT
const LOW_MASK := LevelReachability.Solver.LOW_MASK


## Greedy best-first toward `exits` (and the cell above each), like
## Solver.search(), from `start` with `start_mask` set. An exit counts under
## any mask; a proved place only in the states it was proved in: `proved` is
## full states, as states_of() makes them (prove_checkpoints()).
static func search(solver: LevelReachability.Solver, start: Vector2i,
		exits: Array[Vector2i], proved: Dictionary, start_mask: int = 0) -> Dictionary:
	var exit_keys := _keys(solver, exits)
	var proved_keys := proved
	var goals: Array[Vector2i] = exits.duplicate()
	goals.append_array(_cells_of(solver, proved))

	var span := solver.cols + solver.rows + 2
	var buckets: Array[Array] = []
	buckets.resize(span)
	for i: int in span:
		buckets[i] = []
	var visited := {}
	var lowest := span
	var starts: Array[int] = []
	arrive(solver, solver.cell_key(LevelReachability.MODE_STAND, start.x, start.y), start_mask,
		starts)
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
		var leaving := _leaving(solver, key)
		for next: int in neighbours:
			arrivals.clear()
			arrive(solver, next, leaving, arrivals, 0, key >> MASK_SHIFT)
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
		var leaving := _leaving(solver, key)
		for next: int in neighbours:
			arrivals.clear()
			arrive(solver, next, leaving, arrivals, 0, key >> MASK_SHIFT)
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


## The torches, in the order given, a death can come back to. Each must reach
## the door, or a torch proved before it, from every mask the flood from the
## spawn stands on it under; one the flood never stands on is proved with
## every wire off, which is the proof a level without mechanisms gives it.
## A flood that runs out of budget proves nothing rather than guess.
static func prove_checkpoints(solver: LevelReachability.Solver, spawn: Vector2i,
		exits: Array[Vector2i], torches: Array[Vector2i]) -> Array[Vector2i]:
	var proved: Array[Vector2i] = []
	# Every wire a trap: every respawn is into the authored state, whatever
	# the flood would say he stood on the torch with, so it is not flooded.
	var claims_by_cell := {}
	if not solver.model().only_traps():
		var flood := standing_masks(solver, spawn, torches)
		if not bool(flood["ok"]):
			return proved
		claims_by_cell = flood["masks"]
	var proved_states := {}
	for torch: Vector2i in torches:
		var claims: Array[int] = [0]
		if claims_by_cell.has(torch):
			claims = _as_respawned(solver, claims_by_cell[torch])
		var holds := true
		for mask: int in claims:
			solver.use_mask(mask)
			if not solver.is_stand(torch.x, torch.y):
				holds = false
				break
			if not bool(search(solver, torch, exits, proved_states, mask)["ok"]):
				holds = false
				break
		if holds:
			proved.append(torch)
			proved_states.merge(states_of(solver, [torch] as Array[Vector2i], claims))
	return proved


## `masks` as a checkpoint respawn leaves them -- every trap put back -- once
## each, ascending.
static func _as_respawned(solver: LevelReachability.Solver, masks: Array) -> Array[int]:
	var seen := {}
	for mask: int in masks:
		seen[solver.model().respawn_mask(mask)] = true
	var out: Array[int] = []
	out.assign(seen.keys())
	out.sort()
	return out


## The masks the prince can be standing in each of `cells` under, flooding
## from `start` with every wire off: `{ok, masks: cell -> Array[int]}`, the
## masks ascending, and no entry for a cell the flood never stands in.
static func standing_masks(solver: LevelReachability.Solver, start: Vector2i,
		cells: Array[Vector2i]) -> Dictionary:
	var wanted := {}
	for cell: Vector2i in cells:
		wanted[solver.cell_key(LevelReachability.MODE_STAND, cell.x, cell.y)] = cell
	var seen := {}
	var queue: Array[int] = []
	var starts: Array[int] = []
	arrive(solver, solver.cell_key(LevelReachability.MODE_STAND, start.x, start.y), 0, starts)
	for full: int in starts:
		if not seen.has(full):
			seen[full] = true
			queue.append(full)
	var masks := {}
	var head := 0
	var neighbours: Array[int] = []
	var arrivals: Array[int] = []
	while head < queue.size():
		var key: int = queue[head]
		head += 1
		if head > LevelReachability.MAX_STATES:
			return {"ok": false, "masks": {}}
		if wanted.has(key & LOW_MASK):
			var cell: Vector2i = wanted[key & LOW_MASK]
			if not masks.has(cell):
				masks[cell] = [] as Array[int]
			(masks[cell] as Array[int]).append(key >> MASK_SHIFT)
		_expand(solver, key, neighbours)
		var leaving := _leaving(solver, key)
		for next: int in neighbours:
			arrivals.clear()
			arrive(solver, next, leaving, arrivals, 0, key >> MASK_SHIFT)
			for full: int in arrivals:
				if not seen.has(full):
					seen[full] = true
					queue.append(full)
	for cell: Vector2i in masks:
		(masks[cell] as Array[int]).sort()
	return {"ok": true, "masks": masks}


## The full states -- standing and on a ladder -- of every cell in `cells`
## under every mask in `masks`, for search()'s `proved`.
static func states_of(solver: LevelReachability.Solver, cells: Array[Vector2i],
		masks: Array[int]) -> Dictionary:
	var out := {}
	for key: int in _keys(solver, cells):
		for mask: int in masks:
			out[(mask << MASK_SHIFT) | key] = true
	return out


## Arriving in cell key `low` from a state with `mask`, appending the full
## states the prince ends up in. Standing somewhere can set bits; under the
## new mask he may not be standing any more, and then he falls from there and
## arrives wherever that leaves him. Bits are only ever set, so this recurses
## at most once per channel.
##
## `expanded_under` is the mask the move was found under, when that is not
## `mask` -- a move off a transient stand, found with the floor there and
## arriving with it gone. Such an arrival is checked again under `mask`, and
## falls from where it is if it no longer stands or hangs on a ladder.
static func arrive(solver: LevelReachability.Solver, low: int, mask: int,
		out: Array[int], depth: int = 0, expanded_under: int = -1) -> void:
	if expanded_under >= 0 and expanded_under != mask and not _holds(solver, low, mask):
		if depth >= ReachModel.MAX_CHANNELS:
			return
		var fell: Array[int] = []
		solver.drop(_cell_of(solver, low), fell)
		for next: int in fell:
			arrive(solver, next, mask, out, depth + 1)
		return
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


## Every full state the search moves to from full state `key`, as search()
## and survey() take them: the solver's moves and the races off a held plate,
## leaving a transient stand with its fuse burnt. For a reader that walks the
## proof's graph itself (ReachRoute), so it walks the same graph.
static func moves_from(solver: LevelReachability.Solver, key: int, out: Array[int]) -> void:
	var neighbours: Array[int] = []
	_expand(solver, key, neighbours)
	var leaving := _leaving(solver, key)
	var arrivals: Array[int] = []
	for next: int in neighbours:
		arrivals.clear()
		arrive(solver, next, leaving, arrivals, 0, key >> MASK_SHIFT)
		for full: int in arrivals:
			if not out.has(full):
				out.append(full)


## The neighbours of full state `key`, with its mask's flags in place.
static func _expand(solver: LevelReachability.Solver, key: int, out: Array[int]) -> void:
	solver.use_mask(key >> MASK_SHIFT)
	solver.expand(key & LOW_MASK, out)
	# A held plate is a race: a move to wherever the run beats the hold.
	ReachRace.extend(solver, key, out)


## The mask the moves out of full state `key` arrive under: its own, with
## the fuses of a transient stand burnt.
static func _leaving(solver: LevelReachability.Solver, key: int) -> int:
	var mask := key >> MASK_SHIFT
	var low := key & LOW_MASK
	if low & 1 != LevelReachability.MODE_STAND:
		return mask
	return solver.model().after_leaving(mask, _cell_of(solver, low))


## Whether cell key `low` still stands, or still hangs on a ladder, under
## `mask`. Leaves that mask's flags in place.
static func _holds(solver: LevelReachability.Solver, low: int, mask: int) -> bool:
	var cell := _cell_of(solver, low)
	solver.use_mask(mask)
	if low & 1 == LevelReachability.MODE_STAND:
		return solver.is_stand(cell.x, cell.y)
	return solver.is_ladder(cell.x, cell.y)


static func _cell_of(solver: LevelReachability.Solver, low: int) -> Vector2i:
	return Vector2i((low >> 1) % solver.cols, (low >> 1) / solver.cols)


## The cells of a set of full states, once each, for the search's heuristic.
static func _cells_of(solver: LevelReachability.Solver, states: Dictionary) -> Array[Vector2i]:
	var seen := {}
	for state: int in states:
		var index := (state & LOW_MASK) >> 1
		seen[Vector2i(index % solver.cols, index / solver.cols)] = true
	var out: Array[Vector2i] = []
	for cell: Vector2i in seen:
		out.append(cell)
	return out


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
