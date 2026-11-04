class_name GlassbearerArt
extends Node2D
## Draws the Glassbearer, posed from his state machine.
##
## ## A circle on a stick
##
## The prince is a narrow red column under a pointed cowl; the sentinel a dark,
## broad-shouldered figure under a spiked dome. The Glassbearer is told from
## both by the one shape nothing else in the game has: a round disc on a staff
## held above his head, higher than anyone's outline. Under it, the narrowest
## figure in the game -- a robe straight to the floor with no legs showing, a
## tall rounded hood, no shoulders to speak of -- so with the colours thrown
## away the three are a cowl, a spike and a circle on a stick
## (tools/glassbearer_poses.gd --silhouette, docs/glassbearer-poses.png).
##
## Two tones, as everything is: the robe is lit on its world-left half and in
## shade on the rest, with the sun's one-pixel rim down its left edge, and a
## gold stole down the front is the one warm band on it.
##
## ## The glass is the rule
##
## The disc is LIGHT_SOFT in the sun and SHADOW_PIT out of it, so whether he
## can shoot is legible from across the tower. The aim is told by the glass
## first: it brightens in three hard steps -- LIGHT, LIGHT_SOFT, PAPER --
## while a star of PAPER grows on its face and the staff tips toward the
## prince; then the shot, a frame of white; then the spent glass, dull, with a
## ring of embers closing round it as it gathers the sun again.
##
## ## Secondary motion
##
## The pose is a pure function of (state, state_time, facing, glass); the
## robe's hem and the stole's tassel chase his velocity with a lag, as the
## sentinel's cloth does. That and the hit flash are all the state this node
## keeps, and none of it reaches the simulation.

const ROBE := Palette.SHADOW_DEEP
const ROBE_SHADE := Palette.INK
const RIM := Palette.SHADOW_WARM
const TRIM := Palette.LIGHT_WARM
const STAFF := Palette.STEEL_DARK
const STAFF_LIT := Palette.STEEL

const HEM_HALF := 4.5
const WAIST_HALF := 3.0
const SHOULDER_HALF := 3.4
const SHOULDER_Y := -15.0
const HOOD_Y := -18.5
const HOOD_TOP := -23.5
const HAND_Y := -12.0

const CLOTH_CHASE := 7.0
const FLASH_TIME := 0.14
const SHATTER_AT := 0.12
const SINK_AT := 0.35
const FLICKER_AT := 0.85
const SHARDS := 9

var _foe: Glassbearer
var _time: float = 0.0
var _sway := 0.0
var _flash: float = 0.0
var _f: float = 1.0
## Where the hand holds the staff and where the glass is, this frame.
var _hand := Vector2.ZERO
var _glass := Vector2.ZERO


func _ready() -> void:
	_foe = get_parent() as Glassbearer
	if _foe == null:
		return
	_foe.defeated.connect(func() -> void: _flash = 1.0)


func _process(delta: float) -> void:
	_time += delta
	_flash = maxf(0.0, _flash - delta / FLASH_TIME)
	if _foe != null:
		var target := clampf(_foe.velocity.x * float(_foe.facing) / Glassbearer.SPEED, -2.0, 2.0)
		_sway = lerpf(_sway, target, 1.0 - exp(-delta * CLOTH_CHASE))
	queue_redraw()


func _c(base: Color) -> Color:
	return base if _flash <= 0.0 else base.lerp(Palette.PAPER, _flash * 0.85)


func _draw() -> void:
	if _foe == null:
		return
	_f = float(_foe.facing)
	var dying := _foe.state == Glassbearer.State.DYING
	var death := _foe.state_time / Glassbearer.DEATH_TIME if dying else 0.0
	if dying:
		_draw_death(death)
		return
	var pose := _pose()
	_draw_contact_shadow()
	_draw_robe(pose)
	_draw_hood(pose)
	_draw_staff(pose)
	_draw_glass(pose)


func _draw_contact_shadow() -> void:
	draw_colored_polygon(PackedVector2Array([
		Vector2(-5.0, -0.4), Vector2(5.0, -0.4), Vector2(4.0, 1.2), Vector2(-4.0, 1.2),
	]), Palette.with_alpha(Palette.INK, 0.3))


## --- the poses -----------------------------------------------------------------

