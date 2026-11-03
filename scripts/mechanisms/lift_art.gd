class_name LiftArt
extends RefCounted
## How a lift is drawn: a stone slab on two chains, the drum the chains run
## over, and the counterweight on the drum's far side, all posed from the
## lift's state and nothing else.
##
## The slab is a course of the same stone as the floor it rests in: a gold cap
## where the sun catches its top, crimson face, the sun-facing left edge lit
## and the right edge in shade, a joint line every tile. At rest at its lower
## stop it is the floor, and should look like it.
##
## Iron is ink, not steel: steel is for blades and spikes and nothing else
## (docs/art-direction.md), so a chain that glinted like a sword would be a
## lie about danger. Each link catches one warm pixel on its lit side.
##
## The counterweight hangs against the landing's wall inside the shaft and
## moves against the slab -- high while the slab is low, low while it is high
## -- so the lift is read as a machine with a weight in it, the same
## vocabulary as the gates' clocks. The drum's spoke turns with the travel.

const CAP := Palette.LIGHT_WARM
const FACE := Palette.SHADOW
const FACE_LIT := Palette.SHADOW_WARM
const FACE_SHADE := Palette.SHADOW_DEEP
const IRON := Palette.INK
const IRON_LIT := Palette.SHADOW_WARM
## Pixels between a chain's lit links.
const LINK := 3.0
## The counterweight's size.
const WEIGHT := Vector2(5.0, 8.0)
const DRUM_R := 3.5


static func draw(lift: Lift) -> void:
	var o := lift.position
	var slab := Rect2(lift.slab_rect().position - o, lift.slab_rect().size)
	var drum := lift.drum - o
	var upper := minf(lift.top_of(Lift.Stop.HOME), lift.top_of(Lift.Stop.FAR)) - o.y
	var lower := maxf(lift.top_of(Lift.Stop.HOME), lift.top_of(Lift.Stop.FAR)) - o.y
	var low := 1.0 if is_equal_approx(lower, upper) else (slab.position.y - upper) / (lower - upper)
	_counterweight(lift, slab, drum, upper, lower, low)
	_chains(lift, slab, drum)
	_drum(lift, drum, slab.position.y)
	if lift.moving or low < 0.99:
		# The slab's own shadow, down and to the right of it: the sun is low
		# on the left, and the mask under it was solved without it.
		lift.draw_rect(Rect2(slab.position.x + 2.0, slab.end.y, slab.size.x, 3.0),
			Palette.with_alpha(Palette.INK, 0.3))
	_slab(lift, slab)


static func _slab(lift: Lift, slab: Rect2) -> void:
	lift.draw_rect(slab, FACE)
	lift.draw_rect(Rect2(slab.position, Vector2(1.0, slab.size.y)), FACE_LIT)
	lift.draw_rect(Rect2(slab.end.x - 1.0, slab.position.y, 1.0, slab.size.y), FACE_SHADE)
	lift.draw_rect(Rect2(slab.position.x, slab.end.y - 1.0, slab.size.x, 1.0), IRON)
	lift.draw_rect(Rect2(slab.position, Vector2(slab.size.x, 2.0)), CAP)
	var x := slab.position.x + Mechanism.TILE
	while x < slab.end.x - 1.0:
		lift.draw_rect(Rect2(x, slab.position.y + 2.0, 1.0, slab.size.y - 3.0), FACE_SHADE)
		x += Mechanism.TILE
	# An iron band across the face, where the chains' rings are fixed.
	lift.draw_rect(Rect2(slab.position.x, slab.position.y + 5.0, slab.size.x, 1.0), FACE_SHADE)
	for ring: Vector2 in _rings(slab):
		lift.draw_rect(Rect2(ring.x - 1.0, ring.y - 1.0, 2.0, 2.0), IRON)


static func _rings(slab: Rect2) -> Array[Vector2]:
	return [slab.position + Vector2(3.0, 0.0), Vector2(slab.end.x - 3.0, slab.position.y)]


static func _chains(lift: Lift, slab: Rect2, drum: Vector2) -> void:
	for ring: Vector2 in _rings(slab):
		var to := drum + Vector2(-DRUM_R * float(lift.drum_side), 0.0) if lift.drum_side != 0 \
			else Vector2(ring.x, drum.y)
		_chain(lift, ring, to)


static func _chain(lift: Lift, from: Vector2, to: Vector2) -> void:
	lift.draw_line(from, to, IRON, 1.0)
	var length := from.distance_to(to)
	var steps := floori(length / LINK)
	for i: int in range(1, steps):
		var at := from.lerp(to, float(i) * LINK / length).floor()
		if i % 2 == 0:
			lift.draw_rect(Rect2(at.x - 1.0, at.y, 1.0, 1.0), IRON_LIT)


## A drum on a short post standing on the landing, or a bracket on the
## ceiling. The spoke turns as the slab travels, a pixel of rim a pixel.
static func _drum(lift: Lift, drum: Vector2, slab_top: float) -> void:
	if lift.drum_side == 0:
		lift.draw_rect(Rect2(drum.x - 4.0, drum.y, 8.0, 2.0), IRON)
		return
	lift.draw_rect(Rect2(drum.x - 1.0, drum.y, 2.0, 6.0), IRON)
	lift.draw_circle(drum, DRUM_R, IRON)
	lift.draw_arc(drum, DRUM_R - 0.5, PI * 0.5, PI * 1.5, 6, IRON_LIT, 1.0)
	var turn := slab_top / DRUM_R
	lift.draw_line(drum, drum + Vector2(cos(turn), sin(turn)) * (DRUM_R - 1.0), IRON_LIT, 1.0)


## Against the landing's wall, inside the shaft: high while the slab is low.
static func _counterweight(lift: Lift, slab: Rect2, drum: Vector2, upper: float,
		lower: float, low: float) -> void:
	var side := lift.drum_side if lift.drum_side != 0 else 1
	var x := slab.end.x - WEIGHT.x - 1.0 if side > 0 else slab.position.x + 1.0
	var y := lerpf(lower + Mechanism.TILE - WEIGHT.y - 1.0, upper + 3.0, low)
	var hang := Vector2(x + WEIGHT.x * 0.5, y)
	var from := Vector2(hang.x, drum.y) if lift.drum_side == 0 \
		else drum + Vector2(-DRUM_R * float(side), 0.0)
	_chain(lift, from, hang)
	var block := Rect2(x, y, WEIGHT.x, WEIGHT.y)
	lift.draw_rect(block, FACE_SHADE)
	lift.draw_rect(Rect2(block.position, Vector2(1.0, block.size.y)), FACE_LIT)
	lift.draw_rect(Rect2(block.position, Vector2(block.size.x, 1.0)), CAP)
	lift.draw_rect(Rect2(block.position.x, block.end.y - 1.0, block.size.x, 1.0), IRON)
