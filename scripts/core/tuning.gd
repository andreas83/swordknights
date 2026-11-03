class_name Tuning
extends RefCounted
## Every number that defines how the character feels, in one place.
##
## Units are pixels and seconds; one tile is 16 px and the viewport is 320x180,
## so these values are the same ones the earlier prototype was tuned with.
##
## The defaults aim at the Prince of Persia cadence: deliberate on the ground,
## committed in the air, forgiving at the edges (coyote time, jump buffering,
## ledge grabs) so a late tap on a touchscreen is not punished.
##
## Deliberate is not the same as mushy. Weight belongs in the wind-up and in
## the landing from a real drop; it does not belong in the half-second it takes
## to reach top speed, nor in a recovery lockout after a routine hop. The
## accelerations below are therefore tight and the landing thresholds are set
## ABOVE flat_jump_land_speed(), so a plain jump flows straight back into a run
## and only a genuine fall costs the player time.
##
## The level grammar is derived from these numbers, not chosen independently:
## a 2-tile rise is a plain hop, a 3-tile rise needs a one-way platform step,
## and a 4-tile rise is only clearable with a ledge grab. tests/ pins that
## relationship, so retuning here fails loudly instead of silently making
## level geometry unreachable.

# Body
const BODY_WIDTH := 9.0
const BODY_HEIGHT := 22.0
const CROUCH_HEIGHT := 13.0

# Horizontal motion
const RUN_SPEED := 88.0
const WALK_SPEED := 40.0
const GROUND_ACCEL := 900.0   ## 0->RUN_SPEED in ~6 frames; 520 took 10.
const GROUND_FRICTION := 1100.0 ## Plants the stop instead of skating it.
const AIR_ACCEL := 480.0      ## Enough steering to thread a gap, not to fly.
const AIR_FRICTION := 260.0   ## Letting go in the air shortens the jump.
const TURN_TIME := 0.1        ## Six frames of planted wind-up; the pose reads.

# Vertical motion
const GRAVITY := 900.0
const MAX_FALL_SPEED := 360.0
const JUMP_SPEED := 252.0
const JUMP_CUT_MULTIPLIER := 0.38
const APEX_GRAVITY_SCALE := 0.62
const APEX_THRESHOLD := 52.0

# Forgiveness windows
const COYOTE_TIME := 0.1
const JUMP_BUFFER := 0.14
## Releasing jump cuts the rise only after this long in the air. A thumb taps
## for a frame or four, and a jump buffered before landing is usually released
## before it fires; with the cut live from the first frame those rose 6 px and
## 2 px. Six frames makes the shortest jump a hop of about 21 px, still well
## short of a held jump, so the cut keeps its meaning. Changes no apex, so it
## cannot move the grammar.
const MIN_JUMP_HOLD := 0.1
## A sword press is kept this long, like a jump press, so one made in the last
## frames of a fall, in a turn or in a landing swings as soon as it can instead
## of being eaten.
const ATTACK_BUFFER := 0.12

# Ledges
const GRAB_PROBE_Y := 6.0
const GRAB_REACH := 3.0
const HANG_HOLD_TIME := 0.06
const CLIMB_UP_TIME := 0.27
const MAX_GRAB_FALL_SPEED := 310.0

# Ladders
const LADDER_SPEED := 48.0

# Combat and damage
const MAX_HEALTH := 3
const INVULNERABLE_TIME := 0.9
const KNOCKBACK_X := 90.0
const KNOCKBACK_Y := 150.0
const ATTACK_TIME := 0.24
const ATTACK_REACH := 14.0
const ATTACK_HEIGHT := 14.0

# Landing.
#
# Both thresholds sit above flat_jump_land_speed(), which is the whole point:
# at 190 every single jump ended in a recovery lockout, so running and jumping
# felt like wading. Now a jump from flat ground lands clean, one extra tile of
# drop costs a short recovery and two tiles thump.
const SOFT_LAND_SPEED := 265.0
const HARD_LAND_SPEED := 330.0
const LAND_RECOVER_TIME := 0.12

# Derived traversal grammar — what the level generator and the hand-authored
# levels are allowed to assume. Kept here so it cannot drift from the tuning.
const TILE := 16.0

static func max_jump_rise() -> float:
	## Apex height of a standing jump, including the reduced apex gravity.
	var full := (JUMP_SPEED * JUMP_SPEED) / (2.0 * GRAVITY)
	var apex_bonus := (APEX_THRESHOLD * APEX_THRESHOLD) / (2.0 * GRAVITY) \
		* (1.0 / APEX_GRAVITY_SCALE - 1.0)
	return full + apex_bonus


