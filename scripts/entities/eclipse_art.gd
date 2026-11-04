class_name EclipseArt
extends Node2D
## Draws the King in his eclipse regalia, posed from the Eclipse's phase and
## state (scripts/entities/eclipse.gd).
##
## ## Silhouette first
##
## At a third of the frame's height he has to read as a shape before he is
## anything else, and the shape has three parts nothing else in the game has:
##
## | | The read |
## | --- | --- |
## | the disc | 24 px across, wider than his body: black, or polished and bright |
## | the crown | nine gold spikes in a fan; every other head is a cowl, dome or brim |
## | the robe | floor-length with a mantle: twice the prince's mass, half again as tall |
##
## Held up between himself and the light, the disc is the one silhouette in
## the game that is a ring of fire (docs/campaign.md).
##
## ## Drawn a quarter larger than he is refereed
##
## Posed at his body's 32 px he read, in play, as about the prince's size:
## the camera holds a 320-unit frame, the crown was a smudge on top of a
## column as narrow as a cowl, and nothing said boss. So the whole figure is
## drawn at SCALE about his feet -- 40 px to the crown band, a 30 px disc, a
## mantle wider than two princes -- while his hitbox stays Eclipse.BODY, and
## with it every number his fight and its frozen clear run are tied to. The
## one place a drawing larger than the body could lie is the plunge, and it
## errs the right way: the plunge's point reaches PLUNGE_REACH under the
## prince's feet, so they meet the drawn crown just as the point meets the
## refereed one. The scale is held under the galleries: at 1.25 the tallest
## spike, flared, stops a pixel under a gallery's underside (48 px over the
## floor), where he pauses to be plunged.
##
## ## Two tones, lit by the kept sun
##
## The sentinel is near-black because on lit stone a threat is a hole in the
## light. There is no lit stone down here: the Vault at night is the darkest
## ground in the game, and ink on it is no shape at all. So the King is the
## sentinel's crimson a step up -- shade and deep shade, gold trim -- and he is
## lit: every plane is split the sentinel's way, but the light is the kept
## sun's, so the lit half and the gold rim are on the side that faces it, his
## left as he walks east of it and his right as he walks west. In the dark of
## the third phase there is no sun to light him: he is pure ink, a black
## shape against a blacker room, and the only light on him is his own
## corona's rim, his eyes and his crown.
##
## ## What he tells, and how
##
## Every tell is a pose, a glint and a sound together, and each is drawn
## across the whole of `warn()`'s length, so the LONGER WARNINGS assist
## stretches the drawing with the clock:
##
## | Tell | Pose | Light |
## | --- | --- | --- |
## | the shove's draw | the disc pulled in to the body, knees bent | a star runs round its rim |
## | a bolt's charge | the polished face tipped toward you | its rim brightens in three steps |
## | the pounce's crouch | sunk low under the raised disc | the corona flares, the eyes ignite |
## | the gather | feet planted, disc at the chest | the corona closes to a point |
##
## ## What he has left
##
## No bar. His crown has a spike for every wound the fight takes, nine, and
## each wound puts one out, outer pair first, so the centre spike is the
## finale's; and his disc cracks once for every phase won, light showing
## through. Both are on him, where the eye already is.
##
## The pose is a pure function of the King's state; the mantle's sway and
## the hit flash are the only state this node keeps, all of it cosmetic. It
## also lays the King's darkness over the world (WorldGrade.dim) and hushes
## the music to its bed while it lasts (PlayerAudio.HUSH), because
## presentation is where both belong.

## How much larger than his body he is drawn (above).
const SCALE := 1.25

const ROBE := Palette.SHADOW
const ROBE_SHADE := Palette.SHADOW_DEEP
const MANTLE := Palette.SHADOW_DEEP
const MANTLE_SHADE := Palette.INK
const RIM := Palette.LIGHT_WARM
const TRIM := Palette.LIGHT_WARM
const GOLD := Palette.LIGHT
const BRONZE := Palette.MID

## --- proportions, pixels up from the feet --------------------------------------

const WAIST_Y := -13.0
const CHEST_Y := -19.0
const SHOULDER_Y := -23.0
const HEAD_Y := -27.0
const HEAD_R := 3.2

const HW_HEM := 7.5
const HW_WAIST := 4.0
const HW_CHEST := 5.0
const HW_SHOULDER := 6.6

const DISC_R := 12.0
const SPIKES := 9
## The order the spikes go out in: the outer pair first, the centre last.
const SNUFF_ORDER: Array[int] = [0, 8, 1, 7, 2, 6, 3, 5, 4]

const CLOTH_CHASE := 6.0
const FLASH_TIME := 0.16
const FPS := 12.0

var _king: Eclipse
var _time := 0.0
var _sway := 0.0
var _flash := 0.0

# Scratch, filled by _rig().
var _f := 1.0
var _side := 1.0
var _dark := false
var _hip := Vector2.ZERO
var _waist := Vector2.ZERO
var _chest := Vector2.ZERO
var _shoulder := Vector2.ZERO
var _head := Vector2.ZERO
var _disc := Vector2.ZERO
var _foot_front := Vector2.ZERO
var _foot_back := Vector2.ZERO
var _tilt := 0.0