## What each state does to the figure: `lean` (body forward, px), `bob`,
## `tip` (the staff's angle from upright, forward positive), `hem` (the hem's
## swing), `step` (the glass's brightness, 0 dull to 4 the shot) and `star`
## (the star's arm on the glass, px).
func _pose() -> Dictionary:
	var t := _foe.state_time
	var lit := _foe.glass
	var pose := {"lean": 0.0, "bob": 0.0, "tip": 0.0, "hem": 0.0,
		"step": 1 if lit else 0, "star": 0.0, "embers": 0.0}
	match _foe.state:
		Glassbearer.State.WALK:
			var c := sin(t * 5.0)
			pose["bob"] = -absf(c) * 0.5
			pose["hem"] = c * 0.8
			pose["tip"] = 0.06 + c * 0.03
		Glassbearer.State.LOOK:
			pose["bob"] = sin(_time * 2.0) * 0.25
			pose["tip"] = -0.05
		Glassbearer.State.AIM:
			var p := clampf(t / maxf(_foe.aim_time(), 0.001), 0.0, 1.0)
			var e := smoothstep(0.0, 0.6, p)
			pose["lean"] = -1.2 * e
			pose["tip"] = 0.38 * e
			pose["hem"] = -0.6 * e
			# Three hard steps, never a ramp: the art direction has two tones
			# and a tell, not a glow.
			pose["step"] = 1 + mini(2, floori(p * 3.0))
			pose["star"] = 1.0 + 3.0 * smoothstep(0.2, 1.0, p)
			if p > 0.92 and int(_time * 30.0) % 2 == 0:
				pose["step"] = 4
		Glassbearer.State.SPENT:
			var p := clampf(t / Glassbearer.SPENT_TIME, 0.0, 1.0)
			pose["step"] = 4 if t < 0.05 else 0
			pose["lean"] = lerpf(1.5, 0.0, smoothstep(0.0, 0.5, p))
			pose["tip"] = lerpf(-0.25, 0.0, smoothstep(0.0, 0.6, p))
			pose["embers"] = p
			pose["hem"] = 0.6
	return pose


## The robe: a narrow column from the shoulders to a hem that flares a
## little on the floor, swinging a pixel behind his motion, with a band of
## ink at its foot and the gold stole down its front edge.
func _draw_robe(pose: Dictionary) -> void:
	var lean: float = pose["lean"]
	var bob: float = pose["bob"]
	var hem: float = float(pose["hem"]) - _sway * 0.8
	var top := SHOULDER_Y + bob
	var outline := PackedVector2Array([
		Vector2(-SHOULDER_HALF + lean, top), Vector2(SHOULDER_HALF + lean, top),
		Vector2(WAIST_HALF + 0.4 + lean * 0.5, -8.0 + bob),
		Vector2(HEM_HALF + 0.6 + hem, -0.6), Vector2(-HEM_HALF - 0.4 + hem, -0.6),
		Vector2(-WAIST_HALF + lean * 0.5, -8.0 + bob),
	])
	_plane(_mirror(outline), ROBE, ROBE_SHADE, true)
	var band := PackedVector2Array([
		Vector2(HEM_HALF + 0.6 + hem, -0.6), Vector2(-HEM_HALF - 0.4 + hem, -0.6),
		Vector2(-HEM_HALF + hem, -2.0), Vector2(HEM_HALF + 0.2 + hem, -2.0),
	])
	draw_colored_polygon(_mirror(band), _c(ROBE_SHADE))
	var stole := PackedVector2Array([
		Vector2(1.0 + lean, top + 0.8), Vector2(2.0 + lean, top + 0.8),
		Vector2(2.6 + hem, -2.0), Vector2(1.5 + hem, -2.0),
	])
	draw_colored_polygon(_mirror(stole), _c(TRIM))
	_hand = Vector2((4.2 + lean) * _f, HAND_Y + bob)
	# The sleeve: from the shoulder down and forward to the hand on the staff.
	var shoulder := Vector2((1.6 + lean) * _f, top + 1.0)
	var sleeve := PackedVector2Array([
		shoulder + Vector2(-1.2 * _f, -0.6), shoulder + Vector2(1.0 * _f, -1.0),
		_hand + Vector2(0.8 * _f, -0.8), _hand + Vector2(0.4 * _f, 1.2),
		shoulder + Vector2(-0.8 * _f, 1.8),
	])
	_plane(sleeve, ROBE, ROBE_SHADE, true)


