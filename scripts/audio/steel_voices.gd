class_name SteelVoices
extends RefCounted
## The recipes for a fight's steel and its deaths: the clash, the disarm, the
## kill, and the blow both deaths open on.
##
## Part of the catalogue in every way that matters -- their spec rows and their
## `match` arms are in Voices, and Voices.build_buffer() puts them through the
## same chain as every other voice. They live in their own file because they
## are one family, written together against one measurement (MixRender, as a
## phone plays them; docs/audio.md, "The mix"), and because the catalogue had
## passed the thousand lines gdlint holds a file to. Moving the threshold would
## have argued about the build, not about the code.


## The front of a killing blow, shared by `kill` and `die` so the two deaths
## open on the same sound: an edge tearing in (a short bright band), the cut
## (a wet band of noise at 0.5-1.4 kHz, the range a phone speaker is loudest
## in) and the body taking it (a thump with its own second harmonic, because
## the thump alone is below what a phone can play).
static func blow(buf: PackedFloat32Array, rate: int, seed_value: int, amp: float) -> void:
	Synth.add_noise(buf, {
		"rate": rate, "len": 0.03, "cutoff": 3800.0, "cutoff_end": 1900.0,
		"q": 1.2, "decay": 0.024, "curve": 2.0, "amp": 0.55 * amp, "seed": seed_value,
	})
	Synth.add_noise(buf, {
		"rate": rate, "start": 0.004, "len": 0.17, "cutoff": 1400.0,
		"cutoff_end": 520.0, "q": 1.7, "decay": 0.14, "curve": 2.2,
		"amp": 0.7 * amp, "seed": seed_value + 1,
	})
	Synth.add_tone(buf, {
		"rate": rate, "len": 0.2, "freq": 150.0, "freq_end": 70.0,
		"sweep_curve": 0.7, "attack": 0.002, "decay": 0.18, "curve": 2.2,
		"amp": 0.5 * amp,
	})
	Synth.add_tone(buf, {
		"rate": rate, "len": 0.13, "freq": 320.0, "freq_end": 200.0,
		"shape": Synth.SHAPE_SQUARE, "duty": 0.4, "attack": 0.002,
		"decay": 0.11, "curve": 2.4, "amp": 0.18 * amp,
	})


## Blade on blade in the duel, and neither gives. Brighter and harder than
## sword_hit, which is steel finding steel in the adventure: a crack, a clank
## in the 1-2 kHz band so a phone has it, and four inharmonic partials that
## ring for a fifth of a second and stop. No tail: the next exchange is a
## few frames away and must not land in this one's ring.
static func clash(rate: int, seed_value: int) -> PackedFloat32Array:
	var buf := Synth.buffer(0.3, rate)
	Synth.add_noise(buf, {
		"rate": rate, "len": 0.02, "cutoff": 5200.0, "band": "high", "q": 0.7,
		"decay": 0.015, "curve": 1.8, "amp": 0.55, "seed": seed_value,
	})
	Synth.add_noise(buf, {
		"rate": rate, "len": 0.06, "cutoff": 1800.0, "cutoff_end": 950.0,
		"q": 2.2, "decay": 0.05, "curve": 2.4, "amp": 0.5, "seed": seed_value + 1,
	})
	var partials := [1480.0, 2210.0, 3020.0, 4190.0]
	var gains := [0.42, 0.34, 0.22, 0.1]
	for i: int in partials.size():
		Synth.add_tone(buf, {
			"rate": rate, "len": 0.28, "freq": float(partials[i]),
			"freq_end": float(partials[i]) * 0.99, "attack": 0.001,
			"decay": 0.22 - 0.04 * float(i), "curve": 2.8, "amp": float(gains[i]),
		})
	Synth.add_tone(buf, {
		"rate": rate, "len": 0.08, "freq": 640.0, "freq_end": 520.0,
		"shape": Synth.SHAPE_TRIANGLE, "attack": 0.001, "decay": 0.06,
		"curve": 2.4, "amp": 0.3,
	})
	return buf


## The sword struck out of a hand: a clash with more weight behind it and a
## lower ring, then the blade landing -- two dry iron ticks on stone, which is
## what tells the ear the sword has gone and is on the floor.
static func disarm(rate: int, seed_value: int) -> PackedFloat32Array:
	var buf := Synth.buffer(0.62, rate)
	Synth.add_noise(buf, {
		"rate": rate, "len": 0.025, "cutoff": 4600.0, "band": "high", "q": 0.7,
		"decay": 0.02, "curve": 1.8, "amp": 0.55, "seed": seed_value,
	})
	Synth.add_noise(buf, {
		"rate": rate, "len": 0.08, "cutoff": 1500.0, "cutoff_end": 700.0,
		"q": 1.8, "decay": 0.07, "curve": 2.2, "amp": 0.5, "seed": seed_value + 1,
	})
	var partials := [1120.0, 1690.0, 2380.0]
	var gains := [0.45, 0.32, 0.18]
	for i: int in partials.size():
		Synth.add_tone(buf, {
			"rate": rate, "len": 0.34, "freq": float(partials[i]),
			"freq_end": float(partials[i]) * 0.97, "attack": 0.001,
			"decay": 0.3 - 0.05 * float(i), "curve": 2.6, "amp": float(gains[i]),
		})
	for i: int in 2:
		var at := 0.36 + 0.11 * float(i)
		Synth.add_pluck(buf, {
			"rate": rate, "start": at, "len": 0.1, "freq": 1900.0 + 700.0 * float(i),
			"decay": 0.06, "brightness": 0.95, "amp": 0.36 - 0.1 * float(i),
			"seed": seed_value + 3 + i, "release": 0.03,
		})
		Synth.add_noise(buf, {
			"rate": rate, "start": at, "len": 0.03, "cutoff": 2600.0, "q": 0.9,
			"decay": 0.02, "curve": 2.0, "amp": 0.24 - 0.08 * float(i),
			"seed": seed_value + 7 + i,
		})
	return buf


## A kill, in either mode: the blow, then the body going down -- the first
## two notes of the death figure (D, then the half step to D flat) on the
## same saturated reed, and the fall onto stone. Shorter than `die` by a
## second, because in a duel it comes every few seconds and in the adventure
## it is the prince's moment, not the guard's.
static func kill(rate: int, seed_value: int) -> PackedFloat32Array:
	var buf := Synth.buffer(0.72, rate)
	blow(buf, rate, seed_value, 1.0)
	var steps := [293.66, 277.18]
	for i: int in steps.size():
		Synth.add_tone(buf, {
			"rate": rate, "start": 0.1 + 0.13 * float(i), "len": 0.3,
			"freq": float(steps[i]), "freq_end": float(steps[i]) * 0.94,
			"shape": Synth.SHAPE_SQUARE, "duty": 0.3, "attack": 0.008,
			"decay": 0.26, "curve": 2.6, "amp": 0.2 - 0.04 * float(i),
			"vibrato_hz": 5.5, "vibrato_cents": 22.0,
		})
	# The body on the floor.
	Synth.add_noise(buf, {
		"rate": rate, "start": 0.42, "len": 0.14, "cutoff": 1000.0,
		"cutoff_end": 320.0, "q": 1.0, "decay": 0.12, "curve": 2.4, "amp": 0.34,
		"seed": seed_value + 5,
	})
	Synth.add_tone(buf, {
		"rate": rate, "start": 0.42, "len": 0.14, "freq": 130.0, "freq_end": 62.0,
		"decay": 0.12, "curve": 2.2, "amp": 0.36,
	})
	return buf