func _ready() -> void:
	scale = Vector2(SCALE, SCALE)
	_king = get_parent() as Eclipse
	if _king == null:
		return
	_king.staggered.connect(_on_hit)
	_king.phase_won.connect(func(_p: int) -> void: _on_hit())
	_king.defeated.connect(_on_hit)


func _on_hit() -> void:
	_flash = 1.0


func _process(delta: float) -> void:
	_time += delta
	_flash = maxf(0.0, _flash - delta / FLASH_TIME)
	if _king != null:
		var target := clampf(_king.velocity.x * _king.facing / Eclipse.WALK_SPEED, -2.0, 2.0)
		_sway = lerpf(_sway, target, 1.0 - exp(-delta * CLOTH_CHASE))
		_lay_darkness()
	queue_redraw()


## The vault put out: the grade's dim follows the King's darkness. Found by
## group, so a level without a grade -- an afternoon test floor -- is simply
## not darkened.
func _lay_darkness() -> void:
	if not is_inside_tree():
		return
	var grade := get_tree().get_first_node_in_group(WorldGrade.GROUP) as WorldGrade
	if grade != null:
		grade.dim = _king.darkness()
	# In the dark the music drops to its bed stem.
	var dark := _king.darkness() > 0.5
	if dark != is_in_group(PlayerAudio.HUSH):
		if dark:
			add_to_group(PlayerAudio.HUSH)
		else:
			remove_from_group(PlayerAudio.HUSH)


func _c(base: Color) -> Color:
	if _flash <= 0.0:
		return base
	return base.lerp(Palette.PAPER, _flash * 0.8)


## Where the kept sun hangs, in this node's space; straight up if there is none.
func _sun_local() -> Vector2:
	if is_inside_tree():
		var sun := get_tree().get_first_node_in_group(KeptSun.GROUP) as Node2D
		if sun != null:
			return to_local(sun.global_position)
	# No kept sun -- a pose sheet -- and no shaft to draw.
	return Vector2.ZERO


## --- drawing ------------------------------------------------------------------

func _draw() -> void:
	if _king == null:
		return
	var pose := _posture()
	_rig(pose)
	var mode := String(pose["disc"])
	if _king.state != Eclipse.State.FALL:
		_draw_contact_shadow()
	if mode == "polished":
		_draw_shaft(pose)
	_draw_mantle(pose)
	_draw_back_arm(pose)
	_draw_feet()
	_draw_robe()
	_draw_head(pose)
	_draw_crown(pose)
	_draw_front_arm()
	match mode:
		"black":
			_draw_black_disc(pose)
		"polished":
			_draw_polished_disc(pose)
		"eclipse":
			_draw_eclipse_disc(pose)
		"shattered":
			_draw_shards(pose)


func _draw_contact_shadow() -> void:
	var lift := -_king.position.y + _king.floor_y if _king.state == Eclipse.State.LEAP else 0.0
	var w := 8.0 - minf(4.0, lift * 0.15)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-w, lift - 0.4), Vector2(w, lift - 0.4),
		Vector2(w - 1.4, lift + 1.2), Vector2(-w + 1.4, lift + 1.2),
	]), Palette.with_alpha(Palette.INK, 0.35))


## A plane split down `_chest.x`: lit on the side facing the kept sun, shade on
## the other, and a one-pixel rim on the lit edge for the planes that make the
## outline. In the dark, all shade, and the rim is the corona's.
func _plane(points: PackedVector2Array, lit: Color, shade: Color, rim := false) -> void:
	if points.size() < 3 or Geometry2D.triangulate_polygon(points).is_empty():
		return
	draw_colored_polygon(points, _c(shade if not _dark else Palette.INK))
	if not _dark:
		var half := PackedVector2Array([
			Vector2(_chest.x, -96.0), Vector2(_chest.x + 96.0 * _side, -96.0),
			Vector2(_chest.x + 96.0 * _side, 96.0), Vector2(_chest.x, 96.0),
		])
		for part: PackedVector2Array in Geometry2D.intersect_polygons(points, half):
			if part.size() >= 3:
				draw_colored_polygon(part, _c(lit))
	if not rim:
		return
	var toward := _side if not _dark else _f
	var shifted := Transform2D(0.0, Vector2((-0.9 if not _dark else -1.2) * toward, 0.0)) * points
	var color := RIM if not _dark else Palette.SHADOW_WARM
	for part: PackedVector2Array in Geometry2D.clip_polygons(points, shifted):
		if part.size() >= 3:
			draw_colored_polygon(part, _c(color))


