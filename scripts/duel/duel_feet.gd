class_name DuelFeet
extends RefCounted
## Where the computer opponent's feet may go: the moat, the spike pit and the
## benches, answered on the level's grid.
##
## The brain decides where it wants to be; this decides whether getting there
## means a jump, and when, and refuses a step or a jump that ends in the water.
## Everything the brain does -- running home, leapfrogging a respawn, dodging a
## throw, backing off -- goes through steer() or safe_jump(), so no plan of the
## brain's can walk it into a hazard by forgetting to look.
##
## WHY A PREDICTED ARC AND NOT A LOOK-UP TABLE OF "JUMP N PIXELS BEFORE A GAP".
## The strip has three kinds of hazard and they want three different jumps: the
## moat is cleared in one leap, the spike pit only by landing on its stepping
## stone first, and a bench by going up rather than over. A table keyed on gap
## width would need a row per set piece and would be wrong the day a zone
## changed. Instead leap() integrates the fighter's own motion -- the same
## acceleration, gravity, jump cut and terminal speed from DuelTuning, in the
## same order Fighter.simulate() applies them -- against the same tiles the
## referee kills on, and reports where the feet come down. A jump is taken when
## that landing is safe and well onto its footing; failing that, the last frame
## a safe one exists; failing that, the feet stop at the lip. The prediction is
## the grid's, not the physics engine's, so it can be a pixel out at a corner,
## which is why a landing has to clear the edge by a margin, and why the brain
## keeps steering in the air when the margin turns out thin.
## tests/unit/test_duel_cpu_feet.gd runs the real fighter at every hazard on the
## strip from both sides and holds it to crossing alive.

const DT := DuelRules.DT
## Frames a predicted leap may last before it is called a fall into nothing.
const HORIZON := 60
## How far ahead of the body a hazard is looked for, in px. A running jump is
## about 42 px; this is enough to choose the frame, and no more.
const LOOK := 60.0
## A full jump is held this long; leap() predicts it by default.
const HOLD := 14
## The jumps steer() chooses between: the full one and two hops, because a
## bench wants going up more than going over.
const HOPS: Array[int] = [HOLD, 8, 4]
## How far a landing should be from the edge of its footing, at best, in px.
const GOOD_MARGIN := 10.0
## How much of the body has to come down on the footing for a landing to count.
## The real body stands on a single pixel of corner, but a one-way platform's
## corner does not reliably catch a body falling past it at eight pixels a
## frame, and the stepping stone over the spikes is nothing but corners.
const FOOTHOLD := 3.0
## How far from the feet a corner is looked for, in px: half the body less the
## FOOTHOLD that has to be on it.
const EDGE_REACH := 1.5

enum Ahead { NOTHING, GAP, WALL }

const SOLID_MASK := 1 << Tiles.Kind.SOLID
const DEADLY_MASK := (1 << Tiles.Kind.SPIKES) | (1 << Tiles.Kind.WATER)


## The strip's kinds as one flat array, built once per strip: leap() asks for
## a few thousand cells a call, and the strip answers each through two
## function calls and a zone lookup. The grid never changes during a match --
## it is the level -- so a copy is the same answer, faster.
static var _grid_of: ZoneStrip = null
static var _grid := PackedByteArray()
static var _grid_cols := 0
static var _grid_rows := 0


