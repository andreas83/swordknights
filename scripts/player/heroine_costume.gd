class_name HeroineCostume
extends Costume
## The heroine: bare-headed, a long braid, a belted knee-length tunic over
## dark legs, and two sash ribbons where the prince has a cloak.
##
## She stands on the prince's skeleton -- same rig, same height, same hands on
## the same sword -- so every pose PlayerArt and FighterArt know is hers too,
## and her hitbox is his. What has to differ is the read at 22 px, where a
## figure is a silhouette and a value pattern before it is anything else. So
## each of the prince's three strongest cues is answered by its opposite:
##
## - **The head.** His is a pale cowl with a dark hole for a face and a peak
##   leaning forward. Hers is dark hair with a lit face: the value structure of
##   the head inverted, and a round crown where he has a point. A headband in
##   the accent colour is the one horizontal line across it, on the hair above
##   the face rather than at the brow, so a gold band never merges into a
##   gold face.
## - **The hem.** His robe falls to the floor and hides his legs. Her tunic
##   stops at the knee and flares, so her legs and boots show under it: a
##   figure with a waist and a stride, where his is a cone.
## - **What trails.** His cloak is one broad dark plane behind him. Hers is
##   lines: a braid down her back and two narrow ribbons from the belt. At
##   tile scale that is the difference between a sail and a pennant.
##
## ## Secondary motion
##
## The cloak lags the body with an exponential chase: it never overshoots.
## The braid is a pendulum instead -- an under-damped spring on one angle, in
## *world* space -- so it swings past where it is going and back, flicks
## forward when she lands, and when she turns it crosses her back to the new
## side rather than mirroring there. The ribbons flutter at their own rate,
## faster the faster she moves. Both are cosmetic, like the cloth lag, and
## settle within a second.
##
## The light is still the world's: lit on the left, shaded on the right, an
## ink edge down the shadow side, whichever way she faces -- with one
## exception. Her face is always the lit skin tone, with only the jaw in shade.
## Facing away from the sun it should strictly be the shade tone, and the first
## render did that: the shade steps of the skin ramp are the terrain's own
## oranges, and her face vanished into the wall behind her. The face is her
## whole read, the way the glint is his, so it keeps its light.

## The head, smaller than the prince's hood and round: (height above centre,
## forward push, half width) in units of HEAD_HH / HEAD_HW.
const HEAD_HW := 2.2
const HEAD_HH := 2.5
const HEAD_RUNGS: Array[Vector3] = [
	Vector3(-1.0, -0.08, 0.5),
	Vector3(-0.62, -0.04, 0.94),
	Vector3(0.05, 0.02, 1.0),
	Vector3(0.6, 0.06, 0.86),
	Vector3(0.96, 0.12, 0.5),
]
## A head is not a cowl: it sits a little lower on the shoulders than the
## hood's centre, so the neck is not a stalk.
const HEAD_DROP := 0.4

## The tunic, as shares of the prince's robe widths at the same rungs: narrower
## at the shoulder, cinched at the waist, flared at the hip and the hem.
const TUNIC_SHOULDER := 0.84
const TUNIC_CHEST := 0.92
const TUNIC_WAIST := 0.74
const TUNIC_HIP := 1.12
const TUNIC_HEM := 0.84
## The hem's height, as a share of the way from the hip down to the feet.
const TUNIC_KNEE := 0.5

const BRAID_LINKS := 5
const BRAID_LINK := 2.0
## The braid's spring: stiff enough to come back in under a second, damped
## little enough to swing past twice on the way.
const BRAID_STIFF := 55.0
const BRAID_DAMP := 4.0
## How far behind the head the braid hangs at rest, in radians off vertical.
## Less and it hides behind her back; the read is a line down the back.
const BRAID_REST := 0.5
const RIBBON_FLUTTER := 13.0

var hair: Color
var hair_dark: Color
var skin: Color
var skin_dark: Color

