class_name UiFont
extends RefCounted
## The game's typeface, and the only way anything should put text on screen.
##
## "Alcazar" is drawn by tools/generate_font.py and shipped as three BMFont
## pairs in assets/. It is a bitmap face designed at the sizes it is used at —
## a 180-unit-tall viewport is not a place to scale a display face down — so
## there are three optical cuts and nothing in between:
##
##     MICRO    cap  5 px   hints, readouts, button labels, subtitles
##     TEXT     cap  7 px   menu rows, counters, settings labels
##     DISPLAY  cap 14 px   the title, level cards, overlay titles
##
## Ask for a cut, not a point size. `draw_text` takes the top-left of the *cap
## box*, not a baseline, because every layout in this game is built by stacking
## cap heights and gaps, and it rounds to whole canvas units so the bitmap
## lands on the pixel grid.
##
## Text carries the world's lighting law: the sun rakes in low from the left,
## so a `shadow` draws the same string one unit right and down in ink. That is
## the same shadow the stone gets, and it is what keeps a caption legible over
## a bright sky without a box behind it.

enum Cut { MICRO, TEXT, DISPLAY }
enum Align { LEFT, CENTER, RIGHT }

const PATHS: Array[String] = [
	"res://assets/font_alcazar_micro.fnt",
	"res://assets/font_alcazar_text.fnt",
	"res://assets/font_alcazar_display.fnt",
]
## Cap height per cut, in canvas units. Also the font size the face is
## rasterised at, since it is a bitmap font with one fixed size per file.
const CAP: Array[int] = [5, 7, 14]
## Letterspacing that suits each cut. The face is drawn tight on purpose and
## wants air; the display cut wants more of it.
const TRACKING: Array[float] = [1.0, 1.0, 2.0]
## The cast shadow. One unit right and down — the sun is low and on the left.
const SHADOW_STEP := Vector2(1.0, 1.0)

static var _faces: Array[FontFile] = []


static func face(cut: Cut) -> FontFile:
	if _faces.size() != PATHS.size():
		_faces.resize(PATHS.size())
	if _faces[cut] == null:
		var loaded := load(PATHS[cut]) as FontFile
		if loaded == null:
			push_error("UiFont: could not load %s — run tools/generate_font.py" % PATHS[cut])
			return null
		_faces[cut] = loaded
	return _faces[cut]


static func cap(cut: Cut) -> float:
	return float(CAP[cut])


## Height of one line of this cut including the gap below it, for stacking.
static func line(cut: Cut) -> float:
	return float(CAP[cut]) + (2.0 if cut == Cut.DISPLAY else 1.0) + 2.0


static func tracking(cut: Cut) -> float:
	return TRACKING[cut]


static func width(text: String, cut: Cut, track: float = -1.0) -> float:
	var font := face(cut)
	if font == null or text.is_empty():
		return 0.0
	if track < 0.0:
		track = TRACKING[cut]
	var size := CAP[cut]
	var total := 0.0
	for i: int in text.length():
		total += font.get_char_size(text.unicode_at(i), size).x + track
	return maxf(0.0, total - track)


## The first of `options` that fits in `room`, or the last one regardless.
##
## The viewport width is aspect-derived, so a hint line that fits a 21:9 phone
## may be a hundred units too long on a 4:3 tablet. Write the full sentence
## first and a terse version after it, and the layout degrades instead of
## running off both edges.
static func fit(options: PackedStringArray, room: float, cut: Cut,
		track: float = -1.0) -> String:
	for option: String in options:
		if width(option, cut, track) <= room:
			return option
	return "" if options.is_empty() else options[options.size() - 1]


## Draws `text` with its cap box starting at `at`, and returns the width used.
##
## `at.x` is the left, centre or right edge according to `align`; `at.y` is
## always the cap line, so two cuts set on the same `at.y` share a top edge.
static func draw_text(
	into: CanvasItem,
	text: String,
	at: Vector2,
	cut: Cut,
	colour: Color,
	align: Align = Align.LEFT,
	shadow: float = 0.0,
	track: float = -1.0
) -> float:
	var font := face(cut)
	if font == null or text.is_empty():
		return 0.0
	if track < 0.0:
		track = TRACKING[cut]

	var size := CAP[cut]
	var total := width(text, cut, track)
	var left := at.x
	match align:
		Align.CENTER:
			left = at.x - total * 0.5
		Align.RIGHT:
			left = at.x - total

	# Whole units, or the bitmap samples between pixels and goes soft.
	var origin := Vector2(roundf(left), roundf(at.y) + float(size))

	if shadow > 0.0:
		_run(into, font, text, origin + SHADOW_STEP, size, track,
			Palette.with_alpha(Palette.INK, shadow))
	_run(into, font, text, origin, size, track, colour)
	return total


static func _run(
	into: CanvasItem, font: FontFile, text: String, origin: Vector2,
	size: int, track: float, colour: Color
) -> void:
	var pen := origin
	for i: int in text.length():
		var glyph := text[i]
		into.draw_char(font, pen, glyph, size, colour)
		pen.x += font.get_char_size(text.unicode_at(i), size).x + track