## The tallest rise, in tiles, that a plain jump can land on top of.
## The feet must clear the ledge, so this rounds DOWN.
static func hop_tiles() -> int:
	return floori(max_jump_rise() / TILE)


## The tallest rise, in tiles, that a jump can still catch with a ledge grab,
## measured from the floor the jump started on.
##
## At the apex the hand probe sits BODY_HEIGHT - GRAB_PROBE_Y below the feet.
## That probe lands somewhere inside a tile row, and the ledge it catches is
## that row's TOP edge — so unlike hop_tiles() the reachable rise rounds UP.
## Using floor() here under-reports by a whole tile and quietly contradicts
## both the hand-authored levels and the generator built on top of it.
static func grab_tiles() -> int:
	return ceili((max_jump_rise() + BODY_HEIGHT - GRAB_PROBE_Y) / TILE)


## The rise that needs a one-way platform as an intermediate step: too tall to
## hop onto, low enough that a grab is not required.
static func platform_step_tiles() -> int:
	return hop_tiles() + 1


## Seconds a jump spends off the ground before the feet come back to the
## height they left from.
##
## Integrated frame by frame rather than solved in closed form, because the
## game is a fixed 60 Hz simulation and the two do not agree: semi-implicit
## Euler loses roughly 2 px of apex rise against the continuous arc. The
## closed form would quietly overstate what the engine can actually do, which
## is the same class of mistake as rounding a grab reach the wrong way.
static func jump_airtime() -> float:
	var dt := 1.0 / 60.0
	var velocity := -JUMP_SPEED
	var height := 0.0
	var frames := 0
	while frames < 600:
		frames += 1
		var near_apex := absf(velocity) < APEX_THRESHOLD
		var scale := APEX_GRAVITY_SCALE if near_apex else 1.0
		velocity = minf(velocity + GRAVITY * scale * dt, MAX_FALL_SPEED)
		height += velocity * dt
		if height >= 0.0:
			break
	return float(frames) * dt


## Horizontal distance a full-speed running jump covers over that airtime.
static func run_jump_reach() -> float:
	return RUN_SPEED * jump_airtime()


## The widest flat gap, in tiles, that levels may be authored with.
##
## Deliberately a conservative floor, not the true limit. It is measured
## between the two positions the character can comfortably occupy: taking off
## from the ledge lip with half the body still over solid ground, and landing
## as soon as the far edge of the body is over the landing tile. A player who
## runs to the very edge and releases at the perfect frame can do better —
## `LevelReachability.measure_reach()` reports that real envelope, and
## tests/level_envelope_test.gd holds this value inside it. Authoring to the
## cautious number is what keeps a generated gap a jump rather than a stunt.
static func gap_tiles() -> int:
	var takeoff := TILE * 0.5
	var landing := TILE * 0.5 - BODY_WIDTH * 0.5
	return floori((run_jump_reach() + takeoff - landing) / TILE)


## --- derived feel numbers --------------------------------------------------
##
## These are not extra knobs: they are consequences of the ones above, written
## down so the landing thresholds and the dust can be reasoned about instead of
## guessed at. tests/tuning_feel_test.gd pins the relationships that matter.

## How fast a jump from flat ground is travelling when it lands again.
##
## The apex float is symmetric — the reduced-gravity band costs the same height
## on the way up as it gives back on the way down — so this is exactly
## JUMP_SPEED, independent of APEX_THRESHOLD and APEX_GRAVITY_SCALE.
static func flat_jump_land_speed() -> float:
	return minf(JUMP_SPEED, MAX_FALL_SPEED)


## Landing speed for a jump that comes down `tiles` lower than it started.
static func land_speed_after_drop(tiles: float) -> float:
	var v2 := JUMP_SPEED * JUMP_SPEED + 2.0 * GRAVITY * tiles * TILE
	return minf(sqrt(v2), MAX_FALL_SPEED)


## 0 for a weightless touchdown, 1 for the hardest landing the game can
## produce. The art and the dust both scale off this so they agree.
static func impact_weight(impact_speed: float) -> float:
	var span := maxf(1.0, MAX_FALL_SPEED - flat_jump_land_speed() * 0.5)
	return clampf((impact_speed - flat_jump_land_speed() * 0.5) / span, 0.0, 1.0)
