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
## The tunic is the look's outfit, the cape its shade step, the lining and the
## shield's face the tunic again; in the duel they are the seat's team colour
## (FighterArt.dress), so a seat reads as its team from the chest out. Her own
## look is the concept's -- ROYAL blue, BROWN hair, SAND skin -- put on by
## `CharacterLook.wear_defaults()` when she is chosen. The trim, the lion, the
## buckles, the band and the shield's boss are the accent. Leather, leggings,
## steel and the eyes are fixed browns, greys and whites that belong to neither
## team (Palette.UMBER*, docs/art-direction.md).
##
## ## What is not the concept's
##
## Her sword is the shared 2D one (ModelCostume explains why), coloured hers
## through `blade_colours()`: blue-white steel in a blue glow. The shield is
## slung on her back as decoration, because the game has no shield to block
## with and a shield on the arm would promise one.

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


## A paler sun and a cooler shade than the base's. Under the gold key and the
## crimson ambient a royal-blue tunic goes to mud -- blue times gold is grey --
## and the concept is lit near white with a cool shade. The sun is still warm
## and still from the left; only its saturation comes down.
func _sun() -> Color:
	return Palette.PAPER


func _ambient() -> Color:
	return Palette.STEEL_DARK.lerp(Palette.SHADOW_DEEP, 0.35)


## Turned well toward the viewer, as the concept sheet draws her: the crest,
## both pauldrons and the trim down the front show, where a profile would hide
## them behind the sword arm.
func _yaw() -> float:
	return 0.62


## The concept's sword: blue-white steel in a blue glow, with the trim's gold
## on the guard.
func blade_colours() -> Dictionary:
	return {
		"steel": Palette.ROYAL_STEEL, "edge": Palette.PAPER, "edge_hot": Palette.PAPER,
		"glow": Palette.ROYAL_GLOW,
	}


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
	var trim := Palette.LIGHT_WARM if art == null else art.accent
	return {
		"cloth": cloth, "cape": cape, "trim": trim, "legs": Palette.UMBER_DEEP,
		# The cape's lining is the tunic's colour: the lighter plane the
		# concept shows inside the cape, kept in the seat's team.
		"lining": cloth,
		"leather": Palette.UMBER_DARK, "boot": Palette.UMBER, "sole": Palette.UMBER_DEEP,
		"steel": Palette.STEEL, "steel_dark": Palette.STEEL_DARK, "gem": Palette.LIGHT_SOFT,
		"skin": skin, "hair": hair, "hair_dark": hair_dark,
		"white": Palette.PAPER, "iris": Palette.SHADOW_PIT, "shine": Palette.PAPER,
		"lid": Palette.INK, "brow": hair_dark,
		"mouth": skin.lerp(Palette.SHADOW, 0.6),
		# The cheeks are the skin warmed toward the fire step: a blush lit by
		# the same sun as the face, whatever the skin tone. Not the blood
		# ramp's glint, which is blood's alone (docs/art-direction.md).
		"blush": skin.lerp(Palette.SHADOW_WARM, 0.45),
	}


func _make() -> void:
	_make_cape()
	for i: int in BRAID_BEADS:
		_add("braid_%d" % i, _sphere(), "hair" if i % 2 == 0 else "hair_dark")
	_add("braid_tie", _sphere(), "trim")
	_make_tunic()
	_make_limbs(Vector2(0.82, 0.62), Vector2(0.66, 0.52), Vector2(0.52, 0.46),
		Vector2(0.5, 0.44), 0.55, {
			"leg": "legs", "shin": "boot", "foot": "boot",
			"arm": "cloth", "fore": "leather", "hand": "leather",
		})
	for side: String in ["front", "back"]:
		_add("pauldron_" + side, _sphere(), "steel")
		_add("plate_" + side, _sphere(), "steel_dark")
		_add("pauldron_rim_" + side, _ring(0.82), "trim")
		_add("rivet_" + side, _sphere(), "trim")
		_add("cuff_" + side, _ring(0.7), "leather")
		_add("strap_" + side, _ring(0.78), "sole")
		_add("sole_" + side, _sphere(), "sole")
		_add("bracer_band_" + side, _ring(0.75), "trim")
	_make_head()


