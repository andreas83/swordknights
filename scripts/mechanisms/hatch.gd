class_name Hatch
extends Mechanism
## An iron grate set flush in a floor of stone (`h`): a one-way floor, walked
## on like the stone either side of it, dropped through with down + JUMP and
## plunged through with down + SWORD (Player._plunge_through()). Its cell IS
## a platform in the grid (Tiles.MECHANISM_TERRAIN), so it collides, is
## proved and is grabbed exactly as `=` is; this node is only how it looks.
##
## ## Why it is drawn at all
##
## Chapter II's corridor hatch was first a notch in the roof with a platform
## at its foot, and on a phone it read as a glitch: a gap in the stone the
## prince sank into, over a Bastion nothing connected it to. A way down has
## to say so. So a hatch is iron, not stone -- bars in ink, two pixels wide,
## each lit down its sun-facing left edge, under a frame whose top catches the
## sun like a step -- and it lets the light through.
##
## ## The light through it
##
## Sunlight falls through the bars and on down to the first stone below, at
## the sun's own slope: two across for every one down, the lanes every shadow
## in the game runs on (docs/world.md), so the shaft is never at odds with the
## world around it. It is a hard-edged band of the lit tone, a lit patch where
## it lands, and a few motes drifting down it: drawn over the bodies in it, so
## a Bastion standing in it has light on his helm. "Lead the eye with light"
## (docs/art-direction.md): from below, the shaft points up at the grate; from
## above, down at what is under it. A level puts what the hatch is for where
## the shaft falls -- Chapter II's corridor Bastion stands under the grate's
## right half, where the light crosses his helm.

const BAR := Palette.INK
const BAR_LIT := Palette.SHADOW_WARM
const FRAME_LIT := Palette.LIGHT_WARM
const GAP := Palette.SHADOW_PIT
const SHAFT := Palette.LIGHT_SOFT
const PATCH := Palette.LIGHT
## Pixels from one bar to the next.
const PITCH := 4.0
## How deep the grate is drawn into its cell: the rest is open.
const DEPTH := 5.0
## The longest shaft it draws, in tiles of fall.
const MAX_FALL := 8
const MOTES := 4

var _time := 0.0
## The shaft as world-space corners, top-left, top-right, bottom-right,
## bottom-left, or empty when nothing stops it in range.
var _shaft := PackedVector2Array()


func _setup() -> void:
	z_index = 1
	_shaft = _find_shaft()
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if not _shaft.is_empty():
		queue_redraw()


func left() -> float:
	var x := cells[0].x
	for cell: Vector2i in cells:
		x = mini(x, cell.x)
	return float(x) * TILE


func right() -> float:
	var x := cells[0].x
	for cell: Vector2i in cells:
		x = maxi(x, cell.x)
	return float(x + 1) * TILE


## From the grate's underside down the sun's lane to the first stone the
## middle of the shaft meets.
func _find_shaft() -> PackedVector2Array:
	if level == null:
		return PackedVector2Array()
	var top := float(cells[0].y + 1) * TILE
	var middle := (left() + right()) * 0.5
	for row: int in range(cells[0].y + 1, cells[0].y + 1 + MAX_FALL):
		var y := float(row) * TILE
		var x := middle + 2.0 * (y - top)
		if level.is_solid_cell(Vector2i(floori(x / TILE), row)):
			var run := 2.0 * (y - top)
			return PackedVector2Array([
				Vector2(left(), top), Vector2(right(), top),
				Vector2(right() + run, y), Vector2(left() + run, y),
			])
	return PackedVector2Array()


func _draw() -> void:
	var o := position
	if not _shaft.is_empty():
		_draw_shaft(o)
	var x0 := left() - o.x
	var x1 := right() - o.x
	var y := float(cells[0].y) * TILE - o.y
	draw_rect(Rect2(x0, y + 2.0, x1 - x0, DEPTH - 2.0), GAP)
	var x := x0 + 1.0
	while x < x1 - 1.0:
		draw_rect(Rect2(x, y, 2.0, DEPTH), BAR)
		draw_rect(Rect2(x, y + 1.0, 1.0, DEPTH - 1.0), BAR_LIT)
		x += PITCH
	draw_rect(Rect2(x0, y, x1 - x0, 1.0), FRAME_LIT)
	draw_rect(Rect2(x0, y + 1.0, x1 - x0, 1.0), BAR)
	draw_rect(Rect2(x0, y + DEPTH - 1.0, x1 - x0, 1.0), BAR)


func _draw_shaft(o: Vector2) -> void:
	var band := PackedVector2Array()
	for corner: Vector2 in _shaft:
		band.append(corner - o)
	draw_colored_polygon(band, Palette.with_alpha(SHAFT, 0.2))
	draw_rect(Rect2(band[3].x, band[3].y - 2.0, band[2].x - band[3].x, 2.0),
		Palette.with_alpha(PATCH, 0.55))
	var fall := band[3].y - band[0].y
	for i: int in MOTES:
		var k := fmod(_time * 0.18 + float(i) / float(MOTES), 1.0)
		var across := fmod(float(i) * 0.37 + 0.2, 1.0)
		var at := band[0].lerp(band[1], across) + Vector2(2.0 * fall * k, fall * k)
		draw_rect(Rect2(at.floor(), Vector2.ONE), Palette.with_alpha(Palette.PAPER, 0.8))
