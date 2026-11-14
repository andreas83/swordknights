class_name PrincessCostume
extends ModelCostume
## The warrior princess: the 3D figure. A stylised young swordswoman -- a head
## a little large for her body and big eyes, a braid down her back, a jewelled
## band across her brow -- in a belted tunic with a trim and a crest, a cape,
## steel pauldrons, leather bracers and tall boots.
##
## ## The read at 22 px
##
## Built from ModelCostume's spheres and tapered cylinders on the shared rig,
## so each piece has to earn its place as a shape, not as detail:
##
## - **The pauldrons** are the widest hard edge, steel against cloth, so her
##   shoulders read the way the prince's hood does: one bright plane high up.
## - **The cape** trails on the prince's cloak fields (`cloak_sweep`,
##   `cloak_rise`) and the same cloth lag, so it streams on a run and lifts
##   on a fall exactly where his cloak would.
## - **The braid** is a chain of beads on a pendulum, as the heroine's is: an
##   under-damped spring in world space that swings past and back.
## - **The face** turns toward the viewer, so both eyes show; the eyes are
##   white with a dark iris and an unlit highlight, which at play size is the
##   one bright dot under the brow band.
##
## ## Where the colours come from
##
## The tunic is the look's outfit and the cape its shade step; in the duel both
## are the seat's team colour (FighterArt.dress), and the leggings take the
## seat's darkest step, so a seat's whole silhouette is its team. The trim,
## the crest, the buckle and the brow band are the accent. The hair and the
## skin are the look's. Steel, leather and the eyes are fixed: they belong to
## neither team.
##
## The shield and the glowing blade of the concept art are not here. The sword
## is the shared 2D one (ModelCostume explains why), and there is no shield in
## the game for her to carry.

const HEAD_R := Vector3(2.15, 2.3, 2.1)
## How far her face turns from the run toward the viewer, in radians.
const FACE_TURN := 0.45
## Where the eyes sit round the face from its centre line, in radians.
const EYE_SPREAD := 0.38
const BRAID_BEADS := 5
const BRAID_STEP := 1.0
## The braid's spring, the heroine's numbers: back in under a second, past
## its rest twice on the way.
const BRAID_STIFF := 55.0
const BRAID_DAMP := 4.0
const BRAID_REST := 0.35
## A blink: how often, and how long the eyes stay shut.
const BLINK_EVERY := 3.7
const BLINK_TIME := 0.12

## The braid's angle off hanging straight down, in world space (+ = its tip
## toward world +x), and its angular velocity.
var _swing := 0.0
var _spin := 0.0
var _seen_kick := INF


func tick(art: PlayerArt, delta: float) -> void:
	var dt := minf(delta, 1.0 / 30.0)
	var f := art._f
	var behind := (BRAID_REST + clampf(art._sway.x, -1.5, 1.5) * 0.5
		+ maxf(0.0, clampf(art._sway.y, -1.2, 1.2)) * 1.0)
	var target := clampf(-f * behind, -2.4, 2.4)
	if art._impulse_t < _seen_kick:
		_spin += -f * art._impulse * 13.0
	_seen_kick = art._impulse_t
	_spin += (BRAID_STIFF * (target - _swing) - BRAID_DAMP * _spin) * dt
	_swing = clampf(_swing + _spin * dt, -2.6, 2.6)


func _tones(art: PlayerArt) -> Dictionary:
	var cloth := Palette.CLOTH if art == null else art.cloth
	var cape := Palette.CLOTH_DARK if art == null else art.cloth_dark
	var legs := Palette.SHADOW_DEEP if art == null else art.cloak_shade
	var trim := Palette.LIGHT_WARM if art == null else art.accent
	return {
		"cloth": cloth, "cape": cape, "legs": legs, "trim": trim,
		"leather": Palette.SHADOW_PIT, "steel": Palette.STEEL, "gem": Palette.LIGHT_SOFT,
		"skin": skin, "hair": hair, "hair_dark": hair_dark,
		"white": Palette.PAPER, "iris": Palette.SHADOW_PIT, "shine": Palette.PAPER,
		"lid": Palette.INK, "mouth": Palette.SHADOW,
		# The cheeks are the skin warmed toward the blood ramp's lightest step:
		# a blush lit by the same sun as the face, whatever the skin tone.
		"blush": skin.lerp(Palette.BLOOD_WET, 0.45),
	}


