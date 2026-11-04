class_name BeatProof
extends RefCounted
## The timing proof for blades on the beat: every crossing of every blade
## leaves a window to set off in, and every run of blades can be run.
##
## The reachability search leaves a blade out, as it leaves out a sentinel's
## cut -- a blade is air between its cuts, and the search has no clock. What
## it cannot say, this does (docs/campaign.md, "Blades on the beat"):
##
## 1. **Every blade fits its period.** Its tell, its cut and its recovery fit
##    in the 100 frames between cuts, with the LONGER WARNINGS assist on as
##    well as off -- the tell widens into the rest and must not reach back
##    into the last cut.
## 2. **Every blade has a window.** Crossed at a run (or, in a ladder shaft,
##    at the ladder's speed), the moments a body can set off and meet no live
##    frame span at least the parry's window, `Tuning.PARRY_ACTIVE` -- twelve
##    frames: no execution window in the game is narrower. A scythe's is 74,
##    two slots' 42, exactly the bible's numbers, because the crossing is
##    measured with the body's own width and the blade's own cells.
## 3. **Every run of blades keeps the races' slack.** Blades within RUN_GAP of
##    one another on one floor are one rhythm. Run straight through without
##    stopping, the moments to set off from must span at least SLACK of the
##    period -- a quarter, the same 25% a gate's race keeps -- in either
##    direction, so a thumb that is a little early or late still makes it.
## 4. **Every ride has its dance.** A blade in a lift's shaft is not crossed
##    at a time the prince chooses: the lift carries him through it (the
##    throat, docs/campaign.md "The set piece"). So the question changes. The
##    blade must sweep only part of the slab, leaving a safe half; its tell
##    must cover a step across to that half with the races' slack (one tile
##    at a run, 11 frames, inside three quarters of the 27); and for every
##    moment the lift could set off, two cuts the rider meets from opposite
##    walls must come at least NO_TWO_ANSWERS frames apart -- the bible's
##    rule that no two threats ask for different answers inside 20 frames.
##
## It finds the blades through their reach hooks (BeatBlade.reach() files
## them with ReachModel.note()), and reads every number -- live frames, the
## recovery, the danger rectangle, the tell -- from the blade scripts
## themselves, so the proof measures what play does.
##
## A blade on a wire that is not a beat, or on a period other than the
## music's two beats, is a problem: it would keep time with nothing.

const PERIOD := BeatBlade.PERIOD
## Blades closer than this, in tiles, along one floor are one run: at a run it
## is 65 frames, inside one period, so their rhythms are one rhythm.
const RUN_GAP := 6
## A run's straight-through window, as a share of the period.
const SLACK := 0.25
## The least time between two threats that need different answers
## (docs/campaign.md, "Accessible on touch").
const NO_TWO_ANSWERS := 20.0
## The resolution the windows are measured at, in frames.
const STEP := 0.25


## Proves `level`'s blades. `{ok, problems, blades, runs}`: each blade
## `{kind, cells, phase, live, way, crossing, window}`, each run `{blades,
## east, west}` (windows, in frames, setting off each way).
static func prove(level: AsciiLevel) -> Dictionary:
	var problems := PackedStringArray()
	var blades: Array[Dictionary] = []
	var model := ReachModel.for_level(level)
	for note: Dictionary in model.notes(&"beat"):
		var blade := _blade(level, note, problems)
		if not blade.is_empty():
			blades.append(blade)
	var rides := _rides(level, blades, problems)
	var runs := _runs(blades.filter(func(b: Dictionary) -> bool: return b["way"] != "ride"))
	for run: Dictionary in runs:
		var need := SLACK * float(PERIOD)
		for way: String in ["east", "west"]:
			if float(run[way]) < need:
				problems.append("the run of %d blades from column %d keeps %.1f frames heading %s:"
					% [(run["blades"] as Array).size(), _first_column(run), float(run[way]), way]
					+ " less than %d%% of the beat's period" % roundi(SLACK * 100.0))
	return {"ok": problems.is_empty() and not blades.is_empty(), "problems": problems,
		"blades": blades, "runs": runs, "rides": rides}