## The mantle: from the shoulders down his back to the floor, flaring behind
## him with the walk and lifting in a leap or a reel.
func _draw_mantle(pose: Dictionary) -> void:
	var lift := float(pose["mantle"]) - _sway * 1.5
	var back := -_f
	var hem := Vector2(_hip.x + back * (HW_HEM + 2.0 + lift * 1.6), -0.5 - maxf(0.0, lift) * 2.0)
	_plane(PackedVector2Array([
		_shoulder + Vector2(back * (HW_SHOULDER - 1.0), -1.0),
		_shoulder + Vector2(back * (HW_SHOULDER + 1.4), 1.0),
		_waist + Vector2(back * (HW_WAIST + 3.0 + lift * 0.6), 0.0),
		hem,
		Vector2(_hip.x + back * 1.0, -0.5),
		_chest + Vector2(back * 1.0, 0.0),
	]), MANTLE, MANTLE_SHADE, true)


func _draw_back_arm(pose: Dictionary) -> void:
	var hand := _shoulder + Vector2(-_f * 2.5, 9.0).rotated(float(pose["arm_back"]) * _f)
	_limb(_shoulder + Vector2(-_f * 4.0, 0.5), hand, 3.0, 2.4, ROBE, ROBE_SHADE)


## Boots under the hem: the toe is what says he is walking.
func _draw_feet() -> void:
	for foot: Vector2 in [_foot_back, _foot_front]:
		draw_colored_polygon(PackedVector2Array([
			foot + Vector2(-1.8 * _f, -2.0), foot + Vector2(1.6 * _f, -2.0),
			foot + Vector2(3.0 * _f, -0.8), foot + Vector2(2.8 * _f, 0.0),
			foot + Vector2(-1.8 * _f, 0.0),
		]), _c(ROBE_SHADE))


## The robe: shoulders to a floor-length hem, gold at the hem and the belt.
func _draw_robe() -> void:
	var hem_y := minf(-0.6, _hip.y + 12.0)
	var hem := Vector2(_hip.x - _sway * 0.8 * _f, hem_y)
	var outline := PackedVector2Array([
		_shoulder + Vector2(-HW_SHOULDER, 0.0), _shoulder + Vector2(HW_SHOULDER, 0.0),
		_chest + Vector2(HW_CHEST, 0.0), _waist + Vector2(HW_WAIST, 0.0),
		hem + Vector2(HW_HEM, 0.0), hem + Vector2(-HW_HEM, 0.0),
		_waist + Vector2(-HW_WAIST, 0.0), _chest + Vector2(-HW_CHEST, 0.0),
	])
	_plane(outline, ROBE, ROBE_SHADE, true)
	# A gold border along the hem and a belt: the warm bands across a dark
	# column, where the eye finds his height.
	draw_rect(Rect2(hem.x - HW_HEM + 0.5, hem.y - 1.0, HW_HEM * 2.0 - 1.0, 1.0), _c(TRIM))
	draw_rect(Rect2(_waist.x - HW_WAIST - 0.3, _waist.y - 0.6, HW_WAIST * 2.0 + 0.6, 1.2),
		_c(RIM))
	# The collar: a broad gold yoke over the shoulders.
	draw_colored_polygon(PackedVector2Array([
		_shoulder + Vector2(-HW_SHOULDER + 1.0, -0.6), _shoulder + Vector2(HW_SHOULDER - 1.0, -0.6),
		_shoulder + Vector2(HW_SHOULDER - 2.0, 1.2), _shoulder + Vector2(-HW_SHOULDER + 2.0, 1.2),
	]), _c(TRIM if not _dark else RIM))


## The face, in the shadow of the crown: ink, and two eyes that are embers
## until he means it.
func _draw_head(pose: Dictionary) -> void:
	var c := _head
	var face := PackedVector2Array()
	for i: int in 12:
		var a := TAU * float(i) / 12.0
		face.append(c + Vector2(cos(a) * HEAD_R, sin(a) * HEAD_R * 1.15).rotated(_tilt * _f))
	_plane(face, Palette.SHADOW_DEEP, Palette.INK, true)
	var ignite := float(pose["eyes"])
	var eye := Palette.MID.lerp(Palette.PAPER, ignite)
	var size := 1.0 + roundf(ignite)
	var ex := c.x + _f * 1.2
	draw_rect(Rect2(ex - size * 0.5, c.y - 0.5, size, size), eye)
	draw_rect(Rect2(ex + _f * 2.0 - size * 0.5, c.y - 0.5, size, size), eye)
	if ignite > 0.6:
		draw_circle(Vector2(ex + _f, c.y), 3.0, Palette.with_alpha(Palette.LIGHT_SOFT, 0.25))


