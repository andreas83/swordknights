class_name ParallaxSky
extends Node2D
## Procedural crimson skyline: a sun-washed city of arches, towers and domes.
##
## Generated from a seeded PRNG rather than shipped as art, so there are no
## background images in the build and a level can re-roll its silhouette by
## changing the seed. Drawn in screen space inside a CanvasLayer, with each
## layer offset by the camera position times its depth.

@export var seed_value: int = 1:
	set(value):
		seed_value = value
		_build()
		queue_redraw()

var camera: Camera2D

## 0 at noon, 1 at the last room's dusk: the sky goes to ink, the sun sinks to
## the horizon and burns, and the city becomes a silhouette in front of it.
## Driven by MatchDusk; nothing else sets it.
var dusk: float = 0.0

const _DEPTHS: Array[float] = [0.12, 0.26, 0.46]
## A flock crosses the far sky once every FLOCK_EVERY seconds and takes
## FLOCK_CROSS of them to do it: often enough that the city is inhabited,
## rarely enough that nobody waits for it. Birds are the far plane, so they
## are drawn in the sky's own crimson, a step darker, and never crisp gold.
const FLOCK_EVERY := 31.0
const FLOCK_CROSS := 12.0
const FLOCK_SIZE := 5
const _BASELINES: Array[float] = [0.74, 0.82, 0.92]
## The sun's place across the view, at noon and at dusk. On the left, where
## the light comes from: every shadow in the world falls down and to the right
## (docs/world.md, "One sun"), and a disc on the right stood behind the
## shadows it cast. Dusk draws it in toward the middle as it sinks.
const SUN_NOON_X := 0.28
const SUN_DUSK_X := 0.36
## It drifts left as the camera runs right, at the far skyline's rate, and
## stops here: a 170-column ruin, or the duel's strip, would otherwise carry it
## off the edge of the sky it lights.
const SUN_LEFT_MOST := 0.1
const SUN_DRIFT := 0.04

var _layers: Array = []
var _time: float = 0.0


func _ready() -> void:
	if _layers.is_empty():
		_build()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_layers.clear()

	var span := 1600.0
	for index: int in _DEPTHS.size():
		var scale := 0.55 + _DEPTHS[index]
		var buildings: Array = []
		var x := -320.0
		while x < span:
			var w := (18.0 + rng.randf() * 44.0) * scale
			var h := (26.0 + rng.randf() * 78.0) * scale
			buildings.append({
				"x": x, "w": w, "h": h,
				"cap": rng.randi_range(0, 2),
				"windows": rng.randi_range(0, 3),
			})
			x += w + rng.randf() * 10.0 * scale
		_layers.append(buildings)


func _draw() -> void:
	var view := get_viewport_rect().size
	_draw_sky(view)

	var cam := camera.global_position if camera != null else Vector2.ZERO
	_draw_sun(view, cam)
	_draw_flock(view, cam)

	var colors: Array[Color] = [
		Palette.with_alpha(Palette.SHADOW, 0.55).lerp(
			Palette.with_alpha(Palette.SHADOW_DEEP, 0.9), dusk),
		Palette.with_alpha(Palette.SHADOW_WARM, 0.72).lerp(
			Palette.with_alpha(Palette.INK, 0.82), dusk),
		Palette.MID.lerp(Palette.INK, dusk),
	]
	var haze := Palette.with_alpha(Palette.MID, 0.35).lerp(
		Palette.with_alpha(Palette.SHADOW_WARM, 0.5), dusk)

	for index: int in _layers.size():
		var depth := _DEPTHS[index]
		var baseline := view.y * _BASELINES[index] - cam.y * depth * 0.35
		var offset_x := -cam.x * depth
		for b: Dictionary in _layers[index]:
			var bx: float = b["x"] + offset_x
			# Wrap the band so a long level never runs out of skyline.
			bx = fposmod(bx, 1920.0) - 320.0
			if bx + b["w"] < -8.0 or bx > view.x + 8.0:
				continue
			_draw_building(b, bx, baseline, colors[index])

		# Haze band hides the layer's feet and separates it from the next.
		draw_rect(Rect2(0.0, baseline - 2.0, view.x, 22.0), haze)


func _draw_sky(view: Vector2) -> void:
	# Four flat bands rather than a gradient: the art direction is hard edges.
	var offsets := Palette.SKY_OFFSETS
	for i: int in Palette.SKY_STOPS.size():
		var top := view.y * (0.0 if i == 0 else offsets[i - 1])
		var bottom := view.y * offsets[i]
		draw_rect(Rect2(0.0, top, view.x, bottom - top + 1.0), _band(i))


## The colour of sky band `index`, between noon and dusk.
func _band(index: int) -> Color:
	return Palette.SKY_STOPS[index].lerp(Palette.DUSK_SKY_STOPS[index], dusk)


## The sky colour behind height `y`, for cutting the sun's heat stripes.
func _sky_at(y: float, view: Vector2) -> Color:
	var offsets := Palette.SKY_OFFSETS
	for i: int in range(1, offsets.size()):
		if y <= view.y * offsets[i]:
			return _band(i)
	return _band(offsets.size() - 1)


