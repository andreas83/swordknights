class_name MasonsMark
extends RefCounted
## The mason's mark as it is seen in play: a sign cut into a stone, the same
## sign on the plate's stone and on the lintel of the gate it opens, which is
## how the city teaches its wiring without a word (docs/campaign.md, "Wiring:
## channels and mason's marks"; Chapter II's inscription is SAME MARK / SAME
## GATE).
##
## The level text writes a digit; the stone shows a mason's sign, not a
## numeral -- nine shapes made of straight cuts, told apart by their outline
## at the size of a fingernail, the way real masons' marks are. A number on a
## wall would be a label, and the game writes nothing on screen in play.
##
## Carved, like an inscription: the cut is a line of the darkest stone, and
## its lower and right inner edge -- the face of the cut that looks up at the
## low sun -- catches a pixel of light. The mechanism a mark wires draws it,
## so a mark is shown exactly when it means something.

## Each sign as strokes in a 7 x 7 box, point to point.
const SIGNS := {
	"1": [[Vector2(3, 0), Vector2(3, 6)], [Vector2(1, 6), Vector2(5, 6)]],
	"2": [[Vector2(0, 6), Vector2(3, 0), Vector2(6, 6)]],
	"3": [[Vector2(0, 6), Vector2(3, 0), Vector2(6, 6), Vector2(0, 6)]],
	"4": [[Vector2(3, 0), Vector2(3, 6)], [Vector2(0, 3), Vector2(6, 3)]],
	"5": [[Vector2(0, 0), Vector2(6, 6)], [Vector2(6, 0), Vector2(0, 6)]],
	"6": [[Vector2(3, 0), Vector2(6, 3), Vector2(3, 6), Vector2(0, 3), Vector2(3, 0)]],
	"7": [[Vector2(3, 6), Vector2(3, 0)], [Vector2(0, 3), Vector2(3, 0), Vector2(6, 3)]],
	"8": [[Vector2(0, 0), Vector2(6, 0), Vector2(6, 6), Vector2(0, 6), Vector2(0, 0)]],
	"9": [[Vector2(0, 0), Vector2(6, 0), Vector2(0, 6), Vector2(6, 6), Vector2(0, 0)]],
}
const CUT := Palette.SHADOW_PIT
const CATCH := Palette.LIGHT_WARM
## Where the sign sits in its 16 px cell.
const INSET := Vector2(4.5, 4.5)


## Draws `digit`'s sign carved into the cell whose top-left is `corner`, in
## `canvas`'s local coordinates. Nothing for a channel that is not a digit.
static func draw(canvas: CanvasItem, corner: Vector2, digit: String) -> void:
	var strokes: Array = SIGNS.get(digit, [])
	for pass_index: int in 2:
		var lit := pass_index == 0
		var shift := Vector2(1.0, 1.0) if lit else Vector2.ZERO
		for stroke: Array in strokes:
			var line := PackedVector2Array()
			for point: Vector2 in stroke:
				line.append(corner + INSET + point + shift)
			canvas.draw_polyline(line, CATCH if lit else CUT, 1.0)


## The mason's mark cell that wires a mechanism made of `cells` on `channel`,
## from the level's marks, or (-1, -1) for none.
static func cell_of(level: Level, cells: Array[Vector2i], channel: StringName) -> Vector2i:
	if level == null or level.data == null:
		return Vector2i(-1, -1)
	for cell: Vector2i in cells:
		for step: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var at := cell + step
			if String(level.data.masons_marks.get(at, "")) == String(channel):
				return at
	return Vector2i(-1, -1)
