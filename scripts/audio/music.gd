class_name Music
extends RefCounted
## The score: one procedurally baked loop, in two stems.
##
## Mode and harmony. The loop is an Andalusian cadence — i / VII / VI / V, two
## bars each — walked down from D minor to the A that leads back to the top:
## Dm, C, B flat, A. Over it the melody uses Hijaz on D (D Eb F# G A Bb C), the
## Phrygian-dominant colour with the augmented second between Eb and F#, and
## the last two bars switch to Hijaz on A so the C sharp pulls the cadence
## round. That is the sound of the art direction: low sun, hard shadows, a mode
## that is not major and not minor.
##
## Instrumentation is all Synth: a plucked oud (Karplus-Strong), a sustained
## saw drone pair for the root and its fifth (lowpassed, see DRONE_LOWPASS), a
## frame drum built from a pitched membrane and a slap, and a reed doubling
## that only appears when the game raises the intensity.
##
## Two stems, not two mixes. `build_stems()` returns [bed, drive]: the bed is
## drone and oud and always plays, the drive adds the drum and the reed. The
## director cross-fades the drive by intensity, so raising the tension costs a
## volume ramp instead of a re-bake, and both stems share one loop length so
## they stay locked.
##
## Rate is 16 kHz on purpose. The loop is the largest resident sample in the
## game (about 0.85 MB per stem) and nothing in it lives above 5 kHz, so the
## full 22 kHz of the sound effects would be a megabyte of headroom spent on
## nothing.

const RATE := 16000
const BPM := 72.0
const BEATS_PER_BAR := 4
const BARS := 8
## Notes may ring past the end; the tail is folded back onto the head so the
## seam is a continuation rather than a cut.
const TAIL := 3.0

const TONIC := 293.66 # D4; the melody is written in semitones from here

## Bar -> chord root, in semitones from the tonic (an octave down is applied
## when the drone is voiced). i - VII - VI - V in D.
const CHORD_ROOTS := [0, 0, -2, -2, -4, -4, -5, -5]

## [bar, beat, semitone, amp, gate_in_beats]. Written out rather than
## generated: eight bars of data is cheaper to read, and to re-voice, than a
## generator with a taste parameter.
##
## Sparse on purpose. The first version had twenty-seven notes in the loop,
## eighth-note ornaments in every bar and the octave D on top, and a phone test
## called it annoying: a busy phrase that comes round every 27 seconds is a
## phrase the player learns by the third pass and hears as a nag from then on.
## This is the same contour at half the density -- fifteen notes, mostly long,
## nothing above the C sharp that turns the cadence -- with the end of each
## pair of bars left to the drone. The gaps are where the swords are heard.
const MELODY := [
	[0, 0.0, 0, 0.70, 3.0], [0, 3.0, 1, 0.40, 1.0],
	[1, 0.0, 4, 0.60, 2.0], [1, 2.0, 1, 0.45, 2.0],
	[2, 0.0, 10, 0.60, 2.0], [2, 2.0, 7, 0.45, 2.0],
	[3, 0.0, 8, 0.50, 3.0],
	[4, 0.0, 8, 0.60, 2.0], [4, 2.0, 5, 0.45, 2.0],
	[5, 0.0, 7, 0.50, 3.0],
	[6, 0.0, 7, 0.60, 2.0], [6, 2.0, 11, 0.50, 2.0],
	[7, 0.0, 8, 0.50, 1.0], [7, 1.0, 7, 0.55, 3.0],
]

## Bars where the reed doubles the melody, at pitch rather than an octave up:
## the octave put it at 600-1200 Hz, which is exactly where a phone speaker is
## loudest and exactly where the sword lives. Only the turn of the cadence.
const REED_BARS := [6, 7]

## Frame drum, in beats: dum is the low open stroke, tek the rim. One tek a
## bar, not three, and no shaker: the eighth-note hiss of the first version
## sat at 4-5 kHz the whole time the prince was moving, which on a phone is
## the loudest thing in the loop and the most tiring.
const DUM_BEATS := [0.0, 2.5]
const TEK_BEATS := [3.0]

## The drone and the moving root are saws, and a saw's harmonics run all the
## way up through the band a phone plays: on the device the drone was a buzz,
## not a floor. They are lowpassed here before they are mixed, which keeps the
## warmth on headphones and takes the buzz off the phone.
const DRONE_LOWPASS := 420.0