## The braid's angle off vertical in world space (+ = the tip toward world +x)
## and its angular velocity.
var _swing := 0.0
var _spin := 0.0
var _seen_kick := INF
## The last pose's cloth quantities, so tick() can lean the braid the way the
## pose wants its cloth to go.
var _sweep_hint := 0.0
var _rise_hint := 0.0


func _init(hair_lit: Color = Palette.SHADOW_PIT, hair_shade: Color = Palette.INK,
		skin_lit: Color = Palette.LIGHT_WARM, skin_shade: Color = Palette.MID) -> void:
	hair = hair_lit
	hair_dark = hair_shade
	skin = skin_lit
	skin_dark = skin_shade


func worn_colours() -> Array[Color]:
	return [hair, hair_dark, skin, skin_dark]


## --- secondary motion -------------------------------------------------------

func tick(art: PlayerArt, delta: float) -> void:
	var dt := minf(delta, 1.0 / 30.0)
	var f := art._f
	var trail := clampf(art._sway.x, -1.5, 1.5)
	var fall := clampf(art._sway.y, -1.2, 1.2)
	var behind := (
		BRAID_REST + trail * 0.55 + maxf(0.0, fall) * 1.1
		+ _sweep_hint * 0.06 + _rise_hint * 0.12
	)
	var target := clampf(-f * behind, -2.4, 2.4)
	# A landing or a jump kicked the body (PlayerArt restarts _impulse_t). The
	# braid takes the same kick as a swing: forward on a landing, back on a jump.
	if art._impulse_t < _seen_kick:
		_spin += -f * art._impulse * 13.0
	_seen_kick = art._impulse_t
	_spin += (BRAID_STIFF * (target - _swing) - BRAID_DAMP * _spin) * dt
	_swing = clampf(_swing + _spin * dt, -2.6, 2.6)


## --- layers -----------------------------------------------------------------

func draw_back(art: PlayerArt, pose: Dictionary) -> bool:
	frames_drawn += 1
	drawn = Rect2(art._hip, Vector2.ZERO)
	_sweep_hint = float(pose["cloak_sweep"])
	_rise_hint = float(pose["cloak_rise"])
	_draw_ribbons(art, pose)
	_draw_braid(art, pose)
	return true


func draw_body(art: PlayerArt, pose: Dictionary) -> bool:
	var f := art._f
	var hw: Dictionary = art._hw
	var hem_fwd: float = float(pose["hem_fwd"]) * 0.7 - art._sway.x * 1.2
	var knee_line := lerpf(art._hip.y, art._foot_y, TUNIC_KNEE)
	var hem_y := maxf(minf(art._hem_y, knee_line), art._hip.y + 1.6)
	var rungs: Array[Vector3] = [
		Vector3(art._shoulder.x, art._shoulder.y, float(hw["shoulder"]) * TUNIC_SHOULDER),
		Vector3(art._chest.x, art._chest.y, float(hw["chest"]) * TUNIC_CHEST),
		Vector3(art._waist.x, art._waist.y, float(hw["waist"]) * TUNIC_WAIST),
		Vector3(art._hip.x, art._hip.y, float(hw["hip"]) * TUNIC_HIP),
		Vector3(art._hip.x * 0.4 + hem_fwd * f, hem_y, float(hw["hem"]) * TUNIC_HEM),
	]
	_poly(art, art._side(rungs, -1.0), art.cloth)
	_poly(art, art._side(rungs, 1.0), art.cloth_dark)
	_poly(art, art._edge(rungs, 1.0, PlayerArt.RIM), art.ink)
	var hem := rungs[rungs.size() - 1]
	_poly(art, PackedVector2Array([
		Vector2(hem.x - hem.z, hem.y - 0.8), Vector2(hem.x + hem.z, hem.y - 0.8),
		Vector2(hem.x + hem.z, hem.y), Vector2(hem.x - hem.z, hem.y),
	]), art.ink)

	# The belt, and its knot at the back where the ribbons come from.
	var waist := art._waist
	var w := float(hw["waist"]) * TUNIC_WAIST + 0.5
	_poly(art, PackedVector2Array([
		Vector2(waist.x - w, waist.y - 0.2), Vector2(waist.x + w, waist.y + 0.2),
		Vector2(waist.x + w, waist.y + 1.1), Vector2(waist.x - w, waist.y + 0.7),
	]), art.accent)
	var knot := waist + Vector2(-w * f, 0.5)
	_poly(art, PackedVector2Array([
		knot + Vector2(-0.9, -0.9), knot + Vector2(0.9, -0.9),
		knot + Vector2(0.9, 0.9), knot + Vector2(-0.9, 0.9),
	]), art.accent)
	return true


