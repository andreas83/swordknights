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
#
# None of these feed the traversal grammar, and that is a fact about the
# proof rather than a hope: LevelReachability moves between ladder cells as
# discrete steps whatever the speed, and offers no ladder jump at all (its
# docstring lists that among the moves it deliberately leaves out). So a
# retune here can make a proved level faster to climb or easier to leave, and
# can never make it unprovable or prove a level the player cannot finish.
#
## Climb speed, up and down. Was 48 -- three tiles a second, so the feel lab's
## seven-tile ladder took longer than walking the whole lab. Now a run's pace:
## a ladder is a corridor stood on its end, and a corridor walked at half pace
## is a wait.
const LADDER_SPEED := 88.0
## A jump off the rungs rises this share of a floor jump. Less than a full
## jump because there is no floor to push from; enough to clear the rung row.
const LADDER_JUMP_SCALE := 0.82
## After a ladder jump the hands stay off every ladder this long. The thumb is
## nearly always still holding the stick up or down when it taps JUMP, and
## without this the very next frame put the prince back on the rungs. Long
## enough to leave the column sideways; short enough that a straight-up hop
## still catches the ladder again on the way down.
const LADDER_REGRAB_TIME := 0.3

# Combat and damage
const MAX_HEALTH := 3
const INVULNERABLE_TIME := 0.9
const KNOCKBACK_X := 90.0
const KNOCKBACK_Y := 150.0
const ATTACK_TIME := 0.24
const ATTACK_REACH := 14.0
const ATTACK_HEIGHT := 14.0
## The air slash is the ground swing's timing -- ATTACK_TIME, the same live
## window, so one swing reads the same wherever it is thrown -- on a steeper
## arc whose band runs from the chest to 4 px below the feet. That depth is
## what lets a tapped hop (about 21 px) cut a guard standing in front of it
## for the whole live window; at 18 px the window passed over his head. It
## changes no velocity (Player._steer() says why), so it adds nothing to the
## grammar.
const AIR_SLASH_HEIGHT := 21.0

# The two specials. Like the air slash, neither feeds the grammar: the plunge
# only ever drops straight down, which no level needs and every fall already
# covers, and the parry does not move the prince at all. LevelReachability
# offers neither.

## THE PLUNGE: down + SWORD in a jump or a fall. The run is given up, the
## point goes under the feet and the body drops at MAX_FALL_SPEED. Its point
## reaches this far below the feet, so it finds a guard's head a frame or two
## before the boots would.
const PLUNGE_REACH := 8.0
## The blade bitten into the floor after a plunge that met stone instead of a
## guard. Longer than a guard's raise minus the sword's lead
## (tests/unit/test_specials.gd), so a plunge that misses in front of him
## cannot be swung out of: that is its price.
const PLUNGE_RECOVER := 0.42
## The share of JUMP_SPEED a stomp or a landed plunge springs back with.
const STOMP_BOUNCE := 0.68

## THE PARRY: up + SWORD on the ground. The blade goes up over the head, where
## the sentinel's cut comes from. It turns a cut only inside PARRY_ACTIVE, and
## the rest of PARRY_TIME is a recovery the cut can still land in, so a parry
## thrown up the moment the raise starts is down again when the blade arrives.
## The swing is the answer to a raise caught early; the parry is the answer to
## one caught late.
const PARRY_TIME := 0.4
const PARRY_ACTIVE := 0.2

# The backstep. A third move made of the stick and SWORD, and the only one of
# the three that moves the prince along the floor, so it is the one that had
# to be kept out of the grammar on purpose: it is ground-only, it stops at the
# lip of any drop the way a careful step does (Player._careful()), and
# so it cannot carry him over a gap of any width. LevelReachability offers it
# nowhere. tests/unit/test_backstep.gd pins every number below against
# Patrol's raise, cut and opening, the way test_specials.gd pins the parry.

