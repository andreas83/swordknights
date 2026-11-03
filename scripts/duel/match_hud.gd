class_name MatchHud
extends Control
## What the rope is doing: who has initiative, which way, and how far.
##
## Drawn rather than built out of Control nodes, for the same reason
## scripts/ui/hud.gd is: it shares the palette and the shapes with everything
## else on screen. Typography, safe areas and the reserved overlay band all come
## from scripts/ui (docs/ui.md), so this screen and the adventure HUD cannot
## drift apart -- and nothing here touches ThemeDB.fallback_font.
##
## WHERE THINGS GO
## Chrome hangs from the top of `UiLayout.content()`: the rope, the line that
## names it, the network line, then the persistent hint. Words thrown up by an
## event (a death, the initiative, the gate) and the result go in
## `UiLayout.banner()` and nowhere else. The bottom of the screen is the floor
## the fight is on, and a zone's floor can be a row of spikes; the only things
## drawn down there are the two respawn rings, which are marks, not words.
##
## THE INITIATIVE INDICATOR
## The specification calls for showArrowUI(currentLeader), and an arrow is right
## — but it has to say three things at once, because a player glancing up mid-
## sprint needs all three: WHO is leading (the colour), WHICH WAY the world is
## open (the direction it points), and HOW FAR along the rope is (the zone
## pips). Neutral is drawn as neither arrow rather than as a dimmed one: nobody
## is leading is a real state, not a missing value, and the usual bug in a mode
## like this is a screen that implies someone is pushing when nobody is.
##
## WHO IS WHO
## Against the computer the seats have names, and the screen says which is
## which where the eye already is: a tag at each end of the rope, on the side
## of that seat's gate, with a lozenge in the seat's colour -- YOU beside the
## west gate, CPU and its level beside the east. The tags hug the rope rather
## than the screen's corners, because the top right corner is the pause and
## mute buttons' on a phone. The names then carry through the line under the
## rope and the result. The one-keyboard duel sets no tags: ONE and TWO are
## the arrow's colours, and the arrow says it.

const PIP := 4.0
const PIP_GAP := 13.0
const ARROW := 13.0
## How far beyond an end pip a seat's lozenge sits: past the arrow's tip, which
## is ARROW + 8 out, by a few units more than the lozenge is wide.
const TAG_OFFSET := ARROW + 14.0
## Seconds a flashed word stays up.
const FLASH_TIME := 1.1
## A hint wider than the safe area is broken at its separators instead of
## running off both edges of a 4:3 screen.
const HINT_BREAK := "  ·  "

var fight: DuelMatch
## Optional. Set for an online match; left null for a local one.
var session: NetSession
## Which seat this screen is driving, or -1 for a local match with both.
var your_slot := -1
## Per seat, a name and an optional second line -- ["YOU"], ["CPU", "HARD"] --
## or empty for seats known only as ONE and TWO. See WHO IS WHO above.
var seat_tags: Array[PackedStringArray] = []
var footer := ""

var _time := 0.0
var _flash := 0.0
var _flash_options := PackedStringArray()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	get_viewport().size_changed.connect(queue_redraw)


## A short line thrown up in the band. `terse` is said instead when `text` will
## not fit across the screen at the display cut -- a 4:3 tablet is 320 units
## wide and "ONE HAS THE INITIATIVE" is not.
func flash(text: String, terse: String = "") -> void:
	_flash_options = PackedStringArray([text])
	if terse != "":
		_flash_options.append(terse)
	_flash = FLASH_TIME


## Takes `text` off the band if it is still showing. For a word that a network
## correction has made untrue -- "ONE DOWN" over a fighter the host says is
## standing -- and only for that one: a newer flash is left alone.
func withdraw(text: String) -> void:
	if not _flash_options.is_empty() and _flash_options[0] == text:
		_flash = 0.0


func _process(delta: float) -> void:
	_time += delta
	_flash = maxf(0.0, _flash - delta)
	queue_redraw()


func _draw() -> void:
	if fight == null or fight.strip == null or size.x <= 0.0:
		return
	var content := UiLayout.content(size)
	var band := UiLayout.banner(size)

	var y := _draw_rope(content)
	y = _draw_status(content, y)
	_draw_respawns(content)
	if fight.phase == DuelMatch.Phase.MATCH_OVER:
		_draw_result(band)
		return
	_draw_hint(content, y)
	if session != null and session.desync_count > 0:
		_draw_desync(band)
	else:
		_draw_flash(band)


