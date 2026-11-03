class_name UiLayout
extends RefCounted
## Where things are allowed to be.
##
## The viewport is fixed-height and aspect-derived: 180 units tall, and
## anywhere from about 240 units wide (4:3) to 440 (21:9). **Nothing may assume
## 320.** Every number below is either a height, a gutter, or derived from the
## measured width.
##
## Two rectangles matter.
##
## `safe()` is the display's safe area — the notch, the rounded corners, the
## home indicator — converted from physical pixels into canvas units. Chrome
## (health, score, seed, buttons) lives inside it.
##
## `banner()` is a fixed band across the middle of the safe area, and it is the
## only place an overlay is allowed to put words. Centring on "wherever the
## middle of the screen happens to be" is how `PAUSE TO QUIT` ended up printed
## across the duel arena's spikes: a reserved band is a promise to the level
## art that nothing will be written outside it.

## Distance from the safe edge to the first thing drawn.
const GUTTER := 7.0
## Height of the overlay band, in canvas units. Tall enough for a display line,
## a rule and a line of micro, and not one unit taller.
const BANNER_HEIGHT := 48.0
## The band sits a little above true centre; the eye reads it as centred and
## it leaves the floor of a level clear.
const BANNER_BIAS := -6.0
## A safe-area report larger than this fraction of the screen is not believed.
## Desktop returns the whole desktop rather than the window, which would push
## every button off the edge.
const MAX_INSET := 0.22


## The usable rectangle in canvas units, notches and rounded corners removed.
static func safe(view: Vector2) -> Rect2:
	if view.x <= 0.0 or view.y <= 0.0:
		return Rect2(Vector2.ZERO, view)

	var window := Vector2(DisplayServer.window_get_size())
	if window.x <= 0.0 or window.y <= 0.0:
		return Rect2(Vector2.ZERO, view)

	# The safe area is reported in physical pixels; the canvas is in units.
	var to_units := view.x / window.x
	var area := DisplayServer.get_display_safe_area()
	var left := maxf(0.0, float(area.position.x)) * to_units
	var top := maxf(0.0, float(area.position.y)) * to_units
	var right := maxf(0.0, window.x - float(area.position.x + area.size.x)) * to_units
	var bottom := maxf(0.0, window.y - float(area.position.y + area.size.y)) * to_units

	left = minf(left, view.x * MAX_INSET)
	right = minf(right, view.x * MAX_INSET)
	top = minf(top, view.y * MAX_INSET)
	bottom = minf(bottom, view.y * MAX_INSET)

	return Rect2(
		roundf(left), roundf(top),
		roundf(view.x - left - right), roundf(view.y - top - bottom)
	)


## The safe rectangle pulled in by the gutter: where chrome is drawn.
static func content(view: Vector2) -> Rect2:
	return safe(view).grow(-GUTTER)


## The reserved band for overlays and title cards.
static func banner(view: Vector2) -> Rect2:
	var area := safe(view)
	var centre := area.position.y + area.size.y * 0.5 + BANNER_BIAS
	return Rect2(
		area.position.x,
		roundf(centre - BANNER_HEIGHT * 0.5),
		area.size.x,
		BANNER_HEIGHT
	)


## The y of the title screen's terrace rail — the face a hint line is cut into.
##
## Shared so the menu and the settings page put their hint on the same course
## of stone, rather than each picking a number near the bottom.
static func rail(view: Vector2) -> float:
	return roundf(minf(view.y * 0.84, safe(view).end.y - GUTTER - 7.0)) + 2.0


## A column of `want` units, centred in the safe area and never wider than it.
## Menus and settings use this so a 21:9 phone gets a column, not a 440-unit
## line of text.
static func column(view: Vector2, want: float) -> Rect2:
	var area := safe(view)
	var wide := minf(want, area.size.x - GUTTER * 2.0)
	return Rect2(
		roundf(area.position.x + (area.size.x - wide) * 0.5),
		area.position.y, roundf(wide), area.size.y
	)