## A small head under a tall rounded cap -- the narrowest thing on him, so the
## outline goes up in a column to the glass -- with a slot of a face whose eye
## burns when he aims.
func _draw_hood(pose: Dictionary) -> void:
	var lean: float = pose["lean"]
	var bob: float = pose["bob"]
	var c := Vector2(lean * 1.1, HOOD_Y + bob)
	var head := PackedVector2Array()
	for i: int in 10:
		var a := TAU * float(i) / 10.0
		head.append(c + Vector2(cos(a) * 2.3, sin(a) * 2.6))
	_plane(_mirror(head), ROBE, ROBE_SHADE, true)
	# The cap: straight sides, a round crown, a gold band at its foot.
	var cap := PackedVector2Array([Vector2(c.x - 2.0, c.y - 1.6), Vector2(c.x + 2.0, c.y - 1.6)])
	for i: int in 7:
		var a := float(i) / 6.0 * PI
		cap.append(Vector2(c.x + cos(a) * 2.0, c.y - 5.6 - sin(a) * 1.8))
	_plane(_mirror(cap), ROBE, ROBE_SHADE, true)
	draw_rect(Rect2(_mirror(PackedVector2Array([Vector2(c.x - 2.2, c.y - 2.4)]))[0].x
		- (4.4 if _f < 0.0 else 0.0), c.y - 2.4, 4.4, 0.9), _c(TRIM))
	# The face: ink, and an eye that burns with the glass's aim.
	var face := Vector2(c.x + 0.9, c.y - 0.6)
	draw_rect(Rect2(_mirror(PackedVector2Array([face]))[0] - Vector2(0.0 if _f > 0.0 else 1.6,
		0.0), Vector2(1.6, 2.2)), Palette.INK)
	var step: int = pose["step"]
	if step >= 2:
		var eye := _mirror(PackedVector2Array([face + Vector2(0.6, 0.6)]))[0]
		draw_rect(Rect2(eye.floor(), Vector2.ONE), Palette.LIGHT_SOFT)


## The staff from the hand to the glass, tipped toward the prince when he
## aims. Two pixels, the sun-facing one lit.
func _draw_staff(pose: Dictionary) -> void:
	var tip: float = pose["tip"]
	var up := Vector2(sin(tip) * _f, -cos(tip))
	var foot := _hand - up * 5.0
	_glass = _hand + up * (Glassbearer.GLASS_HEIGHT + HAND_Y + 2.0)
	_glass.y = minf(_glass.y, -Glassbearer.GLASS_HEIGHT + 1.0)
	draw_line(foot, _glass, _c(STAFF), 2.0)
	draw_line(foot + Vector2(-0.5, 0.0), _glass + Vector2(-0.5, 0.0), _c(STAFF_LIT), 1.0)
	# The hand on the staff, in the sleeve's shade.
	draw_rect(Rect2(_hand.x - 1.0, _hand.y - 1.2, 2.0, 2.4), _c(Palette.SHADOW))


## The glass: a disc rimmed in ink, its face the chapter's rule.
func _draw_glass(pose: Dictionary) -> void:
	var r := Glassbearer.GLASS_R
	var at := _glass.round()
	draw_circle(at, r + 1.0, Palette.INK)
	# 0 dull; 1 lit; 2 lit with a white heart; 3 white; 4 the shot, which
	# swallows the rim. Each a hard step: the aim climbs 1, 2, 3.
	var step: int = pose["step"]
	var face := Palette.SHADOW_PIT if step == 0 else Palette.LIGHT_SOFT
	if step >= 3:
		face = Palette.PAPER
	draw_circle(at, r + (1.0 if step == 4 else 0.0), face)
	if step == 2:
		draw_circle(at, r - 1.5, Palette.PAPER)
	# A lit glass catches the sun on its upper left: one pixel of paper.
	if step >= 1:
		draw_rect(Rect2(at + Vector2(-2.0, -2.0), Vector2.ONE), Palette.PAPER)
	var star: float = pose["star"]
	if star > 0.0:
		var arm := roundf(star)
		draw_rect(Rect2(at.x - arm, at.y, arm * 2.0 + 1.0, 1.0), Palette.PAPER)
		draw_rect(Rect2(at.x, at.y - arm, 1.0, arm * 2.0 + 1.0), Palette.PAPER)
	var embers: float = pose["embers"]
	if embers > 0.0:
		var count := int(embers * 8.0)
		for i: int in count:
			var a := -PI * 0.5 + TAU * float(i) / 8.0
			draw_rect(Rect2((at + Vector2(cos(a), sin(a)) * (r + 0.5)).floor(), Vector2.ONE),
				Palette.SHADOW_WARM)


