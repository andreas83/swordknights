class_name BastionArt
extends Node2D
## Draws the Bastion, posed from its state machine (scripts/entities/bastion.gd).
##
## ## Not the sentinel, not the prince
##
## At 22 px a figure is its outline before it is anything else, so the
## Bastion is built to differ from both at every point the eye uses:
##
## | | Prince | Sentinel | Bastion |
## | --- | --- | --- | --- |
## | mass | a tall narrow column | broad shoulders, a coat | squat: a board before a short body |
## | top | a pointed cowl | a dome and a spike | a broad flat brim: one horizontal line |
## | front | a sword low | a sabre on the shoulder | a pavise from shin to above the head |
## | feet | under a robe | boots under a coat | heavy boots, wide apart |
##
## The brim is the whole read -- nothing else in the game has a flat top
## wider than its body -- and the shield is the second: a tall plank taller
## than the man, its face the lit plane when he faces the sun and in shade
## when he turns his back to it, with one gold rivet line across it.
##
## Dark, like the sentinel, because a threat is a hole in the light; and lit
## on the world-left edge of every plane that makes the outline, because the
## sun is fixed in the world, not on the figure.
##
## ## What each state reads as
##
## | State | The read |
## | --- | --- |
## | STAND | shield planted, upright, still: a wall |
## | BRACE | shield set lower, weight forward: the wall leans in |
## | WINDUP | the telegraph: shield drawn back, knees bent, a star runs up the rim |
## | SHOVE | the board thrown forward, the body behind it |
## | RECOVER | the shield still up; only the breathing says it is spent |
## | TURN | the board swings round edge-on, and for a moment his back is bare |
## | STAGGER | driven down from above, the hat knocked askew, burned white |
## | DYING | the board falls flat; he kneels, topples and flickers out |

const ARMOUR := Palette.SHADOW_DEEP
const ARMOUR_SHADE := Palette.INK
const RIM := Palette.SHADOW_WARM
## The board's two planes are the dark figure's, not the wall's: a crimson
## face vanished into every crimson wall it stood against.
const BOARD_LIT := Palette.SHADOW_DEEP
const BOARD_SHADE := Palette.INK
const BOARD_EDGE := Palette.LIGHT_WARM
const RIVET := Palette.LIGHT
const HAT := Palette.INK
const BRIM_LIT := Palette.LIGHT_WARM

const FLASH_TIME := 0.14
const KNEEL_AT := 0.18
const TOPPLE_AT := 0.5
const FLOOR_AT := 0.72
const FLICKER_AT := 0.86

var _guard: Bastion
var _time := 0.0
var _flash := 0.0
var _f := 1.0
var _split := 0.0


func _ready() -> void:
	_guard = get_parent() as Bastion
	if _guard == null:
		return
	_guard.staggered.connect(_on_hit)
	_guard.defeated.connect(_on_hit)


func _on_hit() -> void:
	_flash = 1.0


func _process(delta: float) -> void:
	_time += delta
	_flash = maxf(0.0, _flash - delta / FLASH_TIME)
	queue_redraw()


func _c(base: Color) -> Color:
	return base if _flash <= 0.0 else base.lerp(Palette.PAPER, _flash * 0.85)


## --- the pose -----------------------------------------------------------------

## Everything a frame needs: where the board is relative to the body, how
## far the body has sunk and leans, how wide the board looks, and the glint.
func pose() -> Dictionary:
	var t := _guard.state_time
	var p := {
		"sink": 0.0, "lean": 0.0, "board": 5.0, "board_y": 0.0, "board_w": 7.0,
		"stance": 2.6, "glint": -1.0, "tilt": 0.0, "back": false, "breath": 0.0,
	}
	match _guard.state:
		Bastion.State.BRACE:
			p["sink"] = 1.0
			p["lean"] = 1.0
			p["board_y"] = 1.0
			p["stance"] = 3.2
		Bastion.State.WINDUP:
			var k := clampf(t / _guard.windup_time(), 0.0, 1.0)
			var e := smoothstep(0.0, 0.5, k)
			p["sink"] = 3.0 * e
			p["lean"] = -2.0 * e
			p["board"] = 5.0 - 3.5 * e
			p["stance"] = 3.2 + 0.8 * e
			p["glint"] = smoothstep(0.25, 0.95, k) if k < 0.97 else -1.0
		Bastion.State.SHOVE:
			var e := 1.0 - pow(1.0 - clampf(t / Bastion.SHOVE_TIME, 0.0, 1.0), 3.0)
			p["sink"] = lerpf(3.0, 0.6, e)
			p["lean"] = lerpf(-2.0, 3.0, e)
			p["board"] = lerpf(1.5, 10.0, e)
			p["stance"] = 4.2
		Bastion.State.RECOVER:
			var rise := smoothstep(0.6, 1.0, t / Bastion.RECOVER_TIME)
			p["board"] = lerpf(8.0, 5.0, rise)
			p["lean"] = lerpf(1.6, 0.0, rise)
			p["sink"] = 1.0 - rise * 0.6
			p["breath"] = sin(t * 10.0) * 0.5
			p["stance"] = 3.6
		Bastion.State.TURN:
			# The board swings round in front of him to his other side, edge-on
			# half-way: his back is bare to whoever made him turn.
			var k := clampf(t / Bastion.TURN_TIME, 0.0, 1.0)
			var swing := cos(PI * k)
			p["board"] = 5.0 * swing
			p["board_w"] = maxf(1.5, 7.0 * absf(swing))
			p["back"] = k < 0.5
			p["lean"] = -0.6
		Bastion.State.STAGGER:
			var k := clampf(t / Bastion.STAGGER_TIME, 0.0, 1.0)
			p["sink"] = lerpf(3.5, 0.0, smoothstep(0.2, 1.0, k))
			p["tilt"] = lerpf(0.35, 0.0, k)
			p["board_y"] = lerpf(2.0, 0.0, k)
		Bastion.State.DYING:
			var d := t / Bastion.DEATH_TIME
			p["sink"] = lerpf(0.0, 7.0, smoothstep(KNEEL_AT, TOPPLE_AT, d))
			p["tilt"] = lerpf(0.0, -1.3, smoothstep(TOPPLE_AT, FLOOR_AT, d))
			p["board"] = 6.0
		_:
			p["breath"] = sin(_time * 2.0) * 0.3
	return p