static func beat_seconds() -> float:
	return 60.0 / BPM


static func loop_seconds() -> float:
	return beat_seconds() * float(BEATS_PER_BAR * BARS)


static func loop_samples() -> int:
	return int(round(loop_seconds() * float(RATE)))


static func note_hz(semitones: float) -> float:
	return TONIC * pow(2.0, semitones / 12.0)


## [bed, drive] — both exactly one loop long, both loop-flagged.
static func build_stems(seed_value: int = 20250) -> Array[AudioStreamWAV]:
	var out: Array[AudioStreamWAV] = []
	out.append(Synth.to_wav(build_bed(seed_value), RATE, true))
	out.append(Synth.to_wav(build_drive(seed_value), RATE, true))
	return out


## Drone and oud: what the game sounds like when nothing is happening.
static func build_bed(seed_value: int = 20250) -> PackedFloat32Array:
	var beat := beat_seconds()
	var bar := beat * float(BEATS_PER_BAR)
	var buf := Synth.buffer(loop_seconds() + TAIL, RATE)
	var drone := Synth.buffer(loop_seconds() + TAIL, RATE)

	# A tanbur-style tonic that never moves, so the cadence is heard against a
	# fixed centre rather than as four unrelated chords.
	# Two saws four cents apart rather than one with vibrato: the beating is
	# the same slow movement, and a static sawtooth costs no sin() or pow() per
	# sample, which halves the time to bake the longest buffer in the game.
	for detune: float in [0.0, 0.04]:
		Synth.add_tone(drone, {
			"rate": RATE, "len": loop_seconds() + 1.2,
			"freq": note_hz(-12.0 + detune), "shape": Synth.SHAPE_SAW,
			"env": "asr", "attack": 1.4, "release": 1.4, "amp": 0.055,
		})

	# The moving root and its fifth, two bars at a time.
	for section: int in BARS / 2:
		var root: float = float(CHORD_ROOTS[section * 2])
		var start := float(section) * bar * 2.0
		Synth.add_tone(drone, {
			"rate": RATE, "start": start, "len": bar * 2.0 + 0.6,
			"freq": note_hz(root - 12.0), "shape": Synth.SHAPE_SAW,
			"env": "asr", "attack": 0.5, "release": 0.6, "amp": 0.16,
		})
		Synth.add_tone(drone, {
			"rate": RATE, "start": start + 0.05, "len": bar * 2.0 + 0.5,
			"freq": note_hz(root - 5.0), "shape": Synth.SHAPE_TRIANGLE,
			"env": "asr", "attack": 0.9, "release": 0.6, "amp": 0.09,
		})
	Synth.one_pole(drone, DRONE_LOWPASS, false, RATE)
	Synth.one_pole(drone, DRONE_LOWPASS, false, RATE)
	Synth.mix_into(buf, drone, 0.0, 1.0, RATE)

	for i: int in MELODY.size():
		var note: Array = MELODY[i]
		var at := float(note[0]) * bar + float(note[1]) * beat
		var gate := float(note[4]) * beat
		Synth.add_pluck(buf, {
			"rate": RATE, "start": at, "len": gate + 0.5,
			"freq": note_hz(float(note[2])), "decay": 0.8 + float(note[3]) * 0.5,
			"brightness": 0.72, "amp": float(note[3]) * 0.5,
			"release": 0.22, "seed": seed_value + i * 31,
		})
		# A short grace note a semitone below on the long notes: the
		# ornamentation is the genre, and it costs one extra pluck.
		if float(note[4]) >= 1.5:
			Synth.add_pluck(buf, {
				"rate": RATE, "start": maxf(0.0, at - 0.075), "len": 0.14,
				"freq": note_hz(float(note[2]) - 1.0), "decay": 0.2,
				"brightness": 0.6, "amp": float(note[3]) * 0.16,
				"release": 0.05, "seed": seed_value + 991 + i,
			})

	var folded := Synth.fold_tail(buf, loop_samples())
	Synth.remove_dc(folded)
	Synth.soft_clip(folded, 1.1)
	Synth.normalize(folded, 0.80)
	return folded


