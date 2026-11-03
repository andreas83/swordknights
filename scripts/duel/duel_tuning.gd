class_name DuelTuning
extends Resource
## Every number that defines how a DUEL fighter feels, in one place.
##
## This is deliberately NOT scripts/core/tuning.gd. The adventure character is
## built on weight: a six-frame run-up, a wind-up on the turn, coyote time and
## a jump buffer so a late tap on a touchscreen is forgiven, and a level
## grammar (2-tile hop, 3-tile step, 4-tile grab, 3-tile gap) derived from
## those numbers and pinned by tests. A duellist is the opposite animal. It
## reaches top speed in two frames, stops in three, falls like a brick, and is
## never forgiven anything. Putting both sets of numbers in one file would
## mean every duel retune threatened the levels, so the duel carries its own
## profile and the fighter reads it through `Fighter.setup(id, profile)`.
##
## Units are pixels and seconds, as everywhere else, and the physics tick is a
## fixed 60 Hz (see docs/architecture.md), so a "frame" below is exactly one
## simulation step and the spec's frame counts map 1:1.
##
## The accelerations are written as px/s^2 but chosen in px/frame:
##
##   ground_accel 4800 = 80 px/frame   -> 0 to 120 px/s in 2 frames (120/80)
##   ground_friction 2400 = 40 px/frame -> 120 px/s to 0 in 3 frames
##   gravity 2400 = 40 px/frame        -> a 420 jump peaks 33 px up in 11
##                                        frames and is over in 21
##
## tests/fighter_profile_test.gd asserts those three counts against this
## resource rather than against literals, so a retune reports what it did to
## the feel instead of silently changing it.

## The three sword heights. Also the first three columns of the combat matrix,
## so the ordinals matter: see DuelCombat.MATRIX.
enum Stance { HIGH, MID, LOW }

## The matrix's fourth defender column. Not a stance — a posture: a fighter who
## is ducking, rolling or lying on the floor has no stance at all, because the
## blade is not up at any height.
const DUCKED := 3

# --- body and blade geometry ------------------------------------------------
#
# The three bands are cut so that the geometry alone already produces the duck
# and roll columns of the combat matrix, and the matrix only has to resolve
# what two standing fighters do to each other:
#
#   HIGH  22..15 above the feet   over a 13px duck, over a 7px roll
#   MID   15..9                   into a duck's head, over a roll
#   LOW   9..1                    into a duck's torso, into a roll's back
#
# Changing a band therefore changes the rules, not just the pixels, and
# tests/combat_matrix_test.gd will say so.

@export var body_width: float = 9.0
@export var body_height: float = 22.0
@export var duck_height: float = 13.0
## ~30% of standing height: under HIGH and MID, and under a thrown sword.
@export var roll_height: float = 7.0

@export var band_high_top: float = 22.0
@export var band_high_bottom: float = 15.0
@export var band_mid_bottom: float = 9.0
@export var band_low_bottom: float = 1.0

## How far past the body edge the blade reaches in the four active frames of a
## thrust, and how far it rests the rest of the time. The resting blade is what
## a clash and a disarm are measured against, so it is short but not zero: you
## can turn a blade aside slightly further out than it can reach your body.
@export var blade_reach: float = 18.0
@export var blade_rest: float = 7.0

## A sword lying on the floor or in flight.
@export var blade_length: float = 14.0
@export var blade_thickness: float = 4.0

# --- horizontal motion -----------------------------------------------------

@export var run_speed: float = 120.0
@export var ground_accel: float = 4800.0
@export var ground_friction: float = 2400.0
## Air control is deliberately weaker than ground control, but still immediate:
## a committed jump can be steered, not re-aimed.
@export var air_accel: float = 2400.0
@export var air_friction: float = 900.0

# --- vertical motion -------------------------------------------------------

@export var gravity: float = 2400.0
@export var max_fall_speed: float = 660.0
@export var jump_speed: float = 420.0
## Releasing jump on the way up cuts the arc. No apex float, no coyote time and
## no jump buffer: a duel does not forgive a late press, it punishes it.
@export var jump_cut: float = 0.35

# --- the moveset, in frames ------------------------------------------------

## 12-15 frames total per the spec. Frames 1..thrust_active are the active
## blade; the rest is recovery with the blade out of position.
@export var thrust_frames: int = 14
@export var thrust_active: int = 4
## "The fighter drifts slightly forward during the thrust": 36 px/s over 14
## frames is 8.4 px, half a tile, which reads as a lunge and closes no gap.
@export var thrust_drift: float = 36.0

@export var roll_frames: int = 25
@export var roll_speed: float = 160.0

@export var divekick_speed_x: float = 180.0
@export var divekick_speed_y: float = 420.0
## Frames spent planted after a dive kick lands. The commitment is the cost.
@export var divekick_recover: int = 10

## The unarmed sub-machine.
@export var disarmed_frames: int = 10
@export var sweep_frames: int = 16
@export var sweep_active_from: int = 3
@export var sweep_active_to: int = 8
@export var sweep_reach: float = 13.0
@export var pound_speed_y: float = 600.0
@export var pound_recover: int = 12
@export var downed_frames: int = 45

## Frames from the start of a thrust during which a defender who moves their
## blade into its height disarms the attacker. THE most important number in the
## combat system; see docs/duel-combat.md for why it is 5 and not 4 or 6.
@export var disarm_window: int = 5

