class_name ReachRace
extends RefCounted
## The race against a held gate, for the reachability proof: the one timed
## move the proof makes (docs/campaign.md, "Counterweights", Reachability 3).
##
## A plate on a `hold` wire opens its gate while it is stood on and for so
## many seconds after the last foot leaves. Without a clock the proof could
## only call that gate shut, and a level built on races -- Chapter II is --
## could not be proved at all. So standing on a race plate is one more move:
## from there, a search with the gate open, charged in frames, finds every
## place the prince can reach before the hold runs out, and each of those is
## offered as an arrival like any arc's landing. The gate is shut again in
## the state he arrives in, so nothing behind it is claimed after the race.
##
## ## The clock and the slack
##
## The hold counts from the last foot leaving the plate (ChannelBus), and the
## gate is already up by then -- he can wait on the plate as long as it takes
## to rise -- so the race is the run from stepping off to arriving. It must
## fit in SLACK of the hold: 25% spare, because a thumb on a phone does not
## hold a perfect run. A race with less slack is not a route at all.
##
## ## Frames from the primitives' own counts
##
## The proof's moves are the character's own arithmetic stepped frame by
## frame (LevelReachability._trace), so an arc costs exactly the frames it was
## stepped for -- the solver says which frame it was on when it offered a
## landing (`arc_frame`). Moves that are not arcs cost what the player's code
## makes them cost: a tile at a run, a rung at ladder speed, a grab's hang and
## mantle on top of the arc that reached it, and the few frames a standing
## start takes to reach a run. Nothing here is a second derivation of a jump:
## the timed solver is the proof's solver, with each offer weighed.
##
## ## What it does not do
##
## It sets no bit. A checkpoint is proved from every mask the prince can
## stand on it under, and that is sound because every bit is a latch
## (ReachSearch); a race leaves the masks exactly as it found them. Nor does
## it look into the route measure for `;! checkpoints route` (ReachRoute),
## which floods with the plain expansion: a level that needs both would
## extend that flood the same way.

## The share of a hold a race may use.
const SLACK := 0.75
## A tile at a run, in frames: Tuning.RUN_SPEED over Tuning.TILE.
const RUN_TILE := Tuning.TILE / Tuning.RUN_SPEED * 60.0
## A cell crawled, in frames (Tuning.CRAWL_SPEED, ReachCrawl): twice a walk's.
const CRAWL_TILE := Tuning.TILE / Tuning.CRAWL_SPEED * 60.0
## A rung, in frames.
const RUNG := Tuning.TILE / Tuning.LADDER_SPEED * 60.0
## A ledge grab's hang and mantle, on top of the arc that caught the ledge.
const GRAB := (Tuning.HANG_HOLD_TIME + Tuning.CLIMB_UP_TIME) * 60.0
## Off a ladder sideways: half a tile at the ladder's half walk speed.
const LADDER_OFF := Tuning.TILE * 0.5 / (Tuning.WALK_SPEED * 0.5) * 60.0
## The frames a standing start loses reaching a run: half the time
## Tuning.GROUND_ACCEL takes to get there.
const START := Tuning.RUN_SPEED / Tuning.GROUND_ACCEL * 60.0 * 0.5

const MASK_SHIFT := LevelReachability.Solver.MASK_SHIFT
const LOW_MASK := LevelReachability.Solver.LOW_MASK


## The proof's solver, with every offer weighed in frames: `costs[i]` is the
## frames the move to `out[i]` took. Built over the same level and model.
class Timed extends LevelReachability.Solver:
	var costs: Array[float] = []
	var _from_ladder := false
	var _grabbing := false

	func _init(level: AsciiLevel, model: ReachModel) -> void:
		super(level, model)

	func expand(low: int, out: Array[int]) -> void:
		costs.clear()
		arc_frame = -1
		_from_ladder = low & 1 == LevelReachability.MODE_LADDER
		super.expand(low, out)

	func _offer_stand(x: int, y: int, out: Array[int]) -> void:
		var before := out.size()
		super._offer_stand(x, y, out)
		if out.size() > before:
			costs.append(_cost(true))

	func _offer_ladder(x: int, y: int, out: Array[int]) -> void:
		var before := out.size()
		super._offer_ladder(x, y, out)
		if out.size() > before:
			costs.append(_cost(false))

	func _probe_ledge(cx: float, feet: float, dir: int, out: Array[int]) -> void:
		_grabbing = true
		super._probe_ledge(cx, feet, dir, out)
		_grabbing = false

	func _cost(standing: bool) -> float:
		if arc_frame >= 0:
			return float(arc_frame + 1) + (GRAB if _grabbing else 0.0)
		if crawl_tiles > 0:
			return float(crawl_tiles) * CRAWL_TILE
		if _from_ladder:
			return LADDER_OFF if standing else RUNG
		return RUN_TILE if standing else 1.0


## Standing on a race plate is a move to every place the race reaches: appends
## the cell keys to `out`, after the ordinary moves from the full state `key`.
## Called by ReachSearch for every state it expands.
static func extend(solver: LevelReachability.Solver, key: int, out: Array[int]) -> void:
	var model := solver.model()
	if model == null or not model.has_races():
		return
	var low := key & LOW_MASK
	if low & 1 != LevelReachability.MODE_STAND:
		return
	var cell := Vector2i((low >> 1) % solver.cols, (low >> 1) / solver.cols)
	var mask := key >> MASK_SHIFT
	for channel: StringName in model.races_at(cell):
		for arrival: int in arrivals(model, cell, mask, channel):
			if not out.has(arrival):
				out.append(arrival)
	solver.use_mask(mask)


