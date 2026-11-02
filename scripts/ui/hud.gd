class_name Hud
extends Control
## Health crescents, relic tally, the level title card and the pause/complete
## overlay. Drawn rather than built from Control nodes so it shares the exact
## palette and shapes as the rest of the game.

const TITLE_HOLD := 2.6
const TITLE_FADE := 0.9

var health: int = Tuning.MAX_HEALTH
var max_health: int = Tuning.MAX_HEALTH
var relics: int = 0
var relics_total: int = 0

var _title: String = ""
var _title_time: float = 999.0
var _overlay_title: String = ""
var _overlay_subtitle: String = ""

var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font


func update_model(hp: int, hp_max: int, got: int, total: int) -> void:
	health = hp
	max_health = hp_max
	relics = got
	relics_total = total
	queue_redraw()


func show_title(level_name: String) -> void:
	_title = level_name.to_upper().replace("_", " ")
	_title_time = 0.0


func set_overlay(title: String, subtitle: String) -> void:
	_overlay_title = title
	_overlay_subtitle = subtitle
	queue_redraw()


func _process(delta: float) -> void:
	if _title_time <= TITLE_HOLD + TITLE_FADE:
		_title_time += delta
		queue_redraw()


func _draw() -> void:
	var view := size
	var x := 10.0
	var y := 10.0

	for i: int in max_health:
		var cx := x + i * 13.0
		draw_circle(Vector2(cx, y), 4.6, Palette.with_alpha(Palette.INK, 0.35))
		if i < health:
			draw_circle(Vector2(cx, y), 4.0, Palette.LIGHT_SOFT)
			draw_circle(Vector2(cx + 1.4, y - 0.8), 3.1, Palette.with_alpha(Palette.INK, 0.55))
		else:
			draw_arc(Vector2(cx, y), 4.0, 0.0, TAU, 16,
				Palette.with_alpha(Palette.LIGHT_SOFT, 0.4), 1.0)

	if relics_total > 0:
		var rx := x + max_health * 13.0 + 8.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(rx, y - 4.5), Vector2(rx + 3.2, y),
			Vector2(rx, y + 4.5), Vector2(rx - 3.2, y),
		]), Palette.LIGHT)
		_text("%d/%d" % [relics, relics_total], Vector2(rx + 7.0, y + 3.0), 8, Palette.PAPER)

	if _title != "" and _title_time <= TITLE_HOLD + TITLE_FADE:
		var alpha := clampf(1.0 - (_title_time - TITLE_HOLD) / TITLE_FADE, 0.0, 1.0)
		_centered(_title, view.x * 0.5, view.y * 0.33, 15,
			Palette.with_alpha(Palette.PAPER, alpha), 4.0)
		draw_rect(Rect2(view.x * 0.5 - 34.0, view.y * 0.33 + 10.0, 68.0, 1.0),
			Palette.with_alpha(Palette.LIGHT_SOFT, alpha * 0.8))

	if _overlay_title != "":
		draw_rect(Rect2(Vector2.ZERO, view), Palette.with_alpha(Palette.INK, 0.55))
		_centered(_overlay_title, view.x * 0.5, view.y * 0.5 - 8.0, 20, Palette.PAPER, 6.0)
		_centered(_overlay_subtitle, view.x * 0.5, view.y * 0.5 + 14.0, 7,
			Palette.with_alpha(Palette.LIGHT_SOFT, 0.8), 1.0)


func _text(value: String, at: Vector2, font_size: int, color: Color) -> void:
	draw_string(_font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## Draws centred text with letter spacing, which the default draw_string lacks.
func _centered(value: String, cx: float, cy: float, font_size: int,
		color: Color, tracking: float) -> void:
	if value == "":
		return
	var widths: Array[float] = []
	var total := 0.0
	for i: int in value.length():
		var w := _font.get_string_size(
			value[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
		).x
		widths.append(w)
		total += w + tracking
	total -= tracking

	var pen := cx - total * 0.5
	for i: int in value.length():
		draw_string(_font, Vector2(pen, cy + font_size * 0.35), value[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		pen += widths[i] + tracking
