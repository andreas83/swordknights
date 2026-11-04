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
##
## HAZARDS ON A CLOCK, AND STONE THAT GOES
## The other strips add three things the grid alone does not say (StripHazards):
## blades that cut on the beat, water that rises on a timer, and slabs that
## fall. The first two are a pure function of the match frame, so the
## prediction asks about them on the frame it is predicting -- `_clock` is the
## frame being decided, set by look() -- and a jump whose arc crosses a slot
## while it is up is as unsafe as one that lands in the moat. Walking is
## planned the same way: a cell ahead is a gap if a blade or the water will be
## in it while the body passes, and the feet stop at its lip and wait for the
## beat, or take the stones. The stones are on the grid itself: look() writes
## the slabs as the view saw them, and a slab that is burning or gone is not
## somewhere to put a foot. doomed() and refuge() are for when the ground
## itself is about to kill a fighter standing still: the brain asks them first.

## How much wider than the body, each side in px, a blade or the water is kept
## from in a prediction.
const SLACK := 3.0
## How far from a wall too tall to hop from a standstill the feet back off to,
## in px, for the run-up that clears it.
const RUN_UP := 10.0
## Frames a landing must stay safe to count as one: a body that lands in a
## slot's lane on the frame before it rises has not landed safely.
const SETTLE := 20
## Frames a body takes to pass a cell, at a run, with slack. A cell a blade
## cuts inside this window of the body's arrival is a gap.
const PASS := 22
## A basin is not walked into if it floods within this many frames of the
## body reaching it: long enough to cross the widest basin and climb out.
const FLOOD_MARGIN := 150

## The frame the next predictions start on, and what the stones looked like.
## Set by look(); both describe the view the brain is deciding on, and both
## are static for the reason the grid cache is: the feet are a set of static
## questions about one strip, asked many times a frame.
static var _clock := 0
static var _stones_seen := PackedByteArray()

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


## Takes the frame and the stones of `view` as the ground the next questions
## are about. The brain calls it first thing every frame it decides.
static func look(view: DuelView) -> void:
	_clock = view.frame
	_kind(view.strip, 0, 0)
	var hazards := view.strip.hazards
	for i: int in hazards.stone_count():
		var byte := view.stones[i] if i < view.stones.size() else 0
		var cell: Vector2i = hazards.stones[i]
		var kind := Tiles.Kind.SOLID if StripHazards.is_whole(byte) else Tiles.Kind.EMPTY
		_grid[cell.y * _grid_cols + cell.x] = kind
	_stones_seen = view.stones


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
		if _deadly(strip, tuning, pos, _clock + f):
			return {"safe": false, "landed": false, "position": pos, "margin": -INF,
				"frames": f}
		if grounded and (f > 0 or not jump):
			var margin := _margin(strip, pos, half)
			var settles := _settles(strip, pos, _clock + f)
			return {"safe": margin >= -half + FOOTHOLD and settles, "landed": true,
				"position": pos, "margin": margin, "frames": f}
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
	if not me.grounded:
		# In the air, standing still is a choice like any other and is only
		# taken if it comes down alive. A brain that wanted no direction --
		# in reach, facing the other -- used to let go of the stick mid-jump
		# and drop short into whatever the jump was over; two of them closing
		# over a flooded court on the Floodgates did it on the same frame.
		var options := [dir, 0, -dir] if dir != 0 else [0, me.facing, -me.facing]
		for option: int in options:
			var arc := leap(strip, tuning, me, option, held > 0, held)
			if bool(arc["safe"]):
				return {"dir": option, "jump": false, "hold": 0}
		return {"dir": dir, "jump": false, "hold": 0}
	if dir == 0:
		return {"dir": 0, "jump": false, "hold": 0}

	var ahead := scan(strip, tuning, me, dir)
	var brink := _at_brink(strip, tuning, me, dir)
	# A cell a blade or the water is about to take is a lip to stop at, like
	# the moat's, until the beat lets the body through.
	if bool(ahead.get("timed", false)):
		brink = brink or float(ahead["distance"]) <= tuning.run_speed * DT * 3.0 + 1.0
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
	var walled := int(ahead["kind"]) == Ahead.WALL and float(ahead["distance"]) < 1.0
	# Face to the stone with no jump that lands on top of it: a chimney two
	# tiles tall is cleared from a run and not from a standstill, so step back
	# for a run-up rather than push at it for the rest of the match.
	var climbs := not best.is_empty() \
		and (best["position"] as Vector2).y < me.position.y - 1.0
	if int(ahead["kind"]) == Ahead.WALL and float(ahead["distance"]) < RUN_UP:
		if not climbs:
			return {"dir": -dir, "jump": false, "hold": 0}
		return {"dir": dir, "jump": true, "hold": int(best["hold"])}
	if best.is_empty():
		return {"dir": 0 if brink else dir, "jump": false, "hold": 0}
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
##
## On the ground a thrust drifts half a tile forward (thrust_drift) and cannot
## stop for the beat, so it is unsafe if a blade or the water takes the place it
## drifts to before it is over.
static func safe_to_commit(strip: ZoneStrip, tuning: DuelTuning, me: DuelView.Body) -> bool:
	if me.grounded:
		var drift := tuning.thrust_drift * DT * float(tuning.thrust_frames)
		var to := me.position + Vector2(float(me.facing) * drift, 0.0)
		return not _timed(strip, tuning, to, _clock, _clock + tuning.thrust_frames)
	return bool(leap(strip, tuning, me, 0, false, 0, true)["safe"])


