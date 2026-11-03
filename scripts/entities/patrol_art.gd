class_name PatrolArt
extends Node2D
## Draws the palace sentinel, posed from the Patrol's state machine.
##
## ## Not the prince
##
## The prince is a tall, narrow column of mid-value red under a pointed cowl.
## The sentinel is built to be the opposite at every point the eye uses at
## 22 px, so the two never read as the same figure even with the colours
## thrown away:
##
## | | Prince | Sentinel |
## | --- | --- | --- |
## | value | mid red, lit | near-black: deep shade and ink, gold trim |
## | head | pointed cowl leaning forward | a dome helm with a gold spike, upright |
## | shoulders | narrowest hard edge | the widest thing on it: pauldrons |
## | below the waist | a robe to the floor | a knee-length coat, legs and boots |
## | blade | straight, low along the forearm | a curved sabre carried on the shoulder |
##
## Dark is also the right value for an enemy in this world: on gold floors and
## crimson walls a dark figure is a hole in the light, which is what a threat
## should be. The one problem with it -- vanishing into the ink of an arch's
## void -- is answered by the same sun that lights everything else: the
## sun-facing (world-left) edge of every plane carries a one-pixel rim. The
## light is fixed in the world, so the rim is on the left whichever way the
## guard faces, exactly as the prince's lit plane is.
##
## ## What each state reads as
##
## | State | The read |
## | --- | --- |
## | WALK | a slow, heavy march; the sabre rides on the shoulder, swaying |
## | LOOK | stops, and the eye slit goes over the shoulder: it is about to turn |
## | WINDUP | the telegraph, below |
## | STRIKE | a hard downward cut, body over the front foot, edge hot |
## | RECOVER | blade point on the floor, bent over, breathing: the opening |
## | STAGGER | thrown back and burned white, like the prince |
## | DYING | the sabre spins away; the body kneels, topples, flickers out |
##
## WINDUP is the only warning the guard gives, so everything in it says the
## same thing at once: the sabre cocked back over the helm, the weight sunk
## into a wide stance, the eye slit burning white and a star of light running
## up the blade. Nothing else in the game makes that shape.
##
## ## Secondary motion
##
## The pose is a pure function of (state, state_time, facing). The cloth is
## not: `_sway` chases the body's velocity with a lag, the way PlayerArt's
## does, and reaches the helm's trailing cloth and the coat's hem. That and
## the hit flash are the only state this node keeps, all of it cosmetic.

const ARMOUR := Palette.SHADOW_DEEP
const ARMOUR_SHADE := Palette.INK
const CLOTH := Palette.SHADOW
const CLOTH_SHADE := Palette.SHADOW_DEEP
const RIM := Palette.SHADOW_WARM
const TRIM := Palette.LIGHT_WARM
const EYE := Palette.LIGHT_SOFT

## --- proportions, pixels up from the feet ----------------------------------

const HIP_Y := -8.0
const BELT_Y := -10.4
const CHEST_Y := -13.4
const SHOULDER_Y := -15.6
const HEAD_Y := -18.6
const HEM_Y := -5.0

const HW_HEM := 4.6
const HW_HIP := 3.4
const HW_BELT := 3.0
const HW_CHEST := 3.9
const HW_PAULDRON := 5.6

const HELM_R := 3.0
const SPIKE := 3.2
const BLADE_LEN := 10.5
## How far the sabre's point bows back off its line, in pixels.
const BLADE_CURVE := 1.8

const CLOTH_CHASE := 8.0
const FLASH_TIME := 0.14
## Death beats, as shares of the time from the killing blow.
const KNEEL_AT := 0.18
const TOPPLE_AT := 0.5
const FLOOR_AT := 0.72
const FLICKER_AT := 0.86

var _guard: Patrol
var _time: float = 0.0
var _sway := Vector2.ZERO
var _flash: float = 0.0

# Scratch, filled by _rig().
var _f: float = 1.0
var _hip := Vector2.ZERO
var _belt := Vector2.ZERO
var _chest := Vector2.ZERO
var _shoulder := Vector2.ZERO
var _head := Vector2.ZERO
var _hand_front := Vector2.ZERO
var _hand_back := Vector2.ZERO
var _foot_front := Vector2.ZERO
var _foot_back := Vector2.ZERO
var _knee_front := Vector2.ZERO
var _knee_back := Vector2.ZERO
var _hem_y: float = HEM_Y
var _split: float = 0.0
var _tilt: float = 0.0


