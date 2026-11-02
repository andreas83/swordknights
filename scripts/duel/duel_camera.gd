class_name DuelCamera
extends Camera2D
## Keeps both duellists on screen.
##
## A duel has no protagonist, so there is nothing to follow: the camera frames
## the pair. It centres on the box they occupy and zooms out until that box
## fits, down to the point where the whole arena is visible — which is the floor
## on the zoom, and the reason levels/arena_01.txt has as much sky as it does.
##
## Nothing here runs in _physics_process. The duel steps at a fixed 60 Hz and
## may step twice in one frame while a client reconciles; the camera should
## glide at the display's rate regardless, so it reads positions in _process.

## Breathing room around the two bodies, in world pixels.
const MARGIN := Vector2(72.0, 56.0)
const ZOOM_SMOOTHING := 4.5
const MOVE_SMOOTHING := 8.0

var duel: Duel

var _min_zoom := 0.5
var _shake_time := 0.0
var _shake_magnitude := 0.0
var _rng := RandomNumberGenerator.new()


func setup(fight: Duel) -> void:
	duel = fight
	ignore_rotation = true
	position_smoothing_enabled = false
	rotation_smoothing_enabled = false

	var arena := fight.arena_size()
	limit_left = 0
	limit_top = 0
	limit_right = int(arena.x)
	limit_bottom = int(arena.y)

	# Zooming out further than this would show the void past the edge of the
	# arena, which Camera2D's limits cannot clamp away.
	var view := _view_size()
	_min_zoom = maxf(view.x / arena.x, view.y / arena.y)

	var target := _frame_box()
	zoom = Vector2.ONE * _zoom_for(target)
	global_position = target.get_center()
	reset_smoothing()


func shake(magnitude: float, duration: float = 0.25) -> void:
	_shake_magnitude = maxf(_shake_magnitude, magnitude)
	_shake_time = maxf(_shake_time, duration)


func _process(delta: float) -> void:
	if duel == null or duel.players.size() < 2:
		return

	var target := _frame_box()
	var want_zoom := _zoom_for(target)
	var current := zoom.x
	var next := lerpf(current, want_zoom, 1.0 - exp(-ZOOM_SMOOTHING * delta))
	zoom = Vector2.ONE * next

	global_position = global_position.lerp(
		target.get_center(), 1.0 - exp(-MOVE_SMOOTHING * delta)
	)

	if _shake_time > 0.0:
		_shake_time -= delta
		# Scaled by the zoom so a shake reads the same however far out we are.
		var amount := _shake_magnitude * clampf(_shake_time / 0.25, 0.0, 1.0) / next
		offset = Vector2(
			_rng.randf_range(-amount, amount), _rng.randf_range(-amount, amount)
		)
	else:
		offset = Vector2.ZERO
		_shake_magnitude = 0.0


## The box the camera wants to show: both bodies plus margin.
func _frame_box() -> Rect2:
	var box: Rect2 = duel.players[0].body_rect().merge(duel.players[1].body_rect())
	return box.grow_individual(MARGIN.x, MARGIN.y, MARGIN.x, MARGIN.y)


func _zoom_for(box: Rect2) -> float:
	var view := _view_size()
	var fit := minf(view.x / maxf(1.0, box.size.x), view.y / maxf(1.0, box.size.y))
	return clampf(fit, _min_zoom, 1.0)


func _view_size() -> Vector2:
	var viewport := get_viewport()
	if viewport == null:
		return Vector2(320.0, 180.0)
	var size := viewport.get_visible_rect().size
	return size if size.x > 1.0 and size.y > 1.0 else Vector2(320.0, 180.0)
