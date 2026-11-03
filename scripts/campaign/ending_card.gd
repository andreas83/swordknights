class_name EndingCard
extends Control
## The card after the last entry of The Last Light: DAWN, and under it THE SUN
## REMEMBERS (Campaign.ENDING), in the level card's own place and cuts -- the
## reserved band, a display line, a rule, a line of micro (docs/ui.md).
##
## Only the words. The dawn itself -- the kept sun rising out of the Well and
## the one frame lit from the right -- is the epilogue's, and lands in front
## of this card when it is built. Jump, sword or a tap returns to the chapter
## select, but not before HOLD: a card that a held jump skips is a card
## nobody saw.

signal done()

## Seconds before anything dismisses it.
const HOLD := 1.5

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
	draw_rect(Rect2(Vector2.ZERO, view), Palette.with_alpha(Palette.INK, 0.35))
	var band := UiLayout.banner(view)
	var cx := band.position.x + band.size.x * 0.5
	var fade := clampf(_time / 0.6, 0.0, 1.0)
	var top := band.position.y + 6.0
	UiFont.draw_text(self, String(Campaign.ENDING["title"]).to_upper(), Vector2(cx, top),
		UiFont.Cut.DISPLAY, Palette.with_alpha(Palette.PAPER, fade), UiFont.Align.CENTER, 0.85)
	var rule_y := top + UiFont.cap(UiFont.Cut.DISPLAY) + 6.0
	UiMarks.rule(self, Vector2(cx, rule_y), minf(band.size.x * 0.3, 64.0),
		Palette.with_alpha(Palette.LIGHT_SOFT, 0.8 * fade))
	UiFont.draw_text(self, String(Campaign.ENDING["epigraph"]).to_upper(),
		Vector2(cx, rule_y + 7.0), UiFont.Cut.MICRO,
		Palette.with_alpha(Palette.LIGHT, fade), UiFont.Align.CENTER, 0.6)
	if can_leave():
		var hint := UiFont.fit(PackedStringArray([
			"JUMP TO RETURN TO THE CHAPTERS", "JUMP TO RETURN",
		]), UiLayout.content(view).size.x, UiFont.Cut.MICRO)
		UiFont.draw_text(self, hint, Vector2(cx, UiLayout.rail(view) + 1.0), UiFont.Cut.MICRO,
			Palette.with_alpha(Palette.PAPER, 0.66), UiFont.Align.CENTER)