## Where a jump (or, with `jump` false, a step) from `me` lands if `dir` is held.
## Returns { safe, landed, position, margin, frames }: `safe` is landed and
## alive; `margin` is how far the feet are from the edge of what they land on,
## less half the body, in px. With `coast`, nothing steers at all: the arc of a
## fighter who has committed to a thrust or a throw in the air.
static func leap(strip: ZoneStrip, tuning: DuelTuning, me: DuelView.Body, dir: int,
		jump: bool, hold: int = HOLD, coast: bool = false) -> Dictionary:
	var pos := me.position
	var vel := me.velocity
	var grounded := me.grounded
	var half := tuning.body_width * 0.5
	for f: int in HORIZON:
		var pressed := jump and f < hold
		if jump and f == 0 and grounded:
			vel.y = -tuning.jump_speed
			grounded = false
		var accel := tuning.ground_accel if grounded else tuning.air_accel
		var friction := tuning.ground_friction if grounded else tuning.air_friction
		if coast:
			pass
		elif dir != 0:
			vel.x = move_toward(vel.x, dir * tuning.run_speed, accel * DT)
		else:
			vel.x = move_toward(vel.x, 0.0, friction * DT)
		if vel.y < 0.0 and not pressed:
			vel.y *= tuning.jump_cut
		vel.y = minf(vel.y + tuning.gravity * DT, tuning.max_fall_speed)

		var x := pos.x + vel.x * DT
		if _hits_solid(strip, tuning, Vector2(x, pos.y)):
			vel.x = 0.0
		else:
			pos.x = x
		var y := pos.y + vel.y * DT
		grounded = false
		if vel.y > 0.0:
			var top := _floor_crossed(strip, pos.x, half, pos.y, y)
			if top >= 0.0:
				y = top
				vel.y = 0.0
				grounded = true
		elif _hits_solid(strip, tuning, Vector2(pos.x, y)):
			y = pos.y
			vel.y = 0.0
		pos.y = y
		if _deadly(strip, tuning, pos):
			return {"safe": false, "landed": false, "position": pos, "margin": -INF,
				"frames": f}
		if grounded and (f > 0 or not jump):
			var margin := _margin(strip, pos, half)
			return {"safe": margin >= -half + FOOTHOLD, "landed": true, "position": pos,
				"margin": margin, "frames": f}
	return {"safe": false, "landed": false, "position": pos, "margin": -INF,
		"frames": HORIZON}


## The input that moves `me` in `dir` without dying of it: { dir, jump, hold }.
## `hold` is how many frames to keep jump down, when `jump` is true.
##
## In the air it only steers, toward whichever of on, stop or back lands safe;
## `held` is how many more frames the brain will hold the jump it is in. On the
## ground it looks LOOK px ahead; with nothing there it runs. With a gap or a
## wall there it tries a full jump and two shorter hops, and takes the best of
## them on the first frame it lands safely with a good margin (or as good as
## the footing allows); at the lip, or with its face against a wall, it takes
## any safe one; and at the lip with none, it stops. `slop` frames of
## deliberate error make an easy opponent's timing human: it waits until
## waiting `slop` frames more would leave no safe jump, never past the lip.
static func steer(strip: ZoneStrip, tuning: DuelTuning, me: DuelView.Body, dir: int,
		held: int = 0, slop: int = 0) -> Dictionary:
	if dir == 0:
		return {"dir": 0, "jump": false, "hold": 0}
	if not me.grounded:
		for option: int in [dir, 0, -dir]:
			var arc := leap(strip, tuning, me, option, held > 0, held)
			if bool(arc["safe"]):
				return {"dir": option, "jump": false, "hold": 0}
		return {"dir": dir, "jump": false, "hold": 0}

	var ahead := scan(strip, tuning, me, dir)
	var brink := _at_brink(strip, tuning, me, dir)
	if int(ahead["kind"]) == Ahead.NOTHING and not brink:
		return {"dir": dir, "jump": false, "hold": 0}

	var best := {}
	for hold: int in HOPS:
		var arc := leap(strip, tuning, me, dir, true, hold)
		if not (bool(arc["safe"]) and _progressed(me, arc, dir)):
			continue
		if best.is_empty() or float(arc["margin"]) > float(best["margin"]):
			best = arc
			best["hold"] = hold
	var jump := {"dir": dir, "jump": true, "hold": int(best.get("hold", HOLD))}
	if best.is_empty():
		return {"dir": 0 if brink else dir, "jump": false, "hold": 0}
	var walled := int(ahead["kind"]) == Ahead.WALL and float(ahead["distance"]) < 1.0
	if brink or walled:
		return jump
	if slop <= 0 and float(best["margin"]) >= _wanted_margin(strip, best):
		return jump
	if slop > 0 and _late_enough(strip, tuning, me, dir, slop):
		return jump
	return {"dir": dir, "jump": false, "hold": 0}


## Whether a jump now, held `hold` frames with `dir` held, lands alive.
static func safe_jump(strip: ZoneStrip, tuning: DuelTuning, me: DuelView.Body,
		dir: int, hold: int = HOLD) -> bool:
	return bool(leap(strip, tuning, me, dir, true, hold)["safe"])


## Whether a commitment started now, in the air, comes down alive: a thrust or
## a throw takes the steering away until it is over.
static func safe_to_commit(strip: ZoneStrip, tuning: DuelTuning, me: DuelView.Body) -> bool:
	if me.grounded:
		return true
	return bool(leap(strip, tuning, me, 0, false, 0, true)["safe"])


