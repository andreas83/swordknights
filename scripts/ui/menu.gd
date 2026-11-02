class_name MenuScene
extends Control
## Mode select.
##
## Navigated with up/down and confirmed with jump, so the keyboard, a gamepad
## and the on-screen touch controls all work without any extra plumbing.

const ROW_HEIGHT := 26.0
const REPEAT_DELAY := 0.26

var _index := 0
var _time := 0.0
var _repeat := 0.0
var _modes: Array[Dictionary] = []
var _available: Array[Dictionary] = []
var _font: Font

@onready var _sky: ParallaxSky = $Sky/ParallaxSky


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font
	_modes = ModeRegistry.modes()
	_available = ModeRegistry.available()
	_sky.seed_value = 0xa17e5


func _process(delta: float) -> void:
	_time += delta
	_repeat = maxf(0.0, _repeat - delta)
	queue_redraw()

	if _available.is_empty():
		return

	var axis := Input.get_axis("move_up", "move_down")
	if absf(axis) > 0.5 and is_zero_approx(_repeat):
		_index = wrapi(_index + signi(int(signf(axis))), 0, _available.size())
		_repeat = REPEAT_DELAY
		AudioDirector.play("ui_move")
	elif absf(axis) <= 0.5:
		_repeat = 0.0

	if Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("attack"):
		var scene: String = _available[_index]["scene"]
		if ResourceLoader.exists(scene):
			AudioDirector.play("ui_confirm")
			get_tree().change_scene_to_file(scene)
		else:
			AudioDirector.play("ui_back")
			push_error("mode '%s' points at a missing scene: %s"
				% [_available[_index]["id"], scene])


func _draw() -> void:
	var view := size
	draw_rect(Rect2(Vector2.ZERO, view), Palette.with_alpha(Palette.INK, 0.45))

	var cx := view.x * 0.5
	_centered("SWORDKNIGHTS", cx, view.y * 0.16, 22, Palette.PAPER, 7.0)
	draw_rect(Rect2(cx - 52.0, view.y * 0.16 + 14.0, 104.0, 1.0),
		Palette.with_alpha(Palette.LIGHT_SOFT, 0.7))

	var list_top := view.y * 0.42
	var selected_id: String = _available[_index]["id"] if not _available.is_empty() else ""

	for position: int in _modes.size():
		var mode: Dictionary = _modes[position]
		var y := list_top + position * ROW_HEIGHT
		var enabled: bool = mode.get("available", true)
		var selected: bool = enabled and mode["id"] == selected_id

		if selected:
			var pulse := 0.18 + sin(_time * 4.0) * 0.05
			draw_rect(Rect2(cx - 86.0, y - 10.0, 172.0, 22.0),
				Palette.with_alpha(Palette.LIGHT_SOFT, pulse))
			draw_colored_polygon(PackedVector2Array([
				Vector2(cx - 94.0, y - 4.0), Vector2(cx - 88.0, y), Vector2(cx - 94.0, y + 4.0),
			]), Palette.LIGHT)

		var color := Palette.with_alpha(Palette.PAPER, 0.3)
		if enabled:
			color = Palette.PAPER if selected else Palette.with_alpha(Palette.PAPER, 0.72)

		_centered(String(mode["title"]).to_upper(), cx, y - 3.0, 10, color, 2.4)
		var sub: String = String(mode["subtitle"])
		if not enabled:
			sub += "  —  COMING SOON"
		_centered(sub.to_upper(), cx, y + 7.0, 6,
			Palette.with_alpha(Palette.LIGHT_SOFT, 0.65 if enabled else 0.25), 0.8)

	_centered("UP / DOWN TO CHOOSE   ·   JUMP TO BEGIN", cx, view.y - 16.0, 6,
		Palette.with_alpha(Palette.LIGHT_SOFT, 0.5), 1.4)


func _centered(value: String, cx: float, cy: float, font_size: int,
		color: Color, tracking: float) -> void:
	if value == "":
		return
	var widths: Array[float] = []
	var total := 0.0
	for i: int in value.length():
		var w := _font.get_string_size(value[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		widths.append(w)
		total += w + tracking
	total -= tracking

	var pen := cx - total * 0.5
	for i: int in value.length():
		draw_string(_font, Vector2(pen, cy + font_size * 0.35), value[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		pen += widths[i] + tracking