## Shattered: the glass bursts into shards of light, the staff topples, the
## cap falls, and the robe slumps forward into a heap and flickers out.
func _draw_death(death: float) -> void:
	if death >= FLICKER_AT and int(_time * 24.0) % 2 == 0:
		return
	if death >= 0.99:
		return
	var t := death * Glassbearer.DEATH_TIME
	var sink := smoothstep(0.0, SINK_AT * 1.6, death)
	var top := lerpf(SHOULDER_Y, -4.0, sink)
	var slump := 3.0 * sink
	var outline := PackedVector2Array([
		Vector2(-SHOULDER_HALF + slump, top), Vector2(SHOULDER_HALF + slump, top + 0.6 * sink),
		Vector2(HEM_HALF + 1.6 * sink, -0.6), Vector2(-HEM_HALF - 2.0 * sink, -0.6),
	])
	_plane(_mirror(outline), ROBE, ROBE_SHADE, true)
	# The cap rolls off the way he falls.
	var cap_at := Vector2(slump + 4.0 * sink, lerpf(HOOD_Y - 4.0, -2.0, smoothstep(0.1, 0.5,
		death)))
	draw_rect(Rect2(_mirror(PackedVector2Array([cap_at]))[0] - Vector2(2.0, 2.0),
		Vector2(4.0, 3.0)), _c(ROBE))
	# The staff, toppling away from where the blow came.
	var fall := smoothstep(0.0, SINK_AT, death) * 1.45
	var foot := Vector2(3.0 * _f, -1.0)
	var tip := foot + Vector2(sin(fall) * -_f, -cos(fall)) * 24.0
	draw_line(foot, tip, STAFF, 2.0)
	if death < SHATTER_AT:
		var at := Vector2(2.0 * _f, -Glassbearer.GLASS_HEIGHT)
		draw_circle(at, Glassbearer.GLASS_R + 1.0, Palette.INK)
		draw_circle(at, Glassbearer.GLASS_R, Palette.PAPER)
		return
	# The shards: hard bright splinters thrown out of the glass and falling.
	var since := t - SHATTER_AT * Glassbearer.DEATH_TIME
	for i: int in SHARDS:
		var a := TAU * float(i) / float(SHARDS) + 0.4
		var v := Vector2(cos(a) * 70.0, sin(a) * 55.0 - 80.0)
		var p := Vector2(2.0 * _f, -Glassbearer.GLASS_HEIGHT) + v * since \
			+ Vector2(0.0, 0.5 * 420.0 * since * since)
		if p.y > 0.0:
			continue
		var c := Palette.PAPER if i % 3 == 0 else Palette.LIGHT_SOFT
		draw_rect(Rect2(p.floor(), Vector2(2.0, 1.0 + float(i % 2))), c)


## --- planes --------------------------------------------------------------------

## Points drawn facing right, turned to face the way he does.
func _mirror(points: PackedVector2Array) -> PackedVector2Array:
	if _f > 0.0:
		return points
	var out := PackedVector2Array()
	for p: Vector2 in points:
		out.append(Vector2(-p.x, p.y))
	return out


## A plane lit on its world-left half and in shade on the rest, with the
## sun's rim down its left edge: the sentinel's rule, so the light cannot
## disagree between the two (scripts/entities/patrol_art.gd).
func _plane(points: PackedVector2Array, lit: Color, shade: Color, rim := false) -> void:
	if points.size() < 3 or Geometry2D.triangulate_polygon(points).is_empty():
		return
	draw_colored_polygon(points, _c(shade))
	var left := PackedVector2Array([
		Vector2(-64.0, -64.0), Vector2(0.0, -64.0), Vector2(0.0, 64.0), Vector2(-64.0, 64.0),
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
