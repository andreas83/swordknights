class_name StickCostume
extends Costume
## The stick avatar: a round head on a line of a body, the pose and nothing
## else.
##
## It is the figure with the clothes taken off the rig. Every joint it strokes
## is one PlayerArt already placed -- hip, knee, foot, shoulder, elbow, hand --
## so where the robed figures argue a pose through cloth, this one shows the
## argument itself, and a pose that reads badly reads badly here first. That
## makes it as much a tool for the pose lab as a look.
##
## ## What it keeps of the art direction
##
## A line one pixel wide vanishes against terrain that is itself lit gold and
## crimson, so every stroke is a core in the robe colour inside an ink casing,
## the same four-tones-in-a-fixed-relationship rule the robed figures follow:
## the near limbs in the lit cloth, the far limbs in the shade cloth, ink
## around everything. In a duel the cloth is the seat's team colour, so a
## stick avatar is as unmistakably crimson or sea-green as a hooded one.
##
## The head is large on purpose -- a fifth of the height, like the prince's
## hood -- because at 22 px a stick figure is a head and a gesture. One ink eye
## on the facing side tells front from back, the way the glint does under the
## hood.
##
## ## What trails
##
## A stick has nothing to sweep, and a figure with nothing trailing reads as
## stopped even mid-run. So the accent is a short scarf from the neck, on the
## same pose fields and the same cloth lag as the prince's cloak: back on a
## run, up on a fall, a beat behind on a landing.

const CORE := 1.3 ## Width of a stroke's colour.
const CASING := 0.65 ## Ink on each side of it.
const HEAD_R := 2.3
## The head sits on the neck rather than on the shoulder line.
const HEAD_DROP := 0.5
const NECK := 0.6
const SCARF_LEN := 5.0


func draw_back(art: PlayerArt, pose: Dictionary) -> bool:
	frames_drawn += 1
	drawn = Rect2(art._hip, Vector2.ZERO)
	_draw_scarf(art, pose)
	return true


func draw_leg(art: PlayerArt, knee: Vector2, foot: Vector2, back: bool) -> bool:
	var colour := art.cloth_dark if back else art.cloth
	var toe := foot + Vector2(1.4 * art._f, 0.0)
	_stroke(art, [art._hip, knee, foot, toe], colour)
	return true


func draw_arm(art: PlayerArt, hand: Vector2, back: bool) -> bool:
	var colour := art.cloth_dark if back else art.cloth
	_stroke(art, [art._shoulder, art._elbow(hand), hand], colour)
	return true


## The spine through the rig's own torso points, so a lean or a tilt bends it
## where the robe would bend, then the neck.
func draw_body(art: PlayerArt, _pose: Dictionary) -> bool:
	var neck := art._shoulder.lerp(_head_centre(art), NECK)
	_stroke(art, [art._hip, art._waist, art._chest, art._shoulder, neck], art.cloth)
	return true


func draw_head(art: PlayerArt, pose: Dictionary) -> bool:
	var c := _head_centre(art)
	_disc(art, c, HEAD_R + CASING, art.ink)
	_disc(art, c, HEAD_R, art.cloth)
	# The shade half, split down the world's vertical like every other plane:
	# the light is the world's, not the figure's.
	var shade := PackedVector2Array()
	for i: int in 9:
		var a := -PI * 0.5 + PI * float(i) / 8.0
		shade.append(c + Vector2(cos(a), sin(a)) * HEAD_R)
	_poly(art, shade, art.cloth_dark)
	var look: float = float(pose["hood_face"])
	var fdir: float = art._f * signf(look) * maxf(absf(look), 0.3)
	var eye := c + Vector2(HEAD_R * 0.5 * fdir, -HEAD_R * 0.12)
	if float(pose["glint"]) > 0.0:
		_disc(art, eye, 0.6, art.ink)
	else:
		_poly(art, PackedVector2Array([
			eye + Vector2(-0.8, -0.2), eye + Vector2(0.8, -0.2),
			eye + Vector2(0.8, 0.3), eye + Vector2(-0.8, 0.3),
		]), art.ink)
	return true


## --- the pieces -------------------------------------------------------------

func _head_centre(art: PlayerArt) -> Vector2:
	return art._head + Vector2(0.0, HEAD_DROP)


## The scarf answers the cloak's fields with the cloak's lag, at a scarf's
## length: two strokes from the neck, the far end lifting with the fall.
func _draw_scarf(art: PlayerArt, pose: Dictionary) -> void:
	var f := art._f
	var root := art._shoulder.lerp(_head_centre(art), NECK * 0.7)
	var sweep: float = float(pose["cloak_sweep"]) + art._sway.x * 2.6
	var rise: float = float(pose["cloak_rise"]) + art._sway.y * 3.4
	var flutter := sin(art._time * 11.0) * clampf(absf(art._sway.x), 0.0, 1.0) * 0.6
	var lean := Vector2(-(1.2 + sweep * 0.9), 2.4 - rise * 0.9).normalized()
	var tip := root + Vector2(lean.x * f, lean.y) * SCARF_LEN + Vector2(0.0, flutter)
	if art._grounded():
		tip.y = minf(tip.y, 0.6)
	var mid := root.lerp(tip, 0.5) + Vector2(0.0, -flutter * 0.6)
	_stroke(art, [root, mid, tip], art.accent)


## A polyline in ink, then the same polyline in colour over it, with round
## joints, so the casing closes around every bend and the far end.
func _stroke(art: PlayerArt, points: Array, colour: Color) -> void:
	_polyline(art, points, art.ink, CORE + CASING * 2.0)
	_polyline(art, points, colour, CORE)


func _polyline(art: PlayerArt, points: Array, colour: Color, width: float) -> void:
	for i: int in points.size() - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		if a.distance_squared_to(b) > 0.0001:
			art.draw_line(a, b, art._c(colour), width)
	for p: Vector2 in points:
		_disc(art, p, width * 0.5, colour)


func _disc(art: PlayerArt, at: Vector2, radius: float, colour: Color) -> void:
	drawn = drawn.expand(at - Vector2(radius, radius)).expand(at + Vector2(radius, radius))
	art.draw_circle(at, radius, art._c(colour))


func _poly(art: PlayerArt, points: PackedVector2Array, colour: Color) -> void:
	for p: Vector2 in points:
		drawn = drawn.expand(p)
	art.draw_colored_polygon(points, art._c(colour))