## The zone pips, with the arrow of initiative over them, and the line that
## names what the arrow says. Reads left to right as the strip does: seat one is
## pulling toward the left pip, seat two the right. Returns the y below it.
func _draw_rope(content: Rect2) -> float:
	var zones := fight.zone_count()
	var span := float(zones - 1) * PIP_GAP
	var cx := roundf(content.position.x + content.size.x * 0.5)
	var origin := Vector2(roundf(cx - span * 0.5), content.position.y + PIP)
	var leader := fight.leader_slot()

	for zone: int in zones:
		var at := origin + Vector2(float(zone) * PIP_GAP, 0.0)
		var is_here := zone == fight.zone_index
		var is_gate := zone == 0 or zone == zones - 1
		var colour := Palette.LIGHT_SOFT if is_here else Palette.with_alpha(
			Palette.LIGHT, 0.30
		)
		if is_here:
			draw_circle(at, PIP, colour)
		else:
			draw_arc(at, PIP, 0.0, TAU, 16, colour, 1.0)
		if is_gate:
			# The two ends are gates, not stops: a thicker ring says so.
			var seat := 0 if zone == 0 else 1
			draw_arc(at, PIP + 2.4, 0.0, TAU, 20,
				Palette.with_alpha(GoreField.BLOOD_FRESH[seat], 0.75), 1.2)

	var below := origin.y + PIP + 4.0
	_draw_tags(origin, span, below)
	if leader < 0:
		UiFont.draw_text(self, "NEUTRAL", Vector2(cx, below), UiFont.Cut.MICRO,
			Palette.with_alpha(Palette.PAPER, 0.6), UiFont.Align.CENTER, 0.6)
		return below + UiFont.line(UiFont.Cut.MICRO)

	# The arrow: the leader's colour, pointing the way the world is open.
	var direction := float(ZoneStrip.goal_direction(leader))
	var tip := origin + Vector2(
		roundf(span * 0.5 + direction * (span * 0.5 + ARROW + 8.0)), 0.0
	)
	var colour := GoreField.BLOOD_FRESH[leader]
	var arrow := PackedVector2Array([
		tip,
		tip - Vector2(direction * ARROW, -ARROW * 0.52),
		tip - Vector2(direction * ARROW, ARROW * 0.52),
	])
	var cast := PackedVector2Array()
	for point: Vector2 in arrow:
		cast.append(point + UiMarks.CAST)
	draw_colored_polygon(cast, Palette.with_alpha(Palette.INK, 0.6))
	draw_colored_polygon(arrow, colour)

	# The words are paper, not the seat's colour: crimson type on a crimson
	# sky is the arrow's job to carry, and a line nobody can read says nothing.
	var way := "WEST" if direction < 0.0 else "EAST"
	var said := "%s PUSHING %s" % [seat_name(leader), way]
	if leader == your_slot:
		said = "YOU ARE PUSHING %s" % way
	if not seat_tags.is_empty():
		# With tags up the arrow points at the leader's own tag -- each seat's
		# gate is on its own side -- so the line need only say who, and it has
		# to: a longer one runs into the tags' second lines at 320 units.
		said = "YOU LEAD" if leader == your_slot else "%s LEADS" % seat_name(leader)
	UiFont.draw_text(self, said, Vector2(cx, below), UiFont.Cut.MICRO,
		Palette.PAPER, UiFont.Align.CENTER, 0.8)
	return below + UiFont.line(UiFont.Cut.MICRO)


## What the band and the rope call a seat: its tag's name, or ONE and TWO.
func seat_name(slot: int) -> String:
	if slot >= 0 and slot < seat_tags.size() and not seat_tags[slot].is_empty():
		return seat_tags[slot][0]
	return DuelRules.slot_label(slot)


## A tag at each end of the rope, outside the arrow: the seat's lozenge in its
## colour, its name on the pip row, its second line under it, dimmer. Seat one
## is the west end and reads leftward from the rope; seat two the east.
func _draw_tags(origin: Vector2, span: float, below: float) -> void:
	if seat_tags.size() < 2:
		return
	var cut := UiFont.Cut.MICRO
	var name_y := roundf(origin.y - UiFont.cap(cut) * 0.5)
	for slot: int in 2:
		var tag := seat_tags[slot]
		if tag.is_empty():
			continue
		var side := -1.0 if slot == 0 else 1.0
		var end := origin.x + (0.0 if slot == 0 else span)
		var mark := Vector2(roundf(end + side * TAG_OFFSET), origin.y)
		# A rim of light under the seat's colour: crimson on a crimson sky is
		# otherwise a mark nobody can find.
		UiMarks.lozenge(self, mark, 4.4, Palette.with_alpha(Palette.LIGHT_SOFT, 0.85), 0.8)
		UiMarks.lozenge(self, mark, 3.0, GoreField.BLOOD_FRESH[slot])
		var at := Vector2(mark.x + side * 6.0, name_y)
		var align := UiFont.Align.RIGHT if slot == 0 else UiFont.Align.LEFT
		UiFont.draw_text(self, tag[0], at, cut, Palette.PAPER, align, 0.8)
		if tag.size() > 1:
			UiFont.draw_text(self, tag[1], Vector2(at.x, below), cut,
				Palette.with_alpha(Palette.LIGHT_SOFT, 0.85), align, 0.6)


## The connection, for an online match. Returns the y below it.
func _draw_status(content: Rect2, y: float) -> float:
	if session == null:
		return y
	var cx := content.position.x + content.size.x * 0.5
	UiFont.draw_text(self, session.status_line(), Vector2(cx, y), UiFont.Cut.MICRO,
		Palette.with_alpha(Palette.LIGHT_SOFT, 0.8 if session.desync_count > 0 else 0.55),
		UiFont.Align.CENTER, 0.6)
	return y + UiFont.line(UiFont.Cut.MICRO)


