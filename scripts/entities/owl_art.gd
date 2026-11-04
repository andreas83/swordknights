class_name OwlArt
extends Node2D
## Draws the owl, posed from the Owl's state machine (scripts/entities/owl.gd).
##
## ## A silhouette nothing else has
##
## | | Perched | In the air |
## | --- | --- | --- |
## | shape | an upright oval, two ear-tufts, 10 x 12 | a flat bar of wing, 24 x 6 |
## | reads as | something on the cornice, watching | the only bar in the air in the game |
## | eyes | two round LIGHT_SOFT eyes, on the prince | the same two, on the front of the bar |
##
## In two tones: the body is INK, outlined all round in SHADOW_DEEP with the
## wing edges and the crown in SHADOW. Ink alone was tried first and drawn on
## the pose sheet's night sky it was a pair of eyes and nothing else: the
## night's sky IS ink, and the night grade takes the stone down to a wine
## barely lighter. The outline is what holds the shape against both, and
## crimson is the only light a night frame has besides fire -- so the owl
## reads as the dark shape with a red edge that everything else in the Well
## is. The eyes are the brightest thing in a night
## frame, which is the bible's point: an owl is found by its eyes, then its
## shape. The spread is the tell, and everything in it says the same thing at
## once: the wings open in three steps to their full span, the tufts go up,
## and the eyes get a PAPER pupil -- the one glint -- on the last step.
##
## ## The rest of the motion
##
## The pose is a pure function of (state, state_time, facing, look, velocity),
## as the sentinel's is. The pull-up flaps at a stepped 10 fps; the dive is a
## bar tilted along its own line, wings swept, talons out; a kill flickers out
## in whole frames, the hard-edged way to go.

const BODY := Palette.INK
const EDGE := Palette.SHADOW_DEEP
const RIM := Palette.SHADOW
const EYE := Palette.LIGHT_SOFT
const BEAK := Palette.SHADOW_WARM
const FLAP_FPS := 10.0
const FLASH_TIME := 0.14

var _owl: Owl
var _time := 0.0
var _flash := 0.0


func _ready() -> void:
	_owl = get_parent() as Owl
	if _owl != null:
		_owl.defeated.connect(func() -> void: _flash = 1.0)


func _process(delta: float) -> void:
	_time += delta
	_flash = maxf(0.0, _flash - delta / FLASH_TIME)
	queue_redraw()


func _c(base: Color) -> Color:
	return base if _flash <= 0.0 else base.lerp(Palette.PAPER, _flash * 0.85)


func _draw() -> void:
	if _owl == null:
		return
	match _owl.state:
		Owl.State.PERCH:
			_perched(0.0)
		Owl.State.FOLD:
			_perched(1.0 - clampf(_owl.state_time / Owl.FOLD_TIME, 0.0, 1.0))
		Owl.State.SPREAD:
			var step := mini(2, int(_owl.state_time / maxf(_owl.spread_time(), 0.001) * 3.0))
			_perched(float(step + 1) / 3.0, step == 2)
		Owl.State.STOOP:
			_flying(_owl.velocity, 0.0, true)
		Owl.State.PULL_UP:
			var beat := int(_time * FLAP_FPS) % 2
			_flying(_owl.velocity, -2.0 if beat == 0 else 2.0, false)
		Owl.State.DYING:
			if _owl.state_time / Owl.DEATH_TIME > 0.7 and int(_time * 24.0) % 2 == 0:
				return
			_fallen()


## Upright, wings folded -- or opened by `open`, 0 to 1, in the spread.
func _perched(open: float, glint: bool = false) -> void:
	var f := float(_owl.facing)
	# Wings first, behind the body: a bar out to each side, tips raised.
	if open > 0.0:
		var span := 4.0 + 8.0 * open
		for side: float in [-1.0, 1.0]:
			var root := Vector2(side * 3.0, -1.0)
			var tip := Vector2(side * span, -2.0 - 4.0 * open)
			_quad(root + Vector2(0.0, -2.0), tip, tip + Vector2(-side * 2.0, 3.0),
				root + Vector2(0.0, 3.0), EDGE)
			draw_line(root + Vector2(0.0, -2.0), tip, _c(RIM), 1.0)
	# The oval, outlined.
	_outlined(_oval(5.0, 6.0, Vector2.ZERO))
	draw_line(Vector2(-3.0, -5.4), Vector2(3.0, -5.4), _c(RIM), 1.0)
	# Folded wings along the flanks: shade down each side, the rim on the
	# leading one.
	draw_line(Vector2(-4.6, -2.0), Vector2(-3.4, 4.6), _c(EDGE), 1.6)
	draw_line(Vector2(4.6, -2.0), Vector2(3.4, 4.6), _c(EDGE), 1.6)
	draw_line(Vector2(-5.0 * f, -1.0), Vector2(-4.2 * f, 3.0), _c(RIM), 1.0)
	# The tufts: up higher when it is about to go.
	var lift := 1.5 * open
	for side: float in [-1.0, 1.0]:
		var tip := Vector2(side * (3.4 + lift * 0.4), -8.6 - lift)
		_tri(Vector2(side * 1.0, -5.6), tip + Vector2(0.0, -1.0), Vector2(side * 5.0, -4.0), EDGE)
		_tri(Vector2(side * 1.6, -5.4), tip, Vector2(side * 4.2, -4.4), BODY)
	# The eyes, turned toward him; a beak between.
	var turn := roundf(_owl.look * 1.4)
	for side: float in [-1.0, 1.0]:
		var at := Vector2(side * 2.0 + turn, -2.4)
		draw_circle(at, 1.25 + 0.25 * open, _c(EYE))
		if glint:
			draw_rect(Rect2(at - Vector2(0.5, 0.5), Vector2.ONE), Palette.PAPER)
	draw_rect(Rect2(turn - 0.5, -1.4, 1.0, 1.6), _c(BEAK))
	# Talons on the stone.
	draw_rect(Rect2(-2.5, 5.2, 1.5, 1.0), _c(EDGE))
	draw_rect(Rect2(1.0, 5.2, 1.5, 1.0), _c(EDGE))