## One blade, measured; empty when it cannot be.
static func _blade(level: AsciiLevel, note: Dictionary, problems: PackedStringArray) -> Dictionary:
	var kind := String(note["kind"])
	var cells: Array[Vector2i] = []
	cells.assign(note["cells"])
	var at := cells[cells.size() - 1]
	var named := "the %s at column %d, row %d" % [kind, at.x, at.y]
	var script := EntityRegistry.script_for(kind)
	var spec := level.channels.get(String(note["channel"]), {}) as Dictionary
	if String(spec.get("mode", "")) != "beat":
		problems.append("%s is on wire '%s', which is not a beat" % [named, note["channel"]])
		return {}
	if int(spec.get("period", PERIOD)) != PERIOD:
		problems.append("%s keeps a period of %d frames, not the music's %d"
			% [named, int(spec["period"]), PERIOD])
		return {}
	var live := int(script.call(&"live_frames"))
	var recover := int(script.call(&"recover_frames"))
	for scale: float in [1.0, Assist.LONGER]:
		var tell := roundi(BeatBlade.TELL * scale / BeatBlade.FRAME)
		if tell + live + recover > PERIOD:
			problems.append("%s: a %d-frame tell, its cut and its recovery overrun the period"
				% [named, tell])
	var rect := BeatBlade.danger_rect(cells)
	var way := _way(level, cells)
	var crossing := _crossing(rect, way)
	var window := float(PERIOD - live) - crossing
	if way == "ride":
		# Carried through it: the window is the tell, less the step across.
		var tell := BeatBlade.TELL / BeatBlade.FRAME
		window = tell - crossing
		if crossing > (1.0 - SLACK) * tell:
			problems.append("%s: stepping clear takes %.1f frames of its %d-frame tell"
				% [named, crossing, roundi(tell)])
	if window < Tuning.PARRY_ACTIVE / BeatBlade.FRAME:
		problems.append("%s leaves %.1f frames to set off in, under the parry's %d"
			% [named, window, roundi(Tuning.PARRY_ACTIVE / BeatBlade.FRAME)])
	return {
		"kind": kind, "cells": cells, "rect": rect, "phase": int(spec.get("phase", 0)),
		"live": live, "way": way, "crossing": crossing, "window": window,
	}


## How a body crosses `cells`: "run" along the floor under them, "ladder"
## down a shaft whose ladder runs through them, or "ride" on a lift whose
## shaft they are cut into.
static func _way(level: AsciiLevel, cells: Array[Vector2i]) -> String:
	if not _lift_of(level, cells).is_empty():
		return "ride"
	return "ladder" if Scythe.in_ladder(cells, level) else "run"


## The lift whose shaft holds every one of `cells`: `{home, far, first, last}`
## (Lift.geometry()), or empty.
static func _lift_of(level: AsciiLevel, cells: Array[Vector2i]) -> Dictionary:
	for mark: Dictionary in level.entities:
		if String(mark["kind"]) != "lift":
			continue
		var shape := Lift.geometry(Mechanism.mark_cells(mark), mark.get("glyphs", {}))
		var top := mini(int(shape["home"]), int(shape["far"]))
		var bottom := maxi(int(shape["home"]), int(shape["far"]))
		var inside := true
		for cell: Vector2i in cells:
			if cell.x < int(shape["first"]) or cell.x > int(shape["last"]) \
					or cell.y <= top or cell.y >= bottom:
				inside = false
		if inside:
			return shape
	return {}


## Frames a body is in `rect` crossing it `way`: its own width (or height)
## plus the blade's, at the speed that way goes.
static func _crossing(rect: Rect2, way: String) -> float:
	if way == "ride":
		return Tuning.TILE / Tuning.RUN_SPEED / BeatBlade.FRAME
	if way == "ladder":
		return (rect.size.y + Tuning.BODY_HEIGHT) / Tuning.LADDER_SPEED / BeatBlade.FRAME
	return (rect.size.x + Tuning.BODY_WIDTH) / Tuning.RUN_SPEED / BeatBlade.FRAME


