class_name MatchHud
extends Control
## What the rope is doing: who has initiative, which way, and how far.
##
## Drawn rather than built out of Control nodes, for the same reason
## scripts/duel/duel_hud.gd and scripts/ui/hud.gd are: it shares the palette and
## the shapes with everything else on screen.
##
## THE INITIATIVE INDICATOR
## The specification calls for showArrowUI(currentLeader), and an arrow is right
## — but it has to say three things at once, because a player glancing up mid-
## sprint needs all three: WHO is leading (the colour), WHICH WAY the world is
## open (the direction it points), and HOW FAR along the rope is (the zone
## pips). Neutral is drawn as neither arrow rather than as a dimmed one: nobody
## is leading is a real state, not a missing value, and the usual bug in a mode
## like this is a screen that implies someone is pushing when nobody is.

const PIP := 4.0
const PIP_GAP := 13.0
const ARROW := 13.0

var fight: DuelMatch
## Which seat this screen is driving, or -1 for a local match with both.
var your_slot := -1
var footer := ""

var _font: Font
var _flash := 0.0
var _flash_text := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font


func flash(text: String) -> void:
	_flash_text = text
	_flash = 1.1


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	queue_redraw()


func _draw() -> void:
	if fight == null or fight.strip == null:
		return
	_draw_rope(size)
	_draw_respawns(size)
	_draw_flash(size)
	_draw_footer(size)


## The zone pips, with the arrow of initiative over them. Reads left to right as
## the strip does: seat one is pulling toward the left pip, seat two the right.
func _draw_rope(view: Vector2) -> void:
	var zones := fight.zone_count()
	var span := float(zones - 1) * PIP_GAP
	var origin := Vector2(view.x * 0.5 - span * 0.5, 13.0)
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

	if leader < 0:
		_text(Vector2(view.x * 0.5, 30.0), "NEUTRAL",
			Palette.with_alpha(Palette.PAPER, 0.55), true)
		return

	# The arrow: the leader's colour, pointing the way the world is open.
	var direction := float(ZoneStrip.goal_direction(leader))
	var tip := origin + Vector2(
		(span * 0.5) + direction * (span * 0.5 + ARROW + 8.0), 0.0
	)
	var colour := GoreField.BLOOD_FRESH[leader]
	draw_colored_polygon(PackedVector2Array([
		tip,
		tip - Vector2(direction * ARROW, -ARROW * 0.52),
		tip - Vector2(direction * ARROW, ARROW * 0.52),
	]), colour)
	_text(
		Vector2(view.x * 0.5, 30.0),
		"%s PUSHING %s" % [
			DuelRules.slot_label(leader), "WEST" if direction < 0.0 else "EAST",
		],
		colour, true
	)


## A ring closing on each fighter who is down, so the leader can see how long
## they have before the other one is standing in front of them.
func _draw_respawns(view: Vector2) -> void:
	for slot: int in 2:
		var left := fight.respawn_left(slot)
		if left <= 0.0:
			continue
		var done := 1.0 - clampf(left / DuelMatch.RESPAWN_DELAY, 0.0, 1.0)
		var at := Vector2(24.0 if slot == 0 else view.x - 24.0, view.y - 22.0)
		var colour := GoreField.BLOOD_FRESH[slot]
		draw_arc(at, 8.0, 0.0, TAU, 24, Palette.with_alpha(colour, 0.25), 1.0)
		draw_arc(at, 8.0, -PI * 0.5, -PI * 0.5 + TAU * done, 24, colour, 2.0)
		if slot == your_slot:
			draw_circle(at, 2.0, Palette.PAPER)


func _draw_flash(view: Vector2) -> void:
	if _flash <= 0.0 or _flash_text == "":
		return
	var alpha := clampf(_flash, 0.0, 1.0)
	_text(
		Vector2(view.x * 0.5, view.y * 0.42), _flash_text,
		Palette.with_alpha(Palette.PAPER, alpha), true, 2.0
	)


func _draw_footer(view: Vector2) -> void:
	if fight.phase == DuelMatch.Phase.MATCH_OVER:
		_text(
			Vector2(view.x * 0.5, view.y * 0.5),
			"%s IS TAKEN THROUGH THE GATE" % DuelRules.slot_label(fight.winner),
			GoreField.BLOOD_FRESH[maxi(fight.winner, 0)], true, 1.6
		)
	if footer == "":
		return
	_text(
		Vector2(view.x * 0.5, view.y - 9.0), footer,
		Palette.with_alpha(Palette.PAPER, 0.5), true
	)


## Letter-spaced small caps, the same shape scripts/ui/hud.gd uses. Repeated
## rather than shared because scripts/ui is not this branch's to change.
func _text(
	at: Vector2, text: String, colour: Color, centred: bool, scale: float = 1.0
) -> void:
	if _font == null:
		return
	var points := 8.0 * scale
	var spacing := 1.6 * scale
	var width := 0.0
	for i: int in text.length():
		width += _font.get_string_size(text[i], HORIZONTAL_ALIGNMENT_LEFT, -1,
			int(points)).x + spacing
	var cursor := at - Vector2(width * 0.5 if centred else 0.0, 0.0)
	for i: int in text.length():
		var glyph := text[i]
		draw_string(_font, cursor, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1,
			int(points), colour)
		cursor.x += _font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1,
			int(points)).x + spacing
