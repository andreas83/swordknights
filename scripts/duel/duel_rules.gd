class_name DuelRules
extends RefCounted
## The few numbers and names the duel shares between its simulation, its
## network session and its screens.
##
## The fighter's own feel lives in scripts/duel/duel_tuning.gd, and the shape
## of the match -- initiative, the window, respawns, the gates -- lives with the
## state it belongs to in scripts/duel/match.gd. What is here is what more than
## one of those has to agree on.

## The simulation step. Fixed, never the frame's real delta: a duel that is a
## function of its inputs is one that can be replayed, tested and reconciled.
const DT := 1.0 / 60.0

## Both fighters stand on their marks while this runs down.
const COUNTDOWN_TIME := 1.25

## Seat names. Slot 0 starts on the left and faces right.
const SLOT_A := 0
const SLOT_B := 1
const DRAW := -1


static func slot_label(slot: int) -> String:
	match slot:
		SLOT_A:
			return "ONE"
		SLOT_B:
			return "TWO"
		_:
			return "DRAW"
