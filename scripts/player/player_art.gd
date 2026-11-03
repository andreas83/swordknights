class_name PlayerArt
extends Node2D
## Draws the prince: a hooded figure in a deep red robe, posed from the state
## machine rather than from a sprite sheet.
##
## There are no image assets on purpose, so everything here is flat planes of
## Palette colour with hard edges — the concept art's language. The whole thing
## is 22 px tall on a 180 px viewport, which is the constraint that decides
## every number below: at that size a silhouette reads, an outline reads, and
## interior detail does not. So the figure is built from a handful of planes:
##
##     lit cloth | shade cloth | ink edge, over a darker cloak
##
## four tones across nine pixels, which is what makes it pop against terrain
## that is itself gold and crimson.
##
## ## How it is built
##
## `_posture()` turns (state, state_time) into a **pose**: a flat dictionary of
## named quantities — lean, sink, stride, hem lift, cloak sweep and so on. The
## pose never contains coordinates. `_rig()` turns a pose into the handful of
## points the drawing needs (hip, waist, chest, shoulder, head, hands, feet),
## applying squash, lean, sink and the mirror for `facing` exactly once. The
## `_draw_*` helpers then read that rig and know nothing about state.
##
## Adding a state means adding one case to `_posture()`. See docs/character.md.
##
## The cloak, robe, sash and hood helpers below are the prince's costume. A
## `costume` (scripts/player/costume.gd) may draw those three layers instead --
## the heroine's does -- over the same rig, so a new pose is every figure's.
##
## ## Coordinates
##
## The parent's origin is at the character's FEET, so everything is drawn in
## negative Y. Poses are written in **forward space**: +x means "the way the
## character is facing", and `_rig()` mirrors it. The light, however, is fixed
## in the world — it comes from the left, the same direction the terrain atlas
## is lit from — so the lit plane is always the world-left side of the body
## regardless of which way the character faces.
##
## ## Secondary motion
##
## Pose is a pure function of (state, state_time, velocity, facing), which
## keeps a replay or a network peer drawing the same frames. The *cloth* is
## not: `_sway` lags behind the body's velocity, and `landed` / `jumped` kick
## a damped spring into `_squash_impulse()`. That is the only state this node
## keeps, it is cosmetic, and it self-corrects within a few frames.

@export var cloth: Color = Palette.CLOTH
@export var cloth_dark: Color = Palette.CLOTH_DARK
@export var cloak_shade: Color = Palette.SHADOW_DEEP
@export var ink: Color = Palette.INK
## The one warm accent on the figure: the sash, and the crest of the hood.
@export var accent: Color = Palette.LIGHT_WARM

## What the figure wears over the rig. The base Costume is the prince and draws
## nothing of its own, so a bare PlayerArt draws exactly what it always has; see
## costume.gd for why the second figure is a costume and not a second PlayerArt.
var costume := Costume.new()

## --- proportions -----------------------------------------------------------
##
## Pixels up from the feet at rest. Tall and thin: the hood is a fifth of the
## height, the shoulders are the widest hard edge, and the robe falls to the
## floor.

const HIP_Y := -9.0
const WAIST_Y := -12.2
const CHEST_Y := -15.4
const SHOULDER_Y := -17.0

const HW_HEM := 4.8
const HW_HIP := 2.9
const HW_WAIST := 2.4
const HW_CHEST := 3.2
const HW_SHOULDER := 4.3

const HOOD_HW := 2.6
const HOOD_HH := 2.7

## The cowl, as (height above centre, forward push, half width), all in units
## of HOOD_HH / HOOD_HW. A narrow crown pushed forward is what turns a circle
## into a hood.
const HOOD_RUNGS: Array[Vector3] = [
	Vector3(-1.0, 0.34, 0.4),
	Vector3(-0.3, 0.5, 0.92),
	Vector3(0.5, 0.24, 1.0),
	Vector3(1.05, -0.22, 0.7),
]

const RIM := 0.9 ## Width of the ink edge along the shadow side.

## --- secondary motion ------------------------------------------------------

const CLOTH_CHASE := 9.0 ## How fast the cloth catches up with the body.
const SQUASH_DECAY := 11.0
const SQUASH_RING := 26.0
const FLASH_TIME := 0.14 ## How long a hit burns the whole figure white.

## Where the blade's point is this frame, in this node's local space, and how
## hot the swing is. PlayerFx reads these for the trail, so the trail cannot
## drift away from the sword it is following.
var blade_tip := Vector2.ZERO
var blade_hot: float = 0.0

## --- idle -----------------------------------------------------------------
##
## The fidgets and bits the prince plays when left alone are IdleArt
## (scripts/player/idle_art.gd), a child of this node: it lays its pose over
## `_idle()` and draws its props over the figure. Null on any other body;
## nobody idles in a duel.
var idle_art: IdleArt

var _player: Player
var _time: float = 0.0

