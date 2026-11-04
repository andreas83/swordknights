class_name SunLight
extends RefCounted
## Where the light goes: the low sun on the mirrors, and the beams they throw,
## traced over the level's grid (docs/campaign.md, "Sun mirrors and
## sun-seals").
##
## ## One tracer, three readers
##
## The game asks it every frame what is lit (SunMirror, SunSeal, the
## Glassbearer's glass); the art asks it where to draw; the proof asks it
## what a setting of the mirrors would light (scripts/levels/sun_proof.gd).
## All three go through `network()`, so a beam the player sees is exactly a
## beam the proof traced: there is no second idea of where light goes to
## drift from the first. That is why it is pure -- cells, directions and two
## callables in, a plain dictionary out -- and why it knows nothing about
## nodes.
##
## ## The grid is the beam
##
## A beam leaves a mirror's cell along a row or a column and steps one cell at
## a time, so a level author reads every beam straight off the ASCII: a
## mirror facing east in row 31 lights row 31 until something stops it.
## Nothing is ray-marched, nothing is a float, and the same level gives the
## same beams on every device on every frame. What stops a beam is what the
## bible lists -- stone, a one-way platform, a shut seal (stone, as far as the
## grid is concerned), the edge of the level -- and what does not is
## everything else: ladders, spikes, water, backdrop, bodies. A beam that
## enters another mirror's cell ends there, and that mirror is lit.
##
## ## The sun on a mirror
##
## Whether the sun reaches a mirror is the caller's question, not this
## file's: the game reads the dressed shadow mask, the proof reads the bare
## terrain, and a test holds the two to the same answer for every mirror in
## every state of the doors (tests/unit/test_mirrors.gd). What both share is
## `sun_lane()`: the cells between a pivot and the sun, back along the (2, 1)
## lane the shadow solve casts on, as far as the shadow reaches. A shut door
## in that lane is stone in the light's way even though the static mask --
## solved once, before any door moved -- never saw it.

## A mirror's four faces, in the order a quarter turn clockwise visits them.
enum Face { UP, RIGHT, DOWN, LEFT }

const TILE := 16
## What a beam ended on.
const ENDS_STONE := "stone"
const ENDS_MIRROR := "mirror"
const ENDS_SKY := "sky"
const ENDS_EDGE := "edge"


## The cell step for `face`.
static func step_of(face: int) -> Vector2i:
	match face:
		Face.UP:
			return Vector2i.UP
		Face.RIGHT:
			return Vector2i.RIGHT
		Face.DOWN:
			return Vector2i.DOWN
		_:
			return Vector2i.LEFT


## The face after one strike: a quarter turn clockwise.
static func turned(face: int) -> int:
	return (face + 1) % 4


## A mirror's pivot -- its disc's centre, where its beam starts -- in world
## pixels: the middle of its cell.
static func pivot(cell: Vector2i) -> Vector2:
	return Vector2(cell) * float(TILE) + Vector2(TILE, TILE) * 0.5


## One beam from `from`, leaving along `face`. `blocks` is `(cell) -> bool`,
## true for a cell that stops light; `mirrors` holds every mirror's cell as a
## key. Returns `{cells: Array[Vector2i] (every cell the light crosses, the
## end excluded), end: Vector2i, ends: String}`.
static func trace(from: Vector2i, face: int, cols: int, rows: int, blocks: Callable,
		mirrors: Dictionary) -> Dictionary:
	var step := step_of(face)
	var cells: Array[Vector2i] = []
	var at := from + step
	# A beam crosses the level at most once in either direction, so this
	# bound is never what ends it; it only keeps a malformed call finite.
	for _i: int in cols + rows + 2:
		if at.y < 0:
			return {"cells": cells, "end": at, "ends": ENDS_SKY}
		if at.x < 0 or at.x >= cols or at.y >= rows:
			return {"cells": cells, "end": at, "ends": ENDS_EDGE}
		if mirrors.has(at):
			return {"cells": cells, "end": at, "ends": ENDS_MIRROR}
		if bool(blocks.call(at)):
			return {"cells": cells, "end": at, "ends": ENDS_STONE}
		cells.append(at)
		at += step
	return {"cells": cells, "end": at, "ends": ENDS_EDGE}


## The whole of the light in one state of the level.
##
## `mirrors` maps each mirror's cell to `{face: int, turning: bool, sun: bool}`
## -- `sun` is whether the sun itself reaches its pivot now. A lit mirror that
## is not mid-turn throws a beam; a beam into another mirror lights it; a lit
## mirror is traced once, so two mirrors facing each other do not loop. The
## order is reading order, so the result is the same whatever order the
## mirrors were handed in.
##
## Returns `{lit: {cell: true}, beams: Array[{from, face, cells, end, ends}],
## struck: {cell: true}}` -- `struck` being every stone cell a beam ends on,
## which is how a seal knows the light is resting on it.
static func network(mirrors: Dictionary, cols: int, rows: int,
		blocks: Callable) -> Dictionary:
	var order: Array = mirrors.keys()
	order.sort_custom(reading_order)
	var lit := {}
	var queue: Array[Vector2i] = []
	for cell: Vector2i in order:
		if bool((mirrors[cell] as Dictionary).get("sun", false)):
			lit[cell] = true
			queue.append(cell)
	var beams: Array[Dictionary] = []
	var struck := {}
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		var mirror: Dictionary = mirrors[cell]
		if bool(mirror.get("turning", false)):
			continue
		var face := int(mirror.get("face", Face.UP))
		var beam := trace(cell, face, cols, rows, blocks, mirrors)
		beam["from"] = cell
		beam["face"] = face
		beams.append(beam)
		var end: Vector2i = beam["end"]
		match String(beam["ends"]):
			ENDS_MIRROR:
				if not lit.has(end):
					lit[end] = true
					queue.append(end)
			ENDS_STONE:
				struck[end] = true
	return {"lit": lit, "beams": beams, "struck": struck}


## Every cell some beam in `light` (a network() result) crosses or ends in.
static func lit_cells(light: Dictionary) -> Dictionary:
	var out := {}
	for beam: Dictionary in light["beams"]:
		for cell: Vector2i in beam["cells"]:
			out[cell] = true
	return out


## The cells between `at` (world pixels) and the sun: back along the shadow
## solve's lane -- RUN across for every RISE up -- for as many lane steps as
## a shadow reaches at this hour. Anything that casts in one of these cells
## puts `at` in shade; nothing outside them can.
static func sun_lane(at: Vector2, reach_tiles: float) -> Array[Vector2i]:
	var steps := int(reach_tiles * float(TILE) / float(SunShadow.RUN))
	var seen := {}
	var out: Array[Vector2i] = []
	var px := Vector2i(floori(at.x), floori(at.y))
	for k: int in range(1, steps + 1):
		var p := px - Vector2i(SunShadow.RUN, SunShadow.RISE) * k
		var cell := Vector2i(floori(float(p.x) / TILE), floori(float(p.y) / TILE))
		if not seen.has(cell):
			seen[cell] = true
			out.append(cell)
	return out


static func reading_order(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)