## Nine gold spikes in a fan, a band under them. A spike is put out for every
## wound: a short stub of shade where the gold was.
func _draw_crown(pose: Dictionary) -> void:
	var flare := float(pose["flare"])
	var out := _king.wounds_total()
	var base := _head + Vector2(0.0, -HEAD_R + 0.4)
	for i: int in SPIKES:
		var a := lerpf(-1.25, 1.25, float(i) / float(SPIKES - 1)) + _tilt * _f
		var dir := Vector2(sin(a), -cos(a))
		var lit := SNUFF_ORDER.find(i) >= out
		var length := (6.5 if i == 4 else (5.0 if i % 2 == 0 else 3.6)) + (flare * 1.5 if lit else 0.0)
		if not lit:
			length = 1.6
		var root := base + Vector2(dir.x * 2.6, dir.y * 1.2)
		var side := Vector2(-dir.y, dir.x) * 0.8
		draw_colored_polygon(PackedVector2Array([
			root - side, root + dir * length, root + side,
		]), _c(GOLD if lit else Palette.SHADOW_DEEP))
		if lit and flare > 0.5:
			draw_rect(Rect2((root + dir * length).round() - Vector2(0.5, 0.5), Vector2.ONE),
				Palette.PAPER)
	draw_rect(Rect2(base.x - 3.4, base.y - 0.8, 6.8, 1.4), _c(TRIM))


func _draw_front_arm() -> void:
	var elbow := _shoulder.lerp(_disc, 0.5) + Vector2(-0.8 * _f, 1.6)
	_limb(_shoulder + Vector2(_f * 3.6, 0.5), elbow, 3.2, 2.8, ROBE, ROBE_SHADE)
	_limb(elbow, _disc, 2.8, 2.4, ROBE, ROBE_SHADE)


## --- the disc ------------------------------------------------------------------

## The black face: a circle of ink that swallows light, a bronze rim lit on
## the side facing the sun, the boss at its centre, and a crack of light
## through it for every phase he has lost.
func _draw_black_disc(pose: Dictionary) -> void:
	var at := _disc
	var radius := DISC_R * float(pose["disc_scale"])
	draw_circle(at, radius + 0.5, _c(Palette.INK))
	draw_circle(at, radius, _c(Palette.SHADOW_WARM))
	# The rim is lit on the half that faces the kept sun: an arc of bronze
	# from the top round to the bottom on that side.
	var from := -PI * 0.5 if _side > 0.0 else PI * 0.5
	draw_arc(at, radius - 0.6, from, from + PI, 14, _c(BRONZE), 1.2)
	draw_circle(at, radius - 1.6, _c(Palette.INK))
	draw_rect(Rect2(at - Vector2(1.0, 1.0), Vector2(2.0, 2.0)), _c(Palette.SHADOW_WARM))
	_draw_cracks(at, radius)
	var glint := float(pose["glint"])
	if glint > 0.0:
		var a := -PI * 0.5 + TAU * glint * _f
		_star(at + Vector2(cos(a), sin(a)) * (radius - 0.5), 1.0 + 1.6 * sin(glint * PI))


## The cracks the phases won have put in it: straight runs of light from the
## boss outward, each bent once, the way a struck bronze plate splits.
func _draw_cracks(at: Vector2, radius: float) -> void:
	var cracks := _king.phase
	if _king.state == Eclipse.State.WON and _king.state_time >= Eclipse.CRACK_AT:
		cracks += 1
	for i: int in mini(cracks, 3):
		var a := -0.7 + float(i) * 2.2
		var mid := at + Vector2(cos(a), sin(a)) * radius * 0.45
		var bend := a + (0.5 if i % 2 == 0 else -0.5)
		var end := mid + Vector2(cos(bend), sin(bend)) * radius * 0.55
		draw_line(at, mid, Palette.LIGHT_SOFT, 1.0)
		draw_line(mid, end, Palette.LIGHT, 1.0)


## The polished face, tipped up to the kept sun: an ellipse of the sun's own
## tones. A bolt's charge burns its rim brighter in three steps.
func _draw_polished_disc(pose: Dictionary) -> void:
	var at := _disc
	var tip := float(pose["tip"])
	var squash := lerpf(0.32, 0.9, tip)
	var burn := int(floorf(float(pose["burn"]) * 3.0 + 0.0001))
	var rims: Array[Color] = [Palette.MID, Palette.LIGHT, Palette.LIGHT_SOFT, Palette.PAPER]
	var rim := rims[clampi(burn, 0, 3)]
	var angle := lerpf(0.0, 0.5 * _f, tip)
	_ellipse(at, DISC_R + 1.0, (DISC_R + 1.0) * squash, angle, _c(Palette.SHADOW_WARM))
	_ellipse(at, DISC_R, DISC_R * squash, angle, rim)
	_ellipse(at, DISC_R - 2.0, (DISC_R - 2.0) * squash, angle, Palette.LIGHT_SOFT)
	_ellipse(at + Vector2(-2.0 * _f, -1.0), DISC_R * 0.4, DISC_R * 0.4 * squash, angle,
		Palette.PAPER)
	if burn >= 3:
		draw_circle(at, DISC_R + 3.0 + float(int(_time * FPS) % 2),
			Palette.with_alpha(Palette.LIGHT_SOFT, 0.3))