func _make_cape() -> void:
	_add("cape_top", _cylinder(0.55, 0.85), "cape")
	_add("cape_joint", _sphere(0.85), "cape")
	_add("cape_tail", _cylinder(0.85, 1.0), "cape")
	_add("lining_top", _cylinder(0.5, 0.8), "lining")
	_add("lining_tail", _cylinder(0.8, 0.95), "lining")
	_add("clasp", _sphere(), "trim")


func _make_tunic() -> void:
	_add("chest", _sphere(), "cloth")
	_add("waist", _cylinder(1.0, 1.0), "cloth")
	_add("skirt", _cylinder(1.0, 1.4), "cloth")
	_add("hem_trim", _ring(0.86), "trim")
	_add("hem_trim_2", _ring(0.92), "trim")
	_add("collar", _ring(0.7), "trim")
	_add("v_near", _box(), "trim")
	_add("v_far", _box(), "trim")
	_add("front_trim", _box(), "trim")
	for id: String in ["lion_body", "lion_mane", "lion_head"]:
		_add(id, _sphere(), "trim")
	for id: String in ["lion_paw", "lion_hind", "lion_tail"]:
		_add(id, _cylinder(1.0, 1.0), "trim")
	_add("shield", _sphere(), "cloth")
	_add("shield_rim", _ring(0.9), "steel")
	_add("shield_boss", _sphere(), "trim")
	_add("belt", _cylinder(1.0, 1.0), "leather")
	_add("buckle", _box(), "trim")
	_add("sword_belt", _ring(0.86), "leather")
	_add("sword_buckle", _sphere(), "trim")
	_add("pouch", _box(), "leather")
	_add("pouch_flap", _box(), "trim")


func _make_head() -> void:
	_add("neck", _cylinder(0.5, 0.55), "skin")
	_add("head", _sphere(), "skin")
	_add("hair_cap", _sphere(), "hair")
	_add("hair_back", _sphere(), "hair_dark")
	_add("band", _ring(0.86), "trim")
	_add("band_gem", _sphere(), "gem")
	_add("nose", _sphere(), "skin")
	_add("mouth", _sphere(), "mouth")
	for side: String in ["near", "far"]:
		_add("hair_side_" + side, _sphere(), "hair")
		_add("sweep_" + side, _sphere(), "hair")
		_add("band_stud_" + side, _sphere(), "gem")
		_add("white_" + side, _sphere(), "white")
		_add("iris_" + side, _sphere(), "iris")
		_add("shine_" + side, _sphere(), "shine")
		_add("liner_" + side, _box(), "lid")
		_add("lid_" + side, _box(), "lid")
		_add("brow_" + side, _box(), "brow")
		_add("cheek_" + side, _sphere(), "blush")


func _pose_parts(art: PlayerArt, pose: Dictionary, up: Vector3, forward: Vector3) -> void:
	_pose_body(art, up, forward)
	_pose_cape(art, pose, up, forward)
	_pose_limbs(art, 0.8, 1.85, 0.75, 0.9, Vector3(1.3, 0.62, 0.68))
	_pose_armour(up, forward)
	_pose_head(art, pose, up)


## The rampant lion of the concept's crest, in gold relief on the chest: a
## body, a mane and a head, a raised forepaw, a hind leg and a tail, laid flat
## on the tunic in the plane across the chest (`across` toward the camera,
## `up`). At play size it is a gold mark with a ragged edge; in the wardrobe
## it is a lion.
func _pose_lion(art: PlayerArt, at: Vector3, up: Vector3, forward: Vector3) -> void:
	var across := Vector3.BACK
	var flat := 0.1
	var lean := _axes(up.rotated(forward, 0.45 * art._f), forward)
	_put("lion_body", lean, at + up * -0.1, Vector3(flat, 0.55, 0.32))
	_put("lion_mane", _axes(up, forward), at + up * 0.38 + across * 0.12,
		Vector3(flat, 0.34, 0.34))
	_put("lion_head", _axes(up, forward), at + up * 0.45 + across * 0.3,
		Vector3(flat * 1.4, 0.18, 0.2))
	_segment(art, "lion_paw", at + up * 0.18 + across * 0.12, at + up * 0.5 + across * 0.5,
		Vector2(flat * 0.6, 0.09))
	_segment(art, "lion_hind", at - up * 0.45, at - up * 0.8 + across * 0.22,
		Vector2(flat * 0.6, 0.1))
	_segment(art, "lion_tail", at - up * 0.3 - across * 0.2, at + up * 0.15 - across * 0.45,
		Vector2(flat * 0.5, 0.06))