func _ready() -> void:
	_guard = get_parent() as Patrol
	if _guard == null:
		return
	_guard.staggered.connect(_on_hit)
	_guard.defeated.connect(_on_hit)


func _on_hit() -> void:
	_flash = 1.0


func _process(delta: float) -> void:
	_time += delta
	_flash = maxf(0.0, _flash - delta / FLASH_TIME)
	if _guard != null:
		var target := Vector2(
			clampf(_guard.velocity.x * _guard.facing / Patrol.SPEED, -2.0, 2.0),
			clampf(_guard.velocity.y / Patrol.MAX_FALL, -1.0, 1.0))
		_sway = _sway.lerp(target, 1.0 - exp(-delta * CLOTH_CHASE))
	queue_redraw()


func _c(base: Color) -> Color:
	if _flash <= 0.0:
		return base
	return base.lerp(Palette.PAPER, _flash * 0.85)


## --- drawing ---------------------------------------------------------------

func _draw() -> void:
	if _guard == null:
		return
	var dying := _guard.state == Patrol.State.DYING
	var death := _guard.state_time / Patrol.DEATH_TIME if dying else 0.0
	if dying:
		_draw_dropped_blade(death)
		_draw_death_dust(death)
		# Flicker out: whole frames skipped, the hard-edged way to go.
		if death >= FLICKER_AT and int(_time * 24.0) % 2 == 0:
			return
		if death >= 0.99:
			return

	var pose := _posture()
	_rig(pose)

	if not dying:
		_draw_contact_shadow()
	_draw_tail(pose)
	var in_front := bool(pose["blade_front"])
	if not in_front and not dying:
		_draw_blade(pose)
	_draw_arm(_hand_back, ARMOUR_SHADE, ARMOUR_SHADE)
	_draw_leg(_knee_back, _foot_back, ARMOUR_SHADE, ARMOUR_SHADE)
	_draw_leg(_knee_front, _foot_front, ARMOUR, ARMOUR_SHADE)
	_draw_coat(pose)
	_draw_pauldrons()
	_draw_head(pose)
	_draw_arm(_hand_front, ARMOUR, ARMOUR_SHADE)
	if in_front and not dying:
		_draw_blade(pose)


func _draw_contact_shadow() -> void:
	draw_colored_polygon(PackedVector2Array([
		Vector2(-5.6, -0.4), Vector2(5.6, -0.4), Vector2(4.4, 1.2), Vector2(-4.4, 1.2),
	]), Palette.with_alpha(Palette.INK, 0.3))


## Draws a plane lit on its world-left half and in shade on the rest. Every
## body part goes through here, so the light cannot disagree between them.
##
## `rim` adds a one-pixel edge of sun down whatever side faces it. Only the
## planes that make the outline take it -- coat, pauldrons, helm, cloth. On
## the limbs too, the figure became a tangle of orange outlines and stopped
## reading as one dark body.
func _plane(points: PackedVector2Array, lit: Color, shade: Color, rim := false) -> void:
	# A pose pushed far enough can fold an outline over itself; skip that one
	# plane for that frame rather than hand the renderer something it rejects.
	if points.size() < 3 or Geometry2D.triangulate_polygon(points).is_empty():
		return
	draw_colored_polygon(points, _c(shade))
	var left := PackedVector2Array([
		Vector2(-64.0, -64.0), Vector2(_split, -64.0), Vector2(_split, 64.0), Vector2(-64.0, 64.0),
	])
	for part: PackedVector2Array in Geometry2D.intersect_polygons(points, left):
		if part.size() >= 3:
			draw_colored_polygon(part, _c(lit))
	if not rim:
		return
	var shifted := Transform2D(0.0, Vector2(0.9, 0.0)) * points
	for part: PackedVector2Array in Geometry2D.clip_polygons(points, shifted):
		if part.size() >= 3:
			draw_colored_polygon(part, _c(RIM))


