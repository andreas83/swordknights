class_name PortcullisArt
extends RefCounted
## How a portcullis and its counterweight are drawn, posed from the gate's
## state and nothing else (scripts/mechanisms/gate.gd argues the look).

const BAR := Palette.INK
const BAR_LIT := Palette.SHADOW_WARM
const RAIL_SHADE := Palette.SHADOW_PIT
const POINT := Palette.STEEL
const POINT_DARK := Palette.STEEL_DARK
const STONE := Palette.SHADOW_DEEP
const STONE_LIT := Palette.SHADOW_WARM
const STONE_CAP := Palette.LIGHT_WARM
const CHAIN := Palette.INK
const CHAIN_LIT := Palette.SHADOW_WARM


static func draw(gate: Gate, top: float, floor_y: float, column: int, mark: Vector2i) -> void:
	var o := gate.position
	var x0 := float(column) * Mechanism.TILE - o.x
	var y_top := top - o.y
	var foot := gate.foot() - o.y
	var y_floor := floor_y - o.y
	_counterweight(gate, x0, y_top, y_floor)
	if foot > y_top + 0.5:
		_bars(gate, x0, y_top, foot)
	if foot >= y_floor - 4.0:
		# Contact shadow: the points on the stone, down and to the right of
		# them, where the low sun would put it.
		gate.draw_rect(Rect2(x0 + 2.0, y_floor, Mechanism.TILE, 1.0),
			Palette.with_alpha(Palette.INK, 0.35))
	if mark.x >= 0:
		MasonsMark.draw(gate, Vector2(mark) * Mechanism.TILE - o, String(gate.channel))


## The bars below the lintel, from its underside to the foot. The rails are
## laid from the foot up, so they ride up with the gate.
static func _bars(gate: Gate, x0: float, y_top: float, foot: float) -> void:
	var length := foot - y_top
	var rail := foot - Gate.POINT - 2.0
	while rail > y_top:
		gate.draw_rect(Rect2(x0, rail, Mechanism.TILE, 1.0), BAR)
		gate.draw_rect(Rect2(x0, rail + 1.0, Mechanism.TILE, 1.0), RAIL_SHADE)
		rail -= Gate.RAIL
	for offset: float in Gate.BARS:
		var x := x0 + offset
		var shaft := maxf(0.0, length - Gate.POINT)
		gate.draw_rect(Rect2(x, y_top, 2.0, shaft), BAR)
		gate.draw_rect(Rect2(x, y_top, 1.0, shaft), BAR_LIT)
		if length > Gate.POINT:
			var tip := foot
			gate.draw_colored_polygon(PackedVector2Array([
				Vector2(x, tip - Gate.POINT), Vector2(x + 2.0, tip - Gate.POINT),
				Vector2(x + 1.0, tip),
			]), POINT)
			gate.draw_rect(Rect2(x + 1.0, tip - Gate.POINT, 1.0, 1.0), POINT_DARK)


## A stone on a chain from the lintel, beside the gate on its plate's side:
## up with time in hand, down when it has run out. A tick jolts it a pixel.
static func _counterweight(gate: Gate, x0: float, y_top: float, y_floor: float) -> void:
	var x := x0 - Gate.WEIGHT.x - 2.0 if gate.side < 0 else x0 + Mechanism.TILE + 2.0
	var low := y_floor - Gate.WEIGHT.y
	var high := y_top + 3.0
	var y := lerpf(low, high, gate.weight) + (1.0 if gate.jolt > 0 else 0.0)
	var hang := floorf(x + Gate.WEIGHT.x * 0.5)
	gate.draw_rect(Rect2(hang, y_top, 1.0, y - y_top), CHAIN)
	var link := y_top + 2.0
	while link < y - 1.0:
		gate.draw_rect(Rect2(hang - 1.0, link, 1.0, 1.0), CHAIN_LIT)
		link += 3.0
	var block := Rect2(x, y, Gate.WEIGHT.x, Gate.WEIGHT.y)
	gate.draw_rect(block, STONE)
	gate.draw_rect(Rect2(block.position, Vector2(1.0, block.size.y)), STONE_LIT)
	gate.draw_rect(Rect2(block.position, Vector2(block.size.x, 1.0)), STONE_CAP)
	gate.draw_rect(Rect2(block.position.x, block.end.y - 1.0, block.size.x, 1.0), Palette.INK)