## The light the disc drinks: a hard shaft from the kept sun down to its face.
func _draw_shaft(pose: Dictionary) -> void:
	var sun := _sun_local()
	var at := _disc
	if sun.y >= at.y - 4.0:
		return
	var width := 3.0 + float(pose["burn"]) * 2.0
	var shaft := PackedVector2Array([
		sun + Vector2(-width, 0.0), sun + Vector2(width, 0.0),
		at + Vector2(width * 1.4, 0.0), at + Vector2(-width * 1.4, 0.0),
	])
	draw_colored_polygon(shaft, Palette.with_alpha(Palette.LIGHT, 0.22))
	draw_line(sun, at, Palette.with_alpha(Palette.LIGHT_SOFT, 0.45), 1.0)


## Held up before the light: a black circle ringed with fire. `corona` is the
## ring's size and fire; `contract` closes it to a point at the centre.
func _draw_eclipse_disc(pose: Dictionary) -> void:
	var at := _disc
	var contract := float(pose["contract"])
	var corona := float(pose["corona"])
	var ring := lerpf(DISC_R + 1.0, 0.0, contract)
	var step := int(_time * FPS)
	if ring > 1.0:
		var tongues := 14
		for i: int in tongues:
			var a := TAU * float(i) / float(tongues) + float(step % 2) * 0.12
			var reach := (2.0 + corona * 2.5) * (0.6 + 0.4 * float((i + step) % 3) / 2.0)
			var dir := Vector2(cos(a), sin(a))
			var side := Vector2(-dir.y, dir.x) * 1.4
			var root := at + dir * ring
			draw_colored_polygon(PackedVector2Array([
				root - side, root + dir * reach, root + side,
			]), Palette.LIGHT if i % 2 == 0 else Palette.MID)
		draw_arc(at, ring, 0.0, TAU, 28, Palette.LIGHT_SOFT, 1.5)
	var radius := DISC_R * (1.0 - 0.25 * contract)
	draw_circle(at, radius + 0.8, Palette.SHADOW_WARM)
	draw_circle(at, radius, Palette.INK)
	_draw_cracks(at, radius)
	if contract > 0.0:
		_star(at, 1.0 + 3.0 * contract)
		if contract > 0.75:
			draw_circle(at, 2.0 + 2.0 * contract, Palette.with_alpha(Palette.PAPER, 0.5))


## The disc after the last blow: four pieces of bronze falling from where it
## broke, turning over, and the light gone out of them.
func _draw_shards(pose: Dictionary) -> void:
	var t := float(pose["shatter"])
	for i: int in 4:
		var a := -PI * 0.75 + float(i) * PI * 0.5
		var dir := Vector2(cos(a), sin(a))
		var fly := Vector2(dir.x * 18.0 * t, dir.y * 6.0 * t + 70.0 * t * t)
		var at := _disc + dir * 4.0 + fly
		at.y = minf(at.y, -1.0)
		var spin := a + t * 6.0 * (1.0 if i % 2 == 0 else -1.0)
		var r := DISC_R * 0.55
		draw_colored_polygon(PackedVector2Array([
			at, at + Vector2(cos(spin), sin(spin)) * r,
			at + Vector2(cos(spin + 0.9), sin(spin + 0.9)) * r,
		]), Palette.INK if i % 2 == 0 else Palette.SHADOW_DEEP)