## THE BACKSTEP: back + SWORD on the ground. The whole move, slide and
## recovery: nothing comes out of it -- no swing, no jump, no turn, no second
## backstep -- until it is over. 27 frames, which is what makes it the move
## that SURVIVES the exchange where the parry wins it: from a backstep that
## needed its window, this plus the run back into reach and the swing's lead
## is longer than the guard's opening, so the cut he dodged costs the guard
## nothing.
const BACKSTEP_TIME := 0.45
## How long the feet are moving. The rest of BACKSTEP_TIME is the recovery.
const BACKSTEP_SLIDE := 0.2
## The speed the slide starts at, falling off linearly to nothing at
## BACKSTEP_SLIDE. Gives backstep_distance(), 22.75 px, about 1.4 tiles: from
## where a guard raises, four times the step out of his cut, and enough ground
## that the run back in costs his whole opening (test_backstep.gd).
const BACKSTEP_SPEED := 210.0
## A guard's cut from the FRONT does not land for this long from the first
## frame. Longer than Patrol.STRIKE_TIME, so a backstep with its back to a
## wall can outlast the whole cut; shorter than Patrol.WINDUP_TIME, so one
## thrown on sight with nowhere to go is over before the blade arrives.
const BACKSTEP_ACTIVE := 0.25
## After a backstep, the stick and SWORD cannot make another one for this long
## (from the end of the first). Without it a held stick and a mashed button
## chain them, and a chain retreats faster than a walk with the window up
## twice a second.
const BACKSTEP_REARM := 0.2
## How long after the stick turned him on the spot a SWORD press still reads
## the stick against the way he faced BEFORE that turn, and takes the turn
## back. A thumb does not land the stick and the button on the same frame,
## and standing or walking, the stick going back turns him at once; without
## this, back-then-SWORD would turn him and swing away from the guard. Six
## frames: as long as a planted TURN takes, so an on-the-spot turn is never
## more final than a running one.
const BACKSTEP_READ := 0.1

# Landing.
#
# Both thresholds sit above flat_jump_land_speed(), which is the whole point:
# at 190 every single jump ended in a recovery lockout, so running and jumping
# felt like wading. Now a jump from flat ground lands clean, one extra tile of
# drop costs a short recovery and two tiles thump.
const SOFT_LAND_SPEED := 265.0
const HARD_LAND_SPEED := 330.0
const LAND_RECOVER_TIME := 0.12

# The fatal fall.
#
# The owner's rule (docs/campaign.md, "Decided by the owner"): a fall of ten
# tiles or more kills. That is twice the deepest drop a level may ask for --
# five, because the camera shows about 5.6 tiles under the feet and no
# landing may be out of frame at take-off ("No blind jumps") -- so the rule
# never ends a route, only a mistake.
#
# It is a HEIGHT, and it cannot be a landing speed. A fall from rest reaches
# MAX_FALL_SPEED terminal_fall_height() below where it started, which at 60 Hz
# is five tiles to the pixel: the deepest drop a level is allowed and a drop
# that should kill land at the same 360 px/s, and land_speed_after_drop(5)
# equals land_speed_after_drop(10). A speed threshold would kill on every
# intended five-tile drop or on no drop at all. What tells them apart is how
# far the feet came down from where the body last stopped rising -- the apex,
# so a jump that peaks and falls ten tiles counts -- and that is what Player
# measures and LevelReachability prunes, both through is_fatal_fall().
#
# Raising MAX_FALL_SPEED until terminal speed came only at ten tiles (about
# 540 px/s) was the alternative, and was turned down. The plunge drops at that
# speed and is timed against a guard's raise (tests/unit/test_specials.gd);
# impact_weight() and GameCamera.fall_lead() are both scaled to it, so every
# landing the game has today would read lighter and every fall would be led
# less. One constant would have retuned three systems to state one rule.
const FATAL_FALL_TILES := 10
## How far under fatal_fall_height() a fall still counts. A ten-tile drop off
## a ledge is exactly 160 px in the proof's arithmetic, but the body rests a
## few hundredths of a pixel off the floor (the physics engine's margin) at
## both ends, so a line drawn at exactly 160 would fall on one side or the
## other by rounding. Half a pixel is far below anything a level can express
## and far above that noise, so both the player and the proof see the line at
## ten tiles.
const FALL_SLACK := 0.5

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