## The tunic: a chest, a waist, a short flared skirt to mid-thigh with a
## double trim round its hem, a V of trim at the neck and a band of it down
## the front, the crest on the chest, a belt with a buckle, a slanted sword
## belt and a pouch. Its depth follows the rig's chest width, so a turn
## foreshortens it.
func _pose_body(art: PlayerArt, up: Vector3, forward: Vector3) -> void:
	var width := float(art._hw["chest"]) / PlayerArt.HW_CHEST
	var shoulder := _lift(art._shoulder, 0.0)
	var chest := _lift(art._chest, 0.0)
	var waist := _lift(art._waist, 0.0)
	var hip := _lift(art._hip, 0.0)
	var frame := _axes(up, forward)
	var front := forward * 1.48 * width
	_put("chest", frame, shoulder.lerp(chest, 0.7) - up * 0.2,
		Vector3(1.5 * width, 2.3, 1.95))
	_segment(art, "waist", chest, waist, Vector2(1.15 * width, 1.6))
	var hem := hip - up * 1.7
	_segment(art, "skirt", waist, hem, Vector2(1.25 * width, 1.75))
	_put("hem_trim", frame, hem + up * 0.1, Vector3(1.78 * width, 0.9, 2.45))
	_put("hem_trim_2", frame, hem + up * 0.55, Vector3(1.7 * width, 0.5, 2.36))
	_put("collar", frame, shoulder + up * 0.25, Vector3(0.9, 0.7, 0.9))
	var sternum := shoulder.lerp(chest, 0.75) + forward * 1.38 * width
	for i: int in 2:
		var across := Vector3.BACK * (0.85 if i == 0 else -0.85)
		_segment(art, "v_near" if i == 0 else "v_far",
			shoulder + forward * 0.75 + across + up * 0.15, sternum, Vector2(0.16, 0.2))
	_segment(art, "front_trim", sternum, hem + front * 0.9 + up * 0.4, Vector2(0.14, 0.32))
	# Toward the far side of the chest: the near half is behind the sword arm.
	_pose_lion(art, shoulder.lerp(chest, 0.95) + forward * 1.5 * width
		- Vector3.BACK * 0.35, up, forward)
	# The shield, slung on the back: a face in the tunic's colour, a steel rim,
	# a gold boss. Decoration -- there is no shield in the game to block with.
	var slung := _axes(-forward, up)
	var shield := shoulder.lerp(waist, 0.45) - forward * 2.4 + Vector3.BACK * 0.3
	_put("shield", slung, shield, Vector3(0.3, 1.65, 1.35))
	_put("shield_rim", _axes(-forward, up), shield, Vector3(1.38, 0.5, 1.68))
	_put("shield_boss", slung, shield - forward * 0.3, Vector3.ONE * 0.38)
	_segment(art, "belt", waist + up * 0.3, waist - up * 0.3, Vector2(1.28 * width, 1.75))
	_put("buckle", frame, waist + forward * 1.3 * width, Vector3(0.25, 0.55, 0.6))
	# The sword belt slants from the waist at the back to the hip at the front.
	var slant := _axes(up.rotated(Vector3.BACK, 0.32 * art._f), forward)
	_put("sword_belt", slant, waist.lerp(hip, 0.55), Vector3(1.48 * width, 0.7, 1.98))
	_put("sword_buckle", frame, waist.lerp(hip, 0.75) + forward * 1.35 * width,
		Vector3.ONE * 0.28)
	var pouch := waist - up * 0.8 + Vector3.BACK * 1.6 - forward * 0.35
	_put("pouch", frame, pouch, Vector3(0.9, 1.0, 0.42))
	_put("pouch_flap", frame, pouch + up * 0.42 + Vector3.BACK * 0.12,
		Vector3(0.92, 0.22, 0.3))