## The cloth that hangs from the back of the helm. The slowest thing on the
## figure: it trails a walk, flies on a strike and keeps moving after a stop.
func _draw_tail(pose: Dictionary) -> void:
	var lift: float = float(pose["tail_lift"]) + _sway.x * 1.6 - _sway.y * 2.0
	# Down the outer edge to the tip, back up the inner edge: written in that
	# order so no lift can fold the outline over itself.
	var outline := PackedVector2Array()
	for p: Vector2 in [
		Vector2(-1.8, -1.0), Vector2(-3.6 - lift * 0.5, 3.4 - lift * 0.6),
		Vector2(-4.6 - lift * 0.9, 7.4 - lift * 1.6), Vector2(-3.3 - lift * 0.8, 7.6 - lift * 1.3),
		Vector2(-2.2, 4.4), Vector2(-0.8, 2.2),
	]:
		outline.append(_head + Vector2(p.x * _f, p.y))
	_plane(outline, CLOTH, CLOTH_SHADE, true)


func _draw_leg(knee: Vector2, foot: Vector2, lit: Color, shade: Color) -> void:
	_limb(_hip, knee, 2.6, 2.2, lit, shade)
	_limb(knee, foot, 2.2, 1.8, lit, shade)
	# A heavy boot with a turned-up toe: the toe is what tells a walking leg
	# from a robe's fold at this size.
	_plane(PackedVector2Array([
		foot + Vector2(-1.4 * _f, -2.0), foot + Vector2(1.0 * _f, -2.0),
		foot + Vector2(2.4 * _f, -0.8), foot + Vector2(2.2 * _f, 0.0),
		foot + Vector2(-1.5 * _f, 0.0),
	]), ARMOUR_SHADE, ARMOUR_SHADE)


func _draw_arm(hand: Vector2, lit: Color, shade: Color) -> void:
	var elbow := _shoulder.lerp(hand, 0.5) + Vector2(-0.4 * _f, 0.9)
	_limb(_shoulder, elbow, 2.6, 2.2, lit, shade)
	_limb(elbow, hand, 2.2, 1.8, lit, shade)
	draw_rect(Rect2(hand.x - 1.0, hand.y - 1.0, 2.0, 2.0), _c(ARMOUR_SHADE))


## The coat: shoulders to a knee-length hem, the hem dragged by `_sway`.
func _draw_coat(pose: Dictionary) -> void:
	var hem_fwd: float = float(pose["hem_fwd"]) - _sway.x * 1.2
	var spread: float = float(pose["hem_spread"])
	var hem_c := Vector2(_hip.x + hem_fwd * _f, _hem_y)
	var hw_hem := HW_HEM + spread
	var outline := PackedVector2Array([
		_shoulder + Vector2(-HW_CHEST - 0.4, 0.0), _shoulder + Vector2(HW_CHEST + 0.4, 0.0),
		_chest + Vector2(HW_CHEST, 0.0), _belt + Vector2(HW_BELT, 0.0),
		_hip + Vector2(HW_HIP, 0.0), hem_c + Vector2(hw_hem, 0.0),
		hem_c + Vector2(-hw_hem, 0.0), _hip + Vector2(-HW_HIP, 0.0),
		_belt + Vector2(-HW_BELT, 0.0), _chest + Vector2(-HW_CHEST, 0.0),
	])
	_plane(outline, ARMOUR, ARMOUR_SHADE, true)
	# The skirt's split up the front, so a step opens it.
	var slit := hem_c + Vector2(0.6 * _f, 0.0)
	draw_line(slit, slit.lerp(_hip, 0.7), _c(ARMOUR_SHADE), 1.0)
	# A gold belt with a buckle: the one warm band across a dark figure, and
	# where the eye finds the waist.
	draw_colored_polygon(PackedVector2Array([
		_belt + Vector2(-HW_BELT - 0.3, -0.6), _belt + Vector2(HW_BELT + 0.3, -0.6),
		_belt + Vector2(HW_BELT + 0.3, 0.6), _belt + Vector2(-HW_BELT - 0.3, 0.6),
	]), _c(Palette.SHADOW_WARM))
	draw_rect(Rect2(_belt.x + 0.6 * _f - 0.8, _belt.y - 0.9, 1.6, 1.8), _c(TRIM))


