class_name FighterArt
extends Node2D
## Draws a Fighter out of its own hitboxes.
##
## Deliberately literal: the body is the hurtbox, the sword is the blade rect,
## a dropped sword is the loose blade rect. A duel is decided by where those
## three rectangles are, so the art that shows them is the art that teaches the
## game — and it means a filmstrip of a clash would be a picture of the
## simulation rather than an illustration of it.
##
## Flat polygons from scripts/core/palette.gd, no image assets, parent origin
## at the feet, exactly as scripts/player/player_art.gd works.
##
## Nothing here is read by the simulation, and nothing here may enter a
## snapshot: it is presentation, and the checksum must never see it.

## Seat one keeps the crimson prince; seat two is steel and sea-green.
const SEAT_CLOTH: Array[Color] = [Palette.CLOTH, Palette.WATER_DEEP]
const SEAT_TRIM: Array[Color] = [Palette.CLOTH_DARK, Palette.STEEL_DARK]

var seat := 0

var _fighter: Fighter


## Attaches the art to a fighter. The match may call this, or the scene may
## carry a FighterArt child and set `seat` — neither changes the simulation.
static func dress(fighter: Fighter, which: int) -> FighterArt:
	var art := fighter.get_node_or_null("FighterArt") as FighterArt
	if art == null:
		art = FighterArt.new()
		art.name = "FighterArt"
		fighter.add_child(art)
	art.seat = which
	return art


func _ready() -> void:
	_fighter = get_parent() as Fighter
	z_index = 1


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _fighter == null:
		return
	var origin := _fighter.position
	_draw_body(origin)
	_draw_blade(origin)
	_draw_strike(origin)
	_draw_loose(origin)


func _draw_body(origin: Vector2) -> void:
	var body := _fighter.hurt_rect()
	if body.size == Vector2.ZERO:
		# A corpse has no hurtbox, so draw it as the thing it now is.
		var tuning := _fighter.tuning
		body = Rect2(
			origin.x - tuning.body_width, origin.y - tuning.roll_height,
			tuning.body_width * 2.0, tuning.roll_height
		)
		draw_rect(Rect2(body.position - origin, body.size), SEAT_TRIM[seat % 2])
		return
	var local := Rect2(body.position - origin, body.size)
	draw_rect(local, SEAT_CLOTH[seat % 2])
	# A lit edge on the side the fighter faces, so the facing reads at 16 px.
	var edge := 2.0
	var x := local.position.x if _fighter.facing < 0 else local.end.x - edge
	draw_rect(Rect2(x, local.position.y, edge, local.size.y), SEAT_TRIM[seat % 2])
	if local.size.y >= _fighter.tuning.duck_height:
		draw_rect(Rect2(local.position.x, local.position.y, local.size.x, 4.0), Palette.PAPER)


func _draw_blade(origin: Vector2) -> void:
	var blade := _fighter.blade_rect()
	if blade.size == Vector2.ZERO:
		return
	var colour := Palette.LIGHT_SOFT if _fighter.is_attacking() else Palette.STEEL
	draw_rect(Rect2(blade.position - origin, blade.size), colour)


func _draw_strike(origin: Vector2) -> void:
	var strike := _fighter.strike_rect()
	if strike.size == Vector2.ZERO:
		return
	draw_rect(Rect2(strike.position - origin, strike.size), Palette.SHADOW_WARM)


func _draw_loose(origin: Vector2) -> void:
	var blade := _fighter.blade
	if blade.is_held():
		return
	var rect := blade.rect(_fighter.tuning)
	var colour := Palette.PAPER if blade.mode == DuelBlade.Mode.FLYING else Palette.STEEL_DARK
	draw_rect(Rect2(rect.position - origin, rect.size), colour)
