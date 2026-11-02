class_name GameCamera
extends Camera2D
## Follow camera with a dead zone, facing look-ahead and screen shake.
##
## Prince-of-Persia-style rooms want a camera that is mostly still, so the dead
## zone (Godot's drag margins) means small hops and turn-arounds do not shove
## the whole screen around. Vertical follow tracks the last grounded height so
## jumping does not pan the view.

@export var look_ahead: float = 34.0
@export var look_ahead_smoothing: float = 6.0
@export var vertical_smoothing: float = 7.0

var target: Player

var _look_ahead_current: float = 0.0
var _anchor_y: float = 0.0
var _shake_time: float = 0.0
var _shake_magnitude: float = 0.0


func _ready() -> void:
	position_smoothing_enabled = true
	position_smoothing_speed = 9.0
	drag_horizontal_enabled = true
	drag_left_margin = 0.18
	drag_right_margin = 0.18
	drag_vertical_enabled = false
	ignore_rotation = true


func setup(player: Player, world_size: Vector2) -> void:
	target = player
	limit_left = 0
	limit_top = 0
	limit_right = int(world_size.x)
	limit_bottom = int(world_size.y)
	_anchor_y = player.position.y
	_look_ahead_current = player.facing * look_ahead
	global_position = Vector2(player.position.x + _look_ahead_current, player.position.y)
	reset_smoothing()


func shake(magnitude: float, duration: float = 0.25) -> void:
	_shake_magnitude = maxf(_shake_magnitude, magnitude)
	_shake_time = maxf(_shake_time, duration)


func _physics_process(delta: float) -> void:
	if target == null:
		return

	_look_ahead_current = lerpf(
		_look_ahead_current, target.facing * look_ahead, 1.0 - exp(-look_ahead_smoothing * delta)
	)
	if target.is_on_floor():
		_anchor_y = target.position.y

	var desired := Vector2(target.position.x + _look_ahead_current, _anchor_y)
	global_position.x = desired.x
	global_position.y = lerpf(
		global_position.y, desired.y, 1.0 - exp(-vertical_smoothing * delta)
	)

	if _shake_time > 0.0:
		_shake_time -= delta
		var amount := _shake_magnitude * clampf(_shake_time / 0.25, 0.0, 1.0)
		offset = Vector2(randf_range(-amount, amount), randf_range(-amount, amount))
	else:
		offset = Vector2.ZERO
		_shake_magnitude = 0.0
