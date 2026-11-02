class_name Torch
extends Node2D
## Pure decoration: a wall torch whose flicker sells the hard duotone light.

var _phase: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	_phase = fmod(global_position.x * 0.37 + global_position.y * 0.11, PI)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var top := -14.0
	var flicker := 0.72 + sin(_time * 9.0 + _phase) * 0.12 + sin(_time * 23.0 + _phase) * 0.06

	draw_circle(Vector2(0.0, top + 2.0), 11.0 * flicker, Palette.with_alpha(Palette.LIGHT, 0.10))
	draw_circle(Vector2(0.0, top + 2.0), 6.0 * flicker, Palette.with_alpha(Palette.LIGHT_SOFT, 0.16))
	draw_rect(Rect2(-1.0, top + 4.0, 2.0, 10.0), Palette.SHADOW_DEEP)
	draw_colored_polygon(PackedVector2Array([
		Vector2(0.0, top - 4.0 * flicker), Vector2(2.4, top + 3.0),
		Vector2(0.0, top + 5.0), Vector2(-2.4, top + 3.0),
	]), Palette.LIGHT_SOFT)
	draw_colored_polygon(PackedVector2Array([
		Vector2(0.0, top - flicker), Vector2(1.2, top + 3.0), Vector2(-1.2, top + 3.0),
	]), Palette.PAPER)
