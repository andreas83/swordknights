class_name EndingCard
extends Control
## The words after the last entry of The Last Light: DAWN, and under it THE
## SUN REMEMBERS (Campaign.ENDING), in the level card's own place and cuts --
## the reserved band, a display line, a rule, a line of text (docs/ui.md).
##
## Only the words; the picture under them is DawnFrame's. They come up after
## the picture has been seen on its own (WORDS_AT), the epigraph a beat after
## the title, as a chapter card's does (Hud.show_card()). Jump, sword or a tap
## returns to the chapter select, but not before HOLD: a card that a held
## jump skips is a card nobody saw, and this one is the last.

signal done()

## Seconds the picture is held alone before the title is set on it.
const WORDS_AT := 1.2
## And the epigraph after the title.
const EPIGRAPH_AT := 2.2
const FADE := 0.6
## Seconds before anything dismisses it: the epigraph has come up and been
## read.
const HOLD := 3.4

## The dawn's light is from the east, so the words cast their shadow to the
## left, as everything else in the frame does (docs/ui.md, "The light").
var light_from_east := false

var _time := 0.0
var _left := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameAudio.cue("level_complete")


func can_leave() -> bool:
	return _time >= HOLD


## Goes back to the chapter select, once the card has been up for HOLD.
func leave() -> bool:
	if not can_leave() or _left:
		return false
	_left = true
	GameAudio.cue("ui_confirm")
	done.emit()
	return true


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()
	if Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("attack"):
		leave()


func _input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch != null and touch.pressed and leave():
		get_viewport().set_input_as_handled()


func _draw() -> void:
	var view := get_viewport_rect().size
	if view.x <= 0.0:
		return
	var band := UiLayout.banner(view)
	var cx := roundf(band.position.x + band.size.x * 0.5)
	var title := clampf((_time - WORDS_AT) / FADE, 0.0, 1.0)
	var line := clampf((_time - EPIGRAPH_AT) / FADE, 0.0, 1.0)
	var top := band.position.y + 6.0
	_text(String(Campaign.ENDING["title"]).to_upper(), Vector2(cx, top), UiFont.Cut.DISPLAY,
		Palette.with_alpha(Palette.PAPER, title), 0.75 * title)
	var rule_y := top + UiFont.cap(UiFont.Cut.DISPLAY) + 8.0
	var open := clampf((_time - WORDS_AT) / 0.15, 0.0, 1.0)
	UiMarks.rule(self, Vector2(cx, rule_y), roundf(minf(band.size.x * 0.3, 64.0) * open),
		Palette.with_alpha(Palette.LIGHT_SOFT, 0.8 * title))
	_text(String(Campaign.ENDING["epigraph"]).to_upper(), Vector2(cx, rule_y + 10.0),
		UiFont.Cut.TEXT, Palette.with_alpha(Palette.PAPER, 0.92 * line), 0.8 * line)
	if can_leave():
		var hint := UiFont.fit(PackedStringArray([
			"JUMP TO RETURN TO THE CHAPTERS", "JUMP TO RETURN",
		]), UiLayout.content(view).size.x, UiFont.Cut.MICRO)
		_text(hint, Vector2(cx, UiLayout.rail(view) + 1.0), UiFont.Cut.MICRO,
			Palette.with_alpha(Palette.PAPER, 0.66), 0.6)


## Centred type with its cast: down and to the right under the afternoon's
## sun, as UiFont.draw_text casts it, and down and to the left at dawn.
func _text(text: String, at: Vector2, cut: UiFont.Cut, colour: Color, shadow: float) -> void:
	if colour.a <= 0.0:
		return
	if not light_from_east:
		UiFont.draw_text(self, text, at, cut, colour, UiFont.Align.CENTER, shadow)
		return
	var cast := Vector2(-UiMarks.CAST.x, UiMarks.CAST.y)
	UiFont.draw_text(self, text, at + cast, cut, Palette.with_alpha(Palette.INK, shadow),
		UiFont.Align.CENTER)
	UiFont.draw_text(self, text, at, cut, colour, UiFont.Align.CENTER)
