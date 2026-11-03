class_name DuelHud
extends Control
## Round score, countdown, results, and — when there is a network — what it is
## doing.
##
## Drawn rather than built out of Control nodes, for the same reason
## scripts/ui/hud.gd is: it shares the palette and the shapes with everything
## else on screen. Typography, safe areas and the reserved overlay band all
## come from scripts/ui, so this screen and the adventure HUD cannot drift
## apart.
##
## Nothing is written outside `UiLayout.banner()` and the two top corners. The
## arena's floor is a row of spikes and its ceiling is where the duellists
## fight; both used to have words across them.
##
## A desync still gets a band of its own. A match that has quietly stopped
## agreeing with itself is worse than one that admits it.

const PIP_GAP := 7.0
const PIP_RADIUS := 3.2

var duel: Duel
## Optional. Set for an online duel; left null for a local one.
var session: NetSession
## Which seat this screen is driving, or -1 for a local duel with both.
var your_slot := -1
## Shown under the main overlay title, e.g. the keys or how to rematch.
var footer := ""

var _time := 0.0
var _flash := 0.0
var _flash_text := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	get_viewport().size_changed.connect(queue_redraw)


## A short word thrown up on a hit, a block or a parry.
func flash(text: String) -> void:
	_flash_text = text
	_flash = 0.9


func _process(delta: float) -> void:
	_time += delta
	_flash = maxf(0.0, _flash - delta)
	queue_redraw()


func _draw() -> void:
	if duel == null or size.x <= 0.0:
		return
	var view := size
	var content := UiLayout.content(view)
	var band := UiLayout.banner(view)

	_draw_scores(content)
	_draw_status(content)
	_draw_phase(band)
	_draw_flash(band)


## Won rounds, as lozenges growing inward from each corner of the safe area, so
## the two seats read as opposite ends of the same scoreboard.
func _draw_scores(content: Rect2) -> void:
	for slot: int in 2:
		var mirrored := slot == DuelRules.SLOT_B
		var edge := content.end.x - PIP_RADIUS if mirrored else content.position.x + PIP_RADIUS
		var direction := -1.0 if mirrored else 1.0
		var colour := DuelArt.SEAT_MARK[slot]
		var middle := content.position.y + PIP_RADIUS + 1.0

		for i: int in duel.rounds_to_win:
			var at := Vector2(edge + direction * i * PIP_GAP, middle)
			if i < duel.scores[slot]:
				UiMarks.lozenge(self, at, PIP_RADIUS, colour, 0.5)
			else:
				UiMarks.lozenge(self, at, PIP_RADIUS,
					Palette.with_alpha(Palette.INK, 0.4))
				UiMarks.lozenge(self, at, PIP_RADIUS - 1.4,
					Palette.with_alpha(colour, 0.28))

		var label := DuelRules.slot_label(slot)
		if your_slot == slot:
			label += " · YOU"
		UiFont.draw_text(
			self, label, Vector2(content.position.x if not mirrored else content.end.x,
				middle + PIP_RADIUS + 3.0),
			UiFont.Cut.MICRO, Palette.with_alpha(Palette.PAPER, 0.75),
			UiFont.Align.RIGHT if mirrored else UiFont.Align.LEFT, 0.7
		)


## The connection, and the persistent hint. Both live at the top centre — not
## at the bottom, which in this arena is a row of spikes.
func _draw_status(content: Rect2) -> void:
	var cx := content.position.x + content.size.x * 0.5
	var y := content.position.y

	if session != null:
		UiFont.draw_text(self, session.status_line(), Vector2(cx, y),
			UiFont.Cut.MICRO,
			Palette.with_alpha(Palette.LIGHT_SOFT, 0.8 if session.desync_count > 0 else 0.55),
			UiFont.Align.CENTER, 0.6)
		y += UiFont.line(UiFont.Cut.MICRO)

	if footer == "" or duel.phase == Duel.Phase.MATCH_OVER:
		return
	UiFont.draw_text(self, footer, Vector2(cx, y), UiFont.Cut.MICRO,
		Palette.with_alpha(Palette.PAPER, 0.45), UiFont.Align.CENTER, 0.5)