## Frame drum and the reed doubling: everything the intensity adds.
static func build_drive(seed_value: int = 20250) -> PackedFloat32Array:
	var beat := beat_seconds()
	var bar := beat * float(BEATS_PER_BAR)
	var buf := Synth.buffer(loop_seconds() + TAIL, RATE)

	for b: int in BARS:
		var bar_at := float(b) * bar
		for d: int in DUM_BEATS.size():
			_dum(buf, bar_at + float(DUM_BEATS[d]) * beat,
				0.9 if d == 0 else 0.7, seed_value + b * 7 + d)
		for t: int in TEK_BEATS.size():
			_tek(buf, bar_at + float(TEK_BEATS[t]) * beat,
				0.5, seed_value + b * 13 + t)

	for i: int in MELODY.size():
		var note: Array = MELODY[i]
		if not REED_BARS.has(int(note[0])):
			continue
		var at := float(note[0]) * bar + float(note[1]) * beat
		var gate := float(note[4]) * beat
		# A ney is mostly breath: a soft triangle with vibrato, plus a band of
		# noise riding the same envelope.
		Synth.add_tone(buf, {
			"rate": RATE, "start": at, "len": gate * 0.95,
			"freq": note_hz(float(note[2])),
			"shape": Synth.SHAPE_TRIANGLE, "env": "asr",
			"attack": 0.05, "release": 0.12, "amp": float(note[3]) * 0.22,
			"vibrato_hz": 4.6, "vibrato_cents": 28.0,
		})
		Synth.add_noise(buf, {
			"rate": RATE, "start": at, "len": gate * 0.9,
			"cutoff": note_hz(float(note[2])) * 2.0, "q": 1.6,
			"env": "asr", "attack": 0.06, "release": 0.12,
			"amp": float(note[3]) * 0.05, "seed": seed_value + 400 + i,
		})

	var folded := Synth.fold_tail(buf, loop_samples())
	Synth.remove_dc(folded)
	Synth.soft_clip(folded, 1.1)
	Synth.normalize(folded, 0.78)
	return folded


## The low open stroke: a membrane is a pitch that falls away fast.
static func _dum(buf: PackedFloat32Array, at: float, amp: float, seed_value: int) -> void:
	Synth.add_tone(buf, {
		"rate": RATE, "start": at, "len": 0.3, "freq": 98.0, "freq_end": 56.0,
		"sweep_curve": 0.55, "attack": 0.002, "decay": 0.26, "curve": 2.4,
		"amp": 0.55 * amp,
	})
	Synth.add_noise(buf, {
		"rate": RATE, "start": at, "len": 0.05, "cutoff": 900.0,
		"cutoff_end": 320.0, "q": 1.0, "decay": 0.04, "curve": 2.6,
		"amp": 0.2 * amp, "seed": seed_value,
	})


## The rim stroke: almost all noise, with just enough pitch to place it.
static func _tek(buf: PackedFloat32Array, at: float, amp: float, seed_value: int) -> void:
	Synth.add_noise(buf, {
		"rate": RATE, "start": at, "len": 0.08, "cutoff": 2100.0,
		"cutoff_end": 1100.0, "q": 1.3, "decay": 0.06, "curve": 3.0,
		"amp": 0.42 * amp, "seed": seed_value,
	})
	Synth.add_tone(buf, {
		"rate": RATE, "start": at, "len": 0.05, "freq": 420.0, "freq_end": 300.0,
		"decay": 0.04, "curve": 2.6, "amp": 0.16 * amp,
	})


## A continuous render of both stems for the previews: the same mix the
## director produces, with the intensity ramped so a listener hears the bed
## first and the drum arrive. Loops the stems rather than re-baking them.
static func render_excerpt(seconds: float, seed_value: int = 20250) -> PackedFloat32Array:
	var bed := build_bed(seed_value)
	var drive := build_drive(seed_value)
	var out := Synth.buffer(seconds, RATE)
	var n := out.size()
	var ramp_in := 10.0
	var ramp_out := 24.0

	for i: int in n:
		var t := float(i) / float(RATE)
		var intensity := clampf((t - ramp_in) / maxf(1.0, ramp_out - ramp_in), 0.0, 1.0)
		out[i] = bed[i % bed.size()] * 0.85 + drive[i % drive.size()] * 0.85 * intensity
	Synth.fade_edges(out, 0.05, 1.5, RATE)
	# Two stems at 0.8 peak sum past full scale; the game solves that with the
	# music bus fader, the preview has to solve it here.
	Synth.normalize(out, 0.92)
	return out