## Cloth lag, in forward space: +x = the body is moving forward (so the cloth
## trails), +y = the body is falling (so the cloth streams up).
var _sway := Vector2.ZERO
var _impulse: float = 0.0 ## Signed: negative squashes, positive stretches.
var _impulse_t: float = 1.0
var _flash: float = 0.0 ## How white the figure burns after a hit.

# Scratch, filled by _rig() and read by the _draw_* helpers.
var _f: float = 1.0 ## facing as a float, the mirror multiplier
var _hem_y: float = 0.0
var _foot_y: float = 0.0
var _hip := Vector2.ZERO
var _waist := Vector2.ZERO
var _chest := Vector2.ZERO
var _shoulder := Vector2.ZERO
var _head := Vector2.ZERO
var _hand_front := Vector2.ZERO
var _hand_back := Vector2.ZERO
var _foot_front := Vector2.ZERO
var _foot_back := Vector2.ZERO
var _knee_front := Vector2.ZERO
var _knee_back := Vector2.ZERO
var _hw := {}


func _ready() -> void:
	_bind()


## --- the body this figure is drawn for -------------------------------------
##
## Everything this class reads from the character it dresses goes through the
## eight methods below, so another kind of character can wear the same figure.
## FighterArt overrides them to dress a duel Fighter; for the prince they read
## the Player exactly as this file always did.

## Finds the character and listens to it. False if there is nothing to dress.
func _bind() -> bool:
	_player = get_parent() as Player
	if _player == null:
		return false
	_player.landed.connect(_on_landed)
	_player.jumped.connect(_on_jumped)
	_player.hurt.connect(_on_hurt)
	_player.died.connect(_on_died)
	PlayerFx.attach(_player)
	idle_art = IdleArt.attach(self, _player)
	return true


func _has_body() -> bool:
	return _player != null


func _body_facing() -> int:
	return _player.facing


## (forward speed, fall speed) as shares of the character's top speeds, for
## the cloth's lag.
func _body_motion() -> Vector2:
	return Vector2(
		_player.velocity.x * _player.facing / Tuning.RUN_SPEED,
		_player.velocity.y / Tuning.MAX_FALL_SPEED
	)


## How fast the run cycle turns over, as a share of top speed.
func _speed_share() -> float:
	return absf(_player.velocity.x) / Tuning.RUN_SPEED


## True on frames the figure is not drawn at all: the invulnerability flicker.
func _skip_frame() -> bool:
	return _player.invulnerable > 0.0 and int(_time * 20.0) % 2 == 0


## Whether the blade is drawn in front of the robe rather than behind it.
func _blade_in_front() -> bool:
	match _player.state:
		Player.State.PLUNGE_LAND, Player.State.PARRY:
			return true
		_:
			return _player.is_striking()


func _show_grip() -> bool:
	return _player.is_hanging()


func _process(delta: float) -> void:
	_time += delta
	_impulse_t += delta
	_flash = maxf(0.0, _flash - delta / FLASH_TIME)
	if _has_body():
		var motion := _body_motion()
		var target := Vector2(clampf(motion.x, -1.5, 1.5), clampf(motion.y, -1.2, 1.2))
		_sway = _sway.lerp(target, 1.0 - exp(-delta * CLOTH_CHASE))
		costume.tick(self, delta)
	queue_redraw()


func _on_landed(impact_speed: float) -> void:
	_impulse = -0.34 * Tuning.impact_weight(impact_speed)
	_impulse_t = 0.0
	# Cloth keeps going down for a moment, then settles.
	_sway.y = maxf(_sway.y, 0.9 * Tuning.impact_weight(impact_speed))


func _on_jumped() -> void:
	_impulse = 0.18
	_impulse_t = 0.0


func _on_hurt(_remaining_health: int) -> void:
	_flash = 1.0


func _on_died() -> void:
	_flash = 1.0


## Every plane of the figure goes through here, so a hit flash is exactly the
## character's own silhouette rather than a rectangle laid over it.
func _c(base: Color) -> Color:
	if _flash <= 0.0:
		return base
	return base.lerp(Palette.PAPER, _flash * 0.85)


## A damped ring, so a landing settles rather than snapping back.
func _squash_impulse() -> float:
	if _impulse_t > 0.7:
		return 0.0
	return _impulse * exp(-_impulse_t * SQUASH_DECAY) * cos(_impulse_t * SQUASH_RING)


## --- drawing ---------------------------------------------------------------