## Whether anything between `me` and `x`, along the floor, would kill a fighter
## who walked it. The moat or the pit between two fighters is a reason to let
## the other one do the crossing; one inside a roll's length is a reason not to
## roll, since a roll cannot be steered and falls off whatever it reaches.
static func gap_between(strip: ZoneStrip, me: DuelView.Body, x: float) -> bool:
	var tile := float(ZoneStrip.TILE)
	var row := _feet_row(me.position.y)
	var from := floori(minf(me.position.x, x) / tile)
	var to := floori(maxf(me.position.x, x) / tile)
	for column: int in range(from, to + 1):
		if not _stands(_kind(strip, column, row)) and _drop_is_deadly(strip, column, row):
			return true
	# A roll is about a second along the floor, and cannot stop for the beat.
	var span := Rect2(minf(me.position.x, x), me.position.y - 22.0, absf(x - me.position.x),
		22.0)
	return strip.hazards.rect_is_deadly_between(span, _clock, _clock + 40)


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
		if _cell_taken(strip, tuning, column, row, distance):
			return {"kind": Ahead.GAP, "distance": distance, "timed": true}
		column += dir
	return {"kind": Ahead.NOTHING, "distance": INF}


## Whether a blade or the water takes the body's place in `column`, standing on
## `row`, while a runner `distance` px off would be passing through it.
static func _cell_taken(strip: ZoneStrip, tuning: DuelTuning, column: int, row: int,
		distance: float) -> bool:
	var hazards := strip.hazards
	if hazards.blades.is_empty() and hazards.floods.is_empty():
		return false
	var tile := float(ZoneStrip.TILE)
	var body := Rect2(column * tile, row * tile - tuning.body_height, tile, tuning.body_height)
	var arrive := _clock + floori(distance / maxf(1.0, tuning.run_speed * DT))
	var leave := arrive + PASS
	if hazards.in_a_basin(body.grow_individual(0.0, 0.0, 0.0, 2.0 * tile)):
		leave = arrive + FLOOD_MARGIN
	return hazards.rect_is_deadly_between(body, maxi(_clock, arrive - 2), leave)


## --- when the ground itself is the danger ---------------------------------------

## Whether a fighter standing where `me` stands, as it stands, dies within
## `within` frames: a blade about to cut its place, the water about to come
## over it, or a slab under it that is going or gone.
static func doomed(strip: ZoneStrip, tuning: DuelTuning, me: DuelView.Body,
		within: int) -> bool:
	if not me.grounded:
		return false
	if _timed(strip, tuning, me.position, _clock, _clock + within):
		return true
	return _footing(strip, me.position).x == me.position.x and _on_stone(strip, me.position)


## Whether ducking where `me` stands keeps it alive for `within` frames: a
## scythe at head height passes over a ducked fighter.
static func duck_saves(strip: ZoneStrip, tuning: DuelTuning, me: DuelView.Body,
		within: int) -> bool:
	if not me.grounded:
		return false
	# A duck is no answer to the floor going.
	if _footing(strip, me.position).x == me.position.x and _on_stone(strip, me.position):
		return false
	var half := tuning.body_width * 0.5
	var low := Rect2(me.position.x - half, me.position.y - tuning.duck_height,
		half * 2.0, tuning.duck_height)
	return not strip.hazards.rect_is_deadly_between(low, _clock, _clock + within)


## The way out of a doomed place: the direction of the nearer column, within
## a few tiles, where the body stands on something and nothing timed takes it
## for a while after it gets there. 0 if there is none either way.
static func refuge(strip: ZoneStrip, tuning: DuelTuning, me: DuelView.Body) -> int:
	var tile := float(ZoneStrip.TILE)
	var speed := maxf(1.0, tuning.run_speed * DT)
	for reach: int in range(1, 9):
		for dir: int in [me.facing, -me.facing]:
			var x := me.position.x + dir * reach * tile
			var column := floori(x / tile)
			var row := _standing_row(strip, column, _feet_row(me.position.y))
			if row < 0:
				continue
			var feet := Vector2(column * tile + tile * 0.5, row * tile)
			var arrive := _clock + ceili(absf(feet.x - me.position.x) / speed)
			if not _timed(strip, tuning, feet, arrive, arrive + 2 * SETTLE):
				return dir
	return 0


