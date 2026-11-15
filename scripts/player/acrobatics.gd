class_name Acrobatics
extends RefCounted
## The stick avatar's flourishes: a front flip on a running jump, a backflip
## out of the backstep, a flip into the dive kick and a spinning air slash.
##
## The owner made the stick avatar the default and asked for poses a stick
## figure can do and a robe cannot: loops and flips. They are a layer over the
## shared pose (PlayerArt._posture()), not new poses, so every state keeps its
## read -- the backstep still leans away, the kick still leads with the heel --
## and only turns the whole body about the waist while it happens (the pose
## field `spin`, applied once in PlayerArt._rig()). A costume opts in
## (`Costume.acrobatic()`); the robed figures do not, because a cowl and a
## floor-length robe drawn on horizontal rungs fall apart upside down.
##
## Nothing here touches play. The hitbox, the timings, the grab probe and the
## sword's reach are the same with or without a flip; the blade turns with the
## body only in the drawing.
##
## ## Timing
##
## Each flourish is a pure function of the state's own clock or of the body's
## motion, so a replay draws it the same, and each ends upright on the frame
## its state can end: a flip that is cut off snaps.
##
## - **Running jump**: started when the jump leaves the floor at
##   `FLIP_FROM` of run speed or more (PlayerArt keeps that one fact, as it
##   keeps the squash spring). Its progress is read from the vertical speed --
##   take-off to just past the apex, `FLIP_DONE` of the way from JUMP_SPEED up
##   to JUMP_SPEED down -- not from a clock, so it spans JUMP and FALL without
##   a seam, a cut jump flips faster, and it is upright before any landing a
##   jump can make, even on a ledge higher than the take-off.
## - **Backstep**: one backflip over `BACKFLIP_TIME`, inside BACKSTEP_TIME.
## - **Dive kick**: a front flip over `KICK_FLIP_TIME`, then the kick's own
##   pose, heel first.
## - **Air slash**: one turn over ATTACK_TIME, the blade sweeping with the body.

const FLIP_FROM := 0.7
const FLIP_DONE := 0.6
const BACKFLIP_TIME := 0.4
const KICK_FLIP_TIME := 0.3
## How far the feet come up toward the hips at the middle of a flip.
const TUCK_LIFT := 6.5
## Every point of the rig a flip turns: all of them but the waist it turns
## about.
const RIG_POINTS: Array[StringName] = [
	&"_hip", &"_chest", &"_shoulder", &"_head", &"_hand_front", &"_hand_back",
	&"_foot_front", &"_foot_back", &"_knee_front", &"_knee_back",
]


## How far through a running jump's flip the body is, 0 to 1, from its
## vertical speed (+ is down).
static func flip_progress(fall_speed: float) -> float:
	var span := 2.0 * Tuning.JUMP_SPEED * FLIP_DONE
	return clampf((fall_speed + Tuning.JUMP_SPEED) / span, 0.0, 1.0)


## The turn about the waist for a state, in radians (+ is a front flip).
## `flipping` is whether this airborne spell began as a running jump.
static func spin_for(state: Player.State, t: float, fall_speed: float,
		flipping: bool) -> float:
	match state:
		Player.State.JUMP, Player.State.FALL:
			if flipping:
				return TAU * smoothstep(0.0, 1.0, flip_progress(fall_speed))
		Player.State.BACKSTEP:
			return -TAU * smoothstep(0.0, BACKFLIP_TIME, t)
		Player.State.DIVE_KICK:
			return TAU * smoothstep(0.0, KICK_FLIP_TIME, t)
		Player.State.AIR_SLASH:
			return TAU * smoothstep(0.0, Tuning.ATTACK_TIME, t)
	return 0.0


## `pose` with the flourish laid over it: the spin, and the body tucked while
## it turns -- knees up and the free arm round them, most at the half turn and
## none at either end, so the state's own pose is what the flip starts from and
## lands in.
static func flourish(pose: Dictionary, state: Player.State, t: float, fall_speed: float,
		flipping: bool) -> Dictionary:
	var spin := spin_for(state, t, fall_speed, flipping)
	if is_zero_approx(spin) or is_equal_approx(absf(spin), TAU):
		return pose
	var out := pose.duplicate()
	var tuck := sin(absf(spin) / TAU * PI)
	out["spin"] = spin
	# The feet come up under the hips and the knees to the chest: a body that
	# turned straight read as a plank thrown end over end.
	out["dangle"] = lerpf(float(pose["dangle"]), -TUCK_LIFT, tuck)
	out["knee"] = lerpf(float(pose["knee"]), 6.5, tuck)
	out["stride"] = lerpf(float(pose["stride"]), 1.4, tuck)
	out["stance"] = lerpf(float(pose["stance"]), 0.3, tuck)
	out["arm_b"] = lerpf(float(pose["arm_b"]), 1.1, tuck)
	out["arm_b_len"] = lerpf(float(pose["arm_b_len"]), 4.4, tuck)
	if state != Player.State.AIR_SLASH:
		# The sword arm tucks too, except in the slash, where it is the point.
		out["arm_a"] = lerpf(float(pose["arm_a"]), 0.9, tuck)
	return out


## Turns the whole rig about the waist for a flip, once, from PlayerArt._rig():
## the one place a pose may turn the figure further than a topple's tilt.
## Mirrored by the art's facing like every other forward-space quantity. Each
## point is assigned by name and read back, so a renamed rig field cannot
## leave a limb behind in silence (CLAUDE.md, on `set()`).
static func turn(art: PlayerArt, spin: float) -> void:
	if is_zero_approx(spin):
		return
	var by := spin * art._f
	for field: StringName in RIG_POINTS:
		var at: Vector2 = art.get(field)
		var turned := art._waist + (at - art._waist).rotated(by)
		art.set(field, turned)
		assert(art.get(field) == turned, "rig point %s did not turn" % field)
