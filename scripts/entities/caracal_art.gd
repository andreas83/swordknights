class_name CaracalArt
extends Node2D
## Draws the Caracal, posed from the cat's state machine.
##
## ## The only foe on four legs
##
## Every other figure in the game is a person, a column standing on two feet.
## The cat is the opposite at every point the eye uses at 22 px, so its
## outline alone says *animal* before anything says *enemy*:
##
## | | Prince and sentinel | Caracal |
## | --- | --- | --- |
## | mass | vertical, a column | horizontal, a bar on four stilts |
## | top line | a cowl, a dome helm | two tall ink ear-tufts: the read |
## | legs | two, under a robe or a coat | four, long, the hind ones hocked back |
## | colour | mid red; near-black | dark wine, a lit rim along its back |
##
## Two tones, as docs/art-direction.md asks: the body in SHADOW_DEEP with the
## far legs and the tufts in INK, and one pixel of SHADOW_WARM along the back
## where the low sun catches it -- the rim is on the top edge whichever way it
## faces, because the light is in the sky. The one warm point is a gold
## collar dot: it belongs to the King. The eyes are LIGHT_SOFT, and in the
## crouch they go to PAPER and throw a star, the same "about to strike" the
## sentinel's eye slit says.
##
## ## What each state reads as
##
## | State | The read |
## | --- | --- |
## | PROWL | a loose diagonal walk, tail low, head level |
## | LOOK | stops, and the head turns back over the shoulder |
## | STALK | body sunk, head low and forward, slow placed steps |
## | CROUCH | the telegraph: flat to the ground, the rear up and wiggling, eyes burning |
## | POUNCE | stretched to a bar in the air, fore paws reaching, hind legs trailing |
## | SKID | fore legs braced, dust at the paws; then the head shakes: the opening |
## | FALL | legs splayed, nose down |
## | DYING | tumbles once and flickers out |
##
## The pose is a pure function of (state, state_time, facing, velocity), so a
## pose sheet (tools/caracal_poses.gd) can freeze any beat. The tail's lag and
## the hit flash are the only state kept here, all of it cosmetic.

const FUR := Palette.SHADOW_DEEP
const FUR_FAR := Palette.INK
const RIM := Palette.SHADOW_WARM
const TUFT := Palette.INK
const COLLAR := Palette.LIGHT
const EYE := Palette.LIGHT_SOFT
const DUST := Palette.SURFACE_EDGE

const LEG_W := 1.6
const STRIDE_HZ := 3.2
const TAIL_CHASE := 10.0
const FLASH_TIME := 0.14
const FLICKER_AT := 0.75

var _cat: Caracal
var _time := 0.0
var _flash := 0.0
var _tail := 0.0
var _f := 1.0


func _ready() -> void:
	_cat = get_parent() as Caracal
	if _cat != null:
		_cat.defeated.connect(func() -> void: _flash = 1.0)


func _process(delta: float) -> void:
	_time += delta
	_flash = maxf(0.0, _flash - delta / FLASH_TIME)
	if _cat != null:
		var want := clampf(-_cat.velocity.y / 200.0, -1.0, 1.0)
		_tail = lerpf(_tail, want, 1.0 - exp(-delta * TAIL_CHASE))
	queue_redraw()


func _c(base: Color) -> Color:
	return base if _flash <= 0.0 else base.lerp(Palette.PAPER, _flash * 0.85)


## A cat-local point, facing applied: x forward, y up from the feet (negative).
func _p(x: float, y: float) -> Vector2:
	return Vector2(x * _f, y)


func _draw() -> void:
	if _cat == null:
		return
	_f = float(_cat.facing)
	var pose := pose_for(_cat.state, _cat.state_time, _cat.crouch_time(), _cat.velocity)
	if _cat.state == Caracal.State.DYING:
		var death := _cat.state_time / Caracal.DEATH_TIME
		if death >= FLICKER_AT and int(_time * 24.0) % 2 == 0:
			return
		_draw_cat(pose)
		return
	if bool(pose["grounded"]):
		draw_colored_polygon(PackedVector2Array([
			Vector2(-8.0, -0.4), Vector2(8.0, -0.4), Vector2(6.5, 1.2), Vector2(-6.5, 1.2),
		]), Palette.with_alpha(Palette.INK, 0.3))
	_draw_cat(pose)
	_draw_dust(pose)


