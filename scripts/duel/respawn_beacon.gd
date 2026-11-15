class_name RespawnBeacon
extends Node2D
## Where a fighter who is down will come back, drawn where it will happen.
##
## The owner found the respawn unclear, and the screen agreed: the only sign
## was a ring the size of a coin in the bottom corner, and then a fighter
## appeared from nothing a screen and a half ahead of the leader. So the spot
## itself is marked, in the world, for the whole of the wait: a column of
## light in the seat's colour standing on the floor the fighter will stand on,
## filling from the floor up as RESPAWN_DELAY runs out, with the countdown ring
## at the chest. When the fighter appears the column bursts -- a flare up the
## body and a ring along the floor -- so the arrival is an event the eye sees
## rather than a body that is suddenly there. When the spot is off the screen
## the HUD points at it from the edge (MatchHud._draw_respawns()).
##
## It reads the match and writes nothing, like MatchCamera: the plan is
## DuelMatch.respawn_plan(), which the match makes callable at any moment for
## exactly this kind of reader, and the timer is respawn_left(). The burst is
## the one thing it keeps, a cosmetic clock started by the scene on the
## `fighter_respawned` event; a client that rewinds does not re-fire that event
## (docs/netplay.md), so a burst is not drawn twice.

## The column's half width and height, in world pixels: a little wider than a
## body and three bodies tall, so it reads above the floor's clutter.
const HALF_WIDTH := 6.0
const HEIGHT := 64.0
const RING_RADIUS := 7.0
const BURST_TIME := 0.45

var fight: DuelMatch
## Seconds left of each seat's burst, and where it happens.
var _burst: Array[float] = [0.0, 0.0]
var _burst_at: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]


## Light is added, not painted: drawn over the stone it was a dull pink slab,
## and under the dusk's grade it went brown. Added, it brightens whatever is
## behind it in the seat's colour, which is what a column of light does. It
## stands over the foreground arcades (z), because a respawn hidden behind a
## pillar is the thing this node exists to stop.
func _ready() -> void:
	var glow := CanvasItemMaterial.new()
	glow.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = glow
	z_index = 5


## The flare of a fighter arriving at `at`.
func burst(slot: int, at: Vector2) -> void:
	if slot < 0 or slot > 1:
		return
	_burst[slot] = BURST_TIME
	_burst_at[slot] = at


## Seconds left of a seat's burst: for a test.
func burst_left(slot: int) -> float:
	return _burst[slot]


## Whether a seat's column is standing now, and where its foot is: for a test
## and for the HUD's pointer, so the two can never mark different spots.
func marked(slot: int) -> bool:
	return fight != null and fight.respawn_left(slot) > 0.0


func spot(slot: int) -> Vector2:
	return fight.respawn_plan(slot)["position"] as Vector2


func _process(delta: float) -> void:
	for slot: int in 2:
		_burst[slot] = maxf(0.0, _burst[slot] - delta)
	queue_redraw()


func _draw() -> void:
	if fight == null:
		return
	for slot: int in 2:
		if marked(slot):
			var done := 1.0 - clampf(fight.respawn_left(slot) / DuelMatch.RESPAWN_DELAY,
				0.0, 1.0)
			_draw_column(spot(slot), FighterArt.SEAT_CLOTH[slot], done)
		if _burst[slot] > 0.0:
			_draw_burst(_burst_at[slot], FighterArt.SEAT_CLOTH[slot],
				1.0 - _burst[slot] / BURST_TIME)


## The column: a faint shaft the full height, a brighter core filling from the
## floor as the wait runs out, a mark on the floor, and the closing ring.
func _draw_column(foot: Vector2, colour: Color, done: float) -> void:
	# Strong enough to read against a lit wall at a glance: the first cut, at a
	# seventh of the colour, was found on rendered frames only by looking for it.
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
	draw_rect(Rect2(foot.x - HALF_WIDTH * 2.0, foot.y - HEIGHT, HALF_WIDTH * 4.0, HEIGHT),
		Palette.with_alpha(colour, 0.12 + 0.05 * pulse))
	draw_rect(Rect2(foot.x - HALF_WIDTH, foot.y - HEIGHT, HALF_WIDTH * 2.0, HEIGHT),
		Palette.with_alpha(colour, 0.32 + 0.12 * pulse))
	var filled := HEIGHT * maxf(done, 0.08)
	var core := lerpf(1.5, 4.0, done)
	draw_rect(Rect2(foot.x - core, foot.y - filled, core * 2.0, filled),
		Palette.with_alpha(Palette.LIGHT_SOFT, 0.6 + 0.35 * done))
	draw_rect(Rect2(foot.x - HALF_WIDTH * 1.6, foot.y - 1.5, HALF_WIDTH * 3.2, 3.0),
		Palette.with_alpha(colour, 0.75 + 0.25 * pulse))
	var chest := foot + Vector2(0.0, -14.0)
	draw_arc(chest, RING_RADIUS, 0.0, TAU, 24, Palette.with_alpha(Palette.INK, 0.5), 2.4)
	draw_arc(chest, RING_RADIUS, -PI * 0.5, -PI * 0.5 + TAU * done, 24, Palette.PAPER, 1.8)


## The arrival: the column flares up the body and fades, and a ring runs out
## along the floor.
func _draw_burst(foot: Vector2, colour: Color, age: float) -> void:
	var alpha := 1.0 - age
	var width := HALF_WIDTH * (1.0 + age * 0.6)
	draw_rect(Rect2(foot.x - width, foot.y - HEIGHT, width * 2.0, HEIGHT),
		Palette.with_alpha(Palette.PAPER, 0.45 * alpha))
	draw_rect(Rect2(foot.x - 2.0, foot.y - HEIGHT, 4.0, HEIGHT),
		Palette.with_alpha(Palette.PAPER, 0.8 * alpha))
	var spread := lerpf(4.0, 26.0, age)
	draw_rect(Rect2(foot.x - spread, foot.y - 1.5, spread * 2.0, 3.0),
		Palette.with_alpha(colour, alpha))
