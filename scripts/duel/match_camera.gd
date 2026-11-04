class_name MatchCamera
extends Camera2D
## The tug-of-war camera. One zone wide, and it decides nothing.
##
## Nothing to do with scripts/render/game_camera.gd, which follows the
## adventure's protagonist. The retired round duel had a camera that framed a
## pair in a fixed arena and zoomed to fit them.
## This mode has neither shape. It has a rope, and the rope is simulation state.
##
## WHY THERE IS ALMOST NOTHING HERE, AND WHY THAT IS THE POINT
## The initiative gate is not implemented in this file. It cannot be: a camera
## that worked out for itself which way it was allowed to scroll would be a
## second, independent copy of the initiative engine, and the two copies would
## eventually disagree — one screen scrolling and the other not, which is the
## worst-looking bug this mode could have. So the window is decided once, in the
## simulation, carried in the snapshot, and this file reads `match.scroll` and
## puts the view there. Running the wrong way does not scroll the world because
## the simulation did not move the window, not because the camera refused.
##
## That is also why a zone boundary cannot stutter here. There is no boundary
## logic, no transition and no retarget: the window slides continuously and the
## camera follows a float. The seam is a thing in the level files and nowhere
## else.
##
## FRAMED ON TWO FIGHTERS, AS CLOSE AS THEY ALLOW
## The scale breathes: as close as the adventure's while the two are near each
## other, out to the old fixed framing (a fighter FIGHTER_SHARE of the screen)
## as they separate, a whole screen pixel per texel at rest. How far, when and
## how fast is MatchFraming's, which argues each number; this file hands it the
## fighters and draws what it answers. The far level is still the one the
## strip was cut for -- a zone fits across a phone at it -- so a match that
## never comes close looks exactly as it did.
##
## What it is handed is what must be on screen: the living fighters inside the
## playable window, and for a moment after a kill the spot the body fell on.
## Close framing is allowed only while both are alive and inside the window.
## A fighter down, or respawned 1.5 screens ahead of the leader as the spec
## places them, puts the frame at the far level and leans it that way, so the
## respawn is on screen as soon as any readable framing can show it.
##
## It reads the match and writes nothing back. The online duel and DUEL VS CPU
## use this same camera, and two peers may frame the same frame differently --
## different screens, different moments of an ease -- without it mattering,
## because nothing about the frame is in the snapshot.
##
## Nothing here runs in _physics_process. The match steps at a fixed 60 Hz and
## may step twice in one frame while a client reconciles; the camera glides at
## the display's rate regardless.

## How fast the view closes on the window. High enough to track the rope
## honestly, loose enough to pan rather than cut when initiative changes hands
## and the window re-centres on the new leader.
const FOLLOW := 14.0
const VERTICAL_FOLLOW := 6.0

## How tall a standing fighter is at the widest framing, as a share of the
## screen's height. MatchFraming owns it now; kept here under its old name.
const FIGHTER_SHARE := MatchFraming.FIGHTER_SHARE

## The rumble at full tremor, in world pixels. Small on purpose: the fight has to
## stay readable, and a fighter is only 22 px tall.
const TREMOR_PX := 0.9

var fight: DuelMatch

## The world width the view should frame, in pixels. Zero frames one zone, which
## is what the mode is designed around. Anything else is a comparison: 320 shows
## the duel at the adventure's scale, for deciding how wide a zone should be.
var framing_width := 0.0

## 0 to 1: a low, continuous rumble under the view, for the last room. Set by
## MatchDusk. Also scales up every shake while it is on, so a kill in the
## final room lands harder than one in the middle.
var tremor := 0.0

## How close to stand. See MatchFraming.
var framing := MatchFraming.new()

## The screen the framing is worked out for, in pixels, and its pixels per
## canvas unit. Zero measures the window. A seam for a test, which runs with no
## window and has to stand in front of a phone's.
var screen_pixels := Vector2.ZERO
var pixels_per_unit := 0.0

## The spot the last body fell on, kept in the frame while the kill holds.
var _fallen := Vector2.ZERO

## The follow position before it is snapped to whole screen pixels. Snapping the
## smoothed value itself would stall the lerp a fraction of a pixel short.
var _smooth := Vector2.ZERO
var _shake_time := 0.0
var _rumble_time := 0.0
var _shake_magnitude := 0.0
var _rng := RandomNumberGenerator.new()


func setup(match_node: DuelMatch) -> void:
	fight = match_node
	ignore_rotation = true
	position_smoothing_enabled = false
	rotation_smoothing_enabled = false

	var world := match_node.strip.world_size()
	limit_left = 0
	limit_top = 0
	limit_right = int(world.x)
	limit_bottom = int(world.y)

	_measure()
	framing.reset(_subjects(), _together())
	_apply_zoom(0.0)
	_smooth = _target()
	global_position = _snapped(_smooth)
	reset_smoothing()


