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
## A chapter's card (show_card()) is set in three strokes rather than at
## once: the rule opens from the middle as the wipe lifts, the numeral and
## the name are set on it, and the epigraph follows a beat later as a line of
## its own -- read last, so it is the line that stays with you. It holds
## longer than a level's title because there is more to read, and it never
## holds longer than the player wants: see SKIP_FADE.
const CARD_RULE_AT := 0.25
const CARD_RULE_OPEN := 0.15
const CARD_NAME_FADE := 0.4
const CARD_EPIGRAPH_AT := 1.1
const CARD_EPIGRAPH_FADE := 0.5
const CARD_HOLD := 4.4
## The first press of any verb takes the card away this fast, from wherever
## its fade had got to. The card sits in the reserved band, which is the
## middle of the screen and so where the prince is; a card that held over him
## through his first jump would be covering the game to show its name. The
## press itself is never taken: the jump happens, and the card gets out of
## its way. A press counts at once and a hold does not -- the jump that chose
## the chapter may still be down when it opens, and that one was not aimed at
## it -- until CARD_READ: by then the card has been read, and a verb still
## held is play, so a player who ran in through the wipe is not run under the
## card for its whole hold.
const SKIP_FADE := 0.25
const CARD_READ := 2.2
const PLAY_ACTIONS: Array[StringName] = [
	&"jump", &"attack", &"move_left", &"move_right", &"move_up", &"move_down", &"guard",
]
## The secret banner is quicker than the title: it interrupts play rather than
## opening it, so it says its piece and gets out of the way of the room.
const SECRET_HOLD := 1.5
const SECRET_FADE := 0.5
## How long the corner answers a change: a relic count that pops, a health
## mark that burns white and then goes dark, or one that burns white and then
## stays lit. A number that silently changes in the corner is a number nobody
## saw change.
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
# --- the chapter card --- the numeral (or the finale's eclipse in its place)
# and the epigraph; empty for a plain level title. _skip_at is the card time
# a press took it away at, and _skip_from the light it was going from.
var _numeral: String = ""
var _epigraph: String = ""
var _finale := false
var _skip_at: float = -1.0
var _skip_from: float = 1.0
var _held: Dictionary = {}
var _overlay_title: String = ""
var _overlay_subtitle: String = ""
var _relic_pulse: float = 0.0
var _hurt_pulse: float = 0.0
var _heal_pulse: float = 0.0
# --- secrets --- the found banner: which one of how many, and how long ago.
var _secret_text: String = ""
var _secret_time: float = 999.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	get_viewport().size_changed.connect(queue_redraw)


## `refill` is the level starting over -- a restart, a respawn at a torch.
## Health jumps back to full then, which is neither a heal nor news, so the
## corner takes the numbers without answering. Without it a heart regained
## and a level restarted would look the same from here.
func update_model(hp: int, hp_max: int, got: int, total: int, refill: bool = false) -> void:
	# Only a gain pops and only a loss burns: a restart resets both counts
	# and should not celebrate it.
	if not refill:
		if got > relics and total == relics_total:
			_relic_pulse = PULSE_TIME
		if hp < health and hp_max == max_health:
			_hurt_pulse = PULSE_TIME
			_heal_pulse = 0.0
		if hp > health and hp_max == max_health:
			_heal_pulse = PULSE_TIME
			_hurt_pulse = 0.0
	health = hp
	max_health = hp_max
	relics = got
	relics_total = total
	queue_redraw()


func show_title(level_name: String) -> void:
	show_card({"title": level_name})


## A chapter's title card: `{numeral, title, epigraph, finale}`, every field
## but the title optional (Campaign.card()). With only a title it is the
## level card every other mode shows, timed as it always was.
func show_card(card: Dictionary) -> void:
	_title = String(card.get("title", "")).to_upper().replace("_", " ")
	_numeral = String(card.get("numeral", "")).to_upper()
	_epigraph = String(card.get("epigraph", "")).to_upper()
	_finale = bool(card.get("finale", false))
	_title_time = 0.0
	_skip_at = -1.0
	_skip_from = 1.0
	# Whatever is already held when the card opens is not a press at it.
	_held.clear()
	for action: StringName in PLAY_ACTIONS:
		_held[action] = InputMap.has_action(action) and Input.is_action_pressed(action)
	queue_redraw()