## Where in `column` a body that starts on `row` could stand: that row, or one
## within a hop up or a short drop down. -1 for nowhere.
static func _standing_row(strip: ZoneStrip, column: int, row: int) -> int:
	for y: int in [row, row - 1, row - 2, row + 1, row + 2]:
		if _stands(_kind(strip, column, y)) and not _blocks(_kind(strip, column, y - 1)) \
				and not _blocks(_kind(strip, column, y - 2)):
			return y
	return -1


static func _on_stone(strip: ZoneStrip, feet: Vector2) -> bool:
	var tile := float(ZoneStrip.TILE)
	var row := _feet_row(feet.y)
	return strip.hazards.stone_index(Vector2i(floori(feet.x / tile), row)) >= 0


## --- the grid ---------------------------------------------------------------

static func _feet_row(feet_y: float) -> int:
	return floori((feet_y + 0.5) / ZoneStrip.TILE)


static func _stands(kind: int) -> bool:
	return kind == Tiles.Kind.SOLID or kind == Tiles.Kind.PLATFORM


static func _blocks(kind: int) -> bool:
	return kind == Tiles.Kind.SOLID


## Falling down this column from `row`, does anything catch the feet before a
## hazard or the bottom of the world does? And is what catches them about to
## be under water or a blade -- a dry basin floods, and a body in it has to
## get out first.
static func _drop_is_deadly(strip: ZoneStrip, column: int, row: int) -> bool:
	for y: int in range(row, strip.rows()):
		var kind := _kind(strip, column, y)
		if kind == Tiles.Kind.SPIKES or kind == Tiles.Kind.WATER:
			return true
		if _stands(kind):
			if strip.hazards.blades.is_empty() and strip.hazards.floods.is_empty():
				return false
			var tile := float(ZoneStrip.TILE)
			return not _settles(strip, Vector2(column * tile + tile * 0.5, y * tile), _clock)
	return true


## Whether a fighter whose feet come down at `feet` on frame `frame` may stay a
## while: nothing timed takes it for SETTLE frames, or, in a basin, for long
## enough to walk out of it (FLOOD_MARGIN).
static func _settles(strip: ZoneStrip, feet: Vector2, frame: int) -> bool:
	var body := Rect2(feet.x - 4.5, feet.y - 22.0, 9.0, 22.0)
	var window := SETTLE
	if strip.hazards.in_a_basin(body.grow_individual(0.0, 0.0, 0.0, 2.0)):
		window = FLOOD_MARGIN
	return not strip.hazards.rect_is_deadly_between(body, frame, frame + window)


static func _hits_solid(strip: ZoneStrip, tuning: DuelTuning, feet: Vector2) -> bool:
	var half := tuning.body_width * 0.5
	return _body_touches(strip, feet, half, tuning.body_height - 0.5, SOLID_MASK)


static func _deadly(strip: ZoneStrip, tuning: DuelTuning, feet: Vector2, frame: int) -> bool:
	if feet.y > strip.world_size().y:
		return true
	var half := tuning.body_width * 0.5
	if _body_touches(strip, feet, half, tuning.body_height, DEADLY_MASK):
		return true
	# Wider than the body by SLACK each side, two frames either way: the arc is
	# the grid's prediction and the flight is the physics engine's, and a slot
	# missed by a pixel in the prediction is a slot landed in.
	var body := Rect2(feet.x - half - SLACK, feet.y - tuning.body_height,
		half * 2.0 + SLACK * 2.0, tuning.body_height)
	return strip.hazards.rect_is_deadly_between(body, frame - 2, frame + 2)


## Whether a standing body at `feet` is cut or drowned on any frame in [from, to].
static func _timed(strip: ZoneStrip, tuning: DuelTuning, feet: Vector2, from: int,
		to: int) -> bool:
	var half := tuning.body_width * 0.5
	var body := Rect2(feet.x - half - SLACK, feet.y - tuning.body_height,
		half * 2.0 + SLACK * 2.0, tuning.body_height)
	return strip.hazards.rect_is_deadly_between(body, from, to)


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
		# Every slab whole until look() says otherwise.
		for cell: Vector2i in strip.hazards.stones:
			_grid[cell.y * _grid_cols + cell.x] = Tiles.Kind.SOLID
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
