class_name CreatureVoices
extends RefCounted
## The recipes for the animals' throats: the Caracal's hiss and yowl, and the
## owl's hoot.
##
## Part of the catalogue in every way that matters -- their spec rows and their
## `match` arms are in Voices, and Voices.build_buffer() puts them through the
## same chain as every other voice -- as SteelVoices is. They live here because
## they are one family, the only voices in the game that are not a person, a
## blade or a stone, and because the catalogue had passed the thousand lines
## gdlint holds a file to again. Moving the threshold would have argued about
## the build, not about the code.


## A cat's hiss: breath through teeth, noise in a narrow band round 3 kHz that
## swells in fast and is cut off rather than let go. Quiet in the mix -- the
## crouch is told by its pose first -- but unlike anything a person does, so a
## cat about to pounce off the screen's edge is still a cat about to pounce.
static func hiss(rate: int, seed_value: int) -> PackedFloat32Array:
	var buf := Synth.buffer(0.26, rate)
	Synth.add_noise(buf, {
		"rate": rate, "len": 0.25, "cutoff": 2700.0, "cutoff_end": 3300.0,
		"q": 2.2, "attack": 0.03, "decay": 0.22, "curve": 1.2, "amp": 0.5,
		"seed": seed_value,
	})
	Synth.add_noise(buf, {
		"rate": rate, "len": 0.22, "cutoff": 5200.0, "band": "high", "q": 0.8,
		"attack": 0.04, "decay": 0.18, "curve": 1.6, "amp": 0.16, "seed": seed_value + 3,
	})
	return buf


## The cat's death: one short yowl, a reedy square wave bent up and dropped,
## with a throat of noise under it. Dry, like everything here, and over in
## less than half a second: it marks a kill, it does not mourn it.
static func yowl(rate: int, seed_value: int) -> PackedFloat32Array:
	var buf := Synth.buffer(0.42, rate)
	Synth.add_tone(buf, {
		"rate": rate, "len": 0.16, "freq": 540.0, "freq_end": 860.0, "sweep_curve": 0.6,
		"shape": Synth.SHAPE_SQUARE, "duty": 0.3, "attack": 0.02, "decay": 0.16,
		"curve": 0.8, "amp": 0.26, "vibrato_hz": 11.0, "vibrato_cents": 40.0,
	})
	Synth.add_tone(buf, {
		"rate": rate, "start": 0.14, "len": 0.26, "freq": 860.0, "freq_end": 380.0,
		"sweep_curve": 1.4, "shape": Synth.SHAPE_SQUARE, "duty": 0.3, "attack": 0.01,
		"decay": 0.25, "curve": 1.8, "amp": 0.3, "vibrato_hz": 9.0, "vibrato_cents": 55.0,
	})
	Synth.add_noise(buf, {
		"rate": rate, "len": 0.36, "cutoff": 1600.0, "cutoff_end": 700.0, "q": 1.3,
		"attack": 0.02, "decay": 0.32, "curve": 1.6, "amp": 0.2, "seed": seed_value,
	})
	Synth.one_pole(buf, 3400.0, false, rate)
	return buf


## The owl: two soft notes, the second lower and longer -- a sine with a
## slight fall, a breath of second harmonic and a little filtered air through
## it. Dry, like everything else: the call stops where the bird stops.
static func hoot(rate: int, seed_value: int) -> PackedFloat32Array:
	var buf := Synth.buffer(0.5, rate)
	var notes := [[0.0, 0.15, 410.0, 392.0], [0.21, 0.24, 368.0, 346.0]]
	for i: int in notes.size():
		var note: Array = notes[i]
		var start := float(note[0])
		var length := float(note[1])
		Synth.add_tone(buf, {
			"rate": rate, "start": start, "len": length, "freq": note[2], "freq_end": note[3],
			"attack": 0.035, "decay": length - 0.035, "curve": 1.4, "amp": 0.5,
		})
		Synth.add_tone(buf, {
			"rate": rate, "start": start, "len": length, "freq": float(note[2]) * 2.0,
			"freq_end": float(note[3]) * 2.0, "attack": 0.03, "decay": length * 0.6,
			"curve": 2.0, "amp": 0.05,
		})
		Synth.add_noise(buf, {
			"rate": rate, "start": start, "len": length, "cutoff": 900.0, "q": 1.4,
			"attack": 0.03, "decay": length - 0.03, "curve": 1.6, "amp": 0.07,
			"seed": seed_value + i,
		})
	return buf