func _draw() -> void:
	if not _has_body():
		return
	# Invulnerability flicker: skip whole frames so the hit reads clearly.
	if _skip_frame():
		return

	var pose := _posture()
	_rig(pose)

	if _grounded():
		_draw_contact_shadow()
	if not costume.draw_back(self, pose):
		_draw_cloak(pose)
	# Both legs go behind the robe: a hem that reaches the floor has to be able
	# to hide them, and a hem that rides up has to be what reveals them.
	_draw_leg(_knee_back, _foot_back, _c(cloak_shade))
	_draw_leg(_knee_front, _foot_front, _c(ink))
	_draw_arm(_hand_back, _c(cloth_dark))
	# At rest the blade hangs behind the robe and only its point shows past the
	# hem; during a swing it comes round in front of everything.
	var swinging := _blade_in_front()
	if not swinging:
		_draw_weapon(pose)
	if not costume.draw_body(self, pose):
		_draw_robe(pose)
		_draw_sash()
	_draw_arm(_hand_front, _c(cloth))
	if swinging:
		_draw_weapon(pose)
	if not costume.draw_head(self, pose):
		_draw_hood(pose)
	if _show_grip():
		_draw_grip()


func _draw_contact_shadow() -> void:
	var w: float = _hw["hem"] * 1.1
	draw_colored_polygon(PackedVector2Array([
		Vector2(-w, -0.4), Vector2(w, -0.4), Vector2(w * 0.8, 1.2), Vector2(-w * 0.8, 1.2),
	]), Palette.with_alpha(Palette.INK, 0.28))


## The cloak is one plane behind everything, hung from the shoulders. It is the
## slowest thing on the character: `_sway` reaches it multiplied, so it trails
## on a run, streams on a fall and keeps moving for a beat after a landing.
func _draw_cloak(pose: Dictionary) -> void:
	var sweep: float = float(pose["cloak_sweep"]) + _sway.x * 2.6
	var rise: float = float(pose["cloak_rise"]) + _sway.y * 3.4
	var flare: float = float(pose["cloak_flare"])

	var top_back := Vector2(-_hw["shoulder"] * 0.9, _shoulder.y + 0.4)
	var top_front := Vector2(_hw["shoulder"] * 0.35, _shoulder.y + 0.8)
	var tail_y := _hem_y + 1.0 - rise
	if _grounded():
		tail_y = minf(tail_y, 1.2) # cloth pools on the floor, it does not go through it
	var tail := Vector2(-sweep - _hw["hem"] * flare, tail_y)
	var mid := Vector2(-sweep * 0.45 - _hw["hem"] * 0.8, lerpf(_shoulder.y, _hem_y, 0.6))
	var inner := Vector2(-_hw["hip"] * 0.4, _hem_y + 0.6)

	draw_colored_polygon(_fwd([top_front, top_back, mid, tail, inner]), _c(cloak_shade))


## The robe is a stack of rungs — a centre point and a half width at five
## heights — split down the middle into a lit plane and a shade plane. The
## light is fixed in the world, so the split is at world x, not at the
## character's front.
func _draw_robe(pose: Dictionary) -> void:
	var hem_fwd: float = float(pose["hem_fwd"]) - _sway.x * 1.7
	var rungs: Array[Vector3] = [
		Vector3(_shoulder.x, _shoulder.y, _hw["shoulder"]),
		Vector3(_chest.x, _chest.y, _hw["chest"]),
		Vector3(_waist.x, _waist.y, _hw["waist"]),
		Vector3(_hip.x, _hip.y, _hw["hip"]),
		Vector3(_hip.x * 0.4 + hem_fwd * _f, _hem_y, _hw["hem"]),
	]

	draw_colored_polygon(_side(rungs, -1.0), _c(cloth))
	draw_colored_polygon(_side(rungs, 1.0), _c(cloth_dark))
	draw_colored_polygon(_edge(rungs, 1.0, RIM), _c(ink))
	# The hem's own shadow: a hard line is what sells a flat plane standing on
	# ground rather than floating over it.
	var last := rungs[rungs.size() - 1]
	draw_colored_polygon(PackedVector2Array([
		Vector2(last.x - last.z, last.y - 0.9), Vector2(last.x + last.z, last.y - 0.9),
		Vector2(last.x + last.z, last.y), Vector2(last.x - last.z, last.y),
	]), _c(ink))


func _draw_sash() -> void:
	var w: float = _hw["waist"] + 0.5
	draw_colored_polygon(PackedVector2Array([
		Vector2(_waist.x - w, _waist.y - 0.3), Vector2(_waist.x + w, _waist.y + 0.3),
		Vector2(_waist.x + w, _waist.y + 1.3), Vector2(_waist.x - w, _waist.y + 0.7),
	]), accent)


func _draw_leg(knee: Vector2, foot: Vector2, color: Color) -> void:
	_limb(_hip, knee, 2.1, 1.7, color)
	_limb(knee, foot, 1.7, 1.5, color)
	# A boot, so the leg ends in something rather than tapering into the floor.
	# Every x offset is mirrored by _f, not just the toe: mirroring half a quad
	# turns it into a bowtie the moment the character faces left, and Godot
	# refuses to triangulate a self-intersecting polygon.
	draw_colored_polygon(PackedVector2Array([
		foot + Vector2(-1.1 * _f, -1.4), foot + Vector2(1.1 * _f, -1.4),
		foot + Vector2(1.5 * _f, 0.0), foot + Vector2(-1.3 * _f, 0.0),
	]), color)