## A death: the frame holds where it is, with the body in it, before it stands
## back to wait for the respawn. Rung by the scene on `fighter_died`, the beat,
## which a replay never rings twice.
func kill_beat(at: Vector2) -> void:
	_fallen = at
	framing.kill_beat()


func shake(magnitude: float, duration: float = 0.25) -> void:
	_shake_magnitude = maxf(_shake_magnitude, magnitude)
	_shake_time = maxf(_shake_time, duration)


func _process(delta: float) -> void:
	if fight == null or fight.strip == null:
		return
	_apply_zoom(delta)

	var want := _target()
	_smooth = Vector2(
		lerpf(_smooth.x, want.x, 1.0 - exp(-FOLLOW * delta)),
		lerpf(_smooth.y, want.y, 1.0 - exp(-VERTICAL_FOLLOW * delta))
	)
	# The glide is allowed to lag the target, but not to lose a fighter: two
	# running apart at full speed are nine pixels ahead of a 14/s follow.
	_smooth = _kept(_smooth, _subjects())
	global_position = _snapped(_smooth)

	var jolt := Vector2.ZERO
	if _shake_time > 0.0:
		_shake_time -= delta
		# Scaled by the zoom so a shake reads the same whatever the aspect, and
		# up to doubled in the last room.
		var amount := _shake_magnitude * clampf(_shake_time / 0.25, 0.0, 1.0) / zoom.x \
			* (1.0 + tremor)
		jolt = Vector2(_rng.randf_range(-amount, amount), _rng.randf_range(-amount, amount))
	else:
		_shake_magnitude = 0.0
	_rumble_time += delta
	offset = _snapped(jolt + _rumble() * TREMOR_PX * tremor)


## Where the view should be: between the subjects, leaning toward a fighter
## who is down or away, and never so far that a subject leaves the frame.
func _target() -> Vector2:
	var width := fight.strip.zone_width()
	var view := _view_size() / zoom
	var subjects := _subjects()

	# The window's own range for the centre: inside it when the view is
	# narrower, holding all of it when the view is wider.
	var lo := fight.scroll + view.x * 0.5
	var hi := fight.scroll + width - view.x * 0.5
	if lo > hi:
		var swap := lo
		lo = hi
		hi = swap
	var leaning := _leaning(subjects)
	var centre := clampf((leaning.x + leaning.y) * 0.5, lo, hi)

	var high := INF
	var low := -INF
	for at: Vector2 in subjects:
		high = minf(high, at.y)
		low = maxf(low, at.y)
	if subjects.is_empty():
		high = fight.fighter_position(0).y
		low = high
	# Their feet, lifted by a body, so heads are not against the top edge.
	var middle := (high + low) * 0.5 - 14.0
	var height := fight.strip.world_size().y
	var vertical := clampf(middle, view.y * 0.5, maxf(view.y * 0.5, height - view.y * 0.5))

	# The rule the mode cannot lose outranks the window and the lean.
	return _kept(Vector2(centre, vertical), subjects)


## `centre`, moved as little as it takes for every subject to be inside the
## view with MatchFraming's hard margins: EDGE beside the feet, EDGE_UPRIGHT
## above the head and below the feet.
func _kept(centre: Vector2, subjects: PackedVector2Array) -> Vector2:
	if subjects.is_empty():
		return centre
	var half := _view_size() / zoom * 0.5
	var body := DuelTuning.default().body_height
	var left := subjects[0].x
	var right := left
	var top := subjects[0].y
	var bottom := top
	for at: Vector2 in subjects:
		left = minf(left, at.x)
		right = maxf(right, at.x)
		top = minf(top, at.y)
		bottom = maxf(bottom, at.y)
	var x_lo := right + MatchFraming.EDGE - half.x
	var x_hi := left - MatchFraming.EDGE + half.x
	var y_lo := bottom + MatchFraming.EDGE_UPRIGHT - half.y
	var y_hi := top - body - MatchFraming.EDGE_UPRIGHT + half.y
	return Vector2(
		clampf(centre.x, minf(x_lo, x_hi), maxf(x_lo, x_hi)),
		clampf(centre.y, minf(y_lo, y_hi), maxf(y_lo, y_hi))
	)


## What must be on screen: every living fighter inside the playable window,
## and the spot the last body fell on while the kill holds.
func _subjects() -> PackedVector2Array:
	var out := PackedVector2Array()
	for slot: int in 2:
		if fight.is_fighter_alive(slot) and _inside(fight.fighter_position(slot).x):
			out.append(fight.fighter_position(slot))
	if framing.holding():
		out.append(_fallen)
	return out


## Both alive and both in the window: the only time the frame may come close.
func _together() -> bool:
	for slot: int in 2:
		if not fight.is_fighter_alive(slot) or not _inside(fight.fighter_position(slot).x):
			return false
	return true