func _make() -> void:
	_add("cape_top", _cylinder(0.55, 0.85), "cape")
	_add("cape_joint", _sphere(0.85), "cape")
	_add("cape_tail", _cylinder(0.85, 1.0), "cape")
	for i: int in BRAID_BEADS:
		_add("braid_%d" % i, _sphere(), "hair" if i % 2 == 0 else "hair_dark")
	_add("braid_tie", _sphere(), "trim")
	_add("chest", _sphere(), "cloth")
	_add("waist", _cylinder(1.0, 1.0), "cloth")
	_add("skirt", _cylinder(1.0, 1.4), "cloth")
	_add("hem_trim", _ring(0.86), "trim")
	_add("collar", _ring(0.7), "trim")
	_add("crest", _sphere(), "trim")
	_add("belt", _cylinder(1.0, 1.0), "leather")
	_add("buckle", _box(), "trim")
	_add("pouch", _box(), "leather")
	_add("neck", _cylinder(0.5, 0.55), "skin")
	_add("head", _sphere(), "skin")
	_add("hair_cap", _sphere(1.0, true), "hair")
	_add("hair_back", _sphere(), "hair_dark")
	for i: int in 3:
		_add("bang_%d" % i, _sphere(), "hair")
	_add("band", _ring(0.86), "trim")
	_add("band_gem", _sphere(), "gem")
	_add("nose", _sphere(), "skin")
	_add("mouth", _sphere(), "mouth")
	for side: String in ["near", "far"]:
		_add("white_" + side, _sphere(), "white")
		_add("iris_" + side, _sphere(), "iris")
		_add("shine_" + side, _sphere(), "shine")
		_add("lid_" + side, _box(), "lid")
		_add("brow_" + side, _box(), "hair_dark")
		_add("cheek_" + side, _sphere(), "blush")
	_make_limbs(Vector2(0.82, 0.62), Vector2(0.66, 0.52), Vector2(0.52, 0.46),
		Vector2(0.5, 0.44), 0.55, {
			"leg": "legs", "shin": "leather", "foot": "leather",
			"arm": "cloth", "fore": "leather", "hand": "leather",
		})
	for side: String in ["front", "back"]:
		_add("pauldron_" + side, _sphere(), "steel")
		_add("cuff_" + side, _ring(0.7), "leather")


func _pose_parts(art: PlayerArt, pose: Dictionary, up: Vector3, forward: Vector3) -> void:
	_pose_body(art, up, forward)
	_pose_cape(art, pose, up, forward)
	_pose_limbs(art, 0.8, 1.85, 0.75, 0.9, Vector3(1.3, 0.62, 0.68))
	# Steel over each shoulder joint, and a leather cuff at the top of each boot.
	for side: String in ["front", "back"]:
		var joint := (_parts["shoulder_" + side] as MeshInstance3D).position
		var out := (up + Vector3.BACK * (0.5 if side == "front" else -0.5)).normalized()
		_put("pauldron_" + side, _axes(out, forward), joint + up * 0.25,
			Vector3(0.95, 0.62, 0.9))
		var knee := (_parts["knee_" + side] as MeshInstance3D).position
		var shin := _parts["shin_" + side] as MeshInstance3D
		var along := (knee - shin.position).normalized()
		_put("cuff_" + side, _axes(along, forward), knee - along * 0.35,
			Vector3(0.78, 0.9, 0.78))
	_pose_head(art, pose, up)


