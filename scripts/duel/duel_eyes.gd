class_name DuelEyes
extends RefCounted
## The computer opponent's reaction time, as a ring of remembered frames.
##
## After every step the driver shows the match to `record()`, which copies what
## a player could see of it (DuelView.Body and DuelView.Sword, never an input
## bit) into a Glance and keeps the last few. `view(seat, delay)` then builds
## what the brain may decide on: its own fighter from the newest glance, and
## everything else from the one `delay` frames back.
##
## WHY A RING OF COPIES AND NOT A DELAYED POINTER. A reaction time is "acts on
## what it saw N frames ago". The honest way to have that is to have what it
## saw, frozen, and to hand over the old one. Reading the live match and
## subtracting N frames of motion would be a guess at the past made with the
## present in hand, and the present is exactly what the brain must not have.
##
## WHY THE HUMAN'S CURRENT FRAME CANNOT LEAK. The driver asks the brain for the
## next frame's bits before it steps that frame, and the newest glance is of
## the frame before. The human's buttons for the frame being decided have not
## been read yet when the brain is asked; their buttons for the frame before
## are in the glance only as what they did to the fighter, which is on screen.
## tests/unit/test_duel_cpu_seat.gd changes the human's input on one frame and
## holds the brain's answers to the same bits for the whole reaction time.

## The longest reaction any level asks for, plus the newest frame.
const DEPTH := 64


## One stepped frame, as the screen showed it.
class Glance:
	extends RefCounted

	var frame := 0
	var phase := 0
	var leader := -1
	var bodies: Array[DuelView.Body] = []
	var swords: Array[DuelView.Sword] = []
	var respawn := PackedFloat64Array([0.0, 0.0])
	var tuning: DuelTuning


var _ring: Array[Glance] = []
var _strip: ZoneStrip


## Forget everything seen: a rematch, or a new match.
func forget() -> void:
	_ring.clear()


## Copies what can be seen of `fight` after a step. Only the real fighter can
## be seen; a match on the placeholder shows nothing, and the brain then holds
## still rather than guessing.
func record(fight: DuelMatch) -> void:
	_strip = fight.strip
	var glance := Glance.new()
	glance.frame = fight.frame
	glance.phase = int(fight.phase)
	glance.leader = fight.leader_slot()
	glance.respawn = PackedFloat64Array([fight.respawn_left(0), fight.respawn_left(1)])
	for seat: DuelSeat in fight.seats:
		var fighter := seat.node as Fighter
		if fighter == null:
			return
		glance.tuning = fighter.tuning
		glance.bodies.append(DuelView.Body.of(fighter))
		if not fighter.blade.is_held():
			glance.swords.append(DuelView.Sword.of(fighter.blade))
	_ring.append(glance)
	if _ring.size() > DEPTH:
		_ring.pop_front()


func seen() -> int:
	return _ring.size()


## What seat `seat` may decide its next frame on: itself as of the newest
## glance, the rest as of `delay` frames before the frame being decided. A
## delay of one is the newest glance; there is no delay of zero, because the
## frame being decided has not happened. Null until something has been seen.
func view(seat: int, delay: int) -> DuelView:
	if _ring.is_empty():
		return null
	var newest := _ring[_ring.size() - 1]
	var back := clampi(delay, 1, DEPTH)
	var old := _ring[maxi(0, _ring.size() - back)]
	if old.bodies.size() < 2 or newest.bodies.size() < 2:
		return null

	var out := DuelView.new()
	out.seat = seat
	out.frame = newest.frame
	out.age = newest.frame - old.frame + 1
	out.me = newest.bodies[seat]
	out.them = old.bodies[1 - seat]
	out.swords = old.swords
	out.phase = old.phase
	out.leader = old.leader
	out.their_respawn = old.respawn[1 - seat]
	out.strip = _strip
	out.tuning = newest.tuning
	return out