## Sleeve, then forearm, then a dark hand. The hand matters: without it a
## forward-swung arm is a bar of robe-coloured nothing poking out of the body.
func _draw_arm(hand: Vector2, color: Color) -> void:
	var elbow := _shoulder.lerp(hand, 0.5) + Vector2(0.0, 0.8)
	_limb(_shoulder, elbow, 2.4, 1.8, color)
	_limb(elbow, hand, 1.8, 1.4, color)
	draw_rect(Rect2(hand.x - 0.85, hand.y - 0.85, 1.7, 1.7), _c(ink))


## The hood is the whole silhouette read: a narrow peak that leans the way the
## character looks, a face that is a hole rather than a face, and one plane of
## gold on the crown so the head never merges into bright terrain.
##
## Built from rungs like the robe, for the same reason: the light has to split
## it down the world's vertical, not down the character's front.
func _draw_hood(pose: Dictionary) -> void:
	var look: float = float(pose["hood_face"])
	var fdir: float = _f * signf(look) * maxf(absf(look), 0.3)
	var tilt: float = float(pose["hood_tilt"])
	var c := _head

	# A shear rather than a rotation: at five pixels tall the difference is
	# invisible, and the rungs stay horizontal so the edges stay hard.
	var rungs: Array[Vector3] = []
	for spec: Vector3 in HOOD_RUNGS:
		rungs.append(Vector3(
			c.x + (spec.y * HOOD_HW - spec.x * tilt * 1.7) * fdir,
			c.y + spec.x * HOOD_HH,
			HOOD_HW * spec.z))

	draw_colored_polygon(_side(rungs, -1.0), _c(cloth))
	draw_colored_polygon(_side(rungs, 1.0), _c(cloth_dark))
	draw_colored_polygon(_edge(rungs, 1.0, RIM * 0.8), _c(ink))

	# One pixel of sun on the crest. More than that and the hood reads as a
	# gold helmet instead of cloth.
	var top := rungs[0]
	draw_colored_polygon(PackedVector2Array([
		Vector2(top.x - top.z, top.y + RIM * 0.9), Vector2(top.x - top.z * 0.1, top.y),
		Vector2(top.x + top.z * 0.5, top.y + RIM * 0.6),
		Vector2(top.x - top.z * 0.2, top.y + RIM * 1.1),
	]), accent)

	# The face: a void. One glint is the whole performance.
	var brow := c.y - HOOD_HH * 0.52
	var jaw := c.y + HOOD_HH * 0.78
	draw_colored_polygon(PackedVector2Array([
		Vector2(c.x - HOOD_HW * 0.34 * fdir, brow + HOOD_HH * 0.1),
		Vector2(c.x + HOOD_HW * 1.0 * fdir, brow + HOOD_HH * 0.22),
		Vector2(c.x + HOOD_HW * 0.78 * fdir, jaw),
		Vector2(c.x - HOOD_HW * 0.38 * fdir, jaw - HOOD_HH * 0.28),
	]), _c(ink))

	var glint: float = float(pose["glint"])
	if glint > 0.0:
		draw_rect(Rect2(c.x + HOOD_HW * 0.4 * fdir - 0.5, c.y - 0.2, 1.2, 1.0),
			Palette.with_alpha(Palette.LIGHT, glint))


## The sword lives in the front hand the whole time — held low along the
## forearm, swung on an arc during ATTACK.
func _draw_weapon(pose: Dictionary) -> void:
	var angle: float = float(pose["blade"])
	blade_hot = float(pose["blade_hot"])
	if is_inf(angle):
		blade_hot = 0.0
		return
	var length: float = float(pose["blade_len"])
	var dir := Vector2(cos(angle) * _f, sin(angle))
	var side := Vector2(-dir.y, dir.x)
	var hilt := _hand_front + dir * 1.2
	var tip := hilt + dir * length
	blade_tip = tip

	draw_colored_polygon(PackedVector2Array([
		hilt + side * 0.9, tip + side * 0.25, tip - side * 0.25, hilt - side * 0.9,
	]), Palette.STEEL)
	draw_colored_polygon(PackedVector2Array([
		hilt + side * 0.9, tip + side * 0.25,
		tip, hilt + side * 0.1,
	]), Palette.LIGHT_SOFT if blade_hot > 0.0 else Palette.STEEL_DARK)
	# Crossguard.
	draw_colored_polygon(PackedVector2Array([
		hilt + side * 2.0 - dir * 0.5, hilt + side * 2.0 + dir * 0.5,
		hilt - side * 2.0 + dir * 0.5, hilt - side * 2.0 - dir * 0.5,
	]), Palette.LIGHT_WARM)


