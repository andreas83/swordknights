class_name GoreField
extends Node2D
## Where everybody died, in their own colour, for the rest of the match.
##
## A BOUNDED LIST, NOT A RENDER TARGET
## The specification asks for stains baked into the wall and floor textures.
## The engineering note in docs/duel-spec.md argues that down, and this is the
## shape it argues for: bounded lists of decals per zone -- a position, a
## colour, a few points or a few rects -- drawn in one pass beneath the actors.
## Five zones at the bound are well under a hundred kilobytes and no VRAM at
## all, against tens of megabytes for a render target covering the strip, on a
## phone, on the GL compatibility renderer, holding nothing but splatter. It
## survives a zone being streamed out and back, because it is not in the
## tilemap.
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
## A KILL READS AS A KILL
## The first version threw six splats and laid one pool, and on a phone a death
## read as a smudge. A kill is now three things, in this order:
##
## - A SPURT. Three pulses of droplets out of the wound, eight frames apart and
##   each weaker than the last, thrown the way the blow travelled (`blow`, the
##   side the killer struck from) and up, a few spattering back the other way.
##   A hazard, which has no blow, sends them up and to both sides. Each droplet
##   flies a real arc against the tiles, landing on a floor or a platform or
##   sticking to a wall and running a few pixels down it; one that reaches
##   water is gone.
## - A STREAK along the floor in the direction of the blow, from under the
##   body, as far as the floor runs flat.
## - A POOL under the body that spreads for a second and a half, wet -- a
##   fresh-coloured sheen on its sunward side -- for four seconds, then dark
##   for the rest of the match.
##
## Everything is in the seat's two tones (scripts/duel/fighter_art.gd), hard
## edged, and drawn on the texel grid: droplets and their stains are whole-
## pixel rects, because a 22 px fighter's blood is a pixel or two, and a
## smooth droplet at that size would be the one soft thing on the screen. No
## gradient, no glow, nothing additive: docs/art-direction.md keeps its
## restraint everywhere but here, and here the excess is in quantity, not in
## technique.
##
## THE CLOCK IS THE MATCH'S, SO A CORRECTION NEVER RE-SPILLS
## The spurt is not a particle system with state of its own. Every droplet is
## a pure function of its death's frame and the match frame the scene hands to
## tick(): its arc, where it lands and when are worked out once, at spill(),
## and what is drawn is "this many frames since the death". So a death a
## correction moves two frames later carries on from the right age instead of
## spurting again; a kill a correction found late is shown mid-flight, at the
## age the host says it is; and wipe(), which takes back a kill the host never
## had, takes its droplets out of the air as well as off the floor. With no
## clock (a test, or a field nobody ticks) everything is drawn landed.
##
## A STAIN CAN BE TAKEN BACK
## An online client spills on its own prediction, and the host may then say the
## kill never happened, or happened two frames later a pixel to the left. Each
## decal remembers which death it belongs to -- the seat and the frame, which
## identify a death because a fighter is down for two seconds between deaths --
## and wipe() takes that death's blood off the floor. The match decides when
## (DuelMatch.death_retracted); this only does it. Blood for a death that did
## not happen would be a record that lies, and the floor is a record.
##
## THE BOUND, ON A PHONE
## Two lists per zone. Pools and streaks are the marks that say "someone died
## here", MAX_MARKS a zone; droplet stains are texture, MAX_DROPS a zone. They
## are bounded apart so a busy zone sheds its oldest droplets and keeps its
## pools: the record lasts, the spray around it thins. Only zones in view are
## drawn; the field redraws every frame only while a death is younger than its
## spurt and its pool, and otherwise when something changes.
##
## CRIMSON AND TEAL
## Seat one bleeds crimson and seat two bleeds teal, the same two colours
## scripts/duel/fighter_art.gd dresses them in. After a few exchanges the floor is
## a record of who died where -- which is the point of keeping it.

## Per zone. A kill is two marks and DROPS_PER_KILL droplets, so the bounds hold
## twenty-four kills' worth of pools and seventeen kills' worth of spray in
## one zone before the oldest goes -- more than a match produces.
const MAX_MARKS := 48
const MAX_DROPS := 384
const MAX_PER_ZONE := MAX_MARKS + MAX_DROPS