func _ellipse(at: Vector2, rx: float, ry: float, angle: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i: int in 20:
		var a := TAU * float(i) / 20.0
		points.append(at + Vector2(cos(a) * rx, sin(a) * ry).rotated(angle))
	draw_colored_polygon(points, color)


## A hard four-point star of PAPER: a glint.
func _star(at: Vector2, arm: float) -> void:
	draw_rect(Rect2(at.x - arm, at.y - 0.5, arm * 2.0, 1.0), Palette.PAPER)
	draw_rect(Rect2(at.x - 0.5, at.y - arm, 1.0, arm * 2.0), Palette.PAPER)


func _limb(from: Vector2, to: Vector2, w0: float, w1: float, lit: Color, shade: Color) -> void:
	var along := (to - from).normalized()
	if along == Vector2.ZERO:
		return
	var side := Vector2(-along.y, along.x)
	_plane(PackedVector2Array([
		from + side * w0 * 0.5, to + side * w1 * 0.5,
		to - side * w1 * 0.5, from - side * w0 * 0.5,
	]), lit, shade)


## --- the rig --------------------------------------------------------------------

func _rig(pose: Dictionary) -> void:
	_f = float(_king.facing)
	_dark = _king.darkness() > 0.5
	var toward := _king.sun_x - _king.position.x
	_side = signf(toward) if absf(toward) > 3.0 else _f
	_tilt = float(pose["tilt"])
	var sink := float(pose["sink"])
	var lean := float(pose["lean"])
	var bob := float(pose["bob"])
	_hip = _place(0.0, -8.0 + sink + bob, lean * 0.2)
	_waist = _place(0.0, WAIST_Y + sink + bob, lean * 0.4)
	_chest = _place(0.0, CHEST_Y + sink + bob, lean * 0.75)
	_shoulder = _place(0.0, SHOULDER_Y + sink + bob, lean)
	_head = _place(0.6, HEAD_Y + sink + bob, lean * 1.1)
	var stride := float(pose["stride"])
	_foot_front = Vector2((stride + 1.5) * _f, 0.0)
	_foot_back = Vector2((-stride - 1.5) * _f, 0.0)
	var reach: Vector2 = pose["disc_at"]
	_disc = _shoulder + Vector2(reach.x * _f, reach.y)


func _place(forward: float, y: float, lean: float) -> Vector2:
	var p := Vector2((forward + lean) * _f, y)
	return p if is_zero_approx(_tilt) else p.rotated(_tilt * _f)


## --- the pose vocabulary ----------------------------------------------------------

func _pose(over: Dictionary) -> Dictionary:
	var p := {
		"sink": 0.0, "bob": 0.0, "lean": 0.0, "tilt": 0.0, "stride": 0.0,
		"mantle": 0.0, "arm_back": 0.2,
		"disc": "black", "disc_at": Vector2(9.0, 8.0), "disc_scale": 1.0,
		"glint": 0.0, "tip": 0.0, "burn": 0.0, "corona": 0.0, "contract": 0.0,
		"eyes": 0.0, "flare": 0.0, "shatter": 0.0,
	}
	for key: String in over:
		p[key] = over[key]
	return p


func _posture() -> Dictionary:
	var t := _king.state_time
	var dark := _king.phase == Eclipse.Phase.ECLIPSE
	match _king.state:
		Eclipse.State.AWAIT:
			return _await_pose()
		Eclipse.State.RISE:
			return _rise_pose(t)
		Eclipse.State.WALK:
			return _walk_pose(t)
		Eclipse.State.PAUSE:
			return _pause_pose(t)
		Eclipse.State.DRAW:
			return _draw_pose(t)
		Eclipse.State.SHOVE:
			return _shove_pose(t)
		Eclipse.State.RECOVER:
			return _recover_pose(t)
		Eclipse.State.STAGGER:
			return _stagger_pose(t, dark)
		Eclipse.State.REST:
			return _burn_pose(0.0, 0.0)
		Eclipse.State.CHARGE:
			var p := clampf(t / _king.charge_time(), 0.0, 1.0)
			return _burn_pose(p, p)
		Eclipse.State.STALK:
			return _stalk_pose(t)
		Eclipse.State.CROUCH:
			return _crouch_pose(t)
		Eclipse.State.LEAP:
			return _leap_pose(t)
		Eclipse.State.LAND:
			return _land_pose(t)
		Eclipse.State.SKID:
			return _skid_pose(t)
		Eclipse.State.GATHER:
			return _gather_pose(clampf(t / _king.gather_time(), 0.0, 1.0))
		Eclipse.State.POUR:
			return _pour_pose()
		Eclipse.State.SPENT:
			return _spent_pose(t)
		Eclipse.State.WON:
			return _won_pose(t, dark)
		_:
			return _fall_pose(t)


## Under the kept sun, the polished face up to it, drinking: the first thing
## the prince sees, from the antechamber.
func _await_pose() -> Dictionary:
	var breath := sin(_time * 1.6)
	return _pose({
		"bob": breath * 0.3, "lean": -0.6, "disc": "polished", "tip": 0.0,
		"disc_at": Vector2(1.0, -12.0), "arm_back": -0.3, "burn": 0.2,
	})


## Turned on the prince, the disc brought down to the front: the crown flares.
## In the third phase the disc goes up before the light instead.
func _rise_pose(t: float) -> Dictionary:
	var e := smoothstep(0.0, Eclipse.RISE_TIME, t)
	var flare := 1.0 - absf(e * 2.0 - 1.0)
	match _king.phase:
		Eclipse.Phase.BURNING:
			return _pose({"disc": "polished", "disc_at": Vector2(2.0, -12.0), "flare": flare,
				"burn": 0.2})
		Eclipse.Phase.ECLIPSE:
			return _pose({"disc": "eclipse", "disc_at": Vector2(lerpf(5.0, 11.0, e),
				lerpf(8.0, -9.0, e)), "corona": e, "eyes": e, "flare": flare, "sink": 2.0 * e})
		Eclipse.Phase.FINALE:
			return _pose({"disc": "eclipse", "disc_at": Vector2(6.0, 9.0), "flare": flare,
				"corona": 1.0 - e * 0.5})
	return _pose({"disc_at": Vector2(lerpf(1.0, 9.0, e), lerpf(-12.0, 8.0, e)),
		"flare": flare, "lean": lerpf(-0.6, 0.0, e)})


## A stately walk: the hem swings, the mantle trails, the disc rides at the
## chest. After two plunges in a pass the disc goes over his crown instead.
func _walk_pose(t: float) -> Dictionary:
	var c := sin(t * 5.2)
	var over := {
		"bob": -absf(c) * 0.6 + 0.2, "stride": c * 2.6, "lean": 0.5,
		"mantle": 0.3 + absf(c) * 0.3, "arm_back": 0.2 + c * 0.25,
		"disc_at": Vector2(9.0, 8.0 + c * 0.4),
	}
	if _king.crown_guard:
		over["disc_at"] = Vector2(1.0, -14.0)
		over["disc_scale"] = 0.9
	return _pose(over)


## Stopped under the gallery: for the first half he looks on, then back over
## his shoulder, the way he is about to turn.
func _pause_pose(t: float) -> Dictionary:
	var turning := t > _king.pause_time() * 0.55
	return _pose({
		"bob": sin(_time * 2.0) * 0.25, "lean": -0.4 if turning else 0.2,
		"disc_at": Vector2(8.5, 8.0),
	})


## The shove's tell: the disc drawn in to the body, the knees going, and a
## star running round the rim. Drawn across the whole draw, however long.
func _draw_pose(t: float) -> Dictionary:
	var p := clampf(t / _king.draw_time(), 0.0, 1.0)
	var e := smoothstep(0.0, 0.5, p)
	var tremble := sin(_time * 55.0) * 0.3 * smoothstep(0.6, 1.0, p)
	return _pose({
		"sink": 2.4 * e, "lean": lerpf(0.0, -2.2, e) + tremble, "stride": 1.6 * e,
		"mantle": 0.6 * e, "disc_at": Vector2(lerpf(9.0, 4.0, e), lerpf(8.0, 9.5, e)),
		"glint": p if p < 0.97 else 0.0, "eyes": 0.4 * e,
	})


func _shove_pose(t: float) -> Dictionary:
	var e := 1.0 - pow(1.0 - clampf(t / Patrol.STRIKE_TIME, 0.0, 1.0), 3.0)
	return _pose({
		"sink": lerpf(2.4, 1.6, e), "lean": lerpf(-2.2, 3.6, e), "stride": lerpf(1.6, 3.4, e),
		"mantle": lerpf(0.6, 1.6, e), "disc_at": Vector2(lerpf(4.0, 14.0, e), 7.0),
		"eyes": 0.6,
	})


func _recover_pose(t: float) -> Dictionary:
	var rise := smoothstep(0.6, 1.0, t / Patrol.RECOVER_TIME)
	return _pose({
		"sink": lerpf(1.8, 0.2, rise) + sin(t * 8.0) * 0.3, "lean": lerpf(2.2, 0.4, rise),
		"stride": lerpf(2.4, 0.6, rise), "disc_at": Vector2(lerpf(12.0, 9.0, rise),
		lerpf(11.0, 8.0, rise)),
	})


func _stagger_pose(t: float, dark: bool) -> Dictionary:
	var back := smoothstep(0.0, Patrol.STAGGER_TIME, t)
	var disc := "black"
	var at := Vector2(lerpf(4.0, 9.0, back), lerpf(10.0, 8.0, back))
	if _king.phase == Eclipse.Phase.BURNING:
		disc = "polished"
		at = Vector2(3.0, -10.0)
	elif dark:
		disc = "eclipse"
		at = Vector2(11.0, -7.0)
	return _pose({
		"tilt": lerpf(-0.22, -0.05, back), "lean": -2.0, "stride": -1.2, "mantle": 1.6,
		"disc": disc, "disc_at": at, "corona": 0.4 if dark else 0.0, "eyes": 0.3,
	})


## Phase 2: the polished face up to the kept sun, tipping toward the prince as
## the charge burns its rim brighter. `burn` and `tip` run from 0 to 1.
func _burn_pose(burn: float, tip: float) -> Dictionary:
	return _pose({
		"bob": sin(_time * 1.8) * 0.3, "lean": lerpf(-0.8, 0.6, tip),
		"disc": "polished", "tip": tip, "burn": burn,
		"disc_at": Vector2(lerpf(2.0, 8.0, tip), lerpf(-12.0, -4.0, tip)),
		"arm_back": -0.2, "eyes": 0.3 * burn, "flare": 0.4 * burn,
	})


## Phase 3: low, coming on, the disc raised before him; the corona burns.
func _stalk_pose(t: float) -> Dictionary:
	var c := sin(t * 6.0)
	return _pose({
		"sink": 2.0, "lean": 1.2, "stride": c * 2.0, "bob": -absf(c) * 0.5,
		"mantle": 0.6, "disc": "eclipse", "disc_at": Vector2(11.0, -9.0),
		"corona": 0.5 + 0.1 * float(int(_time * FPS) % 2), "eyes": 0.5,
	})


## The pounce's tell: sunk under the disc, the corona flaring and the eyes
## igniting, across the whole crouch.
func _crouch_pose(t: float) -> Dictionary:
	var p := clampf(t / _king.crouch_time(), 0.0, 1.0)
	var e := smoothstep(0.0, 0.6, p)
	return _pose({
		"sink": lerpf(2.0, 5.0, e), "lean": lerpf(1.2, -1.4, e) + sin(_time * 50.0) * 0.25 * p,
		"stride": 2.2, "mantle": 0.8 + e, "disc": "eclipse",
		"disc_at": Vector2(lerpf(11.0, 12.0, e), lerpf(-9.0, -5.0, e)),
		"corona": 0.6 + 1.4 * e, "eyes": smoothstep(0.1, 0.5, p), "flare": e,
	})


func _leap_pose(t: float) -> Dictionary:
	var p := clampf(t / Eclipse.LEAP_TIME, 0.0, 1.0)
	return _pose({
		"tilt": lerpf(-0.15, 0.25, p), "lean": 2.0, "stride": lerpf(3.0, 1.0, p),
		"mantle": 2.4, "disc": "eclipse", "disc_at": Vector2(13.0, lerpf(-6.0, 6.0, p)),
		"corona": 1.6, "eyes": 1.0,
	})


func _land_pose(t: float) -> Dictionary:
	var rise := smoothstep(0.3, 1.0, t / Patrol.RECOVER_TIME)
	return _pose({
		"sink": lerpf(5.0, 2.0, rise), "lean": lerpf(3.0, 1.0, rise), "stride": 2.4,
		"mantle": lerpf(1.6, 0.6, rise), "disc": "eclipse",
		"disc_at": Vector2(lerpf(13.0, 11.0, rise), lerpf(10.0, -9.0, rise)),
		"corona": 1.0, "eyes": 0.8,
	})


## The opening: landed short, skidding, the disc dragged on the stone in
## front and his chest open. It has to look like a man who missed.
func _skid_pose(t: float) -> Dictionary:
	var p := clampf(t / Eclipse.SKID_TIME, 0.0, 1.0)
	var shake := sin(_time * 9.0) * 0.6 * (1.0 - p)
	return _pose({
		"sink": lerpf(5.0, 3.0, p), "tilt": lerpf(0.3, 0.12, p) + shake * 0.04,
		"lean": 3.2, "stride": 3.0, "mantle": lerpf(2.0, 0.8, p),
		"disc": "eclipse", "disc_at": Vector2(11.0, lerpf(13.0, 12.0, p)),
		"corona": 0.25, "eyes": 0.15,
	})


## The finale's tell: feet planted wide, the disc at the chest, and the corona
## closing to a point for twice the length of any other warning.
func _gather_pose(p: float) -> Dictionary:
	return _pose({
		"sink": 1.6 * smoothstep(0.0, 0.3, p), "lean": lerpf(0.0, -1.2, p), "stride": 2.6,
		"mantle": 0.5 + p, "disc": "eclipse", "disc_at": Vector2(7.0, 9.0),
		"corona": 1.0 + p, "contract": p, "eyes": p, "flare": p,
	})


func _pour_pose() -> Dictionary:
	return _pose({
		"sink": 2.2, "lean": -2.0, "stride": 3.0, "mantle": 2.0, "disc": "eclipse",
		"disc_at": Vector2(7.0, 9.0), "corona": 0.4, "contract": 1.0, "eyes": 1.0,
		"flare": 1.0,
	})


func _spent_pose(t: float) -> Dictionary:
	var rise := smoothstep(0.5, Eclipse.SPENT_TIME, t)
	return _pose({
		"sink": lerpf(3.0, 0.8, rise) + sin(t * 4.0) * 0.3, "lean": lerpf(2.2, 0.2, rise),
		"stride": 1.8, "disc": "eclipse", "disc_at": Vector2(6.0, lerpf(12.0, 9.0, rise)),
		"corona": lerpf(0.1, 0.8, rise), "eyes": 0.3,
	})


## A phase lost: thrown back, and the disc cracks a beat after the blow.
func _won_pose(t: float, dark: bool) -> Dictionary:
	var e := smoothstep(0.0, Eclipse.WON_TIME, t)
	return _pose({
		"tilt": lerpf(-0.3, -0.05, e), "sink": lerpf(1.0, 3.0, e), "lean": -2.4,
		"stride": -1.4, "mantle": 2.0 - e,
		"disc": "eclipse" if dark else "black", "disc_at": Vector2(8.0, 8.0),
		"corona": 0.2 if dark else 0.0, "eyes": 0.2,
	})


## The last blow: the light goes back into the disc, it breaks, and he goes
## down to his knees and over, while the kept sun rises out of the Well.
func _fall_pose(t: float) -> Dictionary:
	var crack := smoothstep(0.0, Eclipse.CRACK_AT, t)
	var kneel := smoothstep(Eclipse.CRACK_AT, 1.4, t)
	var topple := smoothstep(1.6, 2.6, t)
	var shatter := clampf((t - Eclipse.CRACK_AT) / 0.9, 0.0, 1.0)
	return _pose({
		"tilt": lerpf(lerpf(-0.25, -0.05, kneel), -1.35, topple),
		"sink": lerpf(0.0, 9.0, kneel) * (1.0 - topple * 0.5), "lean": lerpf(-2.0, 1.0, kneel),
		"stride": lerpf(-1.0, 2.0, kneel), "mantle": lerpf(2.0, -0.5, kneel),
		"disc": "eclipse" if t < Eclipse.CRACK_AT else "shattered",
		"disc_at": Vector2(7.0, 9.0), "contract": 1.0 - crack, "corona": 1.0 - crack,
		"shatter": shatter, "eyes": 1.0 - kneel,
	})
