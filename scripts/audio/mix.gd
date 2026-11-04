class_name Mix
extends RefCounted
## The mix's gain law, in one place: what the music bus is set to, how a duck
## pulls it down and lets it back, how loud the drive stem is at a given
## intensity, and what a mode does to all of it.
##
## Two things apply this law. AudioDirector applies it to the live AudioServer
## a frame at a time; MixRender applies it to sample buffers offline, so that a
## test can measure how far a sword stands above the music on a machine with
## no audio device. If the two kept their own copies, the measurement would be
## of a mixer the game does not have -- the bug CLAUDE.md warns about for the
## jump arc, moved into audio. So neither does: both read these.
##
## ## Why the music sits where it does
##
## Measured before this file existed (docs/audio.md, "The mix"): the music's
## RMS was within a decibel of the sound effects' over a fight, a wound on a
## guard stood 1.3 dB above it on a phone, and the duel had no combat sounds at
## all. The owner's report -- the music is annoying, the swords and the deaths
## cannot be heard -- was the numbers, heard. The music now sits under a fixed
## trim that the player's fader cannot undo, so a settings file saved at the
## old default still gets the quieter bed; every combat cue ducks it; and a
## duel, which is two people listening for steel, takes it lower again and
## leaves the drum out.

## Under the player's fader, always. A fader at the old default of 0.65 was
## -3.7 dB; with this and the new default the bed is about 6 dB lower before
## the drone stopped buzzing (Music.DRONE_LOWPASS), and further on a phone.
const MUSIC_TRIM_DB := -4.0

## How fast the music climbs back after a duck, in dB per second.
const DUCK_RECOVERY := 11.0
## How long a duck holds at its full depth before it starts to recover. Long
## enough to cover the body of a blow, so the music does not swell back into
## the ring of the steel it was pulled down for.
const DUCK_HOLD := 0.18

## Below this the drive stem is switched off rather than left at -60 dB.
const DRIVE_FLOOR := 0.02

const MOOD_DEFAULT := &""
const MOOD_ADVENTURE := &"adventure"
const MOOD_DUEL := &"duel"

## mood -> [trim in dB on top of everything else, the most the drive stem may
## be raised]. The default is the menus' and the adventure's; a duel is
## quieter and has no drum, because the duel's rhythm is the exchange.
const MOODS := {
	MOOD_DEFAULT: [0.0, 1.0],
	MOOD_ADVENTURE: [0.0, 1.0],
	MOOD_DUEL: [-5.0, 0.0],
}
## How fast a change of mood moves the music, in dB per second.
const MOOD_RAMP := 6.0


static func mood_db(mood: StringName) -> float:
	return float((MOODS.get(mood, MOODS[MOOD_DEFAULT]) as Array)[0])


static func mood_intensity_cap(mood: StringName) -> float:
	return float((MOODS.get(mood, MOODS[MOOD_DEFAULT]) as Array)[1])


## The music bus, in dB: the player's fader, the fixed trim, the mood and the
## duck.
static func music_db(fader_db: float, mood_trim_db: float, duck_db: float) -> float:
	return fader_db + MUSIC_TRIM_DB + mood_trim_db - duck_db


## The drive stem's own trim at an intensity of 0..1.
static func drive_db(intensity: float) -> float:
	if intensity <= DRIVE_FLOOR:
		return -60.0
	return maxf(-60.0, linear_to_db(intensity))


## One step of a duck's life: [depth, hold] after `delta` seconds.
static func duck_step(depth: float, hold: float, delta: float) -> Vector2:
	if depth <= 0.0:
		return Vector2.ZERO
	var left := maxf(0.0, hold - delta)
	if left > 0.0:
		return Vector2(depth, left)
	return Vector2(maxf(0.0, depth - DUCK_RECOVERY * delta), 0.0)
