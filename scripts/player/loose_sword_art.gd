class_name LooseSwordArt
extends Node2D
## Draws the prince's sword while it is out of his hand: flying, lying on the
## floor, or coming home (PrinceBlade).
##
## A child of the Player set top_level, so it draws in world space wherever
## the blade is, however far from the body that has gone, and is lifted out
## of the grade like the prince (MatchDusk.LIT): a sword that has to be found
## is a sword that must be seen, at dusk as at noon.
##
## The look is the duel's loose blade (scripts/duel/fighter_art.gd) -- a flat
## bar of steel with a gold guard, along the rect the simulation resolves --
## and one thing more, which is the low sun's: the blade is a mirror, so it
## throws a glint. In flight a hot white edge; lying, a flash every half
## second, so a sword on a busy floor is found by the eye before it is looked
## for; coming home, a streak of light back along its path.

var _player: Player
var _time := 0.0


## Adds the art to `player` once. Null when there is no player.
static func attach(player: Player) -> LooseSwordArt:
	if player == null:
		return null
	var existing := player.get_node_or_null(^"LooseSwordArt") as LooseSwordArt
	if existing != null:
		return existing
	var art := LooseSwordArt.new()
	art.name = "LooseSwordArt"
	art._player = player
	# Deferred: it is attached from PlayerArt._ready(), while the player is
	# still adding its children.
	player.add_child.call_deferred(art)
	return art


func _ready() -> void:
	top_level = true
	z_index = 2
	add_to_group(MatchDusk.LIT)


func _process(delta: float) -> void:
	_time += delta
	global_position = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	if _player == null:
		return
	var blade := _player.moves.blade
	if blade.is_held():
		return
	var box := blade.rect()
	var mid := roundf(box.get_center().y)
	var dir := float(blade.direction)
	match blade.mode:
		PrinceBlade.Mode.RETURNING:
			var back := blade.velocity.normalized() * -10.0
			draw_line(box.get_center(), box.get_center() + back,
				Palette.with_alpha(Palette.LIGHT, 0.5), 1.4)
			draw_rect(Rect2(box.get_center() - Vector2(1.5, 1.5), Vector2(3.0, 3.0)),
				Palette.LIGHT_SOFT)
			return
		PrinceBlade.Mode.FLYING:
			var trail_x := box.position.x - 6.0 if dir > 0.0 else box.end.x
			draw_rect(Rect2(trail_x, mid, 6.0, 1.0), Palette.with_alpha(Palette.LIGHT, 0.4))
	var flying := blade.is_flying()
	draw_rect(Rect2(box.position.x, mid - 0.7, box.size.x, 1.4),
		Palette.PAPER if flying else Palette.STEEL)
	draw_rect(Rect2(box.position.x, mid - 0.7, box.size.x, 0.5), Palette.STEEL_DARK)
	var guard_x := box.position.x + box.size.x * (0.2 if dir > 0.0 else 0.8)
	draw_rect(Rect2(guard_x - 0.6, mid - 1.8, 1.2, 3.6), Palette.LIGHT_WARM)
	if not flying and fmod(_time, 0.5) < 0.08:
		var tip_x := box.end.x - 1.0 if dir > 0.0 else box.position.x
		draw_rect(Rect2(tip_x, mid - 1.5, 1.0, 3.0), Palette.LIGHT)