func _draw_phase(band: Rect2) -> void:
	var cx := band.position.x + band.size.x * 0.5
	match duel.phase:
		Duel.Phase.COUNTDOWN:
			var left := DuelRules.COUNTDOWN_TIME - duel.phase_time
			var count := maxi(1, int(ceil(left)))
			UiFont.draw_text(self, "ROUND %d" % (duel.round_index + 1),
				Vector2(cx, band.position.y + 6.0), UiFont.Cut.TEXT,
				Palette.PAPER, UiFont.Align.CENTER, 0.8)
			# The medallion swells as each second lands.
			var into := 1.0 - fposmod(left, 1.0)
			var alpha := clampf(1.0 - into * 0.55, 0.0, 1.0)
			var at := Vector2(cx, band.position.y + 30.0)
			var radius := 15.0 + into * 3.0
			UiMarks.lozenge(self, at, radius,
				Palette.with_alpha(Palette.LIGHT_WARM, 0.55 * alpha))
			UiMarks.lozenge(self, at, radius - 1.6,
				Palette.with_alpha(Palette.INK, 0.6 * alpha))
			UiFont.draw_text(self, str(count),
				Vector2(at.x, at.y - UiFont.cap(UiFont.Cut.DISPLAY) * 0.5),
				UiFont.Cut.DISPLAY, Palette.with_alpha(Palette.LIGHT_SOFT, alpha),
				UiFont.Align.CENTER, alpha * 0.6)

		Duel.Phase.ROUND_OVER:
			_band_plate(band, 0.5)
			var title := (
				"DRAW" if duel.last_round_winner == DuelRules.DRAW
				else "%s STRIKES" % DuelRules.slot_label(duel.last_round_winner)
			)
			UiFont.draw_text(self, title,
				Vector2(cx, band.position.y + (band.size.y - 14.0) * 0.5),
				UiFont.Cut.DISPLAY, Palette.PAPER, UiFont.Align.CENTER, 0.8)

		Duel.Phase.MATCH_OVER:
			draw_rect(Rect2(Vector2.ZERO, size), Palette.with_alpha(Palette.INK, 0.6))
			_band_plate(band, 0.6)
			# Four things in forty-eight units: title, rule, score, footer.
			# The numbers are the band's, not the screen's, so a taller phone
			# does not spread them out.
			UiFont.draw_text(self, "%s WINS" % DuelRules.slot_label(duel.match_winner),
				Vector2(cx, band.position.y + 4.0), UiFont.Cut.DISPLAY,
				Palette.PAPER, UiFont.Align.CENTER, 0.8)
			UiMarks.rule(self, Vector2(cx, band.position.y + 22.0),
				minf(band.size.x * 0.3, 48.0),
				Palette.with_alpha(Palette.LIGHT_SOFT, 0.6))
			UiFont.draw_text(self, "%d — %d" % [duel.scores[0], duel.scores[1]],
				Vector2(cx, band.position.y + 27.0), UiFont.Cut.TEXT,
				Palette.LIGHT_SOFT, UiFont.Align.CENTER, 0.6)
			if footer != "":
				UiFont.draw_text(self, footer, Vector2(cx, band.position.y + 39.0),
					UiFont.Cut.MICRO, Palette.with_alpha(Palette.PAPER, 0.8),
					UiFont.Align.CENTER, 0.6)

		_:
			if session != null and session.desync_count > 0:
				_draw_desync(band)


## A struck word on a hit, a block or a parry — in the reserved band, where
## nothing of the arena is.
func _draw_flash(band: Rect2) -> void:
	if _flash <= 0.0 or _flash_text == "" or duel.phase != Duel.Phase.FIGHTING:
		return
	var alpha := clampf(_flash / 0.9, 0.0, 1.0)
	UiFont.draw_text(self, _flash_text,
		Vector2(band.position.x + band.size.x * 0.5, band.position.y + 8.0),
		UiFont.Cut.DISPLAY, Palette.with_alpha(Palette.PAPER, alpha),
		UiFont.Align.CENTER, alpha * 0.8)


func _draw_desync(band: Rect2) -> void:
	var pulse := 0.55 + sin(_time * 7.0) * 0.2
	var strip := Rect2(0.0, band.position.y + band.size.y * 0.5 - 9.0, size.x, 18.0)
	draw_rect(strip, Palette.with_alpha(Palette.SHADOW_DEEP, pulse))
	UiFont.draw_text(self, "SIMULATIONS DIVERGED",
		Vector2(strip.position.x + strip.size.x * 0.5, strip.position.y + 6.0),
		UiFont.Cut.TEXT, Palette.PAPER, UiFont.Align.CENTER, 0.8)


## The carved plate an overlay is set on: the same band the adventure HUD uses.
func _band_plate(band: Rect2, opacity: float) -> void:
	draw_rect(band, Palette.with_alpha(Palette.SHADOW_DEEP, opacity))
	draw_rect(Rect2(band.position, Vector2(band.size.x, 1.0)),
		Palette.with_alpha(Palette.LIGHT_WARM, 0.8))
	draw_rect(Rect2(band.position.x, band.end.y - 1.0, band.size.x, 1.0),
		Palette.with_alpha(Palette.LIGHT_WARM, 0.5))