## Pauldrons: the widest hard edge on the guard, and the first thing that
## tells its silhouette from the prince's.
func _draw_pauldrons() -> void:
	var y := _shoulder.y
	var outline := PackedVector2Array([
		Vector2(_shoulder.x - HW_PAULDRON + 0.8, y - 1.2),
		Vector2(_shoulder.x + HW_PAULDRON - 0.8, y - 1.2),
		Vector2(_shoulder.x + HW_PAULDRON, y + 0.4),
		Vector2(_shoulder.x + HW_PAULDRON - 0.6, y + 2.0),
		Vector2(_shoulder.x - HW_PAULDRON + 0.6, y + 2.0),
		Vector2(_shoulder.x - HW_PAULDRON, y + 0.4),
	])
	_plane(outline, ARMOUR, ARMOUR_SHADE, true)
	# Gold along the top of the lit half only: the sun catches one shoulder.
	draw_rect(Rect2(_shoulder.x - HW_PAULDRON + 0.8, y - 1.2, HW_PAULDRON - 0.8, 0.9),
		_c(TRIM))


## A veiled face under a dome helm with a spike. Upright where the prince's
## cowl leans; round where it is pointed.
func _draw_head(pose: Dictionary) -> void:
	var look: float = float(pose["look"])
	var c := _head
	# The veil: a block of ink, the face entirely hidden.
	_plane(_turn(c, [
		Vector2(-2.4, -1.0), Vector2(2.4, -1.0), Vector2(2.2, 2.6), Vector2(-2.2, 2.6),
	]), ARMOUR_SHADE, ARMOUR_SHADE)
	# The eye slit, on whichever side it is looking.
	var burn: float = float(pose["burn"])
	var eye_w := 1.6 + burn * 1.2
	var ex := look * 1.4 - eye_w * 0.5 * _f
	var eye := _turn(c, [
		Vector2(ex, -0.2), Vector2(ex + eye_w * _f, -0.2),
		Vector2(ex + eye_w * _f, 0.7 + burn * 0.3), Vector2(ex, 0.7 + burn * 0.3),
	])
	draw_colored_polygon(eye, EYE.lerp(Palette.PAPER, burn))

	# The dome, then a band of gold round its rim, then the spike.
	var dome: Array[Vector2] = []
	for i: int in 9:
		var a := PI + PI * float(i) / 8.0
		dome.append(Vector2(cos(a) * HELM_R, -1.0 + sin(a) * HELM_R * 1.05))
	_plane(_turn(c, dome), ARMOUR, ARMOUR_SHADE, true)
	var w := HELM_R + 0.3
	draw_colored_polygon(_turn(c, [
		Vector2(-w, -1.6), Vector2(w, -1.6), Vector2(w, -0.7), Vector2(-w, -0.7),
	]), _c(TRIM))
	var top := -1.0 - HELM_R * 1.05
	draw_colored_polygon(_turn(c, [
		Vector2(-0.9, top + 0.4), Vector2(0.0, top - SPIKE), Vector2(0.9, top + 0.4),
	]), _c(TRIM))


