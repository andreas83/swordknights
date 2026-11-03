class_name CrumbleAudit
extends RefCounted
## The proof that crumbling stone can never strand anyone
## (docs/campaign.md, "Crumbling stone", *Reachability*).
##
## A slab is proved by its own reach hook (CrumblingStone.reach()): stone
## until its run is left, then air, with nothing allowed to wait on it. That
## covers every order in which the prince himself can bring runs down, because
## the masked flood walks them all. What it cannot see is a run brought down
## by somebody else -- a Caracal's push-off or landing breaks a slab outright,
## and a body overhanging a slab from the stone beside it lights it too -- so
## the audit plays those, in the style of LevelReachability.audit_secrets():
##
## 1. **The design rule.** Every run is one row, at most three long and no
##    wider than Tuning.gap_tiles(); an end that meets stone meets at least two
##    of it, so with the run gone there is still a gap_tiles() jump from a
##    two-tile runway across it. A run fails with its cell named. (An end in
##    open air -- a stone jutting from a wall face, Chapter III's tower --
##    crosses nothing and is held only by the floods.)
## 2. **Whole.** With every run as authored, the flood reaches the door and
##    no state it reaches is stranded.
## 3. **Broken.** With every subset of runs already fallen -- every subset up
##    to MAX_SUBSETS_FOR runs, past that each alone and all of them together,
##    the secret audit's rule -- the door is still reached, no reachable state
##    is stranded, and every cell that could be stood on with the runs whole
##    either still reaches the door or can no longer be stood on.
##
## The last is the clause about a prince who was somewhere when the floor
## behind him went: he is not where the spawn's flood would put him, so each
## such cell the broken flood does not reach is proved on its own.

const MAX_SUBSETS_FOR := LevelReachability.MAX_SUBSETS_FOR
const KIND := "crumbling"


## `{ok, reason, runs, subsets, states}`. A level without crumbling stone
## passes with nothing to say.
static func audit(level: AsciiLevel) -> Dictionary:
	if level == null:
		return _fail("no level data", 0)
	var runs := runs_of(level)
	if runs.is_empty():
		return {"ok": true, "reason": "no crumbling stone", "runs": 0, "subsets": 0,
			"states": 0}
	var rule := check_runs(level)
	if not rule.is_empty():
		return _fail(rule[0], 0)

	var whole := LevelReachability.survey(level)
	var states := int(whole.get("states", 0))
	if not bool(whole["ok"]):
		return _fail("with every slab whole the exit is out of reach (%s)"
			% String(whole["reason"]), states)
	var stranded: Dictionary = whole.get("stranded_states", {})
	if not stranded.is_empty():
		return _fail("with every slab whole, a state at %s cannot reach the exit"
			% str(LevelReachability._state_cell(level, int(stranded.keys()[0]))), states)

	var subsets := _subsets(runs.size())
	for broken: Array[int] in subsets:
		var played := with_fallen(level, broken)
		var report := LevelReachability.survey(played)
		states += int(report.get("states", 0))
		var which := _names(runs, broken)
		if not bool(report["ok"]):
			return _fail("with %s fallen the exit is out of reach (%s)"
				% [which, String(report["reason"])], states)
		var lost: Dictionary = report.get("stranded_states", {})
		if not lost.is_empty():
			return _fail("with %s fallen, a state at %s cannot reach the exit"
				% [which, str(LevelReachability._state_cell(level, int(lost.keys()[0])))],
				states)
		var reached: Dictionary = report.get("reached", {})
		for cell: Vector2i in whole.get("reached", {}):
			if reached.has(cell) or not _stands(played, cell):
				continue
			if not bool(LevelReachability.verify_from(played, cell)["ok"]):
				return _fail("with %s fallen, standing at %s the exit is gone"
					% [which, str(cell)], states)
	return {"ok": true, "states": states, "runs": runs.size(), "subsets": subsets.size(),
		"reason": "%d run(s), %d fallen subset(s): nothing that falls strands anyone"
			% [runs.size(), subsets.size()]}


## Every crumbling run's mark, in the level's order.
static func runs_of(level: AsciiLevel) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for mark: Dictionary in level.entities:
		if String(mark["kind"]) == KIND:
			out.append(mark)
	return out


## The design rule, run by run: one problem per broken run, its cell named.
static func check_runs(level: AsciiLevel) -> PackedStringArray:
	var out := PackedStringArray()
	var widest := mini(3, Tuning.gap_tiles())
	for mark: Dictionary in runs_of(level):
		var slabs := Mechanism.mark_cells(mark)
		var at: Vector2i = mark["cell"]
		var row := slabs[0].y
		var lo := slabs[0].x
		var hi := slabs[0].x
		var flat := true
		for cell: Vector2i in slabs:
			flat = flat and cell.y == row
			lo = mini(lo, cell.x)
			hi = maxi(hi, cell.x)
		if not flat:
			out.append("the crumbling run at column %d, row %d is not one row" % [at.x, at.y])
			continue
		var length := hi - lo + 1
		if length > widest:
			out.append("the crumbling run at column %d, row %d is %d long: at most %d"
				% [at.x, at.y, length, widest])
			continue
		for end: Array in [[lo - 1, -1], [hi + 1, 1]]:
			var x := int(end[0])
			var step := int(end[1])
			if level.is_solid(x, row) and not level.is_solid(x + step, row):
				out.append("the crumbling run at column %d, row %d ends on one stone at "
					% [at.x, at.y] + "column %d: a runway is two" % x)
	return out


## A copy of `level` with the runs at `indices` (into runs_of()) already
## fallen: their marks say so, and their reach hook makes them air.
static func with_fallen(level: AsciiLevel, indices: Array[int]) -> AsciiLevel:
	var out := level.copy()
	var seen := 0
	for mark: Dictionary in out.entities:
		if String(mark["kind"]) != KIND:
			continue
		if indices.has(seen):
			var params := (mark.get("params", {}) as Dictionary).duplicate()
			params["fallen"] = "1"
			mark["params"] = params
		seen += 1
	return out


static func _stands(level: AsciiLevel, cell: Vector2i) -> bool:
	var solver := LevelReachability.Solver.new(level, ReachModel.for_level(level))
	return solver.is_stand(cell.x, cell.y)


static func _subsets(count: int) -> Array[Array]:
	var out: Array[Array] = []
	if count <= MAX_SUBSETS_FOR:
		for bits: int in range(1, 1 << count):
			var picked: Array[int] = []
			for index: int in count:
				if bits & (1 << index) != 0:
					picked.append(index)
			out.append(picked)
		return out
	var every: Array[int] = []
	for index: int in count:
		out.append([index] as Array[int])
		every.append(index)
	out.append(every)
	return out


static func _names(runs: Array[Dictionary], indices: Array[int]) -> String:
	var parts := PackedStringArray()
	for index: int in indices:
		var at: Vector2i = runs[index]["cell"]
		parts.append("%d,%d" % [at.x, at.y])
	return "the run%s at %s" % ["" if indices.size() == 1 else "s", ", ".join(parts)]


static func _fail(reason: String, states: int) -> Dictionary:
	return {"ok": false, "reason": reason, "runs": 0, "subsets": 0, "states": states}
