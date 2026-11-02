class_name ExitDoor
extends Node2D
## The arched doorway that ends the level.

const WIDTH := 16.0
const HEIGHT := 32.0

var is_open := false:
	set(value):
		is_open = value
		queue_redraw()

var _time: float = 0.0


func bounds() -> Rect2:
	return Rect2(global_position - Vector2(WIDTH * 0.5, HEIGHT), Vector2(WIDTH, HEIGHT))


func _process(delta: float) -> void:
	_time += delta
	if is_open:
		queue_redraw()


func _draw() -> void:
	var x := -WIDTH * 0.5
	var y := -HEIGHT
	_arch(x - 2.0, y - 2.0, WIDTH + 4.0, HEIGHT + 2.0, Palette.SHADOW_DEEP)
	_arch(x, y, WIDTH, HEIGHT, Palette.LIGHT_SOFT if is_open else Palette.INK)
	if is_open:
		_arch(x + 2.0, y + 3.0, WIDTH - 4.0, HEIGHT - 3.0, Palette.PAPER)
		draw_circle(Vector2(0.0, y + HEIGHT * 0.5), 5.0 + sin(_time * 3.0) * 1.5, Palette.PAPER)
	else:
		draw_rect(Rect2(-0.5, y + 6.0, 1.0, HEIGHT - 10.0), Palette.SHADOW_WARM)
		draw_circle(Vector2(-2.5, y + HEIGHT * 0.55), 1.2, Palette.LIGHT_WARM)
		draw_circle(Vector2(2.5, y + HEIGHT * 0.55), 1.2, Palette.LIGHT_WARM)


func _arch(x: float, y: float, w: float, h: float, color: Color) -> void:
	var radius := minf(w * 0.5, h)
	var points := PackedVector2Array([Vector2(x, y + h), Vector2(x, y + radius)])
	for i: int in range(13):
		var a := PI - PI * float(i) / 12.0
		points.append(Vector2(x + w * 0.5 + cos(a) * radius, y + radius - sin(a) * radius))
	points.append(Vector2(x + w, y + h))
	draw_colored_polygon(points, color)
