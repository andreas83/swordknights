class_name ReachRoute
extends RefCounted
## How far along the proved route a place is: the length of the shortest
## route the reachability proof knows from it to the door, in tiles.
##
## For `;! checkpoints route` (Game._progress()). A checkpoint is taken only
## when it is further on than the one held, and "further" has always been
## closeness to the door's column -- the one direction every level agreed on
## until a tower: a zig-zag climb moves away from the door's column and back,
## and the x rule would refuse the higher torch because it is further across.
## Moves left to the door are what "further on" means in any level; a level
## that needs it says so, and every other keeps the rule it was proved with.
##
## One flood from the spawn over the proof's own states -- channel masks
## included, so a mechanism's level works the same way -- recording where each
## state was reached from, then one walk back from the door, shortest first.
## The flood takes the search's own moves (ReachSearch.moves_from()): the
## races off a held plate and the fuse of a transient stand included. Built
## first with the solver's moves alone, it could not follow a race, so in a
## level whose way on is a race -- Chapter II's arcade -- nothing past the
## first held gate had a distance, and a torch there could never be "further
## on" under `;! checkpoints route`.
## Each of the proof's moves (a step, an arc, a rung) costs the tiles it
## crosses, across plus up or down: counting moves instead would make a torch
## at the far end of its ledge as far on as one at the near end, since a run
## along a ledge is one move however long.


## cell -> the tiles from standing there to the door along the shortest
## route, for every cell the flood from the spawn stands in that leads to the
## door at all. Empty for a level with no door, or one too big for the proof's
## budget.
static func remaining(level: AsciiLevel) -> Dictionary:
	var out := {}
	if level == null:
		return out
	var goals: Array[Vector2i] = []
	for mark: Dictionary in level.entities:
		if String(mark["kind"]) == "exit":
			goals.append_array([mark["cell"], (mark["cell"] as Vector2i) + Vector2i.UP])
	if goals.is_empty():
		return out
	var solver := LevelReachability.Solver.new(level, ReachModel.for_level(level))
	var goal_keys := {}
	for cell: Vector2i in goals:
		goal_keys[solver.cell_key(LevelReachability.MODE_STAND, cell.x, cell.y)] = true
		goal_keys[solver.cell_key(LevelReachability.MODE_LADDER, cell.x, cell.y)] = true

	var incoming := _flood(solver, level.spawn_point)
	if incoming.is_empty():
		return out
	# Dijkstra backwards from the door, with a bucket per distance: the costs
	# are small whole numbers of tiles.
	var steps := {}
	var buckets: Array[Array] = [[]]
	for key: int in incoming:
		if goal_keys.has(key & ReachSearch.LOW_MASK):
			steps[key] = 0
			buckets[0].append(key)
	var at := 0
	while at < buckets.size():
		var bucket: Array = buckets[at]
		var index := 0
		while index < bucket.size():
			var key: int = bucket[index]
			index += 1
			if int(steps[key]) != at:
				continue
			for previous: int in incoming[key]:
				var cost := at + _apart(solver, previous, key)
				if steps.has(previous) and int(steps[previous]) <= cost:
					continue
				steps[previous] = cost
				while buckets.size() <= cost:
					buckets.append([])
				buckets[cost].append(previous)
		at += 1

	for key: int in steps:
		var low := key & ReachSearch.LOW_MASK
		if low & 1 != LevelReachability.MODE_STAND:
			continue
		var cell := Vector2i((low >> 1) % solver.cols, (low >> 1) / solver.cols)
		out[cell] = mini(int(out.get(cell, steps[key])), int(steps[key]))
	return out


## Every state the flood from `start` reaches, each with the states it was
## reached from. Empty past the proof's budget. Without mechanisms there are
## no masks, and the solver is left exactly as the plain proof uses it.
static func _flood(solver: LevelReachability.Solver, start: Vector2i) -> Dictionary:
	var masked := solver.model() != null
	var incoming := {}
	var queue: Array[int] = []
	var starts: Array[int] = []
	_arrive(solver, masked, solver.cell_key(LevelReachability.MODE_STAND, start.x, start.y), 0,
		starts)
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
			return {}
		arrivals.clear()
		if masked:
			ReachSearch.moves_from(solver, key, arrivals)
		else:
			solver.expand(key, neighbours)
			arrivals.append_array(neighbours)
		for full: int in arrivals:
			if not incoming.has(full):
				incoming[full] = []
				queue.append(full)
			(incoming[full] as Array).append(key)
	return incoming


## The tiles between two states' cells, across plus up or down.
static func _apart(solver: LevelReachability.Solver, a: int, b: int) -> int:
	var one := (a & ReachSearch.LOW_MASK) >> 1
	var two := (b & ReachSearch.LOW_MASK) >> 1
	return absi(one % solver.cols - two % solver.cols) + absi(one / solver.cols - two / solver.cols)


static func _arrive(solver: LevelReachability.Solver, masked: bool, low: int, mask: int,
		out: Array[int]) -> void:
	if masked:
		ReachSearch.arrive(solver, low, mask, out)
	else:
		out.append(low)