func _inside(x: float) -> bool:
	return x >= fight.scroll - MatchFraming.EDGE \
		and x <= fight.scroll + fight.strip.zone_width() + MatchFraming.EDGE


## The horizontal extent the view leans toward: the subjects, plus where a
## fighter who is down will come back and where one outside the window stands.
## Returned as (left, right).
func _leaning(subjects: PackedVector2Array) -> Vector2:
	var points := subjects.duplicate()
	if framing.holding():
		return _extent(points) # the kill first; the lean waits for it
	for slot: int in 2:
		if not fight.is_fighter_alive(slot):
			points.append(fight.respawn_plan(slot)["position"] as Vector2)
		elif not _inside(fight.fighter_position(slot).x):
			points.append(fight.fighter_position(slot))
	if points.is_empty():
		var middle := fight.scroll + fight.strip.zone_width() * 0.5
		return Vector2(middle, middle)
	return _extent(points)


static func _extent(points: PackedVector2Array) -> Vector2:
	var left := points[0].x
	var right := left
	for at: Vector2 in points:
		left = minf(left, at.x)
		right = maxf(right, at.x)
	return Vector2(left, right)


## The scale MatchFraming answers, as a Camera2D zoom.
##
## `framing_width` overrides it with a fixed world width, for comparing
## framings side by side, at a whole number of screen pixels per texel.
func _apply_zoom(delta: float) -> void:
	var view := _view_size()
	var stretch := _stretch()
	if framing_width > 0.0:
		if stretch <= 0.0:
			zoom = Vector2.ONE * (view.x / framing_width)
			return
		var fitted := maxf(1.0, floorf(view.x * stretch / framing_width))
		zoom = Vector2.ONE * (fitted / stretch)
		return
	_measure()
	if delta > 0.0:
		framing.update(delta, _subjects(), _together())
	zoom = Vector2.ONE * framing.zoom()


## Tells the framing what screen it is framing for.
func _measure() -> void:
	var stretch := pixels_per_unit if pixels_per_unit > 0.0 else _stretch()
	if stretch <= 0.0:
		stretch = 1.0
	framing.per_unit = stretch
	framing.screen = screen_pixels if screen_pixels.x > 0.0 else _view_size() * stretch
	framing.body = DuelTuning.default().body_height


## Screen pixels per virtual unit: the canvas_items stretch factor. Zero when
## there is no window to measure, as under a headless test.
func _stretch() -> float:
	if pixels_per_unit > 0.0:
		return pixels_per_unit
	var window := get_window()
	var view := _view_size()
	if window == null or view.y <= 0.0 or window.size.y <= 0:
		return 0.0
	return float(window.size.y) / view.y


## A slow, irregular sway: incommensurate sines, so it never visibly repeats
## and never jerks. Unit amplitude, roughly.
func _rumble() -> Vector2:
	var t := _rumble_time
	return Vector2(
		sin(t * 9.1) * 0.6 + sin(t * 23.7) * 0.4,
		sin(t * 7.3 + 1.7) * 0.6 + sin(t * 19.1 + 0.4) * 0.4
	)


## A camera position on the screen's pixel grid. With a whole number of screen
## pixels per texel, texel edges then fall on pixel edges too: without this the
## view sits a fraction of a pixel off, and one row of every texel band renders
## a pixel taller than the rest.
func _snapped(at: Vector2) -> Vector2:
	var per_world := zoom.x * _stretch()
	if per_world <= 0.0:
		return at
	return (at * per_world).round() / per_world


func _view_size() -> Vector2:
	if screen_pixels.x > 0.0 and pixels_per_unit > 0.0:
		return screen_pixels / pixels_per_unit
	var viewport := get_viewport()
	if viewport == null:
		return Vector2(320.0, 180.0)
	var size := viewport.get_visible_rect().size
	return size if size.x > 1.0 and size.y > 1.0 else Vector2(320.0, 180.0)


## The world the view shows now, in world pixels, before shake: worked out
## from the camera's own position and limits, as the viewport will place it,
## so it can be asked between frames and with no window.
func view_rect() -> Rect2:
	var seen := _view_size() / zoom
	var centre := global_position
	centre.x = clampf(centre.x, limit_left + seen.x * 0.5,
		maxf(limit_left + seen.x * 0.5, limit_right - seen.x * 0.5))
	centre.y = clampf(centre.y, limit_top + seen.y * 0.5,
		maxf(limit_top + seen.y * 0.5, limit_bottom - seen.y * 0.5))
	return Rect2(centre - seen * 0.5, seen)


## Which zones the view can see, for the gore layer's culling.
func visible_zones() -> PackedInt32Array:
	var half := _view_size().x / zoom.x * 0.5
	var first := fight.strip.zone_of_x(global_position.x - half)
	var last := fight.strip.zone_of_x(global_position.x + half)
	var out := PackedInt32Array()
	for zone: int in range(first, last + 1):
		out.append(zone)
	return out
