class_name TouchControls
extends CanvasLayer
## On-screen controls for touch devices.
##
## The left half is a floating virtual stick: wherever the thumb lands becomes
## the origin, which beats a fixed pad on phones of every size. The right half
## holds the action buttons. Touches are tracked per index, so holding a
## direction while tapping jump works.
##
## Presses are injected straight into the input map, so gameplay code never
## learns that touch exists — the same `Input.is_action_pressed("jump")` works
## for a keyboard, a gamepad and a thumb.

const STICK_RADIUS := 30.0
const STICK_DEADZONE := 7.0
const VERTICAL_DEADZONE := 14.0
const HIT_PADDING := 8.0

var _buttons: Array[Dictionary] = []
var _held: Dictionary = {} # touch index -> action name
var _stick_index := -1
var _stick_origin := Vector2.ZERO
var _stick_point := Vector2.ZERO
var _active_directions: Array[String] = []

@onready var _surface: Control = $Surface


func _ready() -> void:
	layer = 50
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	var view := _surface.size
	if view == Vector2.ZERO:
		view = get_viewport().get_visible_rect().size
	# The safe area is reported in physical pixels; convert to our canvas units.
	var window := Vector2(DisplayServer.window_get_size())
	var scale := view.x / maxf(1.0, window.x)
	var safe := DisplayServer.get_display_safe_area()
	var inset_right := (window.x - (safe.position.x + safe.size.x)) * scale
	var inset_bottom := (window.y - (safe.position.y + safe.size.y)) * scale
	var inset_top := safe.position.y * scale

	var right := view.x - inset_right
	var bottom := view.y - inset_bottom

	_buttons = [
		{"action": "jump", "label": "JUMP", "at": Vector2(right - 40.0, bottom - 38.0), "r": 24.0},
		{"action": "attack", "label": "SWORD", "at": Vector2(right - 88.0, bottom - 26.0), "r": 19.0},
		{"action": "pause", "label": "II", "at": Vector2(right - 16.0, inset_top + 16.0), "r": 11.0},
	]
	_surface.queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_on_drag(event as InputEventScreenDrag)
	elif event is InputEventKey or event is InputEventJoypadButton:
		if _surface.visible:
			_surface.visible = false
			_release_all()


func _on_touch(event: InputEventScreenTouch) -> void:
	var point := _to_canvas(event.position)
	if event.pressed:
		_surface.visible = true
		var button := _button_at(point)
		if not button.is_empty():
			_held[event.index] = button["action"]
			_press(button["action"])
		elif _stick_index < 0 and point.x < _surface.size.x * 0.55:
			_stick_index = event.index
			_stick_origin = point
			_stick_point = point
	else:
		if _held.has(event.index):
			var action: String = _held[event.index]
			_held.erase(event.index)
			if not _held.values().has(action):
				_release(action)
		if _stick_index == event.index:
			_stick_index = -1
			_release_directions()
	_surface.queue_redraw()


func _on_drag(event: InputEventScreenDrag) -> void:
	if _stick_index != event.index:
		return
	_stick_point = _to_canvas(event.position)
	_apply_stick()
	_surface.queue_redraw()


func _apply_stick() -> void:
	var delta := _stick_point - _stick_origin
	var wanted: Array[String] = []
	if delta.x < -STICK_DEADZONE:
		wanted.append("move_left")
	elif delta.x > STICK_DEADZONE:
		wanted.append("move_right")
	# Vertical needs a bigger push so running does not trigger ladders.
	if delta.y < -VERTICAL_DEADZONE:
		wanted.append("move_up")
	elif delta.y > VERTICAL_DEADZONE:
		wanted.append("move_down")
	# A small push walks, a full push runs.
	if absf(delta.x) > STICK_DEADZONE and absf(delta.x) < STICK_RADIUS * 0.55:
		wanted.append("walk")

	for action: String in _active_directions:
		if not wanted.has(action):
			_release(action)
	for action: String in wanted:
		if not _active_directions.has(action):
			_press(action)
	_active_directions = wanted


func _release_directions() -> void:
	for action: String in _active_directions:
		_release(action)
	_active_directions.clear()


func _release_all() -> void:
	_release_directions()
	for action: String in _held.values():
		_release(action)
	_held.clear()
	_stick_index = -1


func _press(action: String) -> void:
	if InputMap.has_action(action):
		Input.action_press(action)


func _release(action: String) -> void:
	if InputMap.has_action(action):
		Input.action_release(action)


func _button_at(point: Vector2) -> Dictionary:
	for button: Dictionary in _buttons:
		var r: float = button["r"] + HIT_PADDING
		if point.distance_squared_to(button["at"]) <= r * r:
			return button
	return {}


func _to_canvas(screen_position: Vector2) -> Vector2:
	return screen_position * (_surface.size.x / maxf(1.0, DisplayServer.window_get_size().x))


func draw_surface() -> void:
	var font := ThemeDB.fallback_font
	for button: Dictionary in _buttons:
		var at: Vector2 = button["at"]
		var r: float = button["r"]
		var held: bool = Input.is_action_pressed(button["action"])
		_surface.draw_circle(at, r, Palette.with_alpha(Palette.INK, 0.4 if held else 0.22))
		_surface.draw_arc(at, r, 0.0, TAU, 32,
			Palette.with_alpha(Palette.LIGHT_SOFT, 0.85 if held else 0.45), 1.2)
		var label: String = button["label"]
		var font_size: int = 7 if r > 14.0 else 6
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		_surface.draw_string(font, at + Vector2(-width * 0.5, font_size * 0.35), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
			Palette.with_alpha(Palette.PAPER, 1.0 if held else 0.7))

	if _stick_index >= 0:
		var delta := _stick_point - _stick_origin
		var knob := _stick_origin + delta.limit_length(STICK_RADIUS)
		_surface.draw_circle(_stick_origin, STICK_RADIUS, Palette.with_alpha(Palette.INK, 0.18))
		_surface.draw_circle(knob, 11.0, Palette.with_alpha(Palette.LIGHT_SOFT, 0.55))
