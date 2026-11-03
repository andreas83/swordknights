class_name EclipseBeam
extends FoeProjectile
## The whole kept sun, poured through the King's disc as one beam: the
## finale's single blow (docs/campaign.md, "The Eclipse -- the boss").
##
## ## A ray, not a bolt
##
## It is a FoeProjectile so that Game referees it the way it referees every
## shot -- parried, landed, or spent on stone -- but what it threatens is not a
## bolt-sized box. Its position is the head, which advances at the King's
## BEAM_SPEED, and the danger is the whole ray from the disc (`origin_x`) to the
## head, BEAM_BAND tall around chest height. So there is no going over it, or
## under it: a jump comes down into the ray behind the head, and the band
## reaches a crouching prince's shoulders. A backstep does not let it by, as
## no projectile is let by. The parry is the only answer, which is the point:
## it is the move the prince has had since Chapter I, and the swordknight's
## blade was always a mirror.
##
## ## Turned
##
## Parried, the light goes back the way it came, faster (RETURN_SPEED): what
## is left of the ray is drained back toward the disc and only its returning
## head is the prince's. That head is the shot Game meets against the foes, so
## the King is struck when the light reaches his disc and not on the frame of
## the parry, while the ray still touches him.

## Its tell on stone, through Game's front door like a foe's.
signal cue(voice: StringName, options: Dictionary)

## How tall the ray is, centred on its position.
const BEAM_BAND := 16.0
## How long the returning head is, the part that strikes.
const PACKET := 12.0

## Where the ray leaves the disc: fixed at the pour.
var origin_x := 0.0
## How far the ray had reached when it was turned.
var turned_at := 0.0

var _time := 0.0


func _init() -> void:
	size = Vector2(PACKET, BEAM_BAND)
	damage = 1


## The ray from the disc to the head while it is the King's; only the
## returning head once a parry has made it the prince's.
func rect() -> Rect2:
	var head := global_position.x
	var top := global_position.y - BEAM_BAND * 0.5
	if reflected:
		var back := head - PACKET * 0.5
		return Rect2(back, top, PACKET, BEAM_BAND)
	return Rect2(minf(origin_x, head), top, absf(head - origin_x), BEAM_BAND)


func reflect() -> bool:
	turned_at = global_position.x
	return super()


## How long the ray is now, origin to head.
func reach() -> float:
	return absf(global_position.x - origin_x)


func _physics_process(delta: float) -> void:
	_time += delta
	var was := is_spent()
	super(delta)
	if not was and is_spent() and level != null and level.is_solid_at(global_position):
		cue.emit(&"masonry", {"pitch": 1.4, "volume_db": -6.0})
	queue_redraw()


## Drawn in local space: x = 0 is the head.
func _draw() -> void:
	var back := origin_x - global_position.x
	if reflected:
		# The ray drains: what is left runs from the disc to the returning head,
		# thinning as it goes, and the head is a knot of white light.
		var left := clampf(absf(back) / maxf(1.0, absf(turned_at - origin_x)), 0.0, 1.0)
		_ray(back, 0.0, BEAM_BAND * (0.25 + 0.5 * left))
		_head(1.0)
		return
	_ray(back, 0.0, BEAM_BAND)
	_head(0.0)


## A ray from x0 to x1 (local), `band` tall: three flat tones from the rim in,
## and a core that steps on the 12 fps clock the way a flame does.
func _ray(x0: float, x1: float, band: float) -> void:
	var from := minf(x0, x1)
	var length := absf(x1 - x0)
	if length < 1.0:
		return
	var step := int(_time * 12.0) % 2
	var half := roundf(band * 0.5)
	draw_rect(Rect2(from, -half, length, half * 2.0), Palette.LIGHT)
	var inner := maxf(1.0, half - 2.0)
	draw_rect(Rect2(from, -inner, length, inner * 2.0), Palette.LIGHT_SOFT)
	var core := maxf(1.0, inner - 2.0 - float(step))
	draw_rect(Rect2(from, -core, length, core * 2.0), Palette.PAPER)


## The head: a flared disc where the light meets the air, larger once it is
## the prince's and running home.
func _head(turned: float) -> void:
	var flare := 2.0 + float(int(_time * 12.0) % 2)
	var radius := roundf(BEAM_BAND * 0.5 + flare + turned * 2.0)
	draw_circle(Vector2.ZERO, radius, Palette.with_alpha(Palette.LIGHT, 0.35))
	draw_circle(Vector2.ZERO, roundf(radius * 0.7), Palette.LIGHT_SOFT)
	draw_circle(Vector2.ZERO, roundf(radius * 0.4), Palette.PAPER)
	if turned > 0.0:
		var dir := signf(velocity.x)
		draw_rect(Rect2(-radius * 0.5 * dir - 0.5, -radius, 1.0, radius * 2.0), Palette.STEEL)