## --- the fatal fall ----------------------------------------------------------
##
## FATAL_FALL_TILES and the block above it say why this is a height. These are
## the only places the rule is computed: Player and LevelReachability call
## is_fatal_fall(), and tests/unit/test_fatal_fall.gd pins the rest.

## The fall, in pixels from the apex to the feet at touchdown, that kills.
static func fatal_fall_height() -> float:
	return float(FATAL_FALL_TILES) * TILE


## Whether a landing `height` pixels below the apex of its fall kills. The one
## comparison: the player dies by it and the proof prunes by it, so they
## cannot disagree about where the line is.
static func is_fatal_fall(height: float) -> bool:
	return height >= fatal_fall_height() - FALL_SLACK


## How far a body falls from rest before it reaches MAX_FALL_SPEED, in pixels.
## Every landing from deeper than this hits at the same speed, which is the
## argument for the rule being a height (FATAL_FALL_TILES).
##
## Integrated at 60 Hz with the apex band's reduced gravity, as jump_airtime()
## is: the closed form says 4.6 tiles, the simulation falls 5.0.
static func terminal_fall_height() -> float:
	var dt := 1.0 / 60.0
	var velocity := 0.0
	var height := 0.0
	while velocity < MAX_FALL_SPEED:
		var scale := APEX_GRAVITY_SCALE if absf(velocity) < APEX_THRESHOLD else 1.0
		velocity = minf(velocity + GRAVITY * scale * dt, MAX_FALL_SPEED)
		height += velocity * dt
	return height


## The deepest drop, in whole tiles, that a full jump can be taken off and
## survived: the jump's rise above the ledge counts toward the fall, so this
## is FATAL_FALL_TILES less the hop and a little more (seven, against the nine
## a walk off the same ledge survives). max_jump_rise() is the closed form,
## which overstates the 60 Hz apex by about 2 px -- the safe side for a number
## that says how deep a jump may go.
static func safe_jump_drop_tiles() -> int:
	var drop := 0
	while not is_fatal_fall(float(drop + 1) * TILE + max_jump_rise()):
		drop += 1
	return drop


## The backstep's speed `t` seconds into it: BACKSTEP_SPEED falling off in a
## straight line to nothing at BACKSTEP_SLIDE. Player moves by this and
## backstep_distance() integrates it, so the two cannot disagree.
static func backstep_speed(t: float) -> float:
	return BACKSTEP_SPEED * maxf(0.0, 1.0 - t / BACKSTEP_SLIDE)


## How far a backstep on open floor carries the body, in pixels.
##
## Integrated a frame at a time, as jump_airtime() is and for the same reason:
## the simulation is a fixed 60 Hz step, and the frame the move starts on
## moves at t = 0. That is the ground the move costs, so tests pin it between
## one tile and a tile and a half.
static func backstep_distance() -> float:
	var dt := 1.0 / 60.0
	var distance := 0.0
	var t := 0.0
	while t < BACKSTEP_SLIDE:
		distance += backstep_speed(t) * dt
		t += dt
	return distance


## 0 for a weightless touchdown, 1 for the hardest landing the game can
## produce. The art and the dust both scale off this so they agree.
static func impact_weight(impact_speed: float) -> float:
	var span := maxf(1.0, MAX_FALL_SPEED - flat_jump_land_speed() * 0.5)
	return clampf((impact_speed - flat_jump_land_speed() * 0.5) / span, 0.0, 1.0)