func _draw_cat(pose: Dictionary) -> void:
	var legs: Array = pose["legs"]
	# Far legs first, in ink: they are behind the body.
	_draw_leg(legs[1], FUR_FAR, false)
	_draw_leg(legs[3], FUR_FAR, true)
	_draw_tail(pose)
	_draw_body(pose)
	_draw_leg(legs[0], FUR, false)
	_draw_leg(legs[2], FUR, true)
	_draw_head(pose)


## The torso: a lean bar from rump to shoulders, the back's top edge rimmed.
func _draw_body(pose: Dictionary) -> void:
	var back: float = pose["back"]
	var belly: float = pose["belly"]
	var rump: float = pose["rump"]
	var lift: float = pose["rear_lift"]
	var front: float = pose["shoulder"]
	var outline := PackedVector2Array([
		_p(rump - 0.6, back - lift + 1.6), _p(rump + 1.0, back - lift - 0.2),
		_p(rump + 3.6, back - lift * 0.5 + 0.2), _p(front - 2.0, back + 0.4),
		_p(front + 0.4, back - 0.4), _p(front + 1.8, back + 1.2),
		_p(front + 1.6, belly + 0.4), _p(front - 1.0, belly + 0.8),
		_p(rump + 4.0, belly - 0.2), _p(rump + 1.0, belly - lift * 0.5 + 0.2),
		_p(rump - 0.8, back - lift + 3.6),
	])
	if Geometry2D.triangulate_polygon(outline).is_empty():
		return
	draw_colored_polygon(outline, _c(FUR))
	# The sun on the back: one pixel along the top edge.
	draw_line(_p(rump + 1.0, back - lift + 0.5), _p(front - 1.0, back + 0.1), _c(RIM), 1.0)
	draw_rect(Rect2(_p(front - 0.6, back + 1.0) - Vector2(0.5, 0.5), Vector2(1.2, 1.2)),
		_c(COLLAR))


func _draw_head(pose: Dictionary) -> void:
	var at: Vector2 = pose["head"]
	var turn: float = pose["head_turn"]
	var c := _p(at.x, at.y)
	var g := _f * turn
	var head := PackedVector2Array([
		c + Vector2(-2.0 * g, -1.4), c + Vector2(-0.6 * g, -2.2), c + Vector2(1.4 * g, -2.0),
		c + Vector2(2.6 * g, -0.8), c + Vector2(2.8 * g, 0.6), c + Vector2(1.6 * g, 1.6),
		c + Vector2(-1.2 * g, 1.8), c + Vector2(-2.4 * g, 0.6),
	])
	if not Geometry2D.triangulate_polygon(head).is_empty():
		draw_colored_polygon(head, _c(FUR))
	draw_line(c + Vector2(-1.4 * g, -1.8), c + Vector2(1.2 * g, -2.1), _c(RIM), 1.0)
	# The ears: two tall triangles, one just behind the other, each topped
	# with an ink tuft -- the caracal's whole read. Laid back in the crouch,
	# never gone.
	var lean: float = pose["ear_lean"]
	for ear: float in [-1.2, 0.4]:
		var base := c + Vector2(ear * g, -1.8)
		var tip := base + Vector2((-0.6 - lean) * g, -3.9 + absf(lean) * 0.5)
		var fill := FUR_FAR if ear < 0.0 else FUR
		draw_colored_polygon(PackedVector2Array([
			base + Vector2(-1.3, 0.4), base + Vector2(1.3, 0.4), tip,
		]), _c(fill))
		draw_line(tip, tip + Vector2((-0.4 - lean * 0.5) * g, -2.0), _c(TUFT), 1.0)
	draw_rect(Rect2(c + Vector2(2.4 * g, 0.2) - Vector2(0.5, 0.5), Vector2(1.0, 1.0)),
		_c(FUR_FAR))
	var glint: float = pose["glint"]
	var eye := c + Vector2(1.7 * g, -0.4)
	draw_rect(Rect2(eye - Vector2(0.5, 0.5), Vector2(1.0, 1.0)), EYE.lerp(Palette.PAPER, glint))
	if glint > 0.5:
		var arm := 1.0 + glint * 1.6
		draw_line(eye - Vector2(arm, 0.0), eye + Vector2(arm, 0.0), Palette.PAPER, 1.0)
		draw_line(eye - Vector2(0.0, arm), eye + Vector2(0.0, arm), Palette.PAPER, 1.0)