## The spurt: droplets in each pulse, the frame each pulse leaves the wound,
## and how hard it is thrown, in px/s at full strength.
const PULSES: Array[int] = [12, 8, 5]
const PULSE_FRAMES: Array[int] = [0, 8, 16]
const PULSE_STRENGTH: Array[float] = [1.0, 0.72, 0.48]
const DROPS_PER_KILL := 25
const SPEED_MIN := 70.0
const SPEED_MAX := 210.0
## Of each pulse, how many go back the other way: the spatter off the far side.
const BACKSPRAY := 2
## Blood falls slower than a duellist, so its arc reads, but not floatily.
const GRAVITY := 560.0
## Longest a droplet is followed before it is let go, in frames.
const FLIGHT_FRAMES := 90
## Where on the body the wound is: above the feet, in pixels.
const WOUND := 12.0

## The pool: how wide, how long it spreads, how long it stays wet.
const POOL_MIN := 13.0
const POOL_MAX := 19.0
const POOL_FRAMES := 90
const WET_FRAMES := 240
## The streak along the floor, from under the body, in the blow's direction.
const STREAK_MIN := 14.0
const STREAK_MAX := 28.0

## How far a mark is walked down to a floor.
const FALL := 72.0

## Seat colours. The deep one is the stain, the bright one the fresh edge.
const BLOOD: Array[Color] = [Palette.CLOTH_DARK, Palette.WATER_DEEP]
const BLOOD_FRESH: Array[Color] = [Palette.CLOTH, Palette.WATER]

var strip: ZoneStrip

## Which zones to draw. Set by the scene from the camera, so the decals of four
## zones nobody can see are not submitted every frame.
var visible_zones := PackedInt32Array([0])

## zone index -> Array of mark decals { kind, at, points, colour, death }
var _marks: Array[Array] = []
## zone index -> Array of droplet decals; see _droplet()
var _drops: Array[Array] = []
var _drawn_for := PackedInt32Array()
## The match frame now, or -1 with no clock: everything drawn as settled.
var _now := -1
## While the clock is before this frame, something is still moving.
var _moving_until := -1


func setup(zones: ZoneStrip) -> void:
	strip = zones
	clear()


func clear() -> void:
	_marks.clear()
	_drops.clear()
	for i: int in (strip.zone_count() if strip != null else 0):
		_marks.append([])
		_drops.append([])
	_moving_until = -1
	queue_redraw()


## The match frame now. The scene calls it every physics frame; the spurt and
## the pool are drawn at their age against it.
func tick(frame: int) -> void:
	var was := _now
	_now = frame
	if frame != was and (frame < _moving_until or was < _moving_until):
		queue_redraw()


## One kill's worth of blood, in the dead fighter's colour.
##
## `at` is where they died and `slot` is who they were. `seed_from` is the
## simulation frame, which is what makes two peers draw the same stains without
## the shapes ever being part of the state, and what the spurt's age is counted
## from. `blow` is the way the killing blow travelled: +1 east, -1 west, 0 for
## a hazard.
func spill(at: Vector2, slot: int, seed_from: int, blow: int = 0) -> void:
	if strip == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector4(float(seed_from), float(slot), snappedf(at.x, 0.25), float(blow)))
	var death := Vector2i(seed_from, slot)
	var side := signi(blow)

	var floor_at := _settle(at + Vector2(0.0, -2.0))
	floor_at.y = roundf(floor_at.y)
	_add_mark(_pool(rng, floor_at, slot, death))
	if side != 0:
		var streak := _streak(rng, floor_at, side, slot, death)
		if not streak.is_empty():
			_add_mark(streak)

	for pulse: int in PULSES.size():
		var wound := at + Vector2(float(side) * 2.0, -WOUND + pulse * 3.0)
		for i: int in PULSES[pulse]:
			var back := i < BACKSPRAY and side != 0
			var velocity := _throw(rng, side, back) * PULSE_STRENGTH[pulse]
			var drop := _droplet(rng, wound, velocity, PULSE_FRAMES[pulse], slot, death)
			_add_drop(drop)
	_moving_until = maxi(_moving_until, seed_from + maxi(POOL_FRAMES,
		PULSE_FRAMES[PULSE_FRAMES.size() - 1] + FLIGHT_FRAMES) + 1)
	queue_redraw()