## The tunic: a chest, a waist, a short flared skirt to mid-thigh with a trim
## round its hem, a belt with a buckle and a pouch, and the crest on the chest.
## Its depth follows the rig's chest width, so a turn foreshortens it.
func _pose_body(art: PlayerArt, up: Vector3, forward: Vector3) -> void:
	var width := float(art._hw["chest"]) / PlayerArt.HW_CHEST
	var shoulder := _lift(art._shoulder, 0.0)
	var chest := _lift(art._chest, 0.0)
	var waist := _lift(art._waist, 0.0)
	var hip := _lift(art._hip, 0.0)
	var frame := _axes(up, forward)
	_put("chest", frame, shoulder.lerp(chest, 0.7) - up * 0.2,
		Vector3(1.5 * width, 2.3, 1.95))
	_segment(art, "waist", chest, waist, Vector2(1.15 * width, 1.6))
	var hem := hip - up * 1.7
	_segment(art, "skirt", waist, hem, Vector2(1.25 * width, 1.75))
	_put("hem_trim", frame, hem + up * 0.1, Vector3(1.78 * width, 0.9, 2.45))
	_put("collar", frame, shoulder + up * 0.25, Vector3(0.9, 0.7, 0.9))
	_put("crest", frame, shoulder.lerp(chest, 0.85) + forward * 1.42 * width,
		Vector3(0.18, 0.55, 0.45))
	_segment(art, "belt", waist + up * 0.3, waist - up * 0.3, Vector2(1.28 * width, 1.75))
	_put("buckle", frame, waist + forward * 1.3 * width, Vector3(0.25, 0.55, 0.6))
	_put("pouch", frame, waist - up * 0.7 + Vector3.BACK * 1.55 - forward * 0.3,
		Vector3(0.9, 1.0, 0.4))


## The cape hangs from the back of the shoulders on the prince's cloak fields
## and the cloth lag: two panels flaring from the shoulders to the hem, the
## lower one swept further. They are slabs with real depth, not sheets: from
## the side a sheet is seen edge on, and a cape that is a line reads as a stick.
func _pose_cape(art: PlayerArt, pose: Dictionary, up: Vector3, forward: Vector3) -> void:
	var sweep: float = minf(float(pose["cloak_sweep"]) + art._sway.x * 2.6, 4.0)
	var rise: float = float(pose["cloak_rise"]) + art._sway.y * 3.4
	var top := _lift(art._shoulder, 0.0) - forward * 1.25 + up * 0.15
	var mid := top - forward * (0.4 + sweep * 0.45) - up * 5.0
	var tail := mid - forward * (0.8 + sweep * 0.9) - up * maxf(1.5, 5.5 - rise * 1.3)
	if art._grounded():
		mid.y = maxf(mid.y, 0.5)
		tail.y = maxf(tail.y, 0.4)
	_segment(art, "cape_top", top, mid, Vector2(1.1, 2.3))
	_put("cape_joint", _axes((top - mid).normalized(), forward), mid,
		Vector3(1.1, 0.5, 2.3))
	_segment(art, "cape_tail", mid, tail, Vector2(1.1, 2.3))


func _pose_head(art: PlayerArt, pose: Dictionary, up: Vector3) -> void:
	var head := _head(art, pose, up, _lift(art._shoulder, 0.0) + up * 0.5, 2.2, FACE_TURN)
	var c: Vector3 = head[0]
	var frame: Basis = head[1]
	var side: Vector3 = head[2]
	var face := frame.x
	var hu := frame.y
	_segment(art, "neck", _lift(art._shoulder, 0.0), c - hu * 1.6, Vector2.ONE)
	_put("head", frame, c, HEAD_R)
	_put("hair_cap", frame, c + hu * 0.25 - face * 0.28, HEAD_R * Vector3(1.08, 1.04, 1.08))
	_put("hair_back", frame, c - face * 0.8 - hu * 0.25, HEAD_R * Vector3(0.82, 0.95, 0.95))
	for i: int in 3:
		var a := (float(i) - 1.0) * 0.55
		_put("bang_%d" % i, frame, c + hu * 1.45 + (face * cos(a) + side * sin(a)) * 1.75,
			Vector3(0.6, 0.5, 0.6))
	# The brow band: a ring round the head just above the eyes, a gem in front.
	_put("band", frame, c + hu * 0.8, Vector3(2.18, 1.1, 2.13))
	_put("band_gem", frame, c + hu * 0.8 + face * 2.15, Vector3.ONE * 0.32)
	_pose_braid(c - face * 1.9 - hu * 0.6)
	_pose_face(art, pose, frame, c, side)