## Blades crossed the same way along the same line, close enough to be one
## rhythm, with their straight-through windows both ways.
static func _runs(blades: Array[Dictionary]) -> Array[Dictionary]:
	var lines := {}
	for blade: Dictionary in blades:
		var rect: Rect2 = blade["rect"]
		var key := "%s %d" % [blade["way"], roundi(rect.end.y if blade["way"] == "run"
			else rect.position.x)]
		if not lines.has(key):
			lines[key] = [] as Array[Dictionary]
		(lines[key] as Array[Dictionary]).append(blade)
	var runs: Array[Dictionary] = []
	for key: String in lines:
		var line: Array[Dictionary] = lines[key]
		var vertical := key.begins_with("ladder")
		line.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return _along(a, vertical) < _along(b, vertical))
		var run: Array[Dictionary] = []
		for blade: Dictionary in line:
			if not run.is_empty() and _gap(run[run.size() - 1], blade, vertical) > RUN_GAP * 16.0:
				_close(run, vertical, runs)
				run = []
			run.append(blade)
		_close(run, vertical, runs)
	return runs


static func _close(run: Array[Dictionary], vertical: bool, runs: Array[Dictionary]) -> void:
	if run.size() < 2:
		return
	runs.append({
		"blades": run.duplicate(),
		"east": straight_through(run, vertical, 1),
		"west": straight_through(run, vertical, -1),
	})


static func _along(blade: Dictionary, vertical: bool) -> float:
	var rect: Rect2 = blade["rect"]
	return rect.position.y if vertical else rect.position.x


static func _gap(a: Dictionary, b: Dictionary, vertical: bool) -> float:
	var one: Rect2 = a["rect"]
	var two: Rect2 = b["rect"]
	return two.position.y - one.end.y if vertical else two.position.x - one.end.x


static func _first_column(run: Dictionary) -> int:
	var first: Dictionary = (run["blades"] as Array)[0]
	return (first["cells"] as Array[Vector2i])[0].x


## Every lift with blades in its shaft, proved as a ride: `{blades, gap}`,
## the least time, over every moment the lift could set off, between the end
## of one cut the rider meets and the start of the next from the other wall.
static func _rides(level: AsciiLevel, blades: Array[Dictionary],
		problems: PackedStringArray) -> Array[Dictionary]:
	var by_lift := {}
	for blade: Dictionary in blades:
		if blade["way"] != "ride":
			continue
		var shape := _lift_of(level, blade["cells"])
		var key := "%d,%d" % [int(shape["first"]), int(shape["home"])]
		if not by_lift.has(key):
			by_lift[key] = {"shape": shape, "blades": [] as Array[Dictionary]}
		(by_lift[key]["blades"] as Array[Dictionary]).append(blade)
		var columns := {}
		for cell: Vector2i in blade["cells"]:
			columns[cell.x] = true
		if columns.size() >= int(shape["last"]) - int(shape["first"]) + 1:
			problems.append("the %s at column %d sweeps the whole slab: there is no safe half"
				% [blade["kind"], (blade["cells"] as Array[Vector2i])[0].x])
	var out: Array[Dictionary] = []
	for key: String in by_lift:
		var ride: Dictionary = by_lift[key]
		var gap := ride_gap(ride["shape"], ride["blades"])
		var need := maxf(NO_TWO_ANSWERS, _crossing(Rect2(), "ride") / (1.0 - SLACK))
		if gap < need:
			problems.append("the lift at column %d brings two cuts from opposite walls %.1f"
				% [int((ride["shape"] as Dictionary)["first"]), gap]
				+ " frames apart, under %.1f" % need)
		out.append({"blades": ride["blades"], "gap": gap})
	return out


