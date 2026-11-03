class_name Relic
extends Node2D
## A collectible shard — the level's optional objective.
##
## Taking one used to delete it on the spot: the shard was simply not there
## on the next frame, and the only sign anything had happened was a digit in
## the corner. Now the shard bursts -- a star of PAPER that opens and goes out,
## and six sparks thrown off along the diagonals -- for BURST_TIME, then the
## node goes. Hard pixels and flat tones throughout, the same vocabulary as a
## sword hit, because a pickup is a small impact.
##
## Taking one also gives back a heart, up to the maximum; at full health it is
## only a shard. That rule lives in `Game._on_relic_collected()`, not here: the
## relic does not know the prince exists, which is what lets a test collect
## one with nobody standing in it.
##
## A shard that has been taken is no longer collectable even while it is still
## on screen: `bounds()` goes empty and `collect()` does nothing, so standing
## in the burst cannot count it twice.

signal collected()

const SIZE := Vector2(10.0, 12.0)
const BURST_TIME := 0.32

var _time: float = 0.0
var _taken_at: float = -1.0


func bounds() -> Rect2:
	if is_taken():
		return Rect2()
	return Rect2(global_position - Vector2(SIZE.x * 0.5, 16.0), SIZE)


func is_taken() -> bool:
	return _taken_at >= 0.0


func collect() -> void:
	if is_taken():
		return
	_taken_at = _time
	collected.emit()


func _process(delta: float) -> void:
	_time += delta
	if is_taken() and _time - _taken_at >= BURST_TIME:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var cy := -10.0 + sin((_taken_at if is_taken() else _time) * 2.4) * 1.6
	if is_taken():
		_draw_burst(Vector2(0.0, roundf(cy)), (_time - _taken_at) / BURST_TIME)
		return
	var r := 4.5
	draw_colored_polygon(PackedVector2Array([
		Vector2(0.0, cy - r), Vector2(r * 0.72, cy), Vector2(0.0, cy + r), Vector2(-r * 0.72, cy),
	]), Palette.LIGHT_SOFT)
	draw_colored_polygon(PackedVector2Array([
		Vector2(0.0, cy - r), Vector2(r * 0.72, cy), Vector2(0.0, cy),
	]), Palette.PAPER)


func _draw_burst(at: Vector2, t: float) -> void:
	# The star: long on the vertical, opening fast and thinning out.
	var reach := roundf(lerpf(5.0, 11.0, sqrt(t)))
	var star := Palette.PAPER if t < 0.5 else Palette.LIGHT_SOFT
	if t < 0.8:
		draw_rect(Rect2(at.x - 0.5, at.y - reach, 1.0, reach * 2.0), star)
		draw_rect(Rect2(at.x - reach * 0.6, at.y - 0.5, reach * 1.2, 1.0), star)
	if t < 0.35:
		draw_rect(Rect2(at.x - 1.5, at.y - 1.5, 3.0, 3.0), Palette.PAPER)
	# Sparks along the diagonals, cooling from gold to orange as they fly.
	for i: int in 6:
		var angle := PI * 0.25 + PI * 0.5 * float(i % 4) + (0.3 if i >= 4 else 0.0)
		var flight := Vector2(cos(angle), sin(angle)) * lerpf(3.0, 13.0 - float(i % 3), t)
		var spark := (at + flight).round()
		draw_rect(Rect2(spark, Vector2.ONE), Palette.LIGHT if t < 0.6 else Palette.MID)