## Takes back the blood of the death `spill(_, slot, seed_from)` drew, in the
## air and on the floor. Returns how many decals came off; none if that death
## had no blood here.
func wipe(slot: int, seed_from: int) -> int:
	var death := Vector2i(seed_from, slot)
	var removed := 0
	for lists: Array[Array] in [_marks, _drops]:
		for list: Array in lists:
			for i: int in range(list.size() - 1, -1, -1):
				if (list[i] as Dictionary).get("death") == death:
					list.remove_at(i)
					removed += 1
	if removed > 0:
		queue_redraw()
	return removed


## --- the shapes ------------------------------------------------------------

## A droplet's launch: the blow's way and up, or back the other way low, or for
## a hazard straight up and to either side. In px/s.
func _throw(rng: RandomNumberGenerator, side: int, back: bool) -> Vector2:
	var speed := rng.randf_range(SPEED_MIN, SPEED_MAX)
	var rise := rng.randf_range(deg_to_rad(12.0), deg_to_rad(68.0))
	var way := float(side)
	if side == 0:
		rise = rng.randf_range(deg_to_rad(45.0), deg_to_rad(86.0))
		way = -1.0 if rng.randf() < 0.5 else 1.0
	elif back:
		way = -way
		speed *= 0.45
		rise = rng.randf_range(deg_to_rad(30.0), deg_to_rad(75.0))
	return Vector2(cos(rise) * way, -sin(rise)) * speed


## Flies one droplet against the tiles, once, and keeps where and when it came
## down. The arc is what tick() draws it along; the landing is its stain.
func _droplet(rng: RandomNumberGenerator, from: Vector2, velocity: Vector2, leaves: int,
		slot: int, death: Vector2i) -> Dictionary:
	var dt := 1.0 / 60.0
	var at := from
	var speed := velocity
	var landed := ""
	var frames := FLIGHT_FRAMES
	for step: int in FLIGHT_FRAMES:
		var next := at + speed * dt
		speed.y += GRAVITY * dt
		var kind := _kind_at(next)
		if kind == Tiles.Kind.WATER:
			frames = step
			break
		if kind == Tiles.Kind.SOLID:
			landed = "wall" if _kind_at(Vector2(next.x, at.y)) == Tiles.Kind.SOLID else "floor"
			frames = step
			break
		if kind == Tiles.Kind.PLATFORM and speed.y > 0.0 \
				and floori(at.y / ZoneStrip.TILE) < floori(next.y / ZoneStrip.TILE):
			at = Vector2(next.x, floorf(next.y / ZoneStrip.TILE) * ZoneStrip.TILE)
			landed = "floor"
			frames = step
			break
		at = next
	var fresh := rng.randf() < 0.4
	return {
		"at": at,
		"from": from,
		"velocity": velocity,
		"leaves": leaves,
		"flight": frames,
		"rects": _stain(rng, at, velocity, landed),
		"colour": BLOOD_FRESH[slot] if fresh else BLOOD[slot],
		"flying": BLOOD_FRESH[slot],
		"death": death,
	}


## A landed droplet's mark, in whole pixels: a flat splat on a floor, longer the
## faster it came in sideways; on a wall, a blob and a run down from it.
func _stain(rng: RandomNumberGenerator, at: Vector2, velocity: Vector2,
		landed: String) -> Array[Rect2]:
	var x := roundf(at.x)
	var y := roundf(at.y)
	match landed:
		"floor":
			var wide := clampf(roundf(1.0 + absf(velocity.x) / 70.0 + rng.randf() * 1.5),
				1.0, 4.0)
			var left := x - floorf(wide * 0.5)
			if absf(velocity.x) > 40.0:
				left = x - wide if velocity.x < 0.0 else x - 1.0
			return [Rect2(left, y - 1.0, wide, 1.0)]
		"wall":
			var run := roundf(rng.randf_range(2.0, 7.0))
			var face := x if velocity.x < 0.0 else x - 1.0
			return [
				Rect2(face, y - 1.0, 1.0, 2.0),
				Rect2(face, y + 1.0, 1.0, run),
			]
		_:
			return []