## Knuckles on the ledge. Two hard blocks above the hood are the whole read
## for a hang: nothing else in the game has them.
func _draw_grip() -> void:
	for hand: Vector2 in [_hand_front, _hand_back]:
		draw_rect(Rect2(hand.x - 1.4, hand.y - 1.3, 2.8, 2.3), _c(ink))
		draw_rect(Rect2(hand.x - 1.4, hand.y - 1.3, 2.8, 0.9), Palette.SHADOW_WARM)


## --- geometry helpers ------------------------------------------------------

## A tapered segment: the only limb primitive, used for arms and legs alike.
func _limb(from: Vector2, to: Vector2, w0: float, w1: float, color: Color) -> void:
	var along := (to - from).normalized()
	if along == Vector2.ZERO:
		return
	var side := Vector2(-along.y, along.x)
	draw_colored_polygon(PackedVector2Array([
		from + side * w0 * 0.5, to + side * w1 * 0.5,
		to - side * w1 * 0.5, from - side * w0 * 0.5,
	]), color)


## One half of the robe: down the centre line, then back up one edge.
func _side(rungs: Array[Vector3], direction: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for r: Vector3 in rungs:
		points.append(Vector2(r.x, r.y))
	for i: int in range(rungs.size() - 1, -1, -1):
		var r := rungs[i]
		points.append(Vector2(r.x + r.z * direction, r.y))
	return points


## A rim strip hugging one edge of the robe.
func _edge(rungs: Array[Vector3], direction: float, width: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for r: Vector3 in rungs:
		points.append(Vector2(r.x + r.z * direction, r.y))
	for i: int in range(rungs.size() - 1, -1, -1):
		var r := rungs[i]
		points.append(Vector2(r.x + (r.z - width) * direction, r.y))
	return points


## Mirrors a list of forward-space points into local space.
func _fwd(points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in points:
		out.append(Vector2(p.x * _f, p.y))
	return out


## --- the rig ---------------------------------------------------------------

## Turns a pose into points. Everything that depends on `facing`, `squash`,
## `lean` or `sink` happens exactly once, here.
func _rig(pose: Dictionary) -> void:
	_f = float(_body_facing())

	var squash: float = clampf(float(pose["squash"]) + _squash_impulse(), 0.55, 1.3)
	var width: float = clampf(1.0 / squash, 0.82, 1.28)
	var sink: float = float(pose["sink"])
	var bob: float = float(pose["bob"])
	var lean: float = float(pose["lean"])
	var twist: float = float(pose["twist"])
	var tilt: float = float(pose["tilt"])

	_foot_y = float(pose["dangle"])
	_hw = {
		"hem": (HW_HEM + float(pose["hem_spread"])) * width,
		"hip": HW_HIP * width,
		"waist": HW_WAIST * width,
		"chest": HW_CHEST * width * lerpf(1.0, twist, 0.6),
		"shoulder": HW_SHOULDER * width * twist,
	}

	# `sink` folds the body down without shrinking the hood, which is what a
	# crouch or a dead hang actually does; `squash` scales the whole column.
	var hip_y := HIP_Y * squash + sink + bob
	var shoulder_y := SHOULDER_Y * squash + sink + bob
	_hip = _place(0.0, hip_y, lean, 0.25, tilt)
	_waist = _place(0.0, WAIST_Y * squash + sink + bob, lean, 0.45, tilt)
	_chest = _place(0.0, CHEST_Y * squash + sink + bob, lean, 0.8, tilt)
	_shoulder = _place(0.0, shoulder_y, lean, 1.0, tilt)
	# The hem rides up when the legs need the room, but never above the hip.
	_hem_y = maxf(_foot_y - float(pose["hem_lift"]), hip_y + 1.6)

	# The hood keeps its own size whatever the body does: at five pixels tall
	# it is the one part of the figure that must never deform.
	_head = _place(float(pose["hood_push"]), shoulder_y - HOOD_HH * 0.85, lean, 1.15, tilt)

	_rig_limbs(pose, squash, tilt, lean)


func _rig_limbs(pose: Dictionary, squash: float, tilt: float, lean: float) -> void:
	var stride: float = float(pose["stride"])
	var stance: float = float(pose["stance"])
	var knee: float = float(pose["knee"])

	_foot_front = _place(stride + stance * 0.9, _foot_y, lean, 0.0, tilt)
	_foot_back = _place(-stride - stance * 0.9, _foot_y - maxf(0.0, -stride) * 0.25,
		lean, 0.0, tilt)
	_knee_front = _place(stride * 0.75 + 0.6, lerpf(_hip.y, _foot_y, 0.5) - knee,
		lean, 0.12, tilt)
	_knee_back = _place(-stride * 0.55 + 0.3, lerpf(_hip.y, _foot_y, 0.52), lean, 0.12, tilt)

	_hand_front = _hand(float(pose["arm_a"]), float(pose["arm_a_len"]), squash)
	_hand_back = _hand(float(pose["arm_b"]), float(pose["arm_b_len"]), squash)


func _hand(angle: float, length: float, squash: float) -> Vector2:
	return _shoulder + Vector2(cos(angle) * length * _f, sin(angle) * length * squash)


## Places a forward-space point in local space, leaning it by `weight` (0 at
## the feet, 1 at the shoulders) and tilting the whole figure about the feet.
func _place(forward: float, y: float, lean: float, weight: float, tilt: float) -> Vector2:
	var p := Vector2((forward + lean * weight) * _f, y)
	if is_zero_approx(tilt):
		return p
	return p.rotated(tilt * _f)


func _grounded() -> bool:
	match _player.state:
		Player.State.IDLE, Player.State.WALK, Player.State.RUN, Player.State.TURN, \
		Player.State.CROUCH, Player.State.LAND, Player.State.ATTACK, \
		Player.State.PLUNGE_LAND, Player.State.PARRY:
			return true
		_:
			return _player.is_grounded()


## --- the pose vocabulary ---------------------------------------------------

## Every field a pose can set, with the value it takes when a state does not
## care. Everything is in forward space and in pixels, except the angles
## (radians, 0 = straight forward, +ve = downward) and the unitless scales.
func _pose(over: Dictionary) -> Dictionary:
	var p := {
		"squash": 1.0,      # vertical scale; width compensates
		"sink": 0.0,        # fold the body down without shrinking the hood
		"bob": 0.0,         # whole-body vertical offset
		"lean": 0.0,        # forward offset at the shoulders
		"tilt": 0.0,        # rotation about the feet, radians
		"twist": 1.0,       # shoulder foreshortening; < 1 reads as turned away
		"dangle": 0.0,      # how far below the origin the feet hang
		"hem_lift": 0.0,    # how far the hem rides up off the floor
		"hem_spread": 0.0,  # extra hem width
		"hem_fwd": 0.0,     # hem displacement; negative trails behind
		"hood_tilt": 0.0,   # + pitches the hood down and forward
		"hood_face": 1.0,   # which way the opening looks; negative = behind
		"hood_push": 0.0,   # head offset along forward
		"glint": 1.0,       # alpha of the eye light
		"stride": 0.0,      # front foot forward, back foot back
		"stance": 1.0,      # how far apart the feet plant
		"knee": 0.0,        # front knee lift
		"arm_a": 1.35,      # front arm angle
		"arm_b": 1.45,      # back arm angle
		"arm_a_len": 6.2,
		"arm_b_len": 5.8,
		"cloak_sweep": 0.6, # how far behind the cloak's tail sits
		"cloak_rise": 0.0,  # how high the tail lifts
		"cloak_flare": 1.0,
		"blade": INF,       # sword angle; INF hides it
		"blade_len": 9.0,
		"blade_hot": 0.0,   # the gleam along the edge, during a swing
	}
	for key: String in over:
		p[key] = over[key]
	return p


func _posture() -> Dictionary:
	var t := _player.state_time
	match _player.state:
		Player.State.WALK:
			return _walk(t)
		Player.State.RUN:
			return _run(t)
		Player.State.TURN:
			return _turn(t)
		Player.State.CROUCH:
			return _crouch()
		Player.State.JUMP:
			return _jump()
		Player.State.FALL:
			return _fall()
		Player.State.LAND:
			return _land()
		Player.State.HANG:
			return _hang()
		Player.State.CLIMB_UP:
			return _mantle(t)
		Player.State.LADDER:
			return _ladder(t)
		Player.State.ATTACK:
			return _pose(SwordPoses.attack(t))
		Player.State.AIR_SLASH:
			return _pose(SwordPoses.air_slash(t))
		Player.State.PLUNGE:
			return _pose(SwordPoses.plunge())
		Player.State.PLUNGE_LAND:
			return _pose(SwordPoses.plunge_land(t))
		Player.State.PARRY:
			return _pose(SwordPoses.parry(t))
		Player.State.HURT:
			return _hurt(t)
		Player.State.DEAD:
			return _dead(t)
		_:
			return _idle()


## Barely moving, but never still: the robe breathes and the hood settles.
func _idle() -> Dictionary:
	var breath := sin(_time * 2.0)
	var rest := _pose({
		"squash": 1.0 + breath * 0.012,
		"bob": breath * 0.22,
		"lean": 0.5,
		"stance": 0.8,
		"hood_tilt": 0.06 + breath * 0.03,
		"arm_a": 1.42, "arm_b": 1.5,
		"cloak_sweep": 0.5 - breath * 0.2,
		"blade": 2.42, "blade_len": 9.0,
	})
	return rest if idle_art == null else idle_art.pose(rest)


func _walk(t: float) -> Dictionary:
	var c := sin(t * 11.0)
	return _pose({
		"lean": 1.2,
		"bob": -absf(c) * 0.5,
		"stride": c * 2.2,
		"knee": maxf(0.0, c) * 1.5,
		"stance": 0.7,
		"hem_lift": 1.4,
		"hem_fwd": -c * 0.9,
		"hood_tilt": 0.08,
		"arm_a": 1.32 - c * 0.38, "arm_a_len": 5.8, "arm_b": 1.44 + c * 0.38,
		"cloak_sweep": 1.0,
		"blade": 2.42, "blade_len": 9.0,
	})


## The run cycle. The stride is the readable thing, so the hem lifts clear of
## it and swings against it — cloth pulled the other way by the leg that just
## went through it.
func _run(t: float) -> Dictionary:
	var speed := _speed_share()
	var c := sin(t * lerpf(13.0, 19.0, clampf(speed, 0.0, 1.0)))
	return _pose({
		"lean": 3.1,
		"bob": -absf(c) * 0.9 - 0.3,
		"stride": c * 3.7,
		"knee": maxf(0.0, c) * 2.8,
		"stance": 0.4,
		"hem_lift": 3.4,
		"hem_fwd": -c * 1.7,
		"hem_spread": 0.5,
		"hood_tilt": 0.16,
		"arm_a": 1.2 - c * 0.62, "arm_a_len": 5.6, "arm_b": 1.55 + c * 0.6,
		"cloak_sweep": 2.4, "cloak_rise": 1.5, "cloak_flare": 1.15,
		"blade": 2.52, "blade_len": 9.0,
	})


## Turning around is the one place the figure is allowed to be narrow: the
## shoulders foreshorten, the heel digs in, the hood is already looking the new
## way and the cloak is still travelling the old way.
func _turn(t: float) -> Dictionary:
	var phase := clampf(t / Tuning.TURN_TIME, 0.0, 1.0)
	return _pose({
		"squash": 0.97,
		"lean": -2.6,
		"twist": 0.58,
		"stride": -2.6,
		"stance": 1.7,
		"knee": 0.5,
		"hem_lift": 1.0,
		"hem_fwd": 3.0,
		"hem_spread": 1.4,
		"hood_tilt": -0.05,
		"hood_face": lerpf(0.4, -1.0, smoothstep(0.0, 0.7, phase)),
		"arm_a": 2.2, "arm_b": 2.5,
		"cloak_sweep": -2.6, "cloak_rise": 0.8, "cloak_flare": 1.5,
		"blade": 2.75, "blade_len": 9.0,
	})


## Folded down, hem pooling on the floor, hood low over the knees.
func _crouch() -> Dictionary:
	return _pose({
		"sink": Tuning.BODY_HEIGHT - Tuning.CROUCH_HEIGHT,
		"lean": 0.9,
		"stance": 1.4,
		"knee": -1.2,
		"hem_lift": -0.8,
		"hem_spread": 2.0,
		"hood_tilt": 0.3,
		"arm_a": 1.1, "arm_a_len": 5.2, "arm_b": 1.3, "arm_b_len": 4.8,
		"cloak_sweep": 0.8, "cloak_rise": -0.4, "cloak_flare": 1.2,
		"blade": 2.3, "blade_len": 7.5,
	})


## Stretched, legs tucked under, cloth streaming straight down.
func _jump() -> Dictionary:
	return _pose({
		"squash": 1.09,
		"lean": 1.8,
		"stride": 2.4,
		"knee": 3.4,
		"stance": 0.6,
		"hem_lift": 4.2,
		"hem_fwd": -1.6,
		"hood_tilt": -0.12,
		"arm_a": -0.35, "arm_a_len": 6.4, "arm_b": 1.9,
		"cloak_sweep": 2.6, "cloak_rise": -1.6, "cloak_flare": 1.1,
		"blade": 2.62, "blade_len": 9.0,
	})


## Reaching: arms up, legs trailing, cloth dragged up past the shoulders. The
## grab probe fires from here, so the pose has to look like it is asking for a
## ledge.
func _fall() -> Dictionary:
	return _pose({
		"squash": 1.05,
		"lean": 0.4,
		"stride": -1.8,
		"knee": 1.6,
		"stance": 1.1,
		"hem_lift": 3.2,
		"hem_fwd": -3.0,
		"hood_tilt": -0.2,
		"arm_a": -0.95, "arm_a_len": 6.6, "arm_b": -0.45, "arm_b_len": 6.2,
		"cloak_sweep": 3.0, "cloak_rise": 3.6, "cloak_flare": 1.3,
		"blade": 2.72, "blade_len": 9.0,
	})


## Absorbing: knees out, hem splayed on the floor, hood dropped. The depth of
## the squash comes from `landed`, so it already scales with last_impact.
func _land() -> Dictionary:
	return _pose({
		"squash": 0.86,
		"sink": 1.6,
		"lean": 1.0,
		"stance": 1.8,
		"knee": -1.2,
		"hem_lift": -0.6,
		"hem_spread": 2.6,
		"hood_tilt": 0.42,
		"arm_a": 1.9, "arm_b": 2.1,
		"cloak_sweep": 0.4, "cloak_rise": 2.4, "cloak_flare": 1.6,
		"blade": 2.3, "blade_len": 9.0,
	})


## Hanging from the hands: the body drops below the ledge, the arms go
## vertical, and the legs dangle past the origin. The silhouette is a narrow
## column under a bar — nothing else in the game looks like it.
func _hang() -> Dictionary:
	var swing := sin(_time * 2.4)
	return _pose({
		"squash": 1.04,
		"sink": 6.6,
		"hem_spread": -1.5,
		"lean": 1.2,
		"dangle": 3.6,
		"stance": 0.5,
		"stride": swing * 0.9,
		"knee": 1.0 + swing * 0.4,
		"hem_lift": -1.0,
		"hem_fwd": swing * 0.8,
		"hood_tilt": -0.3,
		"arm_a": -1.12, "arm_a_len": 7.8, "arm_b": -2.02, "arm_b_len": 7.6,
		"cloak_sweep": 0.1, "cloak_rise": -2.2, "cloak_flare": 0.85,
		"glint": 0.8,
	})


## The mantle: drive a knee onto the ledge, then stand up over it. Two poses
## with the climb's own progress between them, so the arc reads as effort.
func _mantle(t: float) -> Dictionary:
	var phase := smoothstep(0.0, 1.0, clampf(t / Tuning.CLIMB_UP_TIME, 0.0, 1.0))
	return _pose({
		"squash": lerpf(1.02, 0.95, phase),
		"sink": lerpf(5.0, -0.4, phase),
		"lean": lerpf(4.6, 1.6, phase),
		"twist": 0.8,
		"stride": lerpf(3.4, 1.0, phase),
		"stance": 0.9,
		"knee": lerpf(4.4, 1.2, phase),
		"hem_lift": 4.4,
		"hem_fwd": -1.4,
		"hood_tilt": lerpf(0.55, 0.12, phase),
		"arm_a": lerpf(-1.15, 0.5, phase), "arm_a_len": 6.8,
		"arm_b": lerpf(-0.8, 1.2, phase), "arm_b_len": 6.4,
		"cloak_sweep": 2.8, "cloak_rise": lerpf(-1.4, 0.6, phase), "cloak_flare": 1.2,
	})


## Facing the rungs, so the shoulders foreshorten and the hood is nearly edge
## on; hands and feet alternate.
func _ladder(t: float) -> Dictionary:
	var c := sin(t * 8.0)
	return _pose({
		"lean": 0.6,
		"twist": 0.52,
		"stance": 0.6,
		"stride": c * 1.5,
		"knee": absf(c) * 1.4,
		"hem_lift": 2.6,
		"hood_tilt": 0.1,
		"hood_face": 0.3,
		"glint": 0.35,
		"arm_a": -1.35 - c * 0.4, "arm_a_len": 6.4,
		"arm_b": -1.35 + c * 0.4, "arm_b_len": 6.4,
		"cloak_sweep": 0.2, "cloak_rise": -1.2, "cloak_flare": 0.75,
	})


## Thrown back and off balance, hood knocked away from the blow.
func _hurt(t: float) -> Dictionary:
	var recover := smoothstep(0.0, 0.3, t)
	return _pose({
		"squash": 1.03,
		"tilt": lerpf(-0.3, -0.12, recover),
		"lean": -3.4,
		"stride": -2.2,
		"stance": 1.4,
		"knee": 1.2,
		"hem_lift": 2.2,
		"hem_fwd": 2.6,
		"hood_tilt": -0.55,
		"hood_face": 0.7,
		"glint": 0.0,
		"arm_a": 2.5, "arm_b": 2.9,
		"cloak_sweep": -2.2, "cloak_rise": 2.8, "cloak_flare": 1.6,
		"blade": 2.95, "blade_len": 9.0,
	})


## Toppled: the robe keeps its shape, the figure does not.
func _dead(t: float) -> Dictionary:
	var fall := smoothstep(0.0, 0.45, t)
	return _pose({
		"squash": lerpf(1.0, 0.92, fall),
		"tilt": lerpf(-0.25, -1.26, fall),
		"sink": lerpf(0.0, 2.6, fall),
		"lean": -2.0,
		"stride": -2.8,
		"stance": 2.0,
		"knee": -1.0,
		"hem_lift": -0.5,
		"hem_spread": lerpf(0.0, 2.2, fall),
		"hood_tilt": lerpf(-0.4, 0.5, fall),
		"glint": 0.0,
		"arm_a": 2.6, "arm_b": 3.0,
		"cloak_sweep": lerpf(-1.0, 2.6, fall), "cloak_rise": -1.6, "cloak_flare": 2.0,
		"blade": 2.9, "blade_len": 9.0,
	})