## Dark hair, a lit face, one eye, a band across the brow.
func draw_head(art: PlayerArt, pose: Dictionary) -> bool:
	var look: float = float(pose["hood_face"])
	var fdir: float = art._f * signf(look) * maxf(absf(look), 0.3)
	var tilt: float = float(pose["hood_tilt"])
	var c := art._head + Vector2(0.0, HEAD_DROP)

	var rungs: Array[Vector3] = []
	for spec: Vector3 in HEAD_RUNGS:
		rungs.append(Vector3(
			c.x + (spec.y * HEAD_HW - spec.x * tilt * 1.2) * fdir,
			c.y + spec.x * HEAD_HH,
			HEAD_HW * spec.z))
	_poly(art, art._side(rungs, -1.0), hair)
	_poly(art, art._side(rungs, 1.0), hair_dark)
	_poly(art, art._edge(rungs, 1.0, PlayerArt.RIM * 0.8), art.ink)

	# The face, on the forward side under the hairline, lit (see the class
	# comment), with the jaw in shade so it still has a bottom edge.
	_poly(art, _head_points(c, fdir, tilt, [
		Vector2(0.18, -0.16), Vector2(1.0, -0.14), Vector2(1.12, 0.32),
		Vector2(0.88, 0.8), Vector2(0.44, 0.96), Vector2(0.16, 0.66),
	]), skin)
	_poly(art, _head_points(c, fdir, tilt, [
		Vector2(0.96, 0.55), Vector2(0.88, 0.8), Vector2(0.44, 0.96),
		Vector2(0.16, 0.66), Vector2(0.42, 0.72),
	]), skin_dark)

	var eye := _head_points(c, fdir, tilt, [Vector2(0.6, -0.04)])[0]
	if float(pose["glint"]) > 0.0:
		_poly(art, _square(eye, 0.55), art.ink)
	else:
		_poly(art, PackedVector2Array([
			eye + Vector2(-0.7, -0.2), eye + Vector2(0.7, -0.2),
			eye + Vector2(0.7, 0.3), eye + Vector2(-0.7, 0.3),
		]), art.ink)

	# On the hair, a strip of hair clear of the face: a gold band touching a
	# gold face is one shape, not two.
	_poly(art, _head_points(c, fdir, tilt, [
		Vector2(-0.84, -0.74), Vector2(0.84, -0.74), Vector2(0.96, -0.42), Vector2(-0.96, -0.42),
	]), art.accent)
	return true


## --- the pieces -------------------------------------------------------------

