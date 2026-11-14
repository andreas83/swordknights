class_name ParallaxSky
extends Node2D
## Procedural crimson skyline: a sun-washed city of arches, towers and domes.
##
## Generated from a seeded PRNG rather than shipped as art, so there are no
## background images in the build and a level can re-roll its silhouette by
## changing the seed. Drawn in screen space inside a CanvasLayer, with each
## layer offset by the camera position times its depth.
##
## The camera's zoom does not enter, deliberately. The sky is a backdrop at
## its own scale on its own layer, so it fills the viewport whatever the world
## in front of it is scaled by; the duel's camera has always zoomed in front of
## it, and the Adventure's 1.5x (GameCamera.ZOOM) is the same case. The
## parallax reads the camera's travel in world units, so a closer camera only
## makes the near world slide faster past a sky that moves as it did.

@export var seed_value: int = 1:
	set(value):
		seed_value = value
		_build()
		queue_redraw()

var camera: Camera2D

## 0 at noon, 1 at the last room's dusk: the sky goes to ink, the sun sinks to
## the horizon and burns, and the city becomes a silhouette in front of it.
## Driven by MatchDusk in the duel and by WorldGrade from a level's hour.
var dusk: float = 0.0
## 0 by day, 1 at night: the bands go on from dusk to Palette.NIGHT_SKY_STOPS
## and there is no sun. Set by WorldGrade; the duel never does.
var night: float = 0.0

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

# --- the Mirror Tower --- (docs/campaign.md, "Story without words")
## How far away the Mirror Tower stands, from 1 (on the far skyline) toward 0
## (here); 0 is no tower at all, which is every sky but the campaign's -- the
## duel's, the menus' and Endless's draw exactly what they drew before it.
## Set from the chapter's catalogue entry (Campaign "tower"), so it is one
## number per chapter and the chapters agree on which way it moves.
var tower: float = 0.0
## The great mirror turned to the sun and lit. It is dark and turned away in
## every chapter; only the dawn sets this.
var tower_lit := false
## The sun in the east: the disc drawn on the right, mirrored about the
## middle. The dawn's frame only (docs/campaign.md, "Decided by the owner").
var east := false
## Every window in the skyline lit from inside: the kept sun gone out over
## the city (docs/campaign.md, "The ending"). The dawn's frame only.
var windows_lit := false

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
	if shows_sun():
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
		Palette.with_alpha(Palette.SHADOW_WARM, 0.5), dusk).lerp(
		Palette.with_alpha(Palette.SHADOW_PIT, 0.55), night)

	var tower_drawn := tower <= 0.0
	for index: int in _layers.size():
		var depth := _DEPTHS[index]
		if not tower_drawn and tower_depth() < depth:
			_draw_tower(view, cam)
			tower_drawn = true
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
	if not tower_drawn:
		_draw_tower(view, cam)


func _draw_sky(view: Vector2) -> void:
	# Four flat bands rather than a gradient: the art direction is hard edges.
	var offsets := Palette.SKY_OFFSETS
	for i: int in Palette.SKY_STOPS.size():
		var top := view.y * (0.0 if i == 0 else offsets[i - 1])
		var bottom := view.y * offsets[i]
		draw_rect(Rect2(0.0, top, view.x, bottom - top + 1.0), _band(i))


## The colour of sky band `index`, between noon and dusk, and on to night.
func _band(index: int) -> Color:
	var day := Palette.SKY_STOPS[index].lerp(Palette.DUSK_SKY_STOPS[index], dusk)
	return day.lerp(Palette.NIGHT_SKY_STOPS[index], night)


## Whether the disc is drawn: not at night.
func shows_sun() -> bool:
	return night < 0.5


## The sky colour behind height `y`, for cutting the sun's heat stripes.
func sky_at(y: float, view: Vector2) -> Color:
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
			sky_at(band_y, view))


## Where the disc is drawn, in the view, with the camera at `cam`. In the
## east (the dawn) the same place mirrored about the middle of the view.
func sun_center(view: Vector2, cam: Vector2) -> Vector2:
	var x := view.x * lerpf(SUN_NOON_X, SUN_DUSK_X, dusk) - cam.x * SUN_DRIFT
	var at := Vector2(maxf(x, view.x * SUN_LEFT_MOST), view.y * lerpf(0.28, 0.44, dusk))
	if east:
		at.x = view.x - at.x
	return at


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
		_draw_arch(wx, top + 6.0, 3.2, minf(7.0, h * 0.35), _window_colour())


## A window: cut in ink, or lit from inside at the dawn.
func _window_colour() -> Color:
	if windows_lit:
		return Palette.with_alpha(Palette.LIGHT_SOFT, 0.75)
	return Palette.with_alpha(Palette.INK, 0.28)


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


