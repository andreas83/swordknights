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
	global_position = _target()
	reset_smoothing()


func shake(magnitude: float, duration: float = 0.25) -> void:
	_shake_magnitude = maxf(_shake_magnitude, magnitude)
	_shake_time = maxf(_shake_time, duration)


func _process(delta: float) -> void:
	if fight == null or fight.strip == null:
		return
	_apply_zoom()

	var want := _target()
	global_position = Vector2(
		lerpf(global_position.x, want.x, 1.0 - exp(-FOLLOW * delta)),
		lerpf(global_position.y, want.y, 1.0 - exp(-VERTICAL_FOLLOW * delta))
	)

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


## Exactly one zone across, whatever the window's aspect. The world width is
## fixed and the view's height follows from it, rather than the other way round:
## the horizontal is what the mode's distances are written in.
func _apply_zoom() -> void:
	var scale := _view_size().x / fight.strip.zone_width()
	zoom = Vector2(scale, scale)


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
