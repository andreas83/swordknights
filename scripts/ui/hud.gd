class_name Hud
extends Control
## Health, relics, the level title card and the pause/complete overlay.
##
## Drawn rather than built from Control nodes so it shares the exact palette,
## the exact light direction and the exact geometry as the rest of the game.
##
## Two rules it will not break:
##
## **It lives inside the safe area.** Health used to sit at a flat 10 units
## from the corner, which on a notched phone in landscape is underneath the
## notch. Everything is now placed against `UiLayout.content()`.
##
## **Overlays live in the reserved band.** `UiLayout.banner()` is the only
## place words are allowed when the game is stopped, so the level art knows
## what it has to keep clear.

const TITLE_HOLD := 2.6
const TITLE_FADE := 0.9
## How long the corner answers a change: a relic count that pops, a health
## mark that burns white and then goes dark. A number that silently changes
## in the corner is a number nobody saw change.
const PULSE_TIME := 0.45

## Health marks: a 3-unit stroke every 5 units.
const TALLY_STRIDE := 5.0
const TALLY_HEIGHT := 9.0

var health: int = Tuning.MAX_HEALTH
var max_health: int = Tuning.MAX_HEALTH
var relics: int = 0
var relics_total: int = 0

var _title: String = ""
var _title_time: float = 999.0
var _overlay_title: String = ""
var _overlay_subtitle: String = ""
var _relic_pulse: float = 0.0
var _hurt_pulse: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	get_viewport().size_changed.connect(queue_redraw)


func update_model(hp: int, hp_max: int, got: int, total: int) -> void:
	# Only a gain pops and only a loss burns: a restart resets both counts
	# and should not celebrate it.
	if got > relics and total == relics_total:
		_relic_pulse = PULSE_TIME
	if hp < health and hp_max == max_health:
		_hurt_pulse = PULSE_TIME
	health = hp
	max_health = hp_max
	relics = got
	relics_total = total
	queue_redraw()


func show_title(level_name: String) -> void:
	_title = level_name.to_upper().replace("_", " ")
	_title_time = 0.0


func set_overlay(title: String, subtitle: String) -> void:
	_overlay_title = title
	_overlay_subtitle = subtitle
	queue_redraw()


func _process(delta: float) -> void:
	if _title_time <= TITLE_HOLD + TITLE_FADE:
		_title_time += delta
		queue_redraw()
	if _relic_pulse > 0.0 or _hurt_pulse > 0.0:
		_relic_pulse = maxf(0.0, _relic_pulse - delta)
		_hurt_pulse = maxf(0.0, _hurt_pulse - delta)
		queue_redraw()


func _draw() -> void:
	var view := size
	if view.x <= 0.0:
		return
	_draw_vitals(UiLayout.content(view))

	# The title card and the overlay share the reserved band, so only one of
	# them is ever on it. The overlay wins: the game is stopped.
	if _overlay_title != "":
		_draw_overlay(view)
	elif _title != "" and _title_time <= TITLE_HOLD + TITLE_FADE:
		var alpha := clampf(1.0 - (_title_time - TITLE_HOLD) / TITLE_FADE, 0.0, 1.0)
		_draw_title_card(UiLayout.banner(view), alpha)


## Health and relics, cut into the top-left corner of the safe area.
func _draw_vitals(content: Rect2) -> void:
	var pen := content.position
	for i: int in max_health:
		# The mark just lost stays lit, burning white, for a few blinks.
		var burning := i == health and _hurt_pulse > 0.0 \
			and int(_hurt_pulse * 16.0) % 2 == 0
		UiMarks.tally(self, Vector2(pen.x + i * TALLY_STRIDE, pen.y),
			i < health or burning, Palette.PAPER if burning else Palette.LIGHT_SOFT)

	if relics_total <= 0:
		return
	var x := pen.x + max_health * TALLY_STRIDE + 7.0
	var middle := pen.y + TALLY_HEIGHT * 0.5
	# A gain pops the lozenge two units larger and steps it back, in whole
	# units: a smooth scale on a pixel mark is a shimmer, not a pop.
	var pop := ceilf(2.0 * _relic_pulse / PULSE_TIME)
	var lit := relics >= relics_total or _relic_pulse > 0.0
	UiMarks.lozenge(self, Vector2(x + 3.0, middle), 4.5 + pop,
		Palette.PAPER if lit else Palette.LIGHT, 0.5)
	UiFont.draw_text(self, "%d/%d" % [relics, relics_total],
		Vector2(x + 10.0 + pop, middle - UiFont.cap(UiFont.Cut.TEXT) * 0.5),
		UiFont.Cut.TEXT, Palette.LIGHT_SOFT if _relic_pulse > 0.0 else Palette.PAPER,
		UiFont.Align.LEFT, 0.6)


## The level name, in the reserved band, over the picture rather than in a box.
func _draw_title_card(band: Rect2, alpha: float) -> void:
	var cx := band.position.x + band.size.x * 0.5
	var top := band.position.y + (band.size.y - UiFont.cap(UiFont.Cut.DISPLAY)) * 0.5 - 5.0
	var wide := UiFont.draw_text(self, _title, Vector2(cx, top), UiFont.Cut.DISPLAY,
		Palette.with_alpha(Palette.PAPER, alpha), UiFont.Align.CENTER, alpha * 0.75)
	UiMarks.rule(self, Vector2(cx, top + UiFont.cap(UiFont.Cut.DISPLAY) + 6.0),
		maxf(24.0, wide * 0.5), Palette.with_alpha(Palette.LIGHT_SOFT, alpha * 0.8))


## PAUSED / ESCAPED. The game is stopped, so this one gets weight: a scrim over
## the world and a carved band across the reserved area.
func _draw_overlay(view: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, view), Palette.with_alpha(Palette.INK, 0.62))

	var band := UiLayout.banner(view)
	draw_rect(band, Palette.with_alpha(Palette.SHADOW_DEEP, 0.55))
	draw_rect(Rect2(band.position, Vector2(band.size.x, 1.0)),
		Palette.with_alpha(Palette.LIGHT_WARM, 0.8))
	draw_rect(Rect2(band.position.x, band.end.y - 1.0, band.size.x, 1.0),
		Palette.with_alpha(Palette.LIGHT_WARM, 0.5))

	var cx := band.position.x + band.size.x * 0.5
	var top := band.position.y + 9.0
	UiFont.draw_text(self, _overlay_title, Vector2(cx, top), UiFont.Cut.DISPLAY,
		Palette.PAPER, UiFont.Align.CENTER, 0.8)

	var rule_y := top + UiFont.cap(UiFont.Cut.DISPLAY) + 6.0
	UiMarks.rule(self, Vector2(cx, rule_y), minf(band.size.x * 0.36, 60.0),
		Palette.with_alpha(Palette.LIGHT_SOFT, 0.55))

	if _overlay_subtitle == "":
		return
	UiFont.draw_text(self, _overlay_subtitle, Vector2(cx, rule_y + 8.0),
		UiFont.Cut.MICRO, Palette.with_alpha(Palette.PAPER, 0.85),
		UiFont.Align.CENTER, 0.6)
