class_name Torch
extends Node2D
## A standing brazier whose fire is the one thing in the world lit from
## inside rather than by the sun -- and the level's checkpoint.
##
## ## Drawn the way the rest of the world is
##
## Hard edges and flat tones only. The flame is three stacked tongues --
## MID, LIGHT, LIGHT_SOFT -- and it changes shape on a 12 fps clock rather
## than smoothly, the way a hand-animated flame steps between drawings. A
## smoothly interpolated flame is a gradient in time, and it reads as a
## different kind of art from everything around it. The glow is two flat
## discs at integer radii, so it steps too instead of shimmering.
##
## Embers rise off it on their own short loops: a pure function of the clock
## and the torch's position, so two torches never pulse together and nothing
## is spawned or freed.
##
## The iron stand is drawn in the same ink and deep shade as the guard's
## armour, lit down its left edge: the sun is still the sun, even next to a
## fire.

const TOP := -14.0
const FLAME_FPS := 12.0
const EMBERS := 3
const EMBER_RISE := 16.0

## ## The checkpoint
##
## `Game` decides which torches count (only those the exit can be reached
## from, `EntitySite.checkpoint`) and whether a claim moves the checkpoint
## (only forward); this file decides what reaching the torch means and shows
## it. The claim is a single flare that dies back to the ordinary flame, not a
## torch that changes state for good: every torch is already lit, and a level
## full of torches that look "off" until touched would look unfinished. The
## flare is the same flat discs at integer radii as the glow, so it steps like
## the flame rather than swelling smoothly.

## How long the flare takes to die back to the ordinary flame.
const FLARE_TIME := 0.7
## How close, either side of the torch, the feet have to pass to claim it.
## Wider than one frame of full-speed running, so it cannot be skipped, and
## narrow enough that it reads as "I reached the torch".
const REACH := 10.0

## Set when the exit is reachable from here.
var checkpoint := false
var claimed := false

var _phase: float = 0.0
var _time: float = 0.0
var _flare: float = 0.0


func _ready() -> void:
	_phase = fmod(global_position.x * 0.37 + global_position.y * 0.11, TAU)
	# A light, so the hour never dims it (WorldGrade).
	add_to_group(MatchDusk.LIT)


## --- the entity protocol (scripts/entities/entity_registry.gd) ---------------

func place(site: EntitySite) -> void:
	position = site.at
	checkpoint = site.checkpoint
	# At night the fire is the light: a pool of it on the stone around the
	# torch (FireLight), which goes out with the torch.
	FireLight.kindle(self, site.level)


## Claimed by reaching it on your feet: grounded, on the torch's own floor --
## not jumping past it or standing on a ledge above it -- and within REACH.
## Whether it is further on than the checkpoint already held is Game's call.
func meet(contact: Contact) -> void:
	if not checkpoint or claimed or not contact.grounded:
		return
	if absf(contact.body.get_center().x - position.x) > REACH:
		return
	if absf(contact.feet.y - position.y) > 1.0:
		return
	if contact.offer_checkpoint(position):
		claim()


func claim() -> void:
	claimed = true
	_flare = 1.0


func _process(delta: float) -> void:
	_time += delta
	_flare = maxf(0.0, _flare - delta / FLARE_TIME)
	queue_redraw()


func _draw() -> void:
	# The flame's drawing changes twelve times a second, not every frame.
	var frame := floorf(_time * FLAME_FPS + _phase * 3.0)
	var flicker := 0.78 + 0.12 * sin(frame * 1.7 + _phase) + 0.08 * sin(frame * 3.1)
	var sway := roundf(sin(frame * 0.9 + _phase) * 1.0)
	flicker *= 1.0 + _flare * _flare * 0.9
	if _flare > 0.0:
		draw_circle(Vector2(0.0, TOP + 1.0), roundf(18.0 * flicker),
			Palette.with_alpha(Palette.LIGHT_SOFT, 0.12 * _flare))

	_draw_glow(flicker)
	_draw_stand()
	_draw_flame(flicker, sway)
	_draw_embers()


func _draw_glow(flicker: float) -> void:
	var at := Vector2(0.0, TOP + 1.0)
	draw_circle(at, roundf(12.0 * flicker), Palette.with_alpha(Palette.LIGHT, 0.09))
	draw_circle(at, roundf(7.0 * flicker), Palette.with_alpha(Palette.LIGHT_SOFT, 0.14))


## A tripod foot, a shaft, and a bowl with a lit rim.
func _draw_stand() -> void:
	draw_colored_polygon(PackedVector2Array([
		Vector2(-3.0, 0.0), Vector2(-1.0, -3.0), Vector2(1.0, -3.0), Vector2(3.0, 0.0),
		Vector2(1.6, 0.0), Vector2(0.0, -1.6), Vector2(-1.6, 0.0),
	]), Palette.INK)
	draw_rect(Rect2(-1.0, TOP + 5.0, 2.0, -TOP - 7.0), Palette.SHADOW_DEEP)
	draw_rect(Rect2(-1.0, TOP + 5.0, 1.0, -TOP - 7.0), Palette.SHADOW)
	draw_rect(Rect2(-2.0, TOP + 9.0, 4.0, 1.0), Palette.INK)   # a collar
	# The bowl.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-3.5, TOP + 2.0), Vector2(3.5, TOP + 2.0),
		Vector2(2.0, TOP + 5.0), Vector2(-2.0, TOP + 5.0),
	]), Palette.INK)
	draw_rect(Rect2(-3.5, TOP + 2.0, 7.0, 1.0), Palette.LIGHT_WARM)


func _draw_flame(flicker: float, sway: float) -> void:
	var base := TOP + 2.0
	var height := roundf(9.0 * flicker)
	_tongue(Vector2(sway * 0.5, base), 3.2, height, Palette.MID)
	_tongue(Vector2(sway * 0.8 - 0.5, base), 2.2, roundf(height * 0.72), Palette.LIGHT)
	_tongue(Vector2(sway, base), 1.2, roundf(height * 0.42), Palette.LIGHT_SOFT)
	# A side lick that comes and goes.
	if int(_time * FLAME_FPS + _phase) % 3 == 0:
		_tongue(Vector2(2.0, base), 1.0, roundf(height * 0.45), Palette.MID)


func _tongue(at: Vector2, half: float, height: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		at + Vector2(-half, 0.0), at + Vector2(-half * 0.6, -height * 0.45),
		at + Vector2(0.0, -height), at + Vector2(half * 0.6, -height * 0.45),
		at + Vector2(half, 0.0),
	]), color)


func _draw_embers() -> void:
	for i: int in EMBERS:
		var period := 1.1 + 0.37 * float(i)
		var t := fposmod(_time + _phase + float(i) * 0.53, period) / period
		var drift := sin(t * 5.0 + float(i) * 2.0 + _phase) * 2.5
		var at := Vector2(drift + float(i - 1), TOP - 4.0 - t * EMBER_RISE).round()
		# Hot, then cooling, then out: three tones, no fade.
		var color := Palette.LIGHT_SOFT if t < 0.35 else Palette.MID
		if t > 0.8:
			continue
		draw_rect(Rect2(at, Vector2.ONE), color)