## The cell keys the race from `plate` on `channel` reaches inside its slack,
## under `mask`, that are somewhere to be once the gate is down again.
static func arrivals(model: ReachModel, plate: Vector2i, mask: int,
		channel: StringName) -> Array[int]:
	var memo := _memo(model, "arrivals")
	var name := "%s|%d|%s" % [plate, mask, channel]
	if memo.has(name):
		return memo[name]
	var out: Array[int] = []
	var timed := timed_solver(model)
	var frames := run(timed, plate, mask | _bit(model, channel), budget(model, channel))
	timed.use_mask(mask)
	for low: int in frames:
		var at := Vector2i((low >> 1) % timed.cols, (low >> 1) / timed.cols)
		if low & 1 == LevelReachability.MODE_STAND and timed.is_stand(at.x, at.y):
			out.append(low)
		elif low & 1 == LevelReachability.MODE_LADDER and timed.is_ladder(at.x, at.y):
			out.append(low)
	memo[name] = out
	return out


## The frames a race on `channel` may take: SLACK of its hold.
static func budget(model: ReachModel, channel: StringName) -> float:
	return float(model.hold_frames(channel)) * SLACK


## Fastest frames to every state reachable from standing in `start` under
## `mask` within `limit` frames: cell key -> frames. Dijkstra over the timed
## solver's moves, in whole-frame buckets.
static func run(timed: Timed, start: Vector2i, mask: int, limit: float) -> Dictionary:
	timed.use_mask(mask)
	var first := timed.cell_key(LevelReachability.MODE_STAND, start.x, start.y)
	var best := {first: 0.0}
	var buckets: Array[Array] = [[first]]
	var at := 0
	var neighbours: Array[int] = []
	while at < buckets.size():
		var bucket: Array = buckets[at]
		var index := 0
		while index < bucket.size():
			var key: int = bucket[index]
			index += 1
			var spent := float(best[key])
			if floori(spent) != at:
				continue
			timed.use_mask(mask)
			timed.expand(key, neighbours)
			var costs := timed.costs.duplicate()
			for i: int in neighbours.size():
				var step: float = costs[i] if i < costs.size() else RUN_TILE
				if key == first:
					step += START
				var total := spent + step
				if total > limit:
					continue
				var next: int = neighbours[i]
				if best.has(next) and float(best[next]) <= total:
					continue
				best[next] = total
				var slot := floori(total)
				while buckets.size() <= slot:
					buckets.append([])
				buckets[slot].append(next)
		at += 1
	best.erase(first)
	return best


## The solver ReachRace times moves with, one per model.
static func timed_solver(model: ReachModel) -> Timed:
	if not model.extras.has("race_solver"):
		model.extras["race_solver"] = Timed.new(model.level, model)
	return model.extras["race_solver"]


## --- measuring a level's races ----------------------------------------------------

## Every race in `level`, measured: for each plate on a held wire, and each
## mask the prince can stand on it under, the fastest run from it to the far
## side of the wire's gate, against the hold. `{channel, plate, mask, hold,
## frames, budget, ok}`, frames INF when the far side is out of reach
## altogether. The proof needs only `ok`; the numbers are what a designer
## tunes a hold against.
static func measure(level: AsciiLevel) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var model := ReachModel.for_level(level)
	if not model.has_races():
		return out
	var solver := LevelReachability.Solver.new(level, model)
	var plates := model.race_cells()
	var flood := ReachSearch.standing_masks(solver, level.spawn_point, plates)
	var claims: Dictionary = flood.get("masks", {})
	for plate: Vector2i in plates:
		var masks: Array = claims.get(plate, [0])
		for channel: StringName in model.races_at(plate):
			for mask: int in masks:
				out.append(_measure_one(model, plate, mask, channel))
	return out


static func _measure_one(model: ReachModel, plate: Vector2i, mask: int,
		channel: StringName) -> Dictionary:
	var timed := timed_solver(model)
	var gate := model.switched_cells(channel)
	var hold := model.hold_frames(channel)
	var fastest := INF
	if not gate.is_empty():
		var first := gate[0].x
		var last := gate[0].x
		for cell: Vector2i in gate:
			first = mini(first, cell.x)
			last = maxi(last, cell.x)
		var forward := plate.x < first
		var frames := run(timed, plate, mask | _bit(model, channel), float(hold))
		timed.use_mask(mask)
		for low: int in frames:
			var at := Vector2i((low >> 1) % timed.cols, (low >> 1) / timed.cols)
			var beyond := at.x > last if forward else at.x < first
			if beyond and low & 1 == LevelReachability.MODE_STAND and timed.is_stand(at.x, at.y):
				fastest = minf(fastest, float(frames[low]))
	return {
		"channel": channel, "plate": plate, "mask": mask, "hold": hold,
		"frames": fastest, "budget": float(hold) * SLACK,
		"ok": fastest <= float(hold) * SLACK,
	}


static func _bit(model: ReachModel, channel: StringName) -> int:
	var index := model.bit(channel)
	return 0 if index < 0 else 1 << index


static func _memo(model: ReachModel, name: String) -> Dictionary:
	if not model.extras.has(name):
		model.extras[name] = {}
	return model.extras[name]