## A plait of tapered links from the back of the head, each link leaning a
## little further than the one above it, so the swing reads as a curve rather
## than a stick. The links alternate lit and shade, which is all a plait is at
## two pixels wide.
func _draw_braid(art: PlayerArt, pose: Dictionary) -> void:
	var look: float = float(pose["hood_face"])
	var fdir: float = art._f * signf(look) * maxf(absf(look), 0.3)
	var c := art._head + Vector2(0.0, HEAD_DROP)
	var grounded := art._grounded()
	var points: Array[Vector2] = [c + Vector2(-HEAD_HW * 0.9 * fdir, HEAD_HH * 0.15)]
	for i: int in BRAID_LINKS:
		var bend := lerpf(0.6, 1.0, float(i) / float(BRAID_LINKS - 1))
		var a := _swing * bend
		var next := points[i] + Vector2(sin(a), cos(a)) * BRAID_LINK
		if grounded:
			next.y = minf(next.y, 0.4)
		points.append(next)
	for i: int in BRAID_LINKS:
		var share := float(i) / float(BRAID_LINKS)
		_limb(art, points[i], points[i + 1], lerpf(2.1, 1.3, share),
			lerpf(1.9, 1.1, share), hair if i % 2 == 0 else hair_dark)
	var end := points[BRAID_LINKS]
	var along := (end - points[BRAID_LINKS - 1]).normalized()
	_poly(art, _square(end, 0.75), art.accent)
	_limb(art, end, end + along * 1.8, 1.3, 0.3, hair_dark)


## Two ribbons from the belt's knot. They answer the same pose fields as the
## prince's cloak -- swept back on a run, lifted on a fall -- but they are
## lines, and they flutter. Only the near one is the accent: two bright lines
## crossing on a fall read as an X, louder than the figure.
func _draw_ribbons(art: PlayerArt, pose: Dictionary) -> void:
	var f := art._f
	var root := art._waist + Vector2(-float(art._hw["waist"]) * TUNIC_WAIST * f, 0.9)
	var sweep: float = float(pose["cloak_sweep"]) + art._sway.x * 2.6
	var rise: float = float(pose["cloak_rise"]) + art._sway.y * 3.4
	var speed := clampf(absf(art._sway.x) + absf(art._sway.y), 0.0, 1.5)
	var grounded := art._grounded()
	for i: int in 2:
		var length := 5.6 - i * 1.6
		var flutter := sin(art._time * RIBBON_FLUTTER + i * 2.3) * (0.3 + 0.7 * speed)
		var lean := Vector2(-(0.8 + sweep * 0.9 + i * 0.9), length - rise * 1.1)
		var reach := lean.normalized() * length
		var tip := root + Vector2(reach.x * f, reach.y + flutter)
		if grounded:
			tip.y = minf(tip.y, 0.8)
		var mid := root.lerp(tip, 0.5) + Vector2(0.0, -flutter * 0.5)
		var colour := art.cloth_dark if i == 0 else art.accent
		_limb(art, root, mid, 1.5, 1.2, colour)
		_limb(art, mid, tip, 1.2, 0.5, colour)


## Points given in head space -- x forward in HEAD_HW, y down in HEAD_HH --
## sheared by the head's tilt exactly as its rungs are.
func _head_points(c: Vector2, fdir: float, tilt: float, at: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in at:
		out.append(Vector2(
			c.x + (p.x * HEAD_HW - p.y * tilt * 1.2) * fdir,
			c.y + p.y * HEAD_HH))
	return out


func _square(at: Vector2, half: float) -> PackedVector2Array:
	return PackedVector2Array([
		at + Vector2(-half, -half), at + Vector2(half, -half),
		at + Vector2(half, half), at + Vector2(-half, half),
	])


func _limb(art: PlayerArt, from: Vector2, to: Vector2, w0: float, w1: float,
		colour: Color) -> void:
	var along := (to - from).normalized()
	if along == Vector2.ZERO:
		return
	var side := Vector2(-along.y, along.x)
	_poly(art, PackedVector2Array([
		from + side * w0 * 0.5, to + side * w1 * 0.5,
		to - side * w1 * 0.5, from - side * w0 * 0.5,
	]), colour)


## Every plane goes through here: through the art's hit flash, so a hit burns
## her silhouette exactly as it burns his, and into `drawn`, so a test can see
## what was drawn.
func _poly(art: PlayerArt, points: PackedVector2Array, colour: Color) -> void:
	for p: Vector2 in points:
		drawn = drawn.expand(p)
	art.draw_colored_polygon(points, art._c(colour))
