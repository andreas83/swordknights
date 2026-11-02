class_name Relic
extends Node2D
## A collectible shard — the level's optional objective.

signal collected()

const SIZE := Vector2(10.0, 12.0)

var _time: float = 0.0


func bounds() -> Rect2:
	return Rect2(global_position - Vector2(SIZE.x * 0.5, 16.0), SIZE)


func collect() -> void:
	collected.emit()
	queue_free()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var cy := -10.0 + sin(_time * 2.4) * 1.6
	var r := 4.5
	draw_colored_polygon(PackedVector2Array([
		Vector2(0.0, cy - r), Vector2(r * 0.72, cy), Vector2(0.0, cy + r), Vector2(-r * 0.72, cy),
	]), Palette.LIGHT_SOFT)
	draw_colored_polygon(PackedVector2Array([
		Vector2(0.0, cy - r), Vector2(r * 0.72, cy), Vector2(0.0, cy),
	]), Palette.PAPER)
