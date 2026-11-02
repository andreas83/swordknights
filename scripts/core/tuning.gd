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
const GROUND_ACCEL := 520.0
const GROUND_FRICTION := 760.0
const AIR_ACCEL := 340.0
const AIR_FRICTION := 150.0
const TURN_TIME := 0.09

# Vertical motion
const GRAVITY := 900.0
const MAX_FALL_SPEED := 330.0
const JUMP_SPEED := 252.0
const JUMP_CUT_MULTIPLIER := 0.42
const APEX_GRAVITY_SCALE := 0.72
const APEX_THRESHOLD := 36.0

# Forgiveness windows
const COYOTE_TIME := 0.1
const JUMP_BUFFER := 0.14

# Ledges
const GRAB_PROBE_Y := 6.0
const GRAB_REACH := 3.0
const HANG_HOLD_TIME := 0.08
const CLIMB_UP_TIME := 0.34
const MAX_GRAB_FALL_SPEED := 260.0

# Ladders
const LADDER_SPEED := 48.0

# Combat and damage
const MAX_HEALTH := 3
const INVULNERABLE_TIME := 1.1
const KNOCKBACK_X := 90.0
const KNOCKBACK_Y := 150.0
const ATTACK_TIME := 0.28
const ATTACK_REACH := 14.0
const ATTACK_HEIGHT := 14.0

# Landing
const SOFT_LAND_SPEED := 190.0
const HARD_LAND_SPEED := 300.0
const LAND_RECOVER_TIME := 0.18

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