## --- drawing ---------------------------------------------------------------------

func _draw() -> void:
	if _guard == null:
		return
	_f = float(_guard.facing)
	var dying := _guard.state == Bastion.State.DYING
	var death := _guard.state_time / Bastion.DEATH_TIME if dying else 0.0
	if dying and death >= FLICKER_AT and int(_time * 24.0) % 2 == 0:
		return
	if dying and death >= 0.99:
		return
	var p := pose()
	var sink: float = float(p["sink"]) + float(p["breath"])
	_split = 0.0
	if not dying:
		draw_colored_polygon(PackedVector2Array([
			Vector2(-7.0, -0.4), Vector2(7.0, -0.4), Vector2(5.6, 1.2), Vector2(-5.6, 1.2),
		]), Palette.with_alpha(Palette.INK, 0.3))
	var behind := bool(p["back"])
	if dying:
		_draw_fallen_board(death)
	elif behind:
		_draw_board(p, sink)
	_draw_boots(float(p["stance"]))
	_draw_body(p, sink)
	_draw_hat(p, sink)
	if not dying and not behind:
		_draw_board(p, sink)


func _draw_boots(stance: float) -> void:
	for side: float in [-1.0, 1.0]:
		var x := side * stance * 0.5 + (0.6 * _f if side * _f > 0.0 else 0.0)
		_plane(PackedVector2Array([
			Vector2(x - 2.2, -3.0), Vector2(x + 2.2, -3.0), Vector2(x + 2.6, 0.0),
			Vector2(x - 2.4, 0.0),
		]), ARMOUR_SHADE, ARMOUR_SHADE)


## Short, broad and armoured: a coat of plates from the knees to the
## shoulders, the shoulders hardly wider than the hips.
func _draw_body(p: Dictionary, sink: float) -> void:
	var lean: float = float(p["lean"]) * _f
	var tilt: float = float(p["tilt"]) * _f
	var points := PackedVector2Array()
	for q: Vector2 in [
		Vector2(-4.4, -3.0), Vector2(4.4, -3.0), Vector2(4.8, -10.0),
		Vector2(4.4 + lean * 0.6, -15.5), Vector2(-4.0 + lean * 0.6, -15.5), Vector2(-4.8, -10.0),
	]:
		points.append(_tilt(q + Vector2(0.0, sink * (1.0 if q.y < -4.0 else 0.4)), tilt))
	_plane(points, ARMOUR, ARMOUR_SHADE, true)
	# A belt of plate across the middle: the one warm band, where the eye
	# finds the waist.
	var belt := _tilt(Vector2(0.0, -9.0 + sink), tilt)
	draw_rect(Rect2(belt.x - 4.6, belt.y - 0.5, 9.2, 1.0), _c(RIM))
	# The veiled face under the brim.
	var face := _tilt(Vector2(lean * 0.8 + 0.6 * _f, -17.0 + sink), tilt)
	draw_rect(Rect2(face.x - 2.4, face.y - 1.5, 4.8, 3.0), _c(ARMOUR_SHADE))
	if not bool(p["back"]):
		draw_rect(Rect2(face.x + 0.4 * _f - 0.6, face.y - 0.6, 1.4, 1.0), Palette.LIGHT_SOFT)