## The cape hangs from the back of the shoulders on the prince's cloak fields
## and the cloth lag: two panels flaring from the shoulders to the hem, the
## lower one swept further, each with a lining in the tunic's colour on the
## body's side. They are slabs with real depth, not sheets: from the side a
## sheet is seen edge on, and a cape that is a line reads as a stick.
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
	# The lining sits on the body's side of the cape and shows at its edge.
	var inward := forward * 0.35
	_segment(art, "lining_top", top + inward, mid + inward, Vector2(0.85, 2.35))
	_segment(art, "lining_tail", mid + inward, tail + inward, Vector2(0.85, 2.35))
	_put("clasp", Basis.IDENTITY, _lift(art._shoulder, 0.0) + up * 0.35
		+ Vector3.BACK * 1.1 + forward * 0.4, Vector3.ONE * 0.36)


## Steel over each shoulder joint -- a dome, a wider plate below it, a rim of
## trim and a rivet -- a gold band at each wrist, and at each boot a folded
## cuff under the knee, a strap at the ankle and a dark sole.
func _pose_armour(up: Vector3, forward: Vector3) -> void:
	for side: String in ["front", "back"]:
		var outward := Vector3.BACK * (1.0 if side == "front" else -1.0)
		var joint := (_parts["shoulder_" + side] as MeshInstance3D).position
		var out := (up + outward * 0.5).normalized()
		var dome := _axes(out, forward)
		_put("pauldron_" + side, dome, joint + up * 0.25, Vector3(0.95, 0.62, 0.9))
		_put("plate_" + side, dome, joint - up * 0.25 + outward * 0.18,
			Vector3(1.0, 0.42, 0.95))
		_put("pauldron_rim_" + side, dome, joint + up * 0.05, Vector3(0.98, 0.7, 0.93))
		_put("rivet_" + side, dome, joint + up * 0.55 + outward * 0.6 + forward * 0.2,
			Vector3.ONE * 0.13)
		var elbow := (_parts["elbow_" + side] as MeshInstance3D).position
		var hand := (_parts["hand_" + side] as MeshInstance3D).position
		var arm := (elbow - hand).normalized()
		_put("bracer_band_" + side, _axes(arm, forward), hand + arm * 0.75,
			Vector3(0.6, 0.8, 0.6))
		var knee := (_parts["knee_" + side] as MeshInstance3D).position
		var shin := _parts["shin_" + side] as MeshInstance3D
		var along := (knee - shin.position).normalized()
		_put("cuff_" + side, _axes(along, forward), knee - along * 0.35,
			Vector3(0.78, 0.9, 0.78))
		var foot := _parts["foot_" + side] as MeshInstance3D
		# The shin is centred between knee and ankle, so the ankle is its mirror.
		var ankle := shin.position * 2.0 - knee
		_put("strap_" + side, _axes(along, forward), ankle + along * 0.35,
			Vector3(0.6, 0.6, 0.6))
		_put("sole_" + side, foot.basis.orthonormalized(),
			foot.position - foot.basis.orthonormalized().y * 0.45, Vector3(1.32, 0.2, 0.7))