## The pseudocode's applyKnockback(-2.0): 2 px per frame at 60 Hz.
@export var clash_knockback: float = 120.0

## A thrown sword flies in a straight line — no gravity at all until it hits
## something — and `up` + throw angles it slightly up instead of level.
@export var throw_speed: float = 330.0
@export var throw_rise: float = 90.0
## A dropped sword does fall, and settles where it lands.
@export var blade_fall_gravity: float = 1200.0

# --- the catch ---------------------------------------------------------------
#
# THROW with an empty hand opens both hands in front of the chest: a SNATCH.
# A sword flying into them while they are open is caught. docs/duel-combat.md
# argues each number; tests/fighter_frames_test.gd pins the window frame by
# frame and tests/combat_sword_test.gd plays it.

## The whole snatch, a commitment like the thrust: the hands are open on frames
## 1..catch_window and the rest is recovery, standing, unable to duck, roll or
## jump. A snatch at nothing leaves you twelve frames in front of a throw.
@export var snatch_frames: int = 18
@export var catch_window: int = 6
## How far past the body edge the open hands reach. Not less than one frame of a
## throw's travel (throw_speed / 60 = 5.5 px), or a blade could step from clear
## air straight into the body between two samples without ever being in the
## hands. tests/unit/test_duel_catch.gd holds that.
@export var catch_reach: float = 8.0
## Frames spent taking the caught blade into the hand before the fighter is free
## to use it -- the thrower's one chance to get away or sweep.
@export var catch_settle: int = 6


## The default profile. A match may load a .tres over it; nothing in the
## fighter reads anything but the resource it is handed.
static func default() -> DuelTuning:
	return DuelTuning.new()


## (top, bottom) heights above the feet of a stance's blade band.
func band_of(stance: int) -> Vector2:
	match stance:
		Stance.HIGH:
			return Vector2(band_high_top, band_high_bottom)
		Stance.MID:
			return Vector2(band_high_bottom, band_mid_bottom)
		_:
			return Vector2(band_mid_bottom, band_low_bottom)


## The blade's AABB, `reach` px past the body edge at the stance's height.
##
## Axis-aligned, and that is not a shortcut: in a 2D side view with exactly
## three discrete stances a thrust is horizontal at one of three heights, so an
## oriented rectangle would describe the same pixels with more arithmetic and
## less determinism. See the engineering note in docs/duel-spec.md.
func blade_rect(feet: Vector2, facing: int, stance: int, reach: float) -> Rect2:
	var band := band_of(stance)
	var half := body_width * 0.5
	var x := (feet.x + half) if facing > 0 else (feet.x - half - reach)
	return Rect2(x, feet.y - band.x, reach, band.x - band.y)


## Where the open hands of a snatch can take a thrown blade: in front of the
## body, `catch_reach` deep, from the top of the HIGH band down to the bottom of
## MID. Not LOW. Hands catch at the chest and the face, not at the ankles, so a
## LOW throw cannot be caught and has to be jumped -- which is the thrower's
## answer to a fighter waiting with open hands. Geometry, like the duck and the
## roll: the rect says it, and no rule has to.
func catch_rect(feet: Vector2, facing: int) -> Rect2:
	var half := body_width * 0.5
	var x := (feet.x + half) if facing > 0 else (feet.x - half - catch_reach)
	return Rect2(x, feet.y - band_high_top, catch_reach, band_high_top - band_mid_bottom)


## The stance a blade caught at `height` px above the feet is held in: HIGH if
## it came in over the MID band, otherwise MID. Never LOW, which the hands do
## not reach.
func catch_stance(height: float) -> int:
	return Stance.HIGH if height > band_high_bottom else Stance.MID


## A sword lying on the floor or in flight, centred on its own position.
func loose_blade_rect(at: Vector2) -> Rect2:
	return Rect2(
		at.x - blade_length * 0.5, at.y - blade_thickness * 0.5, blade_length, blade_thickness
	)


## Where a thrown or dropped blade leaves the hand.
func hand_position(feet: Vector2, facing: int, stance: int) -> Vector2:
	var band := band_of(stance)
	var half := body_width * 0.5
	return Vector2(
		feet.x + (half + blade_length * 0.5) * facing, feet.y - (band.x + band.y) * 0.5
	)


## Frames to go from a standing start to top speed on the ground.
func frames_to_top_speed() -> int:
	return int(ceil(run_speed / (ground_accel / 60.0)))


## Frames to stop from top speed with no input.
func frames_to_stop() -> int:
	return int(ceil(run_speed / (ground_friction / 60.0)))


## Frames a standing jump spends off the ground, integrated the way the
## simulation integrates it rather than solved in closed form — semi-implicit
## Euler and the continuous arc do not agree, and the engine runs the former.
func jump_frames() -> int:
	var dt := 1.0 / 60.0
	var vy := -jump_speed
	var height := 0.0
	var frames := 0
	while frames < 600:
		frames += 1
		vy = minf(vy + gravity * dt, max_fall_speed)
		height += vy * dt
		if height >= 0.0:
			break
	return frames


## Apex of a standing jump, in pixels.
func jump_rise() -> float:
	var dt := 1.0 / 60.0
	var vy := -jump_speed
	var height := 0.0
	var best := 0.0
	for _frame: int in 600:
		vy = minf(vy + gravity * dt, max_fall_speed)
		height += vy * dt
		best = minf(best, height)
		if height >= 0.0:
			break
	return -best