## The broad flat brim -- the read -- and a low crown on it. The brim's top
## catches the sun along its whole length.
func _draw_hat(p: Dictionary, sink: float) -> void:
	var lean: float = float(p["lean"]) * _f * 0.8
	var tilt: float = float(p["tilt"]) * _f
	var y := -18.6 + sink
	var brim := PackedVector2Array()
	for q: Vector2 in [Vector2(-6.8, y), Vector2(6.8, y), Vector2(6.8, y + 1.4),
			Vector2(-6.8, y + 1.4)]:
		brim.append(_tilt(q + Vector2(lean, 0.0), tilt))
	draw_colored_polygon(brim, _c(HAT))
	draw_line(brim[0], brim[1], _c(BRIM_LIT), 1.0)
	var crown := PackedVector2Array()
	for q: Vector2 in [Vector2(-3.4, y), Vector2(3.4, y), Vector2(2.8, y - 2.8),
			Vector2(-2.8, y - 2.8)]:
		crown.append(_tilt(q + Vector2(lean, 0.0), tilt))
	_plane(crown, ARMOUR, HAT, true)


## The pavise: from the shin to above the head, set `board` px in front of
## him. Its face is the lit plane when he faces the sun (world-left), in shade
## when he faces away; its sun-facing edge is rimmed; one gold rivet line
## across it. In the windup a star runs up its forward rim.
func _draw_board(p: Dictionary, sink: float) -> void:
	var x: float = float(p["board"]) * _f
	var width: float = float(p["board_w"])
	var y0: float = -2.0 + float(p["board_y"]) + sink * 0.5
	var y1: float = -24.0 + float(p["board_y"]) + sink * 0.5
	var near := x - width * 0.5
	var far := x + width * 0.5
	var face := BOARD_LIT if _guard.facing < 0 else BOARD_SHADE
	var outline := PackedVector2Array([
		Vector2(near, y0), Vector2(far, y0), Vector2(far, y1 + 1.2),
		Vector2(x, y1), Vector2(near, y1 + 1.2),
	])
	draw_colored_polygon(outline, _c(face))
	draw_line(Vector2(near, y1 + 1.2), Vector2(x, y1), _c(BOARD_EDGE), 1.0)
	draw_line(Vector2(x, y1), Vector2(far, y1 + 1.2), _c(BOARD_EDGE), 1.0)
	# The sun-facing edge, whichever side that is in the world.
	var lit_x := near
	draw_rect(Rect2(lit_x, y1 + 1.0, 1.0, y0 - y1 - 1.0), _c(BOARD_EDGE))
	draw_rect(Rect2(far - 1.0, y1 + 1.0, 1.0, y0 - y1 - 1.0), _c(ARMOUR_SHADE))
	# The rivet line, and a ridge down the middle.
	if width >= 3.0:
		var ridge := floorf(x)
		draw_rect(Rect2(ridge, y1 + 2.0, 1.0, y0 - y1 - 3.0), _c(Palette.with_alpha(
			ARMOUR_SHADE, 0.6)))
		var ry := floorf((y0 + y1) * 0.5) - 1.0
		var at := near + 1.0
		while at < far - 1.0:
			draw_rect(Rect2(at, ry, 1.0, 1.0), _c(RIVET))
			at += 2.0
	var glint: float = float(p["glint"])
	if glint >= 0.0:
		var rim_x := far if _f > 0.0 else near
		var at := Vector2(rim_x, lerpf(y0, y1, glint))
		var arm := 1.0 + 1.6 * sin(glint * PI)
		draw_rect(Rect2(at.x - arm, at.y - 0.5, arm * 2.0, 1.0), Palette.PAPER)
		draw_rect(Rect2(at.x - 0.5, at.y - arm, 1.0, arm * 2.0), Palette.PAPER)


## After the killing blow the board tips forward and lies flat on the stone.
func _draw_fallen_board(death: float) -> void:
	var fall := smoothstep(0.0, 0.35, death)
	var angle := lerpf(0.0, PI * 0.5, fall) * _f
	var hinge := Vector2(6.0 * _f, 0.0)
	var corners: Array[Vector2] = [Vector2(-2.5, 0.0), Vector2(2.5, 0.0), Vector2(2.5, -22.0),
		Vector2(-2.5, -22.0)]
	var points := PackedVector2Array()
	for q: Vector2 in corners:
		points.append(hinge + q.rotated(angle))
	draw_colored_polygon(points, BOARD_SHADE)
	draw_polyline(PackedVector2Array([points[0], points[3]]), BOARD_EDGE, 1.0)


func _tilt(point: Vector2, tilt: float) -> Vector2:
	if is_zero_approx(tilt):
		return point
	return point.rotated(tilt)


## A plane lit on its world-left half and in shade on the rest, as PatrolArt
## draws them, so the light cannot disagree between figures.
func _plane(points: PackedVector2Array, lit: Color, shade: Color, rim := false) -> void:
	if points.size() < 3 or Geometry2D.triangulate_polygon(points).is_empty():
		return
	draw_colored_polygon(points, _c(shade))
	var left := PackedVector2Array([
		Vector2(-64.0, -64.0), Vector2(_split, -64.0), Vector2(_split, 64.0),
		Vector2(-64.0, 64.0),
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