## Head-local points, turned with the body. The head keeps its shape whatever
## the body does, but it does topple with it.
func _turn(centre: Vector2, points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in points:
		out.append(centre + p.rotated(_tilt * _f))
	return out


## The sabre: a tapered strip that bows back towards its point, steel with a
## dark spine; the edge goes white when it is live or glinting.
func _draw_blade(pose: Dictionary) -> void:
	var angle: float = float(pose["blade"])
	_sabre(_hand_front, angle, float(pose["blade_hot"]), float(pose["glint"]))


func _sabre(hand: Vector2, angle: float, hot: float, glint: float) -> void:
	var dir := Vector2(cos(angle) * _f, sin(angle))
	var side := Vector2(-dir.y, dir.x)
	var hilt := hand + dir * 1.0
	var spine := PackedVector2Array()
	var edge := PackedVector2Array()
	for i: int in 6:
		var s := float(i) / 5.0
		var bow := BLADE_CURVE * s * s
		var at := hilt + dir * BLADE_LEN * s - side * bow * _f
		var half := lerpf(0.85, 0.15, s)
		spine.append(at - side * half)
		edge.append(at + side * half)
	var body := spine.duplicate()
	for i: int in range(edge.size() - 1, -1, -1):
		body.append(edge[i])
	draw_colored_polygon(body, Palette.STEEL)
	draw_polyline(spine, Palette.STEEL_DARK, 0.8)
	if hot > 0.0:
		draw_polyline(edge, Palette.PAPER, 0.8)
	# Crossguard and pommel.
	draw_line(hilt + side * 1.8, hilt - side * 1.8, _c(TRIM), 1.1)
	draw_rect(Rect2(hand.x - dir.x * 1.6 - 0.6, hand.y - dir.y * 1.6 - 0.6, 1.2, 1.2), _c(TRIM))
	if glint > 0.0:
		# A star of light running from hilt to point: the telegraph's second
		# voice, after the eye. Hard pixels, no glow.
		var at := hilt + dir * BLADE_LEN * clampf(glint, 0.0, 1.0)
		var arm := 1.0 + 1.6 * sin(clampf(glint, 0.0, 1.0) * PI)
		draw_rect(Rect2(at.x - arm, at.y - 0.5, arm * 2.0, 1.0), Palette.PAPER)
		draw_rect(Rect2(at.x - 0.5, at.y - arm, 1.0, arm * 2.0), Palette.PAPER)


## The sabre after the killing blow: it leaves the hand, turns over in the air
## and lands flat beside the body.
func _draw_dropped_blade(death: float) -> void:
	_f = float(_guard.facing)
	var t := death * Patrol.DEATH_TIME
	var v := Vector2(-22.0 * _f, -78.0)
	var start := Vector2(3.0 * _f, -15.0)
	var gravity := 420.0
	# When it reaches the floor: solve start.y + v.y t + g t^2 / 2 = -1.
	var land := (-v.y + sqrt(v.y * v.y - 2.0 * gravity * (start.y + 1.0))) / gravity
	var at_t := minf(t, land)
	var at := start + v * at_t + Vector2(0.0, 0.5 * gravity * at_t * at_t)
	var angle := -1.9 + 13.0 * at_t if t < land else (PI if _f > 0.0 else 0.0) + 0.06
	if death >= FLICKER_AT and int(_time * 24.0) % 2 == 0:
		return
	_sabre(at, angle, 0.0, 0.0)


## A hard-edged puff where the body meets the floor.
func _draw_death_dust(death: float) -> void:
	var t := (death - FLOOR_AT) / 0.2
	if t <= 0.0 or t >= 1.0:
		return
	for i: int in 6:
		var side := -1.0 if i % 2 == 0 else 1.0
		var spread := (2.0 + float(i) * 1.6) * side
		var x := spread * (0.4 + t) + 3.0 * _f
		var y := -1.0 - t * (2.0 + float(i % 3) * 1.4)
		var size := 2.0 * (1.0 - t) + 0.6
		draw_rect(Rect2(x - size * 0.5, y - size * 0.5, size, size),
			Palette.LIGHT_WARM if i % 3 == 0 else Palette.SHADOW_WARM)


func _limb(from: Vector2, to: Vector2, w0: float, w1: float, lit: Color, shade: Color) -> void:
	var along := (to - from).normalized()
	if along == Vector2.ZERO:
		return
	var side := Vector2(-along.y, along.x)
	_plane(PackedVector2Array([
		from + side * w0 * 0.5, to + side * w1 * 0.5,
		to - side * w1 * 0.5, from - side * w0 * 0.5,
	]), lit, shade)


## --- the rig ---------------------------------------------------------------

func _rig(pose: Dictionary) -> void:
	_f = float(_guard.facing)
	var sink: float = float(pose["sink"])
	var bob: float = float(pose["bob"])
	var lean: float = float(pose["lean"])
	var tilt: float = float(pose["tilt"])
	_tilt = tilt

	_hip = _place(0.0, HIP_Y + sink + bob, lean, 0.25, tilt)
	_belt = _place(0.0, BELT_Y + sink + bob, lean, 0.45, tilt)
	_chest = _place(0.0, CHEST_Y + sink + bob, lean, 0.8, tilt)
	_shoulder = _place(0.0, SHOULDER_Y + sink + bob, lean, 1.0, tilt)
	_head = _place(0.3, HEAD_Y + sink + bob, lean, 1.1, tilt)
	_hem_y = maxf(HEM_Y + sink * 0.5 - float(pose["hem_lift"]), _hip.y + 1.5)
	_split = _chest.x

	var stride: float = float(pose["stride"])
	var stance: float = float(pose["stance"])
	var knee: float = float(pose["knee"])
	_foot_front = _place(stride + stance, 0.0, 0.0, 0.0, tilt)
	_foot_back = _place(-stride - stance, -maxf(0.0, -stride) * 0.35, 0.0, 0.0, tilt)
	_knee_front = _place(stride * 0.6 + 1.0, lerpf(_hip.y, 0.0, 0.5) - knee, lean, 0.12, tilt)
	_knee_back = _place(-stride * 0.5 + 0.2, lerpf(_hip.y, 0.0, 0.52), lean, 0.12, tilt)

	_hand_front = _hand(float(pose["arm_a"]), float(pose["arm_a_len"]))
	_hand_back = _hand(float(pose["arm_b"]), 5.2)


func _hand(angle: float, length: float) -> Vector2:
	return _shoulder + Vector2(cos(angle) * length * _f, sin(angle) * length)


func _place(forward: float, y: float, lean: float, weight: float, tilt: float) -> Vector2:
	var p := Vector2((forward + lean * weight) * _f, y)
	if is_zero_approx(tilt):
		return p
	return p.rotated(tilt * _f)


## --- the pose vocabulary ---------------------------------------------------

func _pose(over: Dictionary) -> Dictionary:
	var p := {
		"sink": 0.0, "bob": 0.0, "lean": 0.0, "tilt": 0.0,
		"stride": 0.0, "stance": 1.4, "knee": 0.0,
		"hem_lift": 0.0, "hem_fwd": 0.0, "hem_spread": 0.0,
		"look": 1.0,       # +1 the eye slit looks forward, -1 over the shoulder
		"burn": 0.0,       # how white the eye slit burns
		"tail_lift": 0.0,
		"arm_a": 1.0, "arm_a_len": 4.6, "arm_b": 1.5,
		"blade": -1.95,    # forward space: 0 ahead, +ve down
		"blade_front": false,
		"blade_hot": 0.0,
		"glint": 0.0,      # 0 none, else how far up the blade the star is
	}
	for key: String in over:
		p[key] = over[key]
	return p


func _posture() -> Dictionary:
	var t := _guard.state_time
	match _guard.state:
		Patrol.State.LOOK:
			return _look(t)
		Patrol.State.WINDUP:
			return _windup(t)
		Patrol.State.STRIKE:
			return _strike(t)
		Patrol.State.RECOVER:
			return _recover(t)
		Patrol.State.STAGGER:
			return _stagger(t)
		Patrol.State.DYING:
			return _dying(t / Patrol.DEATH_TIME)
		_:
			return _walk(t)


## A slow, heavy march. The sabre rides on the shoulder and rocks with it.
func _walk(t: float) -> Dictionary:
	var c := sin(t * 7.5)
	return _pose({
		"bob": -absf(c) * 0.7 + 0.2,
		"lean": 0.6,
		"stride": c * 2.2,
		"knee": maxf(0.0, c) * 1.6,
		"stance": 0.6,
		"hem_fwd": -c * 0.7,
		"arm_b": 1.45 + c * 0.45,
		"blade": -1.95 + c * 0.08,
	})


## Stopped at the end of its beat. For the first half it looks down the drop,
## for the second over its shoulder, the way it is about to go.
func _look(t: float) -> Dictionary:
	var breath := sin(_time * 2.2)
	var turning := t > Patrol.LOOK_TIME * 0.45
	return _pose({
		"bob": breath * 0.25,
		"stance": 1.6,
		"look": -1.0 if turning else 1.0,
		"lean": -0.4 if turning else 0.3,
		"blade": -2.05,
	})


## The telegraph. Everything in it says the same thing: the sabre is cocked
## back over the helm, the weight sinks into a wide stance, the eye slit burns
## and a star of light runs up the blade. Built to be unmissable, because it is
## the only warning the guard gives.
func _windup(t: float) -> Dictionary:
	var p := clampf(t / Patrol.WINDUP_TIME, 0.0, 1.0)
	var e := smoothstep(0.0, 0.55, p)
	var tremble := sin(_time * 60.0) * 0.25 * smoothstep(0.6, 1.0, p)
	return _pose({
		"sink": 1.6 * e,
		"lean": lerpf(0.4, -1.8, e) + tremble,
		"stride": lerpf(0.0, 1.2, e),
		"stance": lerpf(1.4, 2.6, e),
		"knee": -0.6 * e,
		"hem_spread": 0.8 * e,
		"burn": smoothstep(0.15, 0.45, p),
		"tail_lift": 0.8 * e,
		"arm_a": lerpf(-1.2, -2.25, e), "arm_a_len": lerpf(4.6, 5.8, e),
		"arm_b": lerpf(1.5, 0.6, e),
		"blade": lerpf(-1.95, -3.55, e),
		"glint": smoothstep(0.3, 0.9, p) if p < 0.95 else 0.0,
	})


## The cut: from overhead to forward and down in nine frames, the body thrown
## over the front foot.
func _strike(t: float) -> Dictionary:
	var p := clampf(t / Patrol.STRIKE_TIME, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - p, 3.0)
	return _pose({
		"sink": lerpf(1.6, 2.4, e),
		"lean": lerpf(-1.8, 3.2, e),
		"stride": lerpf(1.2, 3.4, e),
		"stance": 2.4,
		"knee": -1.0,
		"hem_fwd": lerpf(0.0, -2.0, e),
		"hem_spread": 1.0,
		"burn": 1.0 - e * 0.6,
		"tail_lift": lerpf(0.8, 2.6, e),
		"arm_a": lerpf(-2.25, 0.55, e), "arm_a_len": 6.0,
		"arm_b": lerpf(0.6, 2.4, e),
		"blade": lerpf(-3.55, 0.65, e),
		"blade_front": true,
		"blade_hot": 1.0,
	})


## Spent. The point rests on the floor and the guard is bent over it,
## breathing. This is the opening, so it has to look like one.
func _recover(t: float) -> Dictionary:
	var breath := sin(t * 9.0)
	var rise := smoothstep(0.6, 1.0, t / Patrol.RECOVER_TIME)
	return _pose({
		"sink": lerpf(2.2, 0.4, rise) + breath * 0.3,
		"lean": lerpf(2.6, 0.8, rise),
		"stride": lerpf(2.6, 0.6, rise),
		"stance": 1.8,
		"look": 1.0,
		"tail_lift": -0.4,
		"arm_a": lerpf(0.85, -1.0, rise), "arm_a_len": 5.2,
		"arm_b": 1.9,
		"blade": lerpf(1.15, -1.95, rise),
		"blade_front": rise < 0.5,
	})


func _stagger(t: float) -> Dictionary:
	var recover := smoothstep(0.0, Patrol.STAGGER_TIME, t)
	return _pose({
		"tilt": lerpf(-0.32, -0.08, recover),
		"lean": -2.6,
		"stride": -1.6,
		"stance": 1.8,
		"knee": 1.0,
		"hem_lift": 0.6,
		"hem_fwd": 2.0,
		"look": 1.0,
		"tail_lift": 2.4,
		"arm_a": 2.4, "arm_b": 2.8,
		"blade": 2.3,
	})


## Thrown back, down onto the knees, then over onto its face. The sabre is
## drawn separately (_draw_dropped_blade), already out of the hand.
func _dying(d: float) -> Dictionary:
	var kneel := smoothstep(KNEEL_AT, TOPPLE_AT, d)
	var topple := smoothstep(TOPPLE_AT, FLOOR_AT, d)
	return _pose({
		"tilt": lerpf(lerpf(-0.3, -0.05, kneel), 1.42, topple),
		"sink": lerpf(0.0, 6.0, kneel) * (1.0 - topple * 0.6),
		"lean": lerpf(-2.4, 1.0, kneel),
		"stride": lerpf(-1.4, 1.2, kneel),
		"stance": 1.6,
		"knee": lerpf(1.0, 3.0, kneel),
		"hem_spread": 1.2 * kneel,
		"look": 1.0,
		"tail_lift": lerpf(2.0, -1.0, kneel),
		"arm_a": lerpf(2.6, 1.4, kneel), "arm_b": lerpf(2.9, 1.6, kneel),
	})
