class_name GoreField
extends Node2D
## Where everybody died, in their own colour, for the rest of the match.
##
## A BOUNDED LIST, NOT A RENDER TARGET
## The specification asks for stains baked into the wall and floor textures.
## The engineering note in docs/duel-spec.md argues that down, and this is the
## shape it argues for: a bounded list of decals per zone — a position, a
## colour, four points — drawn in one pass beneath the actors. Five zones of
## 192 decals is about fifty kilobytes and no VRAM at all, against tens of
## megabytes for a render target covering the strip, on a phone, on the GL
## compatibility renderer, holding nothing but splatter. It survives a zone
## being streamed out and back, because it is not in the tilemap.
##
## PRESENTATION, AND NOWHERE NEAR THE SNAPSHOT
## Nothing in this file is simulation. It is fed by one signal out of
## scripts/duel/match.gd and it never calls back in; the match's checksum does
## not know it exists. tests/match_gore_test.gd asserts exactly that, because a
## presentation field that found its way into the snapshot would make the
## splatter pattern a thing two peers could diverge over, and a desync detector
## that fires on a blood spot is a desync detector nobody will believe.
##
## The shapes are still the same on both screens, which is nicer than it needs
## to be and costs nothing: the little RNG is seeded from the frame, the seat
## and the place of death, all of which both peers already agree about.
##
## CRIMSON AND TEAL
## Seat one bleeds crimson and seat two bleeds teal, the same two colours
## scripts/duel/duel_art.gd dresses them in. After a few exchanges the floor is
## a record of who died where — which is the point of keeping it.

## Decals per zone. Far more than a match produces: six per kill is thirty-two
## kills in one zone before the oldest stain is dropped.
const MAX_PER_ZONE := 192
const SPLATS_PER_KILL := 6

## How far a splat is thrown, and how far it then runs down a wall or drips to
## the floor, in pixels.
const THROW := 34.0
const FALL := 72.0
const PROBE := 4.0

## Seat colours. The deep one is the stain, the bright one the fresh edge.
const BLOOD: Array[Color] = [Palette.CLOTH_DARK, Palette.WATER_DEEP]
const BLOOD_FRESH: Array[Color] = [Palette.CLOTH, Palette.WATER]

var strip: ZoneStrip

## Which zones to draw. Set by the scene from the authoritative window, so the
## decals of four zones nobody can see are not submitted every frame.
var visible_zones := PackedInt32Array([0])

## zone index -> Array of { at, points, colour }
var _zones: Array[Array] = []
var _drawn_for := PackedInt32Array()


func setup(zones: ZoneStrip) -> void:
	strip = zones
	clear()


func clear() -> void:
	_zones.clear()
	for i: int in (strip.zone_count() if strip != null else 0):
		_zones.append([])
	queue_redraw()


## One kill's worth of blood, in the dead fighter's colour.
##
## `at` is where they died and `slot` is who they were. `seed_from` is the
## simulation frame, which is what makes two peers draw the same stains without
## the shapes ever being part of the state.
func spill(at: Vector2, slot: int, seed_from: int) -> void:
	if strip == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3(float(seed_from), float(slot), snappedf(at.x, 0.25)))

	for i: int in SPLATS_PER_KILL:
		var angle := rng.randf_range(-PI, 0.0) # thrown up and out, not down
		var thrown := at + Vector2.RIGHT.rotated(angle) * rng.randf_range(6.0, THROW)
		var landed := _settle(thrown)
		_add(landed, _splat(rng, landed, slot))

	# One wide pool where the body fell, which is what actually reads at this
	# size; the thrown splats are the texture around it.
	var pool := _settle(at + Vector2(0.0, -2.0))
	_add(pool, _pool(rng, pool, slot))
	queue_redraw()


## Walks a splat out of the air: against a wall if it meets one, otherwise down
## to the floor. A stain that hung in mid-air would read as a bug.
func _settle(from: Vector2) -> Vector2:
	var at := from
	var steps := int(FALL / PROBE)
	for i: int in steps:
		var next := at + Vector2(0.0, PROBE)
		if strip.rect_hits_solid(Rect2(next.x - 1.0, next.y - 1.0, 2.0, 2.0)):
			return at
		at = next
	return at


func _splat(rng: RandomNumberGenerator, at: Vector2, slot: int) -> Dictionary:
	var width := rng.randf_range(2.5, 7.0)
	var height := rng.randf_range(1.2, 3.0)
	var lean := rng.randf_range(-1.6, 1.6)
	return {
		"at": at,
		"colour": BLOOD[slot] if rng.randf() < 0.72 else BLOOD_FRESH[slot],
		"points": PackedVector2Array([
			at + Vector2(-width, 0.0),
			at + Vector2(lean - width * 0.4, -height),
			at + Vector2(width, -height * 0.35),
			at + Vector2(width * 0.5, height * 0.4),
		]),
	}


func _pool(rng: RandomNumberGenerator, at: Vector2, slot: int) -> Dictionary:
	var width := rng.randf_range(9.0, 15.0)
	return {
		"at": at,
		"colour": BLOOD[slot],
		"points": PackedVector2Array([
			at + Vector2(-width, 0.0),
			at + Vector2(-width * 0.55, -2.4),
			at + Vector2(width * 0.6, -1.8),
			at + Vector2(width, 0.6),
			at + Vector2(0.0, 2.2),
		]),
	}


func _add(at: Vector2, decal: Dictionary) -> void:
	var zone := strip.zone_of_x(at.x)
	if zone < 0 or zone >= _zones.size():
		return
	var list: Array = _zones[zone]
	list.append(decal)
	# The bound, enforced where it is cheapest: oldest stain out, newest in.
	while list.size() > MAX_PER_ZONE:
		list.remove_at(0)


## --- what the test asks ----------------------------------------------------

func count_in(zone: int) -> int:
	if zone < 0 or zone >= _zones.size():
		return 0
	return (_zones[zone] as Array).size()


func total() -> int:
	var sum := 0
	for list: Array in _zones:
		sum += list.size()
	return sum


## --- drawing ---------------------------------------------------------------

## Decals never move, so this does not redraw every frame — only when blood is
## spilled, when the field is cleared, or when a different set of zones comes
## into view.
func show_zones(zones: PackedInt32Array) -> void:
	if zones == _drawn_for:
		return
	visible_zones = zones
	_drawn_for = zones
	queue_redraw()


func _draw() -> void:
	for zone: int in visible_zones:
		if zone < 0 or zone >= _zones.size():
			continue
		for decal: Dictionary in _zones[zone]:
			draw_colored_polygon(decal["points"], decal["colour"])
