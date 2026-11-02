class_name DuelArt
extends Node2D
## Tells the two duellists apart, and shows the things a duel needs read at a
## glance: whose guard is up, who is staggered, and which one is you.
##
## scripts/player/player_art.gd already draws the cloak silhouette and knows
## nothing about duelling, so this is a sibling layer rather than an edit to it:
## it re-colours that silhouette through its exported cloth colours and draws
## the duel-only tells on top. Parent origin is at the feet, as there.
##
## No image assets, same as everything else — flat polygons out of
## scripts/core/palette.gd.

## Seat one keeps the crimson prince; seat two is steel and sea-green, which
## separates cleanly against a gold-and-crimson world without adding a hue the
## palette does not already contain.
const SEAT_CLOTH: Array[Color] = [Palette.CLOTH, Palette.WATER_DEEP]
const SEAT_CLOTH_DARK: Array[Color] = [Palette.CLOTH_DARK, Palette.STEEL_DARK]
const SEAT_MARK: Array[Color] = [Palette.LIGHT, Palette.WATER]

var slot := 0
## True for the duellist this screen is controlling. Drawn with a marker so a
## player glancing at a networked match can find themselves immediately.
var is_yours := false

var _duellist: Player
var _time := 0.0


## Colours a duellist for its seat and attaches the tell layer. Called by the
## scene, not by the simulation — Duel itself has no opinion about looks.
static func dress(duellist: Player, seat: int, yours: bool) -> DuelArt:
	var silhouette := duellist.get_node_or_null("PlayerArt") as PlayerArt
	if silhouette != null:
		silhouette.cloth = SEAT_CLOTH[seat]
		silhouette.cloth_dark = SEAT_CLOTH_DARK[seat]

	var art := DuelArt.new()
	art.name = "DuelArt"
	art.slot = seat
	art.is_yours = yours
	duellist.add_child(art)
	return art


func _ready() -> void:
	_duellist = get_parent() as Player
	# Above the cloak, so the guard reads in front of the body.
	z_index = 1


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if _duellist == null:
		return

	var height := Tuning.BODY_HEIGHT
	var facing := float(_duellist.facing)

	if _duellist.is_alive():
		_draw_seat_mark(height)

	match _duellist.state:
		Player.State.GUARD:
			_draw_guard(height, facing)
		Player.State.STAGGER:
			_draw_stagger(height)
		_:
			pass


## A pip over the head: filled for the duellist you are driving, hollow for the
## other one.
func _draw_seat_mark(height: float) -> void:
	var at := Vector2(0.0, -height - 7.0)
	var colour := SEAT_MARK[slot]
	if is_yours:
		var bob := sin(_time * 3.0) * 0.6
		draw_colored_polygon(PackedVector2Array([
			at + Vector2(0.0, 2.4 + bob),
			at + Vector2(-2.6, -1.6 + bob),
			at + Vector2(2.6, -1.6 + bob),
		]), colour)
	else:
		draw_arc(at, 2.2, 0.0, TAU, 12, Palette.with_alpha(colour, 0.75), 1.0)


## The raised sword, held across the body on the side it faces. A parry is a
## timing window, so the window itself is drawn: bright while it is open, plain
## steel once it has closed into an ordinary block.
func _draw_guard(height: float, facing: float) -> void:
	var open := _duellist.guard_time <= Player.PARRY_WINDOW
	var x := facing * (Tuning.BODY_WIDTH * 0.5 + 2.0)
	var top := -height * 0.92
	var bottom := -height * 0.18

	draw_colored_polygon(PackedVector2Array([
		Vector2(x - facing * 1.3, top),
		Vector2(x + facing * 1.3, top + 1.6),
		Vector2(x + facing * 1.3, bottom),
		Vector2(x - facing * 1.3, bottom - 1.6),
	]), Palette.STEEL if not open else Palette.PAPER)

	# Guard hand.
	draw_circle(Vector2(x * 0.55, -height * 0.52), 1.7, Palette.LIGHT_WARM)

	if open:
		# A short flare on the blade while the parry is live.
		draw_line(
			Vector2(x + facing * 2.0, top + 2.0),
			Vector2(x + facing * 5.5, -height * 0.55),
			Palette.with_alpha(Palette.LIGHT_SOFT, 0.85), 1.0
		)


## Knocked open. Sparks where the blades met, and a lean that says the swing is
## gone — the window the defender just earned.
func _draw_stagger(height: float) -> void:
	var phase := _duellist.state_time
	var fade := clampf(1.0 - phase * 2.2, 0.0, 1.0)
	if fade <= 0.0:
		return
	var origin := Vector2(float(_duellist.facing) * 5.0, -height * 0.6)
	for i: int in 4:
		var angle := float(i) * TAU / 4.0 + phase * 7.0
		# Sparks fly out and die.
		var reach := 3.0 + phase * 26.0
		draw_line(
			origin + Vector2(cos(angle), sin(angle)) * reach * 0.45,
			origin + Vector2(cos(angle), sin(angle)) * reach,
			Palette.with_alpha(Palette.PAPER, fade * 0.9), 1.0
		)
	draw_circle(origin, 2.0 + fade * 2.0, Palette.with_alpha(Palette.LIGHT_SOFT, fade * 0.6))