## Noon: a pale disc high in the sky. Dusk: low and nearly three times the
## size, opaque and burning, cut by hard heat bands of sky -- the art
## direction's hard edges rather than a soft glow -- with its lower edge going
## down behind the city, which is drawn after it. Low enough to set, high
## enough that the burning disc itself is seen and not only its glow.
func _draw_sun(view: Vector2, cam: Vector2) -> void:
	var at := sun_center(view, cam)
	var x := at.x
	var y := at.y
	var pulse := 1.0 + sin(_time * lerpf(0.6, 1.4, dusk)) * lerpf(0.02, 0.035, dusk)
	draw_circle(at, lerpf(52.0, 96.0, dusk) * pulse,
		Palette.with_alpha(Palette.LIGHT_WARM, 0.10).lerp(
			Palette.with_alpha(Palette.SHADOW_WARM, 0.32), dusk))
	draw_circle(at, lerpf(34.0, 62.0, dusk) * pulse,
		Palette.with_alpha(Palette.LIGHT, 0.14).lerp(
			Palette.with_alpha(Palette.MID, 0.55), dusk))
	var core := lerpf(17.0, 46.0, dusk) * pulse
	draw_circle(at, core,
		Palette.with_alpha(Palette.LIGHT_SOFT, 0.40).lerp(Palette.LIGHT, dusk))
	if dusk <= 0.05:
		return
	# Heat bands across the lower half, thickening toward the horizon.
	for k: int in 4:
		var band_y := y + core * (0.18 + 0.2 * float(k))
		var thick := core * (0.035 + 0.03 * float(k)) * dusk
		var half := sqrt(maxf(0.0, core * core - (band_y - y) * (band_y - y)))
		draw_rect(Rect2(x - half - 1.0, band_y, half * 2.0 + 2.0, thick),
			_sky_at(band_y, view))


## Where the disc is drawn, in the view, with the camera at `cam`.
func sun_center(view: Vector2, cam: Vector2) -> Vector2:
	var x := view.x * lerpf(SUN_NOON_X, SUN_DUSK_X, dusk) - cam.x * SUN_DRIFT
	return Vector2(maxf(x, view.x * SUN_LEFT_MOST), view.y * lerpf(0.28, 0.44, dusk))


func _draw_building(b: Dictionary, x: float, baseline: float, color: Color) -> void:
	var w: float = b["w"]
	var h: float = b["h"]
	var top := baseline - h
	draw_rect(Rect2(x, top, w, h), color)

	match int(b["cap"]):
		1: # onion dome
			var r: float = minf(w * 0.42, 14.0)
			draw_circle(Vector2(x + w * 0.5, top - r * 0.45), r, color)
			draw_rect(Rect2(x + w * 0.5 - 0.6, top - r * 2.1, 1.2, r * 0.9), color)
		2: # stepped tower
			var w2 := w * 0.42
			draw_rect(Rect2(x + (w - w2) * 0.5, top - h * 0.3, w2, h * 0.3), color)
		_:
			draw_rect(Rect2(x - 1.5, top - 2.0, w + 3.0, 2.5), color)

	var count: int = b["windows"]
	if count <= 0 or w < 12.0:
		return
	var slot := w / float(count + 1)
	for i: int in range(1, count + 1):
		var wx := x + slot * i - 1.6
		_draw_arch(wx, top + 6.0, 3.2, minf(7.0, h * 0.35),
			Palette.with_alpha(Palette.INK, 0.28))


func _draw_arch(x: float, y: float, w: float, h: float, color: Color) -> void:
	var radius := minf(w * 0.5, h)
	var points := PackedVector2Array([Vector2(x, y + h), Vector2(x, y + radius)])
	var steps := 8
	for i: int in range(steps + 1):
		var angle := PI - PI * float(i) / float(steps)
		points.append(Vector2(x + w * 0.5 + cos(angle) * radius, y + radius - sin(angle) * radius))
	points.append(Vector2(x + w, y + h))
	draw_colored_polygon(points, color)


## A loose line of birds crossing behind the city, wings beating in turn. A
## pure function of the clock and the seed, so nothing is spawned or freed.
func _draw_flock(view: Vector2, cam: Vector2) -> void:
	var cycle := floorf(_time / FLOCK_EVERY)
	var t := (_time - cycle * FLOCK_EVERY) / FLOCK_CROSS
	if t >= 1.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(seed_value, int(cycle)))
	var heading := 1.0 if rng.randf() < 0.5 else -1.0
	var y := view.y * rng.randf_range(0.16, 0.4) - cam.y * 0.05
	var lead_x := lerpf(-30.0, view.x + 30.0, t)
	if heading < 0.0:
		lead_x = view.x - lead_x
	lead_x -= cam.x * 0.08
	var color := Palette.with_alpha(Palette.SHADOW_DEEP, 0.8).lerp(Palette.INK, dusk)
	for i: int in FLOCK_SIZE:
		var bx := roundf(lead_x - heading * (6.0 + rng.randf() * 4.0) * float(i))
		var by := roundf(y + absf(float(i) - 1.0) * 2.0 + rng.randf() * 3.0
			+ sin(_time * 0.9 + float(i)) * 1.5)
		# Two strokes: wings up, then wings down, four beats a second.
		var up := int(_time * 8.0 + float(i) * 1.7) % 2 == 0
		var tip := -1.0 if up else 1.0
		draw_rect(Rect2(bx - 2.0, by + tip, 1.0, 1.0), color)
		draw_rect(Rect2(bx - 1.0, by, 1.0, 1.0), color)
		draw_rect(Rect2(bx, by + (1.0 if up else 0.0), 1.0, 1.0), color)
		draw_rect(Rect2(bx + 1.0, by, 1.0, 1.0), color)
		draw_rect(Rect2(bx + 2.0, by + tip, 1.0, 1.0), color)