func _draw_tail(pose: Dictionary) -> void:
	var rump: float = pose["rump"]
	var y: float = float(pose["back"]) - float(pose["rear_lift"]) + 1.0
	var raise: float = float(pose["tail"]) + _tail * 1.5
	var root := _p(rump, y)
	var tip := root + Vector2(-3.4 * _f, 1.4 - raise * 2.4)
	draw_line(root, tip, _c(FUR), 2.0)
	draw_line(tip, tip + Vector2(-0.9 * _f, 0.5 - raise * 0.6), _c(TUFT), 1.6)


## A leg from hip to paw. A hind leg is hocked: forward to the stifle, back
## to the hock, down to the paw -- the zig-zag that says *cat* at this size.
func _draw_leg(leg: Array, colour: Color, hind: bool) -> void:
	var hip := _p((leg[0] as Vector2).x, (leg[0] as Vector2).y)
	var paw := _p((leg[1] as Vector2).x, (leg[1] as Vector2).y)
	var span := paw - hip
	if hind:
		var stifle := hip + span * 0.35 + Vector2(1.2 * _f, 0.0)
		var hock := hip + span * 0.7 + Vector2(-1.4 * _f, 0.0)
		draw_polyline(PackedVector2Array([hip, stifle, hock, paw]), _c(colour), LEG_W)
	else:
		var elbow := hip + span * 0.45 + Vector2(-0.5 * _f, 0.0)
		draw_polyline(PackedVector2Array([hip, elbow, paw]), _c(colour), LEG_W)
	draw_rect(Rect2(paw - Vector2(0.9, 0.9), Vector2(1.8, 1.0)), _c(colour))


func _draw_dust(pose: Dictionary) -> void:
	var puff: float = pose["dust"]
	if puff <= 0.0:
		return
	for i: int in 3:
		var at := _p(7.0 + float(i) * 2.2, -1.0 - float(i % 2) - (1.0 - puff) * 3.0)
		draw_rect(Rect2(at, Vector2(1.0, 1.0)), Palette.with_alpha(DUST, puff))


## --- poses -----------------------------------------------------------------------