## Whether anything between `me` and `x`, along the floor, would kill a fighter
## who walked it: the moat or the pit between two fighters is a reason to let
## the other one do the crossing.
static func gap_between(strip: ZoneStrip, me: DuelView.Body, x: float) -> bool:
	var tile := float(ZoneStrip.TILE)
	var row := _feet_row(me.position.y)
	var from := floori(minf(me.position.x, x) / tile)
	var to := floori(maxf(me.position.x, x) / tile)
	for column: int in range(from, to + 1):
		if not _stands(_kind(strip, column, row)) and _drop_is_deadly(strip, column, row):
			return true
	return false


## Whether holding `dir` for the next few frames keeps the feet on something.
static func safe_step(strip: ZoneStrip, tuning: DuelTuning, me: DuelView.Body,
		dir: int) -> bool:
	return not _at_brink(strip, tuning, me, dir)


## The first thing within LOOK px in `dir` that running would not survive or
## could not pass: { kind: Ahead, distance }.
static func scan(strip: ZoneStrip, tuning: DuelTuning, me: DuelView.Body,
		dir: int) -> Dictionary:
	var half := tuning.body_width * 0.5
	var tile := float(ZoneStrip.TILE)
	var row := _feet_row(me.position.y)
	var front := me.position.x + dir * half
	var column := floori(front / tile)
	var limit := front + dir * LOOK
	while (column * tile - limit) * dir <= 0.0:
		var near := column * tile if dir > 0 else (column + 1) * tile
		var distance := maxf(0.0, (near - front) * dir)
		if _blocks(_kind(strip, column, row - 1)):
			return {"kind": Ahead.WALL, "distance": distance}
		if not _stands(_kind(strip, column, row)) and _drop_is_deadly(strip, column, row):
			return {"kind": Ahead.GAP, "distance": distance}
		column += dir
	return {"kind": Ahead.NOTHING, "distance": INF}


## --- the grid ---------------------------------------------------------------

static func _feet_row(feet_y: float) -> int:
	return floori((feet_y + 0.5) / ZoneStrip.TILE)


static func _stands(kind: int) -> bool:
	return kind == Tiles.Kind.SOLID or kind == Tiles.Kind.PLATFORM


static func _blocks(kind: int) -> bool:
	return kind == Tiles.Kind.SOLID


## Falling down this column from `row`, does anything catch the feet before a
## hazard or the bottom of the world does?
static func _drop_is_deadly(strip: ZoneStrip, column: int, row: int) -> bool:
	for y: int in range(row, strip.rows()):
		var kind := _kind(strip, column, y)
		if kind == Tiles.Kind.SPIKES or kind == Tiles.Kind.WATER:
			return true
		if _stands(kind):
			return false
	return true


static func _hits_solid(strip: ZoneStrip, tuning: DuelTuning, feet: Vector2) -> bool:
	var half := tuning.body_width * 0.5
	return _body_touches(strip, feet, half, tuning.body_height - 0.5, SOLID_MASK)


static func _deadly(strip: ZoneStrip, tuning: DuelTuning, feet: Vector2) -> bool:
	if feet.y > strip.world_size().y:
		return true
	var half := tuning.body_width * 0.5
	return _body_touches(strip, feet, half, tuning.body_height, DEADLY_MASK)


## Whether a body `half` wide each side and `height` tall, feet at `feet`,
## overlaps a tile whose kind is in `mask`. The same cells, by the same
## rounding, as ZoneStrip.rect_has_kind -- which is what the referee asks.
static func _body_touches(strip: ZoneStrip, feet: Vector2, half: float, height: float,
		mask: int) -> bool:
	var tile := float(ZoneStrip.TILE)
	var x0 := floori((feet.x - half) / tile)
	var x1 := floori((feet.x + half - 0.001) / tile)
	var y0 := floori((feet.y - height) / tile)
	var y1 := floori((feet.y - 0.001) / tile)
	for y: int in range(y0, y1 + 1):
		for x: int in range(x0, x1 + 1):
			if (1 << _kind(strip, x, y)) & mask != 0:
				return true
	return false



static func _kind(strip: ZoneStrip, x: int, y: int) -> int:
	if strip != _grid_of:
		_grid_of = strip
		_grid_cols = strip.cols()
		_grid_rows = strip.rows()
		_grid.resize(_grid_cols * _grid_rows)
		for row: int in _grid_rows:
			for column: int in _grid_cols:
				_grid[row * _grid_cols + column] = int(strip.kind_at(column, row))
	if y < 0 or y >= _grid_rows:
		return Tiles.Kind.EMPTY
	if x < 0 or x >= _grid_cols:
		return Tiles.Kind.SOLID
	return _grid[y * _grid_cols + x]


