class_name PlayerArt
extends Node2D
## Draws the prince as a posed cloak silhouette rather than a sprite sheet.
##
## Shapes derive from the character's state and state_time, which keeps the
## foundation asset-free. Swapping in real sprites later means replacing this
## one file; nothing in gameplay reads it.
##
## The parent's origin is at the feet, so everything here is drawn in negative Y.

@export var cloth: Color = Palette.CLOTH
@export var cloth_dark: Color = Palette.CLOTH_DARK

var _player: Player
var _time: float = 0.0


func _ready() -> void:
	_player = get_parent() as Player


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if _player == null:
		return
	# Invulnerability flicker: skip whole frames so the hit reads clearly.
	if _player.invulnerable > 0.0 and int(_time * 18.0) % 2 == 0:
		return

	var pose := _posture()
	var height: float = Tuning.BODY_HEIGHT * pose["squash"]
	var width: float = Tuning.BODY_WIDTH / maxf(0.6, pose["squash"])
	var feet := 0.0
	var top := feet - height
	var lean: float = pose["lean"] * _player.facing
	var leg_swing: float = pose["leg_swing"]

	if _player.is_on_floor():
		draw_circle(Vector2(1.0, 1.0), width * 0.72, Palette.with_alpha(Palette.INK, 0.25))

	if not is_zero_approx(leg_swing):
		draw_rect(Rect2(-2.6 + leg_swing, feet - 5.0, 2.2, 5.0), Palette.INK)
		draw_rect(Rect2(0.6 - leg_swing, feet - 5.0, 2.2, 5.0), Palette.INK)

	# Cloak: a cone from the shoulders to the hem, split into lit and shade.
	var hem_half := width * 0.92
	var shoulder_y := top + height * 0.2
	var apex := Vector2(lean, top + height * 0.08)

	draw_colored_polygon(PackedVector2Array([
		apex, Vector2(hem_half, feet), Vector2(-hem_half, feet),
	]), cloth_dark)
	draw_colored_polygon(PackedVector2Array([
		apex,
		Vector2(hem_half * _player.facing, feet),
		Vector2(hem_half * _player.facing * 0.1, feet),
	]), cloth)

	# Sash catching the light.
	draw_rect(Rect2(-width * 0.5 + lean * 0.4, shoulder_y + height * 0.22, width, 1.6),
		Palette.LIGHT_WARM)

	if _player.state == Player.State.ATTACK:
		_draw_swing(shoulder_y, height)
	elif _player.is_hanging():
		draw_rect(Rect2(-width * 0.8, top + 1.0, width * 1.6, 2.2), Palette.INK)
	else:
		var arm_swing: float = pose["arm_swing"]
		var hand_x := _player.facing * (width * 0.7 + arm_swing)
		var hand_y := shoulder_y + height * 0.18
		draw_rect(Rect2(minf(hand_x, 0.0), hand_y, absf(hand_x) + 1.4, 2.0), cloth_dark)

	_draw_hood(apex.x, top + 3.2 + pose["hood_drop"], width)


func _draw_hood(x: float, y: float, width: float) -> void:
	draw_circle(Vector2(x, y), width * 0.46, Palette.INK)
	draw_colored_polygon(PackedVector2Array([
		Vector2(x - _player.facing * width * 0.1, y - width * 0.5),
		Vector2(x + _player.facing * width * 0.62, y + width * 0.1),
		Vector2(x - _player.facing * width * 0.3, y + width * 0.4),
	]), cloth_dark)
	draw_rect(Rect2(x + _player.facing * width * 0.22, y - 0.4, 1.3, 1.1), Palette.LIGHT)


func _draw_swing(shoulder_y: float, height: float) -> void:
	var phase := minf(1.0, _player.state_time / Tuning.ATTACK_TIME)
	var angle := (-0.9 + phase * 2.1) * _player.facing
	var length := 15.0
	var origin := Vector2(_player.facing * 3.0, shoulder_y + height * 0.16)
	var tip := origin + Vector2(cos(angle) * length * _player.facing, sin(angle) * length)

	draw_colored_polygon(PackedVector2Array([
		origin + Vector2(0.0, -1.4), tip, origin + Vector2(0.0, 1.4),
	]), Palette.STEEL)
	draw_circle(origin, 1.8, Palette.LIGHT_WARM)
	if phase > 0.25 and phase < 0.8:
		draw_circle(tip, 2.2, Palette.with_alpha(Palette.PAPER, 0.5))


func _posture() -> Dictionary:
	var t := _player.state_time
	match _player.state:
		Player.State.RUN:
			var c := sin(t * 16.0)
			return _pose(1.0, 2.6, c * 2.4, c * 2.2, 0.0)
		Player.State.WALK:
			var c2 := sin(t * 9.0)
			return _pose(1.0, 1.2, c2 * 1.4, c2 * 1.3, 0.0)
		Player.State.TURN:
			return _pose(0.96, -2.2, -1.5, 0.0, 0.4)
		Player.State.CROUCH:
			return _pose(0.6, 0.6, 0.0, 0.0, 0.8)
		Player.State.JUMP:
			return _pose(1.06, 1.8, 2.8, 1.4, -0.6)
		Player.State.FALL:
			return _pose(1.03, 1.2, 1.8, -1.2, -0.3)
		Player.State.LAND:
			return _pose(0.84, 0.8, -1.0, 0.0, 1.2)
		Player.State.HANG:
			return _pose(1.08, 0.0, 0.0, sin(_time * 3.0) * 0.6, 1.4)
		Player.State.CLIMB_UP:
			return _pose(0.92, 1.6, 0.0, 1.6, 0.6)
		Player.State.LADDER:
			return _pose(1.0, 0.0, sin(t * 8.0) * 2.0, sin(t * 8.0) * 1.6, 0.0)
		Player.State.HURT:
			return _pose(0.95, -3.0, -2.4, 0.0, 1.6)
		Player.State.DEAD:
			return _pose(0.55, -4.0, -3.0, 0.0, 2.4)
		Player.State.ATTACK:
			return _pose(1.0, 2.2, 3.2, 0.0, 0.0)
		_:
			return _pose(1.0 + sin(_time * 2.2) * 0.012, 0.4, 0.0, 0.0, 0.0)


func _pose(squash: float, lean: float, arm: float, leg: float, hood: float) -> Dictionary:
	return {
		"squash": squash, "lean": lean,
		"arm_swing": arm, "leg_swing": leg, "hood_drop": hood,
	}
