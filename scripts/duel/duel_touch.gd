class_name DuelTouchGuard
extends Control
## One more on-screen button: THROW, in the match. It was GUARD in the round
## duel this file was first written for, hence its class name.
##
## scripts/ui/touch_controls.gd puts a stick on the left and JUMP and SWORD on
## the right, and knows nothing about blocking. A duel on a phone with no block
## button would be a worse game than the same duel on a keyboard, so this adds
## the third button beside the other two rather than editing that file.
##
## Like the controls it sits next to, the press goes straight into the input
## map, so the duel never learns that touch exists — it reads the same "guard"
## action a keyboard sets. And like them, it only appears on a touch device.
##
## The tug-of-war match has no guard -- the stances replaced it -- and the bit
## the guard used is the throw now, so the same button serves both: `action`
## and `glyph` are set by the scene that places it.

const RADIUS := 18.0
const HIT_PADDING := 8.0

## The input action the button presses: "guard" or "throw".
@export var action := "guard"
## What the button shows: "shield" or "throw".
@export var glyph := "shield"

var _at := Vector2.ZERO
var _held := -1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = OS.has_feature("mobile")
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	var view := size
	if view == Vector2.ZERO:
		view = get_viewport().get_visible_rect().size
	# The safe area is reported in physical pixels; convert to canvas units,
	# the same way TouchControls does.
	var window := Vector2(DisplayServer.window_get_size())
	var scale := view.x / maxf(1.0, window.x)
	var safe := DisplayServer.get_display_safe_area()
	var inset_right := (window.x - (safe.position.x + safe.size.x)) * scale
	var inset_bottom := (window.y - (safe.position.y + safe.size.y)) * scale

	# Up and to the left of JUMP, clear of SWORD.
	_at = Vector2(view.x - inset_right - 52.0, view.y - inset_bottom - 78.0)
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventScreenTouch):
		return
	var touch := event as InputEventScreenTouch
	if touch.pressed:
		if touch.position.distance_to(_at) <= RADIUS + HIT_PADDING:
			_held = touch.index
			Input.action_press(action)
			queue_redraw()
	elif touch.index == _held:
		_held = -1
		Input.action_release(action)
		queue_redraw()


func _draw() -> void:
	var down := _held != -1
	draw_circle(_at, RADIUS, Palette.with_alpha(Palette.INK, 0.3 if down else 0.18))
	draw_arc(_at, RADIUS, 0.0, TAU, 24,
		Palette.with_alpha(Palette.LIGHT_SOFT, 0.8 if down else 0.45), 1.0)
	if glyph == "throw":
		_draw_throw_mark(down)
		return
	# A little shield, so the button needs no label to be understood.
	var w := 6.0
	var h := 8.0
	draw_colored_polygon(PackedVector2Array([
		_at + Vector2(-w, -h), _at + Vector2(w, -h),
		_at + Vector2(w, h * 0.1), _at + Vector2(0.0, h),
		_at + Vector2(-w, h * 0.1),
	]), Palette.with_alpha(Palette.STEEL, 0.95 if down else 0.6))


func _exit_tree() -> void:
	if _held != -1:
		Input.action_release(action)
		_held = -1


## A sword flying point-first, with two speed lines behind it: the throw,
## readable without a label at thumb size.
func _draw_throw_mark(down: bool) -> void:
	var steel := Palette.with_alpha(Palette.STEEL, 0.95 if down else 0.6)
	var light := Palette.with_alpha(Palette.LIGHT_SOFT, 0.9 if down else 0.5)
	var dir := Vector2(1.0, -0.55).normalized()
	var side := Vector2(-dir.y, dir.x)
	var tip := _at + dir * 8.0
	var hilt := _at - dir * 4.0
	draw_colored_polygon(PackedVector2Array([
		hilt + side * 1.1, tip, hilt - side * 1.1,
	]), steel)
	draw_line(hilt + side * 3.0, hilt - side * 3.0, light, 1.4)
	for k: int in 2:
		var back := hilt - dir * (3.0 + 2.5 * float(k)) + side * (2.5 - 5.0 * float(k))
		draw_line(back, back - dir * 4.0, light, 1.0)