## The top of the first tile the feet pass through on the way from `from_y`
## down to `to_y` that they could stand on, or -1. A one-way platform counts
## only from above, which is the only way feet going down can meet it.
static func _floor_crossed(strip: ZoneStrip, x: float, half: float, from_y: float,
		to_y: float) -> float:
	var tile := float(ZoneStrip.TILE)
	var first := ceili((from_y - 0.001) / tile)
	var last := floori(to_y / tile)
	var x0 := floori((x - half + 0.01) / tile)
	var x1 := floori((x + half - 0.01) / tile)
	for row: int in range(first, last + 1):
		for column: int in range(x0, x1 + 1):
			if _stands(_kind(strip, column, row)):
				return row * tile
	return -1.0


## How far the feet at `pos` are from the nearer edge of the footing they stand
## on, less half the body: positive is that much to spare, negative is hanging.
static func _margin(strip: ZoneStrip, pos: Vector2, half: float) -> float:
	var span := _footing(strip, pos)
	return minf(pos.x - span.x, span.y - pos.x) - half


## The [left, right] x of the unbroken run of footing under `pos`: from the
## column under the feet if it stands, otherwise the one under the body's edge
## that does -- a fighter landing on a corner stands on that corner.
static func _footing(strip: ZoneStrip, pos: Vector2) -> Vector2:
	var tile := float(ZoneStrip.TILE)
	var row := _feet_row(pos.y)
	var column := floori(pos.x / tile)
	if not _stands(_kind(strip, column, row)):
		var found := false
		for k: float in [-EDGE_REACH, EDGE_REACH]:
			var edge := floori((pos.x + k) / tile)
			if _stands(_kind(strip, edge, row)):
				column = edge
				found = true
				break
		if not found:
			# Nothing under the body but a sliver: no footing to speak of.
			return Vector2(pos.x, pos.x)
	var left := column
	var right := column
	while left > column - 8 and _stands(_kind(strip, left - 1, row)):
		left -= 1
	while right < column + 8 and _stands(_kind(strip, right + 1, row)):
		right += 1
	return Vector2(left * tile, (right + 1) * tile)


## A good margin, or as good as this footing can give: a stepping stone one
## tile wide cannot be landed on ten pixels from its edge.
static func _wanted_margin(strip: ZoneStrip, arc: Dictionary) -> float:
	var at: Vector2 = arc["position"]
	var span := _footing(strip, at)
	var best := (span.y - span.x) * 0.5 - 4.5
	return minf(GOOD_MARGIN, best * 0.6)


static func _progressed(me: DuelView.Body, arc: Dictionary, dir: int) -> bool:
	var at: Vector2 = arc["position"]
	return (at.x - me.position.x) * dir > ZoneStrip.TILE * 0.5


## Whether the next two frames of running would put the whole body past the
## edge of its footing, over something deadly. Two, because stopping from a
## run takes three frames and covers two pixels.
static func _at_brink(strip: ZoneStrip, tuning: DuelTuning, me: DuelView.Body,
		dir: int) -> bool:
	if not me.grounded:
		return false
	var half := tuning.body_width * 0.5
	var speed := maxf(absf(me.velocity.x), tuning.run_speed * 0.5)
	var ahead := Vector2(me.position.x + dir * speed * DT * 3.0, me.position.y)
	if _floor_crossed(strip, ahead.x, half, ahead.y - 1.0, ahead.y + 1.0) >= 0.0:
		return false
	var row := _feet_row(me.position.y)
	var tile := float(ZoneStrip.TILE)
	var column := floori((ahead.x - dir * half) / tile)
	return _drop_is_deadly(strip, column, row)


## The deliberately late jump: taken once waiting `slop` more frames would
## leave no safe jump at all, rather than on the first good frame.
static func _late_enough(strip: ZoneStrip, tuning: DuelTuning, me: DuelView.Body,
		dir: int, slop: int) -> bool:
	var later := DuelView.Body.new()
	later.position = me.position + Vector2(dir * tuning.run_speed * DT * slop, 0.0)
	later.velocity = Vector2(dir * tuning.run_speed, 0.0)
	later.grounded = true
	var arc := leap(strip, tuning, later, dir, true)
	return not (bool(arc["safe"]) and _progressed(later, arc, dir))
