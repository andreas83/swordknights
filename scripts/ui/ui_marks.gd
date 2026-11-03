class_name UiMarks
extends RefCounted
## The small drawn parts the interface is assembled from.
##
## None of them are images; all of them obey the same two rules as the world.
## The sun rakes in low from the left, so every raised thing throws a hard ink
## shadow down and to the right and every carved recess is lit along its lower
## and right inner wall. And everything is rectilinear — the same square
## geometry the typeface is built on, so a tally mark and a letter look like
## they were cut by the same hand.

## The world's light direction, in canvas units.
const CAST := Vector2(1.0, 1.0)


## The rule under a title: two hairlines with a stepped lozenge stopping each
## end, like a band inlaid into stone. One line on its own reads as a divider
## in a settings dialogue; two read as ornament.
static func rule(into: CanvasItem, at: Vector2, half: float, colour: Color) -> void:
	var y := roundf(at.y)
	var left := roundf(at.x - half)
	var span := roundf(half * 2.0)
	into.draw_rect(Rect2(left + 3.0, y, span - 6.0, 1.0), colour)
	into.draw_rect(Rect2(left + 3.0, y + 3.0, span - 6.0, 1.0),
		Palette.with_alpha(colour, colour.a * 0.5))
	for x: float in [left, left + span]:
		lozenge(into, Vector2(x, y + 1.5), 3.5, colour)


## A flat wash that darkens toward one edge. Four vertices, four colours — the
## only gradient in the game, and it exists so type can sit over a bright sky
## without a box behind it.
static func wash(into: CanvasItem, rect: Rect2, top: Color, bottom: Color) -> void:
	into.draw_polygon(
		PackedVector2Array([
			rect.position, Vector2(rect.end.x, rect.position.y),
			rect.end, Vector2(rect.position.x, rect.end.y),
		]),
		PackedColorArray([top, top, bottom, bottom])
	)


## The relic mark, and the bullet the menu uses. A stepped diamond rather than
## a circle, so it belongs to the same alphabet as the letters.
static func lozenge(into: CanvasItem, at: Vector2, radius: float, colour: Color,
		shadow: float = 0.0) -> void:
	var points := PackedVector2Array([
		Vector2(at.x, at.y - radius), Vector2(at.x + radius * 0.72, at.y),
		Vector2(at.x, at.y + radius), Vector2(at.x - radius * 0.72, at.y),
	])
	if shadow > 0.0:
		var moved := PackedVector2Array()
		for point: Vector2 in points:
			moved.append(point + CAST)
		into.draw_colored_polygon(moved, Palette.with_alpha(Palette.INK, shadow))
	into.draw_colored_polygon(points, colour)


## A shape cut into stone: ink inside, with the lower and right inner walls
## catching the light. Used for the health slots and the volume tracks.
static func recess(into: CanvasItem, rect: Rect2, fill: float = 0.5,
		sheen: float = 0.35) -> void:
	into.draw_rect(rect, Palette.with_alpha(Palette.INK, fill))
	var lit := Palette.with_alpha(Palette.LIGHT_WARM, sheen)
	into.draw_rect(Rect2(rect.position.x, rect.end.y - 1.0, rect.size.x, 1.0), lit)
	into.draw_rect(Rect2(rect.end.x - 1.0, rect.position.y, 1.0, rect.size.y), lit)


## One unit of health: a stroke cut into the wall, filled while it is held.
static func tally(into: CanvasItem, at: Vector2, held: bool, colour: Color) -> void:
	var slot := Rect2(roundf(at.x), roundf(at.y), 3.0, 9.0)
	recess(into, slot, 0.45, 0.25)
	if not held:
		return
	var body := Rect2(slot.position.x, slot.position.y + 1.0, 2.0, 7.0)
	into.draw_rect(Rect2(body.position + CAST, body.size),
		Palette.with_alpha(Palette.INK, 0.5))
	into.draw_rect(body, colour)
	# The lit top face of the stroke.
	into.draw_rect(Rect2(body.position, Vector2(2.0, 1.0)), Palette.PAPER)


## The selection arrow. Flat-backed and stepped, like the face's K.
static func caret(into: CanvasItem, at: Vector2, size: float, colour: Color) -> void:
	into.draw_colored_polygon(PackedVector2Array([
		Vector2(at.x, at.y - size), Vector2(at.x + size, at.y),
		Vector2(at.x, at.y + size), Vector2(at.x + size * 0.45, at.y),
	]), colour)


## A crenellated edge: the silhouette of a parapet seen against the sky. `rect`
## is the solid below the merlons; they stand on top of it.
static func parapet(into: CanvasItem, rect: Rect2, step: float, height: float,
		colour: Color) -> void:
	into.draw_rect(rect, colour)
	var x := roundf(rect.position.x)
	var i := 0
	while x < rect.end.x:
		if i % 2 == 0:
			into.draw_rect(Rect2(x, rect.position.y - height,
				minf(step, rect.end.x - x), height), colour)
		x += step
		i += 1


## A wall with horseshoe arches cut through it.
##
## Drawn as the solid that remains, column by column, because that is the only
## way to get a hole in a filled rectangle without a shader: a column is dark
## above every curve, and dark again below it out at the haunches where the
## horseshoe closes back in.
##
## `horseshoe` is how far past the half-circle the curve continues before the
## jambs drop straight. It is the whole difference between a Roman arch and
## this one, and it is why the opening is narrowest at the floor.
static func arcade(into: CanvasItem, band: Rect2, centres: PackedVector2Array,
		radius: float, horseshoe: float, colour: Color) -> void:
	var jamb := sqrt(maxf(0.0, radius * radius - horseshoe * horseshoe))
	var x := floorf(band.position.x)
	while x < band.end.x:
		# The topmost opening this column passes through, and where it ends.
		var open_from := band.end.y
		var open_to := band.position.y
		for centre: Vector2 in centres:
			var dx := absf(x + 0.5 - centre.x)
			if dx >= radius:
				continue
			var reach := sqrt(radius * radius - dx * dx)
			open_from = minf(open_from, centre.y - reach)
			open_to = maxf(open_to, band.end.y if dx <= jamb else centre.y + reach)

		if open_from >= open_to:
			into.draw_rect(Rect2(x, band.position.y, 1.0, band.size.y), colour)
			x += 1.0
			continue

		var top := roundf(clampf(open_from, band.position.y, band.end.y))
		if top > band.position.y:
			into.draw_rect(Rect2(x, band.position.y, 1.0,
				top - band.position.y), colour)
		var bottom := roundf(clampf(open_to, band.position.y, band.end.y))
		if bottom < band.end.y:
			into.draw_rect(Rect2(x, bottom, 1.0, band.end.y - bottom), colour)
		x += 1.0


## A track of square cells, filled up to `value`. The volume sliders, and the
## only widget in the game that is not a word.
static func gauge(into: CanvasItem, at: Vector2, cells: int, cell: Vector2,
		value: float, colour: Color, active: bool) -> void:
	var filled := int(roundf(clampf(value, 0.0, 1.0) * float(cells)))
	for i: int in cells:
		var box := Rect2(roundf(at.x + i * (cell.x + 1.0)), roundf(at.y), cell.x, cell.y)
		recess(into, box, 0.45, 0.2 if active else 0.12)
		if i >= filled:
			continue
		var body := Rect2(box.position + Vector2.ONE, box.size - Vector2(2.0, 2.0))
		into.draw_rect(body, colour if active else Palette.with_alpha(colour, 0.55))