# --- the Mirror Tower --------------------------------------------------------
#
# One landmark, not a building rolled from the seed: the tower the campaign
# crosses the city toward, standing in the skyline from Chapter I, its great
# mirror dark and turned away, nearer every chapter (docs/campaign.md, "Story
# without words"). It is drawn in the sky's own language and nothing else --
# a flat silhouette in the colour of the plane it stands in, arched windows
# cut in ink, a cap -- because the background is never crisp
# (docs/art-direction.md, "three planes"), and a landmark drawn in the
# mid-ground's gold would be a second sun. What makes it the landmark is its
# outline: taller than anything on the skyline, square-shouldered where the
# city is domed, and the one circle on a stick in the sky -- the great mirror
# hung off its parapet. Nearer means larger, a plane further forward, its
# colour that plane's, and a faster parallax; the hour reaches it the way it
# reaches every building, through the plane colours, so it sits in the sky
# at every stop from the afternoon to the night with nothing of its own to
# grade. One rule for it at dusk: the last light still finds its top
# courses, because the bible's Chapter IV is "the last gold in the world".

## Where the tower stands across the view: ahead, to the east, which is the
## way every chapter runs -- and at the dawn, with the sun in the east, behind
## you in the west, mirrored with it. It drifts left at TOWER_DRIFT of the camera's run,
## slower than the far skyline, so a whole chapter does not carry it past
## the middle -- a landmark you are walking toward should not slide behind
## you -- and stops at TOWER_LEFT_MOST.
const TOWER_X := 0.76
const TOWER_DRIFT := 0.03
const TOWER_LEFT_MOST := 0.5
## Below this luminance the sky behind the crown is ink, and the tower stands
## out of it a step lighter instead of a step darker.
const TOWER_DARK_SKY := 0.1


## The parallax depth the tower stands at: the far skyline's when it is far
## away, the near skyline's when it is close.
func tower_depth() -> float:
	return lerpf(_DEPTHS[_DEPTHS.size() - 1] * 0.85, _DEPTHS[0] * 0.5, clampf(tower, 0.0, 1.0))


## The tower's shaft in the view with the camera at `cam`. Its top is what
## is placed -- above every roof on the skyline, higher the nearer it is --
## and its foot runs down behind the planes in front of it, so it is never
## seen to stand on anything: it is across the city, not on the next roof.
## Empty when there is no tower.
func tower_rect(view: Vector2, cam: Vector2) -> Rect2:
	if tower <= 0.0:
		return Rect2()
	var far := clampf(tower, 0.0, 1.0)
	var wide := roundf(lerpf(30.0, 12.0, far))
	var top := roundf(view.y * lerpf(0.03, 0.08, far) - cam.y * tower_depth() * 0.35)
	# A camera low in a tall chapter lifts the skyline, and would lift the
	# crown out of the frame; like the sun's drift, the rise stops where the
	# lantern and the mirror would leave the sky they are the point of.
	top = maxf(top, 5.0 + roundf(wide * 0.45))
	var x := maxf(view.x * TOWER_X - cam.x * TOWER_DRIFT, view.x * TOWER_LEFT_MOST)
	if east:
		x = view.x - x
	# The foot is on its own plane's baseline, as every building's is, where
	# the haze of the plane in front of it takes it.
	var foot := view.y * _baseline_at(tower_depth()) - cam.y * tower_depth() * 0.35
	return Rect2(roundf(x - wide * 0.5), top, wide, maxf(0.0, roundf(foot) - top))


## The baseline, as a share of the view's height, of a plane at `depth`:
## between the planes' own, and the far plane's for anything further away.
func _baseline_at(depth: float) -> float:
	if depth <= _DEPTHS[0]:
		return _BASELINES[0]
	for index: int in range(1, _DEPTHS.size()):
		if depth <= _DEPTHS[index]:
			var t := inverse_lerp(_DEPTHS[index - 1], _DEPTHS[index], depth)
			return lerpf(_BASELINES[index - 1], _BASELINES[index], t)
	return _BASELINES[_BASELINES.size() - 1]


## The tower's tone, for a crown at height `top`: the sky behind the crown a
## step toward ink -- the flock's rule, "the sky's own crimson, a step
## darker" -- or, once that sky has no light left in it (dusk's and night's
## top bands are ink), a step up out of the ink, as the far skyline stands
## out at night. Taken from the band rather than fixed, because a fixed tone
## matches some hour's sky exactly: the far plane's own colour is the
## afternoon's upper band, and a fixed darker one was sunset's, which left
## the tower its windows and nothing else (tests/unit/test_mirror_tower.gd).
## Nearer is more solid.
func tower_colour(view: Vector2, top: float) -> Color:
	var behind := sky_at(top + 1.0, view)
	var near := 1.0 - clampf(tower, 0.0, 1.0)
	var tone := behind.lerp(Palette.INK, 0.5)
	if behind.get_luminance() < TOWER_DARK_SKY:
		tone = behind.lerp(Palette.SHADOW_DEEP.lerp(Palette.SHADOW_PIT, night * 0.5),
			lerpf(0.75, 1.0, night))
	return Palette.with_alpha(tone, lerpf(0.88, 1.0, near))