## The braid: beads from the nape, each leaning a little further than the one
## above it, so a swing reads as a curve rather than a stick.
func _pose_braid(root: Vector3) -> void:
	var at := root
	for i: int in BRAID_BEADS:
		var bend := lerpf(0.6, 1.0, float(i) / float(BRAID_BEADS - 1))
		var a := _swing * bend
		at += Vector3(sin(a), -cos(a), 0.0) * BRAID_STEP
		var size := lerpf(0.62, 0.42, float(i) / float(BRAID_BEADS - 1))
		_put("braid_%d" % i, Basis.IDENTITY, at, Vector3(size, size * 1.2, size))
	_put("braid_tie", Basis.IDENTITY, at + Vector3(sin(_swing), -cos(_swing), 0.0) * 0.55,
		Vector3.ONE * 0.32)


## Two eyes -- white, a dark iris, an unlit highlight -- under two short brows,
## a nose, a mouth, two cheeks. A blink, a doze, a hit and a death close them.
func _pose_face(art: PlayerArt, pose: Dictionary, frame: Basis, c: Vector3,
		side: Vector3) -> void:
	var face := frame.x
	var hu := frame.y
	var shut := (art._flash > 0.0 or float(pose["glint"]) <= 0.0
		or fposmod(art._time, BLINK_EVERY) < BLINK_TIME)
	for i: int in 2:
		var which := "near" if i == 0 else "far"
		var sign := 1.0 if i == 0 else -1.0
		var aim := (face * cos(EYE_SPREAD) + side * sin(EYE_SPREAD) * sign).normalized()
		var eye_frame := _axes(hu, aim)
		var eye := c + aim * HEAD_R.x * 0.9 - hu * 0.05
		for id: String in ["white_", "iris_", "shine_"]:
			(_parts[id + which] as MeshInstance3D).visible = not shut
		(_parts["lid_" + which] as MeshInstance3D).visible = shut
		_put("white_" + which, eye_frame, eye, Vector3(0.3, 0.52, 0.4))
		_put("iris_" + which, eye_frame, eye + aim * 0.16 - hu * 0.04, Vector3(0.24, 0.4, 0.3))
		_put("shine_" + which, eye_frame, eye + aim * 0.3 + hu * 0.14 - side * 0.08,
			Vector3.ONE * 0.11)
		_put("lid_" + which, eye_frame, eye + aim * 0.12, Vector3(0.12, 0.12, 0.75))
		_put("brow_" + which, _axes(hu.rotated(aim, 0.18 * sign), aim),
			eye + hu * 0.7 + aim * 0.05, Vector3(0.14, 0.14, 0.7))
		var cheek_aim := (face * cos(0.75) + side * sin(0.75) * sign).normalized()
		_put("cheek_" + which, _axes(hu, cheek_aim), c + cheek_aim * HEAD_R.x * 0.92
			- hu * 0.75, Vector3(0.12, 0.28, 0.42))
	_put("nose", frame, c + face * HEAD_R.x * 0.98 - hu * 0.4, Vector3(0.28, 0.32, 0.26))
	var mouth := Vector3(0.12, 0.1, 0.42)
	if art._flash > 0.0:
		mouth = Vector3(0.22, 0.32, 0.3)
	_put("mouth", frame, c + face * HEAD_R.x * 0.9 - hu * 1.05, mouth)