## The bar of wing, tilted along `heading`: `flap` lifts the tips.
func _flying(heading: Vector2, flap: float, talons: bool) -> void:
	var dir := heading.normalized() if not heading.is_zero_approx() else Vector2.RIGHT
	var along := Vector2(signf(dir.x) if dir.x != 0.0 else 1.0, 0.0)
	# Tilt the bar up to a third of the way toward the line of the dive.
	var tilt := clampf(dir.angle_to(along) * -0.35, -0.5, 0.5) if talons else 0.0
	var xf := Transform2D(tilt, Vector2.ZERO)
	var half := Owl.FLYING.x * 0.5
	var bar := PackedVector2Array([
		Vector2(-half, -1.0 + flap), Vector2(-3.0, -3.0), Vector2(3.0, -3.0),
		Vector2(half, -1.0 + flap), Vector2(half - 2.0, 1.5 + flap * 0.5),
		Vector2(3.0, 3.0), Vector2(-3.0, 3.0), Vector2(-half + 2.0, 1.5 + flap * 0.5),
	])
	_outlined(xf * bar)
	# Shade under each wing, rim along the leading edges.
	draw_line(xf * Vector2(-half + 2.0, 1.5 + flap * 0.5), xf * Vector2(-3.0, 3.0), _c(EDGE), 1.0)
	draw_line(xf * Vector2(half - 2.0, 1.5 + flap * 0.5), xf * Vector2(3.0, 3.0), _c(EDGE), 1.0)
	draw_line(xf * Vector2(-half, -1.0 + flap), xf * Vector2(-3.0, -3.0), _c(RIM), 1.0)
	draw_line(xf * Vector2(half, -1.0 + flap), xf * Vector2(3.0, -3.0), _c(RIM), 1.0)
	# The head bump and the two eyes on the front of the bar.
	draw_circle(xf * Vector2(0.0, -2.5), 3.6, _c(EDGE))
	draw_circle(xf * Vector2(0.0, -2.5), 2.6, _c(BODY))
	for side: float in [-1.0, 1.0]:
		draw_circle(xf * Vector2(side * 1.3 + along.x * 0.6, -2.4), 0.9, _c(EYE))
	if talons:
		for side: float in [-1.0, 1.0]:
			draw_line(xf * Vector2(side * 1.5, 3.0), xf * Vector2(side * 2.2, 5.6), _c(EDGE), 1.0)


## Thrown off the line: the body tumbling, a few feathers.
func _fallen() -> void:
	var spin := _owl.state_time * 9.0
	var xf := Transform2D(spin, Vector2.ZERO)
	_outlined(xf * _oval(5.0, 4.0, Vector2.ZERO))
	for i: int in 4:
		var t := _owl.state_time + float(i) * 0.37
		var at := Vector2(sin(float(i) * 2.1 + t * 3.0) * (4.0 + t * 8.0), -t * 10.0 + float(i))
		draw_rect(Rect2(at.round(), Vector2.ONE), EDGE)


## `points` in INK inside a one-pixel SHADOW_DEEP edge: the shape grown by a
## pixel, under the shape.
func _outlined(points: PackedVector2Array) -> void:
	if Geometry2D.triangulate_polygon(points).is_empty():
		return
	for grown: PackedVector2Array in Geometry2D.offset_polygon(points, 1.0):
		if grown.size() >= 3 and not Geometry2D.triangulate_polygon(grown).is_empty():
			draw_colored_polygon(grown, _c(EDGE))
	draw_colored_polygon(points, _c(BODY))


static func _oval(rx: float, ry: float, at: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i: int in 16:
		var a := TAU * float(i) / 16.0
		out.append(at + Vector2(cos(a) * rx, sin(a) * ry))
	return out


func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, color: Color) -> void:
	var points := PackedVector2Array([a, b, c, d])
	if not Geometry2D.triangulate_polygon(points).is_empty():
		draw_colored_polygon(points, _c(color))


func _tri(a: Vector2, b: Vector2, c: Vector2, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([a, b, c]), _c(color))