## What the card on screen says, as show_card() was given it, upper-cased.
func card() -> Dictionary:
	return {"numeral": _numeral, "title": _title, "epigraph": _epigraph, "finale": _finale}


## How much of the title card is on screen, 0 to 1.
func title_alpha() -> float:
	if _title == "":
		return 0.0
	if _skip_at >= 0.0:
		return clampf(_skip_from * (1.0 - (_title_time - _skip_at) / SKIP_FADE), 0.0, 1.0)
	if not _is_chapter_card():
		return clampf(1.0 - (_title_time - TITLE_HOLD) / TITLE_FADE, 0.0, 1.0)
	var rise := clampf((_title_time - CARD_RULE_AT) / CARD_RULE_OPEN, 0.0, 1.0)
	return minf(rise, clampf(1.0 - (_title_time - CARD_HOLD) / TITLE_FADE, 0.0, 1.0))


func title_showing() -> bool:
	return title_alpha() > 0.0 or (_title != "" and _title_time < CARD_RULE_AT)


## Whether the card was taken away by a press rather than by its clock.
func title_skipped() -> bool:
	return _skip_at >= 0.0


func _is_chapter_card() -> bool:
	return _numeral != "" or _epigraph != "" or _finale


## --- secrets --- "SECRET FOUND" over the count, in the reserved band. It
## takes the band from the title card, which by the time anyone has found a
## secret has long faded, and gives it back to an overlay, which stops play.
func show_secret(found: int, total: int) -> void:
	_secret_text = "%d OF %d" % [found, total]
	_secret_time = 0.0
	queue_redraw()


func set_overlay(title: String, subtitle: String) -> void:
	_overlay_title = title
	_overlay_subtitle = subtitle
	queue_redraw()


func _process(delta: float) -> void:
	if title_showing():
		_title_time += delta
		var held_on := _title_time >= CARD_READ and _holding_to_play()
		if _skip_at < 0.0 and (_pressed_to_play() or held_on):
			_skip_from = title_alpha()
			_skip_at = _title_time
		queue_redraw()
	if _secret_time <= SECRET_HOLD + SECRET_FADE:
		_secret_time += delta
		queue_redraw()
	if _relic_pulse > 0.0 or _hurt_pulse > 0.0 or _heal_pulse > 0.0:
		_relic_pulse = maxf(0.0, _relic_pulse - delta)
		_hurt_pulse = maxf(0.0, _hurt_pulse - delta)
		_heal_pulse = maxf(0.0, _heal_pulse - delta)
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
	elif _secret_text != "" and _secret_time <= SECRET_HOLD + SECRET_FADE:
		_draw_secret(UiLayout.banner(view))
	elif title_showing():
		if _is_chapter_card():
			_draw_chapter_card(UiLayout.banner(view), title_alpha())
		else:
			_draw_title_card(UiLayout.banner(view), title_alpha())


## Whether any verb is down at all, press or hold.
func _holding_to_play() -> bool:
	for action: StringName in PLAY_ACTIONS:
		if InputMap.has_action(action) and Input.is_action_pressed(action):
			return true
	return false


## A press of any verb since the last frame -- an edge, not a hold.
func _pressed_to_play() -> bool:
	var pressed := false
	for action: StringName in PLAY_ACTIONS:
		var held := InputMap.has_action(action) and Input.is_action_pressed(action)
		if held and not bool(_held.get(action, true)):
			pressed = true
		_held[action] = held
	return pressed


## Health and relics, cut into the top-left corner of the safe area.
func _draw_vitals(content: Rect2) -> void:
	var pen := content.position
	for i: int in max_health:
		UiMarks.tally(self, Vector2(pen.x + i * TALLY_STRIDE, pen.y),
			_tally_lit(i), Palette.PAPER if _tally_burning(i) else Palette.LIGHT_SOFT)

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


## The mark just lost and the mark just gained answer the same way, mirrored:
## both blink white at the same rate for the same PULSE_TIME. The lost one
## then goes dark and the gained one stays lit, so the blink says "this one
## changed" and what is left afterwards says which way.
func _tally_burning(i: int) -> bool:
	if _hurt_pulse > 0.0 and i == health:
		return _blink_on(_hurt_pulse)
	if _heal_pulse > 0.0 and i == health - 1:
		return _blink_on(_heal_pulse)
	return false


