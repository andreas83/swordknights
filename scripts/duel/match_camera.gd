class_name MatchCamera
extends Camera2D
## The tug-of-war camera. One zone wide, and it decides nothing.
##
## NOT scripts/duel/duel_camera.gd, and nothing to do with
## scripts/render/game_camera.gd. The round duel's camera frames a pair in a
## fixed arena and zooms to fit them; the adventure's follows a protagonist.
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
## FRAMED ON TWO FIGHTERS AT OPPOSITE ENDS OF A ZONE
## Solved by construction rather than by zooming. The view is exactly one zone
## wide and the simulation holds both fighters inside that window, so they are
## both on screen at every moment of the match without the zoom ever moving. A
## breathing zoom would also make "1.5 screen widths" ambiguous, and that number
## has to mean the same thing on a phone and on a desktop.
##
## Nothing here runs in _physics_process. The match steps at a fixed 60 Hz and
## may step twice in one frame while a client reconciles; the camera glides at
## the display's rate regardless.

## How fast the view closes on the window. High enough to track the rope
## honestly, loose enough to pan rather than cut when initiative changes hands
## and the window re-centres on the new leader.
const FOLLOW := 14.0
const VERTICAL_FOLLOW := 6.0

var fight: DuelMatch

## The world width the view should frame, in pixels. Zero frames one zone, which
## is what the mode is designed around. Anything else is a comparison: 320 shows
## the duel at the adventure's scale, for deciding how wide a zone should be.
var framing_width := 0.0

## The follow position before it is snapped to whole screen pixels. Snapping the
## smoothed value itself would stall the lerp a fraction of a pixel short.
var _smooth := Vector2.ZERO
var _shake_time := 0.0
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

	_apply_zoom()
	_smooth = _target()
	global_position = _snapped(_smooth)
	reset_smoothing()


func shake(magnitude: float, duration: float = 0.25) -> void:
	_shake_magnitude = maxf(_shake_magnitude, magnitude)
	_shake_time = maxf(_shake_time, duration)


func _process(delta: float) -> void:
	if fight == null or fight.strip == null:
		return
	_apply_zoom()

	var want := _target()
	_smooth = Vector2(
		lerpf(_smooth.x, want.x, 1.0 - exp(-FOLLOW * delta)),
		lerpf(_smooth.y, want.y, 1.0 - exp(-VERTICAL_FOLLOW * delta))
	)
	global_position = _snapped(_smooth)

	if _shake_time > 0.0:
		_shake_time -= delta
		# Scaled by the zoom so a shake reads the same whatever the aspect.
		var amount := _shake_magnitude * clampf(_shake_time / 0.25, 0.0, 1.0) / zoom.x
		offset = Vector2(
			_rng.randf_range(-amount, amount), _rng.randf_range(-amount, amount)
		)
	else:
		offset = Vector2.ZERO
		_shake_magnitude = 0.0


## The centre of the authoritative window, and a vertical framing of whatever
## the two fighters are doing inside it.
func _target() -> Vector2:
	var width := fight.strip.zone_width()
	var centre := fight.scroll + width * 0.5

	var view := _view_size() / zoom
	if view.x < width - 0.5:
		# Framed narrower than the window: follow the fighters inside it rather
		# than staring at its middle while they fight at one end.
		var mid := (fight.fighter_position(0).x + fight.fighter_position(1).x) * 0.5
		centre = clampf(mid, fight.scroll + view.x * 0.5,
			fight.scroll + width - view.x * 0.5)
	var high := fight.fighter_position(0).y
	var low := high
	for slot: int in 2:
		var y := fight.fighter_position(slot).y
		high = minf(high, y)
		low = maxf(low, y)
	# Their feet, lifted by a body, so heads are not against the top edge.
	var middle := (high + low) * 0.5 - 14.0
	var height := fight.strip.world_size().y
	var vertical := clampf(middle, view.y * 0.5, maxf(view.y * 0.5, height - view.y * 0.5))

	return Vector2(centre, vertical)


## One zone across, whatever the window's aspect, at a whole number of screen
## pixels per world pixel.
##
## The world width is fixed and the view's height follows from it, rather than
## the other way round: the horizontal is what the mode's distances are written
## in. But the exact fit is a fractional scale on most screens -- 3.75 screen
## pixels per texel on a 20:9 phone at 1080p -- and a fractional scale on
## nearest-filtered pixel art draws texels alternately three and four pixels
## wide, which shimmers as the view scrolls. So the scale is rounded DOWN to a
## whole number: every texel is the same size, and the view shows a little more
## than one zone rather than a little less. The window's walls are what bound
## the fight, not the screen's edge, so the extra margin costs nothing.
func _apply_zoom() -> void:
	var wanted := framing_width if framing_width > 0.0 else fight.strip.zone_width()
	var view := _view_size()
	var stretch := _stretch()
	if stretch <= 0.0:
		zoom = Vector2.ONE * (view.x / wanted)
		return
	var pixels := maxf(1.0, floorf(view.x * stretch / wanted))
	zoom = Vector2.ONE * (pixels / stretch)


## Screen pixels per virtual unit: the canvas_items stretch factor. Zero when
## there is no window to measure, as under a headless test.
func _stretch() -> float:
	var window := get_window()
	var view := _view_size()
	if window == null or view.y <= 0.0 or window.size.y <= 0:
		return 0.0
	return float(window.size.y) / view.y


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
	var viewport := get_viewport()
	if viewport == null:
		return Vector2(320.0, 180.0)
	var size := viewport.get_visible_rect().size
	return size if size.x > 1.0 and size.y > 1.0 else Vector2(320.0, 180.0)


## Which zones the view can see, for the gore layer's culling.
func visible_zones() -> PackedInt32Array:
	var width := fight.strip.zone_width()
	var first := fight.strip.zone_of_x(global_position.x - width * 0.5)
	var last := fight.strip.zone_of_x(global_position.x + width * 0.5)
	var out := PackedInt32Array()
	for zone: int in range(first, last + 1):
		out.append(zone)
	return out