## The persistent hint, under the rope. Broken at its separators when it is
## wider than the safe area.
func _draw_hint(content: Rect2, y: float) -> void:
	if footer == "":
		return
	var cx := content.position.x + content.size.x * 0.5
	var lines := PackedStringArray([footer])
	if UiFont.width(footer, UiFont.Cut.MICRO) > content.size.x:
		lines = footer.split(HINT_BREAK, false)
	for line: String in lines:
		UiFont.draw_text(self, line, Vector2(cx, y), UiFont.Cut.MICRO,
			Palette.with_alpha(Palette.PAPER, 0.5), UiFont.Align.CENTER, 0.5)
		y += UiFont.line(UiFont.Cut.MICRO)


## A ring closing on each fighter who is down, so the leader can see how long
## they have before the other one is standing in front of them.
func _draw_respawns(content: Rect2) -> void:
	for slot: int in 2:
		var left := fight.respawn_left(slot)
		if left <= 0.0:
			continue
		var done := 1.0 - clampf(left / DuelMatch.RESPAWN_DELAY, 0.0, 1.0)
		var at := Vector2(
			content.position.x + 8.0 if slot == 0 else content.end.x - 8.0,
			content.end.y - 8.0
		)
		var colour := GoreField.BLOOD_FRESH[slot]
		draw_arc(at, 8.0, 0.0, TAU, 24, Palette.with_alpha(colour, 0.25), 1.0)
		draw_arc(at, 8.0, -PI * 0.5, -PI * 0.5 + TAU * done, 24, colour, 2.0)
		if slot == your_slot:
			draw_circle(at, 2.0, Palette.PAPER)


## A struck word in the reserved band, where nothing of the fight is.
func _draw_flash(band: Rect2) -> void:
	if _flash <= 0.0 or _flash_options.is_empty():
		return
	var alpha := clampf(_flash, 0.0, 1.0)
	var room := band.size.x - UiLayout.GUTTER * 2.0
	var cut := UiFont.Cut.DISPLAY
	var said := UiFont.fit(_flash_options, room, cut)
	if UiFont.width(said, cut) > room:
		cut = UiFont.Cut.TEXT
		said = UiFont.fit(_flash_options, room, cut)
	UiFont.draw_text(self, said,
		Vector2(band.position.x + band.size.x * 0.5,
			band.position.y + (band.size.y - UiFont.cap(cut)) * 0.5),
		cut, Palette.with_alpha(Palette.PAPER, alpha), UiFont.Align.CENTER, alpha * 0.8)


## Who was taken through which gate, on the carved plate the adventure HUD
## sets its overlays on. Four things in forty-eight units: title, rule, how,
## and what to press. The numbers are the band's, not the screen's, so a taller
## phone does not spread them out.
func _draw_result(band: Rect2) -> void:
	var winner := maxi(fight.winner, 0)
	var cx := band.position.x + band.size.x * 0.5
	var room := band.size.x - UiLayout.GUTTER * 2.0
	draw_rect(Rect2(Vector2.ZERO, size), Palette.with_alpha(Palette.INK, 0.45))
	_band_plate(band, 0.6)

	var title := UiFont.fit(PackedStringArray([
		"YOU WIN" if winner == your_slot else "%s WINS" % seat_name(winner),
	]), room, UiFont.Cut.DISPLAY)
	UiFont.draw_text(self, title, Vector2(cx, band.position.y + 4.0),
		UiFont.Cut.DISPLAY, Palette.PAPER, UiFont.Align.CENTER, 0.8)
	UiMarks.rule(self, Vector2(cx, band.position.y + 22.0),
		minf(band.size.x * 0.3, 48.0), Palette.with_alpha(GoreField.BLOOD_FRESH[winner], 0.9))
	var gate := "WEST" if ZoneStrip.goal_direction(winner) < 0 else "EAST"
	var how := UiFont.fit(PackedStringArray([
		"TAKEN THROUGH THE %s GATE" % gate, "THROUGH THE %s GATE" % gate,
	]), room, UiFont.Cut.TEXT)
	UiFont.draw_text(self, how, Vector2(cx, band.position.y + 27.0),
		UiFont.Cut.TEXT, Palette.LIGHT_SOFT, UiFont.Align.CENTER, 0.6)
	if footer != "":
		var hint := UiFont.fit(PackedStringArray([
			footer, footer.replace(HINT_BREAK, "  "),
		]), room, UiFont.Cut.MICRO)
		UiFont.draw_text(self, hint, Vector2(cx, band.position.y + 39.0),
			UiFont.Cut.MICRO, Palette.with_alpha(Palette.PAPER, 0.8),
			UiFont.Align.CENTER, 0.6)


## A match that has quietly stopped agreeing with itself is worse than one that
## admits it, so a desync gets the band to itself.
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
