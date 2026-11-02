class_name DuelHud
extends Control
## Round score, countdown, results, and — when there is a network — what it is
## doing.
##
## Drawn rather than built out of Control nodes, for the same reason
## scripts/ui/hud.gd is: it shares the palette and the shapes with everything
## else on screen. The letter-spacing helper at the bottom is the same one that
## file uses; it is repeated here rather than shared because scripts/ui is not
## this branch's to change, and it is fifteen lines.
##
## A desync gets its own band across the screen. A match that has quietly
## stopped agreeing with itself is worse than one that admits it.

const PIP_RADIUS := 3.4
const PIP_GAP := 9.0

var duel: Duel
## Optional. Set for an online duel; left null for a local one.
var session: NetSession
## Which seat this screen is driving, or -1 for a local duel with both.
var your_slot := -1
## Shown under the main overlay title, e.g. the keys or how to rematch.
var footer := ""

var _font: Font
var _time := 0.0
var _flash := 0.0
var _flash_text := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font


## A short word thrown up on a hit, a block or a parry.
func flash(text: String) -> void:
	_flash_text = text
	_flash = 0.9


func _process(delta: float) -> void:
	_time += delta
	_flash = maxf(0.0, _flash - delta)
	queue_redraw()


func _draw() -> void:
	if duel == null:
		return
	var view := size

	_draw_scores(view)
	_draw_phase(view)
	_draw_flash(view)
	if session != null:
		_draw_network(view)


## Won rounds, as pips, growing inward from each corner so the two seats read as
## opposite sides of the same scoreboard.
func _draw_scores(view: Vector2) -> void:
	for slot: int in 2:
		var mirrored := slot == DuelRules.SLOT_B
		var edge := view.x - 12.0 if mirrored else 12.0
		var direction := -1.0 if mirrored else 1.0
		var colour := DuelArt.SEAT_MARK[slot]

		for i: int in duel.rounds_to_win:
			var at := Vector2(edge + direction * i * PIP_GAP, 11.0)
			if i < duel.scores[slot]:
				draw_circle(at, PIP_RADIUS, colour)
				draw_circle(at + Vector2(0.6, -0.5), PIP_RADIUS * 0.55,
					Palette.with_alpha(Palette.INK, 0.45))
			else:
				draw_arc(at, PIP_RADIUS, 0.0, TAU, 14,
					Palette.with_alpha(colour, 0.38), 1.0)

		var label := DuelRules.slot_label(slot)
		if your_slot == slot:
			label += " · YOU"
		_text_aligned(
			label, Vector2(edge, 23.0), 6,
			Palette.with_alpha(Palette.PAPER, 0.7), mirrored
		)


func _draw_phase(view: Vector2) -> void:
	var cx := view.x * 0.5
	match duel.phase:
		Duel.Phase.COUNTDOWN:
			var left := DuelRules.COUNTDOWN_TIME - duel.phase_time
			var count := maxi(1, int(ceil(left)))
			_centered("ROUND %d" % (duel.round_index + 1), cx, view.y * 0.3, 11,
				Palette.PAPER, 3.4)
			# The number swells as each second lands.
			var into := 1.0 - fposmod(left, 1.0)
			var alpha := clampf(1.0 - into * 0.55, 0.0, 1.0)
			_centered(str(count), cx, view.y * 0.48, 26,
				Palette.with_alpha(Palette.LIGHT_SOFT, alpha), 0.0)

		Duel.Phase.ROUND_OVER:
			var title := (
				"DRAW" if duel.last_round_winner == DuelRules.DRAW
				else "%s STRIKES" % DuelRules.slot_label(duel.last_round_winner)
			)
			_band(view, 0.42)
			_centered(title, cx, view.y * 0.47, 16, Palette.PAPER, 5.0)

		Duel.Phase.MATCH_OVER:
			_band(view, 0.0)
			draw_rect(Rect2(Vector2.ZERO, view), Palette.with_alpha(Palette.INK, 0.5))
			_centered("%s WINS" % DuelRules.slot_label(duel.match_winner),
				cx, view.y * 0.42, 20, Palette.PAPER, 6.0)
			_centered("%d — %d" % [duel.scores[0], duel.scores[1]],
				cx, view.y * 0.56, 12, Palette.LIGHT_SOFT, 3.0)
			if footer != "":
				_centered(footer, cx, view.y - 18.0, 6,
					Palette.with_alpha(Palette.LIGHT_SOFT, 0.75), 1.2)

		_:
			if footer != "":
				_centered(footer, cx, view.y - 10.0, 6,
					Palette.with_alpha(Palette.LIGHT_SOFT, 0.4), 1.2)


func _draw_flash(view: Vector2) -> void:
	if _flash <= 0.0 or _flash_text == "":
		return
	var alpha := clampf(_flash / 0.9, 0.0, 1.0)
	_centered(_flash_text, view.x * 0.5, view.y * 0.2, 13,
		Palette.with_alpha(Palette.PAPER, alpha), 4.0)


## One line of truth about the connection, and a band across the screen if the
## two simulations have stopped agreeing.
func _draw_network(view: Vector2) -> void:
	var line := session.status_line()
	var colour := Palette.with_alpha(Palette.LIGHT_SOFT, 0.55)
	if session.desync_count > 0:
		colour = Palette.PAPER
		var pulse := 0.55 + sin(_time * 7.0) * 0.2
		draw_rect(Rect2(0.0, view.y * 0.5 - 11.0, view.x, 22.0),
			Palette.with_alpha(Palette.SHADOW_DEEP, pulse))
		_centered("SIMULATIONS DIVERGED", view.x * 0.5, view.y * 0.5, 9,
			Palette.PAPER, 2.6)
	_centered(line, view.x * 0.5, 11.0, 6, colour, 1.0)


func _band(view: Vector2, at: float) -> void:
	if at <= 0.0:
		return
	draw_rect(Rect2(0.0, view.y * at, view.x, view.y * 0.16),
		Palette.with_alpha(Palette.INK, 0.5))


## --- text -------------------------------------------------------------------

func _text_aligned(
	value: String, at: Vector2, font_size: int, colour: Color, from_right: bool
) -> void:
	var width := _font.get_string_size(
		value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
	).x
	var x := at.x - width if from_right else at.x
	draw_string(_font, Vector2(x, at.y), value,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)


## Centred text with letter spacing, which draw_string does not offer.
func _centered(
	value: String, cx: float, cy: float, font_size: int, colour: Color, tracking: float
) -> void:
	if value == "":
		return
	var widths: Array[float] = []
	var total := 0.0
	for i: int in value.length():
		var w := _font.get_string_size(
			value[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
		).x
		widths.append(w)
		total += w + tracking
	total -= tracking

	var pen := cx - total * 0.5
	for i: int in value.length():
		draw_string(_font, Vector2(pen, cy + font_size * 0.35), value[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)
		pen += widths[i] + tracking