func _draw_tower(view: Vector2, cam: Vector2) -> void:
	var shaft := tower_rect(view, cam)
	if shaft.size.x <= 0.0:
		return
	var colour := tower_colour(view, shaft.position.y)
	var w := shaft.size.x
	# A batter: the lower third a step wider, as a tower's footing is.
	var step := maxf(1.0, roundf(w * 0.12))
	var footing_top := shaft.position.y + roundf(w * 5.0)
	draw_rect(Rect2(shaft.position.x, shaft.position.y, w, footing_top - shaft.position.y),
		colour)
	draw_rect(Rect2(shaft.position.x - step, footing_top, w + step * 2.0,
		shaft.end.y - footing_top), colour)
	# The parapet: a slab a step proud of the shaft, and a lantern course
	# on it, so the top is square where the city's tops are domes.
	var top := shaft.position.y
	draw_rect(Rect2(shaft.position.x - step, top - 2.0, w + step * 2.0, 2.0 + step), colour)
	var lantern := roundf(w * 0.5)
	draw_rect(Rect2(shaft.position.x + roundf((w - lantern) * 0.5), top - 2.0 - roundf(w * 0.45),
		lantern, roundf(w * 0.45)), colour)
	_draw_tower_windows(shaft, footing_top)
	_draw_great_mirror(shaft, colour, step)
	_draw_tower_last_light(shaft)


## A column of the sky's ink arches up the shaft, one per course.
func _draw_tower_windows(shaft: Rect2, footing_top: float) -> void:
	var w := shaft.size.x
	if w < 8.0:
		return
	var arch_w := maxf(2.0, roundf(w * 0.28))
	var arch_h := maxf(4.0, roundf(arch_w * 2.0))
	var pitch := arch_h + maxf(5.0, roundf(w * 0.6))
	var y := shaft.position.y + roundf(w * 0.5) + 2.0
	while y + arch_h < footing_top:
		_draw_arch(shaft.position.x + roundf((w - arch_w) * 0.5), y, arch_w, arch_h,
			_window_colour())
		y += pitch


## The great mirror, hung on an arm off the parapet's west end over open air:
## a disc on a stick, its back to the city -- the bronze back, darker than
## the stone it hangs from. At the dawn it is turned to the sun and lit.
func _draw_great_mirror(shaft: Rect2, colour: Color, step: float) -> void:
	var w := shaft.size.x
	var radius := maxf(3.0, roundf(w * 0.4))
	var arm_y := shaft.position.y - 1.0
	var reach := radius + step + maxf(2.0, roundf(w * 0.2))
	var centre := Vector2(shaft.position.x - reach, arm_y + radius * 0.35)
	if east:
		centre.x = shaft.end.x + reach
	var arm_from := minf(centre.x, shaft.end.x)
	var arm_to := maxf(centre.x, shaft.position.x)
	draw_rect(Rect2(arm_from, arm_y - 1.0, arm_to - arm_from, maxf(1.0, step)), colour)
	var back := Palette.with_alpha(Palette.INK, minf(1.0, colour.a + 0.1)).lerp(
		Palette.with_alpha(Palette.SHADOW_DEEP, colour.a), 0.35 * (1.0 - dusk))
	draw_circle(centre, radius, back)
	if not tower_lit:
		return
	# Turned to the sun, it holds it: one flat face of the sun's gold inside
	# the bronze rim -- flat, because shading it would make it a ball -- and
	# one point of paper on the sun's side, the brightest specular, which is
	# what paper white is kept for. No halo and no pulse: those are the
	# sun's, and a mirror that glowed would be a second one.
	var toward := 1.0 if east else -1.0
	draw_circle(centre, radius - 1.0, Palette.LIGHT_WARM)
	draw_rect(Rect2(roundf(centre.x + toward * radius * 0.4) - 1.0,
		roundf(centre.y - radius * 0.4) - 1.0, 2.0, 2.0), Palette.PAPER)


## From sunset on: the sun is going under the city but not yet under the
## tower, so its top courses keep a rim of the last light on the side it
## comes from -- two pixels, in the sun's own burning colour, never the
## mid-ground's gold. Gone at night, when there is no sun to keep.
func _draw_tower_last_light(shaft: Rect2) -> void:
	var lit := clampf((dusk - 0.3) * 2.0, 0.0, 1.0) * (1.0 - night)
	if lit <= 0.0:
		return
	var courses := roundf(shaft.size.y * 0.22)
	var rim := Palette.with_alpha(Palette.LIGHT_WARM, 0.7 * lit)
	var side := shaft.end.x - 2.0 if east else shaft.position.x
	draw_rect(Rect2(side, shaft.position.y - 2.0, 2.0, courses), rim)