func _tally_lit(i: int) -> bool:
	if _tally_burning(i):
		return true
	# Between the gained mark's blinks it is dark, exactly as the lost mark
	# is between its own, or the blink would be a flicker of colour instead.
	if _heal_pulse > 0.0 and i == health - 1:
		return false
	return i < health


static func _blink_on(pulse: float) -> bool:
	return int(pulse * 16.0) % 2 == 0


## --- secrets --- The banner opens from the middle: the rule draws out to
## its full width in a tenth of a second and the words are set on it, so the
## beat lands on the frame the stone gives way rather than fading up after it.
func _draw_secret(band: Rect2) -> void:
	var alpha := clampf(1.0 - (_secret_time - SECRET_HOLD) / SECRET_FADE, 0.0, 1.0)
	var open := clampf(_secret_time / 0.1, 0.0, 1.0)
	var cx := band.position.x + band.size.x * 0.5
	var top := band.position.y + (band.size.y - UiFont.cap(UiFont.Cut.TEXT)) * 0.5 - 6.0
	var wide := UiFont.width("SECRET FOUND", UiFont.Cut.TEXT)
	UiMarks.rule(self, Vector2(cx, top - 5.0), roundf(maxf(12.0, wide * 0.6) * open),
		Palette.with_alpha(Palette.LIGHT_SOFT, alpha * 0.8))
	if open < 1.0:
		return
	UiFont.draw_text(self, "SECRET FOUND", Vector2(cx, top), UiFont.Cut.TEXT,
		Palette.with_alpha(Palette.PAPER, alpha), UiFont.Align.CENTER, alpha * 0.75)
	UiFont.draw_text(self, _secret_text,
		Vector2(cx, top + UiFont.line(UiFont.Cut.TEXT) + 2.0), UiFont.Cut.MICRO,
		Palette.with_alpha(Palette.LIGHT_SOFT, alpha), UiFont.Align.CENTER, alpha * 0.6)


## The level name, in the reserved band, over the picture rather than in a box.
func _draw_title_card(band: Rect2, alpha: float) -> void:
	var cx := band.position.x + band.size.x * 0.5
	var top := band.position.y + (band.size.y - UiFont.cap(UiFont.Cut.DISPLAY)) * 0.5 - 5.0
	var wide := UiFont.draw_text(self, _title, Vector2(cx, top), UiFont.Cut.DISPLAY,
		Palette.with_alpha(Palette.PAPER, alpha), UiFont.Align.CENTER, alpha * 0.75)
	UiMarks.rule(self, Vector2(cx, top + UiFont.cap(UiFont.Cut.DISPLAY) + 6.0),
		maxf(24.0, wide * 0.5), Palette.with_alpha(Palette.LIGHT_SOFT, alpha * 0.8))