## The least gap, in frames, between the end of a cut a rider meets and the
## start of the next one from the other wall, over every moment in the beat's
## period the lift could set off. INF when no two such cuts can meet him.
static func ride_gap(shape: Dictionary, blades: Array[Dictionary]) -> float:
	var home_top := float(int(shape["home"])) * Tuning.TILE
	var heading := 1.0 if int(shape["far"]) > int(shape["home"]) else -1.0
	var speed := Lift.SPEED * BeatBlade.FRAME
	var least := INF
	var samples := roundi(float(PERIOD) / STEP)
	for i: int in samples:
		var depart := float(i) * STEP
		var cuts: Array[Vector2] = []
		for blade: Dictionary in blades:
			var rect: Rect2 = blade["rect"]
			# The slab's top while the rider's body overlaps the blade's cells.
			var enter := rect.position.y if heading > 0.0 else rect.end.y + Tuning.BODY_HEIGHT
			var leave := rect.end.y + Tuning.BODY_HEIGHT if heading > 0.0 else rect.position.y
			var from := depart + absf(enter - home_top) / speed
			var to := depart + absf(leave - home_top) / speed
			var side := float((blade["cells"] as Array[Vector2i])[0].x)
			var phase := int(blade["phase"])
			var k := ceili((from - float(phase)) / float(PERIOD))
			while float(k * PERIOD + phase) < to:
				cuts.append(Vector2(float(k * PERIOD + phase), side))
				k += 1
		cuts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		for j: int in range(1, cuts.size()):
			if cuts[j].y != cuts[j - 1].y:
				least = minf(least, cuts[j].x - cuts[j - 1].x - float(Scythe.LIVE))
	return least


## The longest span of moments, in frames, a body can set off across all of
## `run` without stopping -- east (or down) with `heading` 1, west (or up)
## with -1 -- and meet no blade live: a circle of PERIOD frames, sampled at
## STEP.
static func straight_through(run: Array[Dictionary], vertical: bool, heading: int) -> float:
	var speed := (Tuning.LADDER_SPEED if vertical else Tuning.RUN_SPEED) * BeatBlade.FRAME
	var size := Tuning.BODY_HEIGHT if vertical else Tuning.BODY_WIDTH
	# Where the body's leading edge starts: just short of the first blade met.
	var start := INF if heading > 0 else -INF
	for blade: Dictionary in run:
		var rect: Rect2 = blade["rect"]
		var near := rect.position.y if vertical else rect.position.x
		var far := rect.end.y if vertical else rect.end.x
		start = minf(start, near) if heading > 0 else maxf(start, far)
	var samples := roundi(float(PERIOD) / STEP)
	var good: Array[bool] = []
	good.resize(samples)
	for i: int in samples:
		good[i] = _clear(run, vertical, heading, start, float(i) * STEP, speed, size)
	return _longest(good) * STEP


## Whether setting off at `depart` (frames into the period) meets every blade
## of `run` while it is not live.
static func _clear(run: Array[Dictionary], vertical: bool, heading: int, start: float,
		depart: float, speed: float, size: float) -> bool:
	for blade: Dictionary in run:
		var rect: Rect2 = blade["rect"]
		var near := rect.position.y if vertical else rect.position.x
		var far := rect.end.y if vertical else rect.end.x
		# Frames until the body's leading edge reaches the blade, and until
		# its trailing edge has left it.
		var enter := (near - start) / speed if heading > 0 else (start - far) / speed
		var leave := enter + (far - near + size) / speed
		if _meets_live(depart + enter, depart + leave, int(blade["phase"]), int(blade["live"])):
			return false
	return true


## Whether the span of frames [from, to) overlaps a live stretch of a blade
## cutting at `phase` for `live` frames every PERIOD.
static func _meets_live(from: float, to: float, phase: int, live: int) -> bool:
	var first := floori((from - float(phase) - float(live)) / float(PERIOD))
	var last := floori((to - float(phase)) / float(PERIOD))
	for k: int in range(first, last + 1):
		var cut := float(k * PERIOD + phase)
		if from < cut + float(live) and to > cut:
			return true
	return false


## The longest run of true values round a circle.
static func _longest(good: Array[bool]) -> int:
	var count := good.size()
	if not good.has(false):
		return count
	var best := 0
	var current := 0
	for i: int in count * 2:
		if good[i % count]:
			current += 1
			best = maxi(best, mini(current, count))
		else:
			current = 0
	return best
