class_name DuelRules
extends RefCounted
## Every number that defines how a duel is scored, in one place.
##
## The character's own feel lives in scripts/core/tuning.gd and the block and
## stagger timings live with the states they belong to, at the bottom of
## scripts/player/player.gd. What is here is the match around the fight.
##
## A duel is first blood: one clean cut ends the round. That is a deliberate
## choice over a health bar — it makes every approach matter, it makes a block
## worth the commitment, and it reads instantly to someone watching.

## The simulation step. Fixed, never the frame's real delta: a duel that is a
## function of its inputs is one that can be replayed, tested and reconciled.
const DT := 1.0 / 60.0

const ROUNDS_TO_WIN := 3

## Both duellists stand on their marks while this runs down.
const COUNTDOWN_TIME := 1.25
## The pause on the kill, long enough to read who won and watch them fall.
const ROUND_OVER_TIME := 1.7
## Nobody wins by refusing to engage. A round that runs this long is a draw and
## scores for neither — so stalling costs you the match clock, not your opponent.
const ROUND_TIME_LIMIT := 75.0

const ARENA_PATH := "res://levels/arena_01.txt"
const PLAYER_SCENE := "res://scenes/player.tscn"

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