func _pool(rng: RandomNumberGenerator, at: Vector2, slot: int, death: Vector2i) -> Dictionary:
	var width := rng.randf_range(POOL_MIN, POOL_MAX)
	return {
		"kind": "pool",
		"at": at,
		"colour": BLOOD[slot],
		"sheen": BLOOD_FRESH[slot],
		"points": PackedVector2Array([
			Vector2(-width, 0.0),
			Vector2(-width * 0.6, -1.6),
			Vector2(width * 0.55, -1.4),
			Vector2(width, 0.4),
			Vector2(width * 0.3, 1.6),
			Vector2(-width * 0.5, 1.4),
		]),
		# The wet sheen: the sunward half of the pool's top edge.
		"sheen_points": PackedVector2Array([
			Vector2(-width * 0.6, -1.6),
			Vector2(-width * 0.05, -1.5),
			Vector2(-width * 0.25, -0.6),
			Vector2(-width * 0.75, -0.7),
		]),
		"death": death,
	}


## A smear along the floor from under the body, in the blow's direction, cut
## short where the floor steps up or drops away.
func _streak(rng: RandomNumberGenerator, at: Vector2, side: int, slot: int,
		death: Vector2i) -> Dictionary:
	var want := rng.randf_range(STREAK_MIN, STREAK_MAX)
	var reach := 0.0
	while reach < want:
		var probe := at + Vector2(float(side) * (reach + 2.0), 0.0)
		var under := _kind_at(probe + Vector2(0.0, 1.0))
		if _kind_at(probe + Vector2(0.0, -1.0)) == Tiles.Kind.SOLID \
				or (under != Tiles.Kind.SOLID and under != Tiles.Kind.PLATFORM):
			break
		reach += 2.0
	if reach < 6.0:
		return {}
	var dir := float(side)
	return {
		"kind": "streak",
		"at": at,
		"colour": BLOOD[slot],
		"points": PackedVector2Array([
			Vector2(dir * 3.0, -1.4),
			Vector2(dir * reach, -0.2),
			Vector2(dir * (reach - 3.0), 0.6),
			Vector2(dir * 3.0, 0.8),
		]),
		"death": death,
	}


## Walks a mark out of the air down onto the top of the floor beneath it --
## exactly onto it, so a streak can tell where that floor runs. A stain that
## hung in mid-air would read as a bug. Nothing below within FALL: left where
## it is.
func _settle(from: Vector2) -> Vector2:
	var column := floori(from.x / ZoneStrip.TILE)
	var first := floori(from.y / ZoneStrip.TILE)
	for row: int in range(first, first + int(FALL / ZoneStrip.TILE) + 1):
		var kind := strip.kind_at(column, row)
		if kind == Tiles.Kind.SOLID or kind == Tiles.Kind.PLATFORM:
			return Vector2(from.x, maxf(from.y, float(row * ZoneStrip.TILE)))
	return from


func _kind_at(at: Vector2) -> Tiles.Kind:
	return strip.kind_at(floori(at.x / ZoneStrip.TILE), floori(at.y / ZoneStrip.TILE))


func _add_mark(decal: Dictionary) -> void:
	_add(_marks, decal, MAX_MARKS)


func _add_drop(decal: Dictionary) -> void:
	_add(_drops, decal, MAX_DROPS)


func _add(lists: Array[Array], decal: Dictionary, bound: int) -> void:
	var zone := strip.zone_of_x((decal["at"] as Vector2).x)
	if zone < 0 or zone >= lists.size():
		return
	var list: Array = lists[zone]
	list.append(decal)
	# The bound, enforced where it is cheapest: oldest stain out, newest in.
	while list.size() > bound:
		list.remove_at(0)


## --- what the test asks ----------------------------------------------------