func _pose_head(art: PlayerArt, pose: Dictionary, up: Vector3) -> void:
	var head := _head(art, pose, up, _lift(art._shoulder, 0.0) + up * 0.5, 2.2, FACE_TURN)
	var c: Vector3 = head[0]
	var frame: Basis = head[1]
	var side: Vector3 = head[2]
	var face := frame.x
	var hu := frame.y
	_segment(art, "neck", _lift(art._shoulder, 0.0), c - hu * 1.6, Vector2.ONE)
	_put("head", frame, c, HEAD_R)
	# The hair: parted in the middle and drawn back, so the forehead is bare
	# under the brow band -- a cap set back on the skull, a swept lock either
	# side of the parting, fullness over the ears and at the nape, and the
	# braid from there.
	_put("hair_cap", frame, c - face * 0.48 + hu * 0.2, HEAD_R * Vector3(1.0, 1.03, 1.05))
	_put("hair_back", frame, c - face * 1.05 - hu * 0.55, Vector3(1.55, 1.85, 1.75))
	for i: int in 2:
		var which := "near" if i == 0 else "far"
		var sign := 1.0 if i == 0 else -1.0
		_put("hair_side_" + which, frame, c - face * 0.5 + side * 1.35 * sign - hu * 0.3,
			Vector3(1.15, 1.7, 0.85))
		var sweep := _axes(hu.rotated(face, -0.35 * sign), face)
		_put("sweep_" + which, sweep, c + hu * 1.75 + face * 0.55 + side * 0.85 * sign,
			Vector3(1.0, 0.55, 0.95))
	# The brow band across the bare forehead, lower at the front than behind,
	# with a gem in the middle and a stone either side of it.
	var band := _axes(hu.rotated(side, -0.28), face)
	var band_at := c + hu * 1.0
	_put("band", band, band_at, Vector3(2.12, 0.75, 2.07))
	var gem := band_at + band.x * 2.08 - band.y * 0.02
	_put("band_gem", frame, gem, Vector3.ONE * 0.34)
	for i: int in 2:
		var sign := 1.0 if i == 0 else -1.0
		var aim := (band.x * cos(0.6) + side * sin(0.6) * sign).normalized()
		_put("band_stud_" + ("near" if i == 0 else "far"), frame,
			band_at + aim * 2.03 + band.y * 0.02, Vector3.ONE * 0.18)
	_pose_braid(c - face * 1.6 - hu * 1.3 + side * 0.4)
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


## Two eyes -- white, a dark iris, an unlit highlight, a line of liner over
## each -- under two short brows, a nose, lips, two cheeks. A blink, a doze, a
## hit and a death close them.
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
		var eye := c + aim * HEAD_R.x * 0.9 - hu * 0.1
		for id: String in ["white_", "iris_", "shine_", "liner_"]:
			(_parts[id + which] as MeshInstance3D).visible = not shut
		(_parts["lid_" + which] as MeshInstance3D).visible = shut
		_put("white_" + which, eye_frame, eye, Vector3(0.3, 0.52, 0.42))
		_put("iris_" + which, eye_frame, eye + aim * 0.16 - hu * 0.05, Vector3(0.24, 0.42, 0.3))
		_put("shine_" + which, eye_frame, eye + aim * 0.3 + hu * 0.12 - side * 0.08,
			Vector3.ONE * 0.11)
		var liner := _axes(hu.rotated(aim, -0.15 * sign), aim)
		_put("liner_" + which, liner, eye + hu * 0.48 + aim * 0.1, Vector3(0.12, 0.12, 0.85))
		_put("lid_" + which, eye_frame, eye + aim * 0.12, Vector3(0.12, 0.12, 0.75))
		_put("brow_" + which, _axes(hu.rotated(aim, 0.2 * sign), aim),
			eye + hu * 0.82 + aim * 0.02, Vector3(0.14, 0.13, 0.72))
		var cheek_aim := (face * cos(0.75) + side * sin(0.75) * sign).normalized()
		_put("cheek_" + which, _axes(hu, cheek_aim), c + cheek_aim * HEAD_R.x * 0.92
			- hu * 0.8, Vector3(0.12, 0.28, 0.42))
	_put("nose", frame, c + face * HEAD_R.x * 0.98 - hu * 0.45, Vector3(0.28, 0.32, 0.26))
	var lips := Vector3(0.16, 0.16, 0.5)
	if art._flash > 0.0:
		lips = Vector3(0.24, 0.34, 0.32)
	_put("mouth", frame, c + face * HEAD_R.x * 0.9 - hu * 1.15, lips)