## The chapter card, in the reserved band: the name in DISPLAY, the rule
## under it broken in the middle for the numeral -- the way a book sets a
## chapter's number into its ornament, so the numeral reads as the rule's and
## not as a fourth line -- and under that the epigraph in TEXT, in paper with
## the ink cast like every caption over the city (docs/ui.md, "The light").
## The finale has no numeral of its own and no epigraph -- it is chapter V's
## last room, and what it is about is not said -- so its rule carries the one
## silhouette in the game that is a ring of light, the eclipse, in the
## numeral's place. Everything is set on whole units and fades as one light;
## the epigraph comes up a beat after the name (CARD_EPIGRAPH_AT).
func _draw_chapter_card(band: Rect2, alpha: float) -> void:
	var cx := roundf(band.position.x + band.size.x * 0.5)
	var top := band.position.y + 6.0
	var open := clampf((_title_time - CARD_RULE_AT) / CARD_RULE_OPEN, 0.0, 1.0)
	var rule_y := top + UiFont.cap(UiFont.Cut.DISPLAY) + 8.0
	var wide := UiFont.width(_title, UiFont.Cut.DISPLAY)
	var gap := 0.0
	if _finale:
		gap = 9.0
	elif _numeral != "":
		gap = roundf(UiFont.width(_numeral, UiFont.Cut.TEXT) * 0.5) + 5.0
	_rule_with_mark(Vector2(cx, rule_y), roundf(maxf(32.0, wide * 0.5) * open), gap,
		Palette.with_alpha(Palette.LIGHT_SOFT, alpha * 0.8))
	if open < 1.0:
		return
	var set_in := alpha
	if _skip_at < 0.0:
		set_in = minf(alpha, clampf((_title_time - CARD_RULE_AT - CARD_RULE_OPEN)
			/ CARD_NAME_FADE, 0.0, 1.0))
	UiFont.draw_text(self, _title, Vector2(cx, top), UiFont.Cut.DISPLAY,
		Palette.with_alpha(Palette.PAPER, set_in), UiFont.Align.CENTER, set_in * 0.75)
	var mark_y := rule_y + 1.0
	if _finale:
		_draw_eclipse(Vector2(cx, mark_y), set_in)
	elif _numeral != "":
		UiFont.draw_text(self, _numeral,
			Vector2(cx, mark_y - roundf(UiFont.cap(UiFont.Cut.TEXT) * 0.5)), UiFont.Cut.TEXT,
			Palette.with_alpha(Palette.LIGHT_SOFT, set_in), UiFont.Align.CENTER, set_in * 0.7)
	if _epigraph == "":
		return
	var line := alpha
	if _skip_at < 0.0:
		line = minf(alpha, clampf((_title_time - CARD_EPIGRAPH_AT) / CARD_EPIGRAPH_FADE,
			0.0, 1.0))
	UiFont.draw_text(self, _epigraph, Vector2(cx, rule_y + 10.0), UiFont.Cut.TEXT,
		Palette.with_alpha(Palette.PAPER, line * 0.92), UiFont.Align.CENTER, line * 0.8)


## UiMarks.rule with its middle left open by `gap` either side of `at.x`, for
## the mark set into it. Without a gap it is the rule.
func _rule_with_mark(at: Vector2, half: float, gap: float, colour: Color) -> void:
	if gap <= 0.0 or half <= gap + 4.0:
		UiMarks.rule(self, at, half, colour)
		return
	var y := roundf(at.y)
	var left := roundf(at.x - half)
	var right := roundf(at.x + half)
	for span: Vector2 in [Vector2(left + 3.0, at.x - gap), Vector2(at.x + gap, right - 3.0)]:
		draw_rect(Rect2(span.x, y, span.y - span.x, 1.0), colour)
		draw_rect(Rect2(span.x, y + 3.0, span.y - span.x, 1.0),
			Palette.with_alpha(colour, colour.a * 0.5))
	for x: float in [left, right]:
		UiMarks.lozenge(self, Vector2(x, y + 1.5), 3.5, colour)


## The Eclipse's mark: a black disc ringed with fire, a pixel of corona round
## an ink face, cast like every raised mark.
func _draw_eclipse(at: Vector2, alpha: float) -> void:
	var centre := Vector2(roundf(at.x), roundf(at.y))
	draw_circle(centre + UiMarks.CAST, 5.0, Palette.with_alpha(Palette.INK, alpha * 0.7))
	draw_circle(centre, 5.0, Palette.with_alpha(Palette.LIGHT, alpha))
	draw_circle(centre, 3.6, Palette.with_alpha(Palette.INK, alpha))


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
	# --- secrets --- a subtitle may carry a second line (the complete screen
	# of a level with secrets); the block rises by half a line per extra line
	# so it stays centred in the band.
	var lines := _overlay_subtitle.split("\n", false)
	var top := band.position.y + 9.0 - 4.0 * float(maxi(0, lines.size() - 1))
	UiFont.draw_text(self, _overlay_title, Vector2(cx, top), UiFont.Cut.DISPLAY,
		Palette.PAPER, UiFont.Align.CENTER, 0.8)

	var rule_y := top + UiFont.cap(UiFont.Cut.DISPLAY) + 6.0
	UiMarks.rule(self, Vector2(cx, rule_y), minf(band.size.x * 0.36, 60.0),
		Palette.with_alpha(Palette.LIGHT_SOFT, 0.55))

	for i: int in lines.size():
		UiFont.draw_text(self, lines[i],
			Vector2(cx, rule_y + 8.0 + float(i) * UiFont.line(UiFont.Cut.MICRO)),
			UiFont.Cut.MICRO, Palette.with_alpha(Palette.PAPER, 0.85),
			UiFont.Align.CENTER, 0.6)