func count_in(zone: int) -> int:
	if zone < 0 or zone >= _marks.size():
		return 0
	return (_marks[zone] as Array).size() + (_drops[zone] as Array).size()


func marks_in(zone: int) -> int:
	if zone < 0 or zone >= _marks.size():
		return 0
	return (_marks[zone] as Array).size()


func total() -> int:
	var sum := 0
	for zone: int in _marks.size():
		sum += count_in(zone)
	return sum


## Droplets in the air at the clock's frame now, and where.
func flying() -> PackedVector2Array:
	var out := PackedVector2Array()
	for list: Array in _drops:
		for drop: Dictionary in list:
			var at := _in_flight(drop)
			if not is_nan(at.x): # in the air
				out.append(at)
	return out


## Whether anything is still moving at the clock's frame now.
func moving() -> bool:
	return _now >= 0 and _now < _moving_until


## --- drawing ---------------------------------------------------------------

## Decals do not move once they are down, so this does not redraw every frame
## -- only while a death is young (tick()), when blood is spilled or wiped,
## when the field is cleared, or when a different set of zones comes into view.
func show_zones(zones: PackedInt32Array) -> void:
	if zones == _drawn_for:
		return
	visible_zones = zones
	_drawn_for = zones
	queue_redraw()


func _draw() -> void:
	for zone: int in visible_zones:
		if zone < 0 or zone >= _marks.size():
			continue
		for decal: Dictionary in _marks[zone]:
			_draw_mark(decal)
		for drop: Dictionary in _drops[zone]:
			_draw_drop(drop)


func _draw_mark(decal: Dictionary) -> void:
	var age := _age(decal)
	if age < 0:
		return
	var at: Vector2 = decal["at"]
	var grown := 1.0
	if decal["kind"] == "pool" and _now >= 0:
		# Spreads fast and then slowly, as a pool does.
		grown = lerpf(0.3, 1.0, 1.0 - pow(1.0 - clampf(float(age) / POOL_FRAMES, 0.0, 1.0), 2.0))
	var scale := Vector2(grown, 1.0)
	draw_colored_polygon(_placed(decal["points"], at, scale), decal["colour"])
	if decal.has("sheen") and _now >= 0 and age < WET_FRAMES:
		draw_colored_polygon(_placed(decal["sheen_points"], at, scale), decal["sheen"])


func _draw_drop(drop: Dictionary) -> void:
	var age := _age(drop)
	if age < 0:
		return
	var air := _in_flight(drop)
	if not is_nan(air.x):
		# Two pixels long along its flight, so it reads as thrown, not as a
		# speck; the later, weaker pulses one.
		var size := Vector2.ONE
		if int(drop["leaves"]) == 0:
			var velocity: Vector2 = drop["velocity"]
			size = Vector2(2.0, 1.0) if absf(velocity.x) > absf(velocity.y) else Vector2(1.0, 2.0)
		draw_rect(Rect2(air.round(), size), drop["flying"])
		return
	if _now >= 0 and age - int(drop["leaves"]) < int(drop["flight"]):
		return # not out of the wound yet
	for rect: Rect2 in drop["rects"]:
		draw_rect(rect, drop["colour"])


## Frames since the death a decal belongs to, or a large number with no clock.
func _age(decal: Dictionary) -> int:
	if _now < 0:
		return 1 << 20
	return _now - (decal["death"] as Vector2i).x


## Where a droplet is at the clock's frame now, or NaN once it is down or before
## it has left the wound.
func _in_flight(drop: Dictionary) -> Vector2:
	var nothing := Vector2(NAN, NAN)
	if _now < 0:
		return nothing
	var t := _age(drop) - int(drop["leaves"])
	if t < 0 or t >= int(drop["flight"]):
		return nothing
	var seconds := float(t) / 60.0
	var from: Vector2 = drop["from"]
	var velocity: Vector2 = drop["velocity"]
	return from + velocity * seconds + Vector2(0.0, GRAVITY * 0.5) * seconds * seconds


static func _placed(points: PackedVector2Array, at: Vector2,
		scale: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(points.size())
	for i: int in points.size():
		out[i] = at + points[i] * scale
	return out
