class_name LocalInput
extends PlayerInput
## Reads the Godot input map. The action suffix lets a second local player use
## a parallel set of bindings ("move_left_p2" and so on) without duplicating
## any logic.

var suffix: String = ""


func _init(action_suffix: String = "") -> void:
	suffix = action_suffix


func poll() -> void:
	var bits := 0
	if Input.is_action_pressed("move_left" + suffix): bits |= BIT_LEFT
	if Input.is_action_pressed("move_right" + suffix): bits |= BIT_RIGHT
	if Input.is_action_pressed("move_up" + suffix): bits |= BIT_UP
	if Input.is_action_pressed("move_down" + suffix): bits |= BIT_DOWN
	if Input.is_action_pressed("jump" + suffix): bits |= BIT_JUMP
	if Input.is_action_pressed("attack" + suffix): bits |= BIT_ATTACK
	if Input.is_action_pressed("walk" + suffix): bits |= BIT_WALK
	apply_bits(bits)
