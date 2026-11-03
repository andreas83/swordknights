class_name DuelView
extends RefCounted
## Everything the computer opponent is allowed to know when it chooses one
## frame of input, and nothing else.
##
## The brain (scripts/duel/duel_brain.gd) is handed one of these per frame and
## is never handed the match, a fighter or a PlayerInput. That is the whole of
## its honesty, and it is structural rather than a promise: the brain has no
## reference through which it could read the human's buttons, so it cannot.
## tests/unit/test_duel_cpu_seat.gd holds the brain's surface to that.
##
## WHAT IS IN IT. What a player watching the screen sees: where each fighter
## is, which way they face, what they are doing and how far into it, the height
## of the blade, whether they hold one, where the loose and flying swords are,
## who has the initiative and how long a respawn has to run. Plus the level,
## which never changes and is drawn on the screen for both players alike.
##
## WHAT IS NOT. Any input bit, any press edge, any "about to": the human's
## buttons for the frame being decided have not been read when the brain is
## asked, and the fighter's own record of its last buttons (the press-edge
## memory in its snapshot) is never copied in here. Body is built field by
## field from the fighter's visible state for exactly that reason.
##
## TWO AGES. `me` is the brain's own fighter as of the last frame stepped: a
## player knows what their thumbs are doing without waiting to see it, and a
## jump over the moat timed off a picture of yourself a fifth of a second old
## would be a suicide, not a reaction. Everything else -- the other fighter,
## the swords, the initiative -- is `age` frames old. That age is the reaction
## time, and DuelEyes is what makes it so (scripts/duel/duel_eyes.gd).

## One fighter as the screen shows it.
class Body:
	extends RefCounted

	var seat := 0
	## Feet, in strip coordinates.
	var position := Vector2.ZERO
	var velocity := Vector2.ZERO
	var facing := 1
	## A Fighter.State, and the frame of it (1 on the frame it began).
	var state := 0
	var state_frame := 1
	## The blade's height, a DuelTuning.Stance.
	var stance := DuelTuning.Stance.MID
	## The combat matrix's column: the stance, or DuelTuning.DUCKED.
	var posture := DuelTuning.Stance.MID
	var armed := true
	var alive := true
	var grounded := true

	## A copy of what can be seen of `fighter`. Copied, not referenced: a view
	## that kept the fighter would be a view that saw it move.
	static func of(fighter: Fighter) -> Body:
		var body := Body.new()
		body.seat = fighter.id
		body.position = fighter.position
		body.velocity = fighter.velocity
		body.facing = fighter.facing
		body.state = int(fighter.state)
		body.state_frame = fighter.state_frame
		body.stance = fighter.stance
		body.posture = fighter.posture()
		body.armed = fighter.is_armed()
		body.alive = fighter.is_alive()
		body.grounded = fighter.grounded
		return body

	## Free to act: the four states that read input.
	func is_free() -> bool:
		return (
			state == Fighter.State.IDLE or state == Fighter.State.RUNNING
			or state == Fighter.State.JUMPING or state == Fighter.State.DUCKING
		)


## A sword that is not in anyone's hand: flying or lying on the floor.
class Sword:
	extends RefCounted

	var flying := false
	var position := Vector2.ZERO
	var velocity := Vector2.ZERO
	var stance := DuelTuning.Stance.MID
	## The seat that threw it, while it flies; -1 once it is lying anywhere.
	var thrown_by := -1

	static func of(record: DuelBlade) -> Sword:
		var sword := Sword.new()
		sword.flying = record.mode == DuelBlade.Mode.FLYING
		sword.position = record.position
		sword.velocity = record.velocity
		sword.stance = record.stance
		sword.thrown_by = record.thrown_by
		return sword


## The seat this view is for.
var seat := 0
## The frame the brain is choosing input for: the next one to be stepped.
var frame := 0
## How many frames old everything but `me` is. At least one.
var age := 1

var me: Body
var them: Body
## Swords out of hand, as seen `age` frames ago.
var swords: Array[Sword] = []

## A DuelMatch.Phase, as seen.
var phase := 0
## The seat with the initiative, or -1 for neutral, as seen.
var leader := -1
## Seconds until the other fighter is back, as seen; 0 when up.
var their_respawn := 0.0

## The level, which nobody's input changes and both players see whole.
var strip: ZoneStrip
## The fighter's movement profile: public numbers, the same for both seats.
var tuning: DuelTuning


func is_fighting() -> bool:
	return phase == DuelMatch.Phase.FIGHTING