## Everything the drawing needs for one frame, from the state alone.
static func pose_for(state: Caracal.State, t: float, crouch_time: float,
		velocity: Vector2) -> Dictionary:
	var pose := {
		"back": -9.4, "belly": -4.8, "rump": -7.0, "shoulder": 4.6, "rear_lift": 0.0,
		"head": Vector2(7.6, -10.8), "head_turn": 1.0, "ear_lean": 0.6, "glint": 0.0,
		"tail": -0.3, "dust": 0.0, "grounded": true,
		"legs": _standing(0.0, 0.0),
	}
	var s := Caracal.State
	match state:
		s.PROWL:
			var phase := t * STRIDE_HZ * TAU
			pose["legs"] = _standing(phase, 2.6)
			pose["head"] = Vector2(7.2, -10.4 + absf(sin(phase)) * 0.5)
		s.LOOK:
			pose["head"] = Vector2(4.6, -11.0)
			pose["head_turn"] = -1.0 if t > 0.12 else 1.0
			pose["tail"] = 0.2
		s.STALK:
			var phase := t * STRIDE_HZ * 0.6 * TAU
			var moving := absf(velocity.x) > 1.0
			pose["back"] = -7.6
			pose["belly"] = -4.2
			pose["head"] = Vector2(8.0, -7.8)
			pose["ear_lean"] = 1.0
			pose["tail"] = -0.1
			pose["legs"] = _sunk(phase if moving else 0.0, 2.2 if moving else 0.0)
		s.CROUCH:
			var k := clampf(t / maxf(crouch_time, 0.01), 0.0, 1.0)
			var wiggle := sin(t * 26.0) * (0.6 + k * 0.8)
			pose["back"] = -5.0 + k * 0.6
			pose["belly"] = -1.2
			pose["rump"] = -7.4 + wiggle * 0.6
			pose["rear_lift"] = 0.6 + k * 2.4
			pose["shoulder"] = 5.0
			pose["head"] = Vector2(8.8, -4.0)
			pose["ear_lean"] = 1.2
			pose["glint"] = clampf((k - 0.3) / 0.6, 0.0, 1.0)
			pose["tail"] = 0.3 + wiggle * 0.35
			pose["legs"] = [
				[Vector2(5.0, -1.8), Vector2(8.6, 0.0)], [Vector2(4.2, -1.8), Vector2(7.6, 0.0)],
				[Vector2(-5.0 + wiggle * 0.3, -2.4 - k), Vector2(-2.6, 0.0)],
				[Vector2(-5.8 + wiggle * 0.3, -2.4 - k), Vector2(-3.6, 0.0)],
			]
		s.POUNCE:
			pose["grounded"] = false
			pose["back"] = -8.6
			pose["belly"] = -5.8
			pose["rump"] = -8.6
			pose["shoulder"] = 6.0
			pose["head"] = Vector2(9.2, -9.0)
			pose["ear_lean"] = 2.0
			pose["glint"] = 1.0
			pose["tail"] = 0.0
			pose["legs"] = [
				[Vector2(5.0, -6.6), Vector2(11.6, -6.0)], [Vector2(4.2, -6.6), Vector2(10.6, -4.8)],
				[Vector2(-6.6, -6.4), Vector2(-12.4, -3.6)], [Vector2(-7.4, -6.4), Vector2(-12.0, -2.2)],
			]
		s.SKID:
			var shake := 0.0 if t < 0.25 else sin((t - 0.25) * 40.0)
			pose["back"] = -8.4
			pose["head"] = Vector2(6.6, -10.0 + absf(shake) * 0.6)
			pose["head_turn"] = 1.0 if shake >= -0.2 else -1.0
			pose["ear_lean"] = 0.4 + shake * 0.8
			pose["dust"] = clampf(1.0 - t / 0.3, 0.0, 1.0)
			pose["legs"] = [
				[Vector2(4.4, -5.6), Vector2(8.4, 0.0)], [Vector2(3.6, -5.6), Vector2(7.4, 0.0)],
				[Vector2(-5.6, -6.0), Vector2(-3.4, 0.0)], [Vector2(-6.4, -6.0), Vector2(-4.4, 0.0)],
			]
		s.FALL:
			pose["grounded"] = false
			pose["head"] = Vector2(7.6, -8.6)
			pose["ear_lean"] = -0.6
			pose["tail"] = 0.9
			pose["legs"] = [
				[Vector2(4.6, -5.6), Vector2(8.0, -1.4)], [Vector2(3.8, -5.6), Vector2(6.0, -0.6)],
				[Vector2(-5.8, -6.0), Vector2(-9.6, -1.8)], [Vector2(-6.6, -6.0), Vector2(-8.0, -0.6)],
			]
		s.DYING:
			# Down on its side: the back is the floor line, legs out stiff.
			pose["back"] = -4.6
			pose["belly"] = -0.6
			pose["head"] = Vector2(7.6, -2.6)
			pose["ear_lean"] = 2.4
			pose["tail"] = -0.8
			pose["legs"] = [
				[Vector2(4.4, -1.4), Vector2(9.0, -3.4)], [Vector2(3.6, -1.4), Vector2(8.4, -1.6)],
				[Vector2(-5.4, -1.6), Vector2(-9.8, -3.8)], [Vector2(-6.2, -1.6), Vector2(-9.6, -1.8)],
			]
	return pose


## Four legs under a level back: near fore, far fore, near hind, far hind, the
## diagonals in step.
static func _standing(phase: float, stride: float) -> Array:
	var out: Array = []
	var hips := [Vector2(4.2, -5.6), Vector2(3.4, -5.6), Vector2(-5.6, -6.0), Vector2(-6.4, -6.0)]
	var offsets := [0.0, PI, PI, 0.0]
	for i: int in 4:
		var hip: Vector2 = hips[i]
		var a := phase + float(offsets[i])
		var paw := Vector2(hip.x + 0.6 + sin(a) * stride * 0.5, -maxf(0.0, cos(a)) * stride * 0.4)
		out.append([hip, paw])
	return out


## The stalk's legs: bent under a sunk back, one placed at a time.
static func _sunk(phase: float, stride: float) -> Array:
	var out: Array = []
	var hips := [Vector2(4.4, -4.2), Vector2(3.6, -4.2), Vector2(-5.4, -4.6), Vector2(-6.2, -4.6)]
	var offsets := [0.0, PI * 0.5, PI, PI * 1.5]
	for i: int in 4:
		var hip: Vector2 = hips[i]
		var a := phase + float(offsets[i])
		var paw := Vector2(hip.x + 1.2 + sin(a) * stride * 0.5, -maxf(0.0, cos(a)) * stride * 0.3)
		out.append([hip, paw])
	return out
