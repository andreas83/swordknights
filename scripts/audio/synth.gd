class_name Synth
extends RefCounted
## The synthesis layer: oscillators, filtered noise, plucked strings, envelopes.
##
## This project ships no assets, and audio follows the same rule as the terrain
## atlas and the character art — every sound is computed from numbers. These
## helpers write float samples into a PackedFloat32Array; `to_wav()` bakes that
## buffer into an AudioStreamWAV once, at load time, so playback on a phone is
## a memcpy rather than a decode.
##
## Two rules make the voices testable:
##
## 1. Everything is deterministic. Noise comes from `Rng` (a seeded xorshift),
##    never from `randf()`, so the same parameters always produce byte-identical
##    samples. tests/audio_synth_test.gd depends on that.
## 2. Nothing is normalised implicitly. `normalize()` is called once per voice
##    with an explicit target peak, which is what keeps the relative loudness of
##    a footstep and a hard landing intact instead of flattening them.
##
## The sound design this serves: hard edges, dry decays, grit and gold. Short
## attacks, no reverb tails, noise that reads as sand on stone, metal that rings
## briefly and stops.

const RATE := 22050

const SHAPE_SINE := 0
const SHAPE_TRIANGLE := 1
const SHAPE_SQUARE := 2
const SHAPE_SAW := 3


## A seeded xorshift32. Deliberately not RandomNumberGenerator: this has to
## produce the same stream on every platform and every engine build, because
## the preview .wav files and the determinism test both pin it.
class Rng extends RefCounted:
	var _state: int

	func _init(seed_value: int = 1) -> void:
		_state = seed_value & 0xffffffff
		if _state == 0:
			_state = 0x9e3779b9

	func next_uint() -> int:
		var x := _state
		x ^= (x << 13) & 0xffffffff
		x ^= x >> 17
		x ^= (x << 5) & 0xffffffff
		_state = x & 0xffffffff
		return _state

	## 0.0 .. 1.0
	func unit() -> float:
		return float(next_uint()) / 4294967296.0

	## -1.0 .. 1.0
	func bipolar() -> float:
		return unit() * 2.0 - 1.0


## --- buffers ---------------------------------------------------------------

static func buffer(seconds: float, rate: int = RATE) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(maxi(1, int(round(seconds * float(rate)))))
	out.fill(0.0)
	return out


## --- envelopes -------------------------------------------------------------

## Percussive attack/decay. `curve` above 1 makes the tail drop away faster,
## which is what keeps a footstep from smearing into the next one.
static func env_ad(t: float, attack: float, decay: float, curve: float = 2.5) -> float:
	if t < 0.0:
		return 0.0
	if t < attack:
		return t / maxf(attack, 1e-6)
	var d := (t - attack) / maxf(decay, 1e-6)
	if d >= 1.0:
		return 0.0
	return pow(1.0 - d, curve)


## Attack / sustain / release, for drones and the wind bed.
static func env_asr(t: float, total: float, attack: float, release: float) -> float:
	if t < 0.0 or t > total:
		return 0.0
	var rise := 1.0 if attack <= 0.0 else minf(1.0, t / attack)
	var fall := 1.0
	if release > 0.0:
		fall = clampf((total - t) / release, 0.0, 1.0)
	return rise * fall


## Instantaneous frequency of an exponential sweep. `curve` bends the ramp:
## above 1 the pitch lingers at f0 and then drops away, which is how a sword
## reads as a whoosh rather than a slide whistle.
static func sweep(k: float, f0: float, f1: float, curve: float = 1.0) -> float:
	var x := pow(clampf(k, 0.0, 1.0), maxf(0.01, curve))
	return f0 * pow(maxf(f1, 1.0) / maxf(f0, 1.0), x)


## --- oscillators -----------------------------------------------------------

static func wave(shape: int, phase: float, duty: float = 0.5) -> float:
	var p := fposmod(phase, 1.0)
	match shape:
		SHAPE_TRIANGLE:
			return 4.0 * absf(p - 0.5) - 1.0
		SHAPE_SQUARE:
			return 1.0 if p < duty else -1.0
		SHAPE_SAW:
			return 2.0 * p - 1.0
		_:
			return sin(TAU * p)


## Adds an oscillator with an optional pitch sweep, vibrato and envelope.
##
## `env` picks the envelope: "ad" (percussive, the default) or "asr" (held for
## `len` with `attack` and `release` ramps) for drones and sustained reeds.
##
## cfg: start, len, freq, freq_end, sweep_curve, shape, duty, amp, attack,
##      decay, curve, release, env, vibrato_hz, vibrato_cents, phase, rate
static func add_tone(buf: PackedFloat32Array, cfg: Dictionary) -> void:
	var rate := int(cfg.get("rate", RATE))
	var length := float(cfg.get("len", 0.2))
	var start := int(round(float(cfg.get("start", 0.0)) * float(rate)))
	var count := int(round(length * float(rate)))
	var f0 := float(cfg.get("freq", 220.0))
	var f1 := float(cfg.get("freq_end", f0))
	var sweep_curve := float(cfg.get("sweep_curve", 1.0))
	var shape := int(cfg.get("shape", SHAPE_SINE))
	var duty := float(cfg.get("duty", 0.5))
	var amp := float(cfg.get("amp", 0.5))
	var attack := float(cfg.get("attack", 0.004))
	var decay := float(cfg.get("decay", length))
	var curve := float(cfg.get("curve", 2.5))
	var vib_hz := float(cfg.get("vibrato_hz", 0.0))
	var vib_cents := float(cfg.get("vibrato_cents", 0.0))
	var phase := float(cfg.get("phase", 0.0))
	var held := String(cfg.get("env", "ad")) == "asr"
	var release := float(cfg.get("release", minf(0.08, length * 0.25)))

	# A drone is minutes of samples at one pitch, so the sweep and vibrato maths
	# are hoisted out of the loop when they are not in use. Leaving pow() calls
	# in the inner loop made baking the music take seconds.
	var sweeping := not is_equal_approx(f0, f1)
	var wobbling := vib_hz > 0.0 and not is_zero_approx(vib_cents)
	var dt := 1.0 / float(rate)
	var step := f0 * dt
	var span := float(maxi(1, count - 1))
	var size := buf.size()

	# `wave()` and the envelope are inlined below. They are one-line functions,
	# but a GDScript call costs more than the arithmetic it wraps and this loop
	# runs for every sample of a 27-second music stem.
	for i: int in count:
		var idx := start + i
		if idx >= size:
			break
		var t := float(i) * dt
		if sweeping or wobbling:
			var freq := sweep(float(i) / span, f0, f1, sweep_curve) if sweeping else f0
			if wobbling:
				freq *= pow(2.0, vib_cents / 1200.0 * sin(TAU * vib_hz * t))
			step = freq * dt
		phase += step
		if phase >= 1.0:
			phase -= floorf(phase)
		if idx < 0:
			continue

		var sample := 0.0
		if shape == SHAPE_SINE:
			sample = sin(TAU * phase)
		elif shape == SHAPE_TRIANGLE:
			sample = 4.0 * absf(phase - 0.5) - 1.0
		elif shape == SHAPE_SAW:
			sample = 2.0 * phase - 1.0
		else:
			sample = 1.0 if phase < duty else -1.0

		var gain := 0.0
		if held:
			gain = 1.0 if attack <= 0.0 else minf(1.0, t / attack)
			if release > 0.0:
				gain *= clampf((length - t) / release, 0.0, 1.0)
		elif t < attack:
			gain = t / maxf(attack, 1e-6)
		else:
			var d := (t - attack) / maxf(decay, 1e-6)
			gain = 0.0 if d >= 1.0 else pow(1.0 - d, curve)

		buf[idx] += sample * amp * gain


## --- filtered noise --------------------------------------------------------

## Adds a noise burst through a resonant state-variable filter whose cutoff can
## sweep. This is the workhorse: a footstep is a short band of noise around
## 1.5 kHz, a cloth movement is the same band swept upward and softer, a stone
## crack is the high output with almost no decay.
##
## `env` picks the envelope, as in `add_tone()`: "ad" (default) or "asr".
##
## cfg: start, len, attack, decay, curve, release, env, cutoff, cutoff_end, q,
##      amp, seed, band ("band" | "low" | "high"), rate
static func add_noise(buf: PackedFloat32Array, cfg: Dictionary) -> void:
	var rate := int(cfg.get("rate", RATE))
	var length := float(cfg.get("len", 0.1))
	var start := int(round(float(cfg.get("start", 0.0)) * float(rate)))
	var count := int(round(length * float(rate)))
	var attack := float(cfg.get("attack", 0.002))
	var decay := float(cfg.get("decay", length))
	var curve := float(cfg.get("curve", 2.5))
	var f0 := float(cfg.get("cutoff", 1200.0))
	var f1 := float(cfg.get("cutoff_end", f0))
	var sweep_curve := float(cfg.get("sweep_curve", 1.0))
	var q := float(cfg.get("q", 1.0))
	var amp := float(cfg.get("amp", 0.5))
	var band := String(cfg.get("band", "band"))
	var low_band := band == "low"
	var high_band := band == "high"
	var rng := Rng.new(int(cfg.get("seed", 1)))
	var held := String(cfg.get("env", "ad")) == "asr"
	var release := float(cfg.get("release", minf(0.08, length * 0.25)))

	# A topology-preserving (zero-delay-feedback) state variable filter. The
	# naive Chamberlin SVF is only stable while the cutoff stays well below
	# Nyquist, and it blew up into a DC rail on the 4-5 kHz bands that give the
	# footsteps and the stone crack their grit — caught by the DC offset in the
	# preview measurements, since nobody here can hear it.
	var damping := clampf(1.0 / maxf(0.2, q), 0.02, 2.0)
	var ic1 := 0.0
	var ic2 := 0.0
	var dt := 1.0 / float(rate)
	var span := float(maxi(1, count - 1))
	var size := buf.size()

	# Same reasoning as add_tone: a fixed cutoff gets its filter coefficients
	# once rather than a tan() per sample.
	var sweeping := not is_equal_approx(f0, f1)
	var g := tan(PI * clampf(f0, 20.0, float(rate) * 0.49) / float(rate))
	var a1 := 1.0 / (1.0 + g * (g + damping))
	var a2 := g * a1
	var a3 := g * a2

	for i: int in count:
		var idx := start + i
		if idx >= size:
			break
		var t := float(i) * dt
		if sweeping:
			var fc := clampf(sweep(float(i) / span, f0, f1, sweep_curve),
				20.0, float(rate) * 0.49)
			g = tan(PI * fc / float(rate))
			a1 = 1.0 / (1.0 + g * (g + damping))
			a2 = g * a1
			a3 = g * a2

		var white := rng.bipolar()
		var v3 := white - ic2
		var v1 := a1 * ic1 + a2 * v3
		var v2 := ic2 + a2 * ic1 + a3 * v3
		ic1 = 2.0 * v1 - ic1
		ic2 = 2.0 * v2 - ic2

		var value := v1
		if low_band:
			value = v2
		elif high_band:
			value = white - damping * v1 - v2
		if idx < 0:
			continue

		var gain := 0.0
		if held:
			gain = 1.0 if attack <= 0.0 else minf(1.0, t / attack)
			if release > 0.0:
				gain *= clampf((length - t) / release, 0.0, 1.0)
		elif t < attack:
			gain = t / maxf(attack, 1e-6)
		else:
			var d := (t - attack) / maxf(decay, 1e-6)
			gain = 0.0 if d >= 1.0 else pow(1.0 - d, curve)

		buf[idx] += value * amp * gain


## --- plucked string --------------------------------------------------------

## Karplus-Strong: a noise-filled delay line, averaged and damped as it
## circulates. Four lines of DSP buy a plucked oud, a wooden tick and a
## brass-struck bell depending on `decay` and `brightness` — which is why the
## music is a lute-and-drum ensemble and not a chip arpeggio.
##
## cfg: start, len, freq, amp, decay (seconds to -60 dB), brightness (0..1),
##      release, seed, rate
static func add_pluck(buf: PackedFloat32Array, cfg: Dictionary) -> void:
	var rate := int(cfg.get("rate", RATE))
	var length := float(cfg.get("len", 0.5))
	var start := int(round(float(cfg.get("start", 0.0)) * float(rate)))
	var count := int(round(length * float(rate)))
	var freq := maxf(20.0, float(cfg.get("freq", 220.0)))
	var amp := float(cfg.get("amp", 0.5))
	var decay := maxf(0.01, float(cfg.get("decay", 0.8)))
	var brightness := clampf(float(cfg.get("brightness", 0.5)), 0.01, 1.0)
	var release := float(cfg.get("release", minf(0.08, length * 0.3)))
	var rng := Rng.new(int(cfg.get("seed", 1)))

	var n := maxi(2, int(round(float(rate) / freq)))
	var line := PackedFloat32Array()
	line.resize(n)
	# A dull pick sounds like a finger, a bright one like a plectrum.
	var excite := 0.0
	var mean := 0.0
	for i: int in n:
		excite = lerpf(excite, rng.bipolar(), brightness)
		line[i] = excite
		mean += excite
	# The averaging filter in the loop has unity gain at DC, so any offset in
	# the excitation circulates for the whole note and shows up as a thump
	# under the pitch. Centre the line before plucking it.
	mean /= float(n)
	for i: int in n:
		line[i] -= mean

	# Round trips per second is the pitch, so the loop gain that reaches
	# -60 dB after `decay` seconds falls straight out of the frequency.
	var loop_gain := pow(0.001, 1.0 / maxf(1.0, freq * decay))
	var bright_coef := 0.35 + 0.6 * brightness
	var pos := 0
	var held := 0.0
	var size := buf.size()

	for i: int in count:
		var idx := start + i
		if idx >= size:
			break
		var t := float(i) / float(rate)
		var current := line[pos]
		var next := line[(pos + 1) % n]
		held = lerpf(held, (current + next) * 0.5, bright_coef)
		line[pos] = held * loop_gain
		pos = (pos + 1) % n
		if idx < 0:
			continue
		buf[idx] += current * amp * env_asr(t, length, 0.001, release)


## --- buffer maths ----------------------------------------------------------

static func mix_into(dst: PackedFloat32Array, src: PackedFloat32Array,
		start_sec: float, gain: float = 1.0, rate: int = RATE) -> void:
	var start := int(round(start_sec * float(rate)))
	var size := dst.size()
	for i: int in src.size():
		var idx := start + i
		if idx < 0:
			continue
		if idx >= size:
			break
		dst[idx] += src[i] * gain


## Folds everything past `loop_len` back onto the head of the buffer and
## truncates. A note that rings past the end of a loop therefore rings into the
## start of the next pass instead of being cut off at the seam.
static func fold_tail(buf: PackedFloat32Array, loop_len: int) -> PackedFloat32Array:
	if buf.size() <= loop_len or loop_len <= 0:
		return buf
	var out := buf.slice(0, loop_len)
	for i: int in range(loop_len, buf.size()):
		out[(i - loop_len) % loop_len] += buf[i]
	return out


## Crossfades the tail of a continuous bed into its head so it loops without a
## click. Used by the wind, which has no note structure to fold.
static func crossfade_loop(buf: PackedFloat32Array, fade_sec: float,
		rate: int = RATE) -> PackedFloat32Array:
	var fade := mini(int(round(fade_sec * float(rate))), buf.size() / 3)
	if fade <= 1:
		return buf
	var out := buf.slice(0, buf.size() - fade)
	for i: int in fade:
		var k := float(i) / float(fade)
		out[i] = out[i] * k + buf[buf.size() - fade + i] * (1.0 - k)
	return out


static func one_pole(buf: PackedFloat32Array, cutoff: float,
		high: bool = false, rate: int = RATE) -> void:
	var coef := clampf(1.0 - exp(-TAU * cutoff / float(rate)), 0.0001, 1.0)
	var state := 0.0
	for i: int in buf.size():
		state += coef * (buf[i] - state)
		buf[i] = (buf[i] - state) if high else state


## tanh saturation. Rounds the transients off a stacked voice without the hard
## edges of digital clipping, so `normalize()` has something sane to scale.
static func soft_clip(buf: PackedFloat32Array, drive: float = 1.0) -> void:
	if is_zero_approx(drive):
		return
	var norm := tanh(drive)
	for i: int in buf.size():
		buf[i] = tanh(buf[i] * drive) / norm


static func remove_dc(buf: PackedFloat32Array) -> void:
	if buf.is_empty():
		return
	var sum := 0.0
	for i: int in buf.size():
		sum += buf[i]
	var mean := sum / float(buf.size())
	if absf(mean) < 1e-7:
		return
	for i: int in buf.size():
		buf[i] -= mean


## Scales the buffer so its loudest sample sits exactly at `target`. Every
## voice declares its own target, which is how the mix balance survives.
static func normalize(buf: PackedFloat32Array, target: float = 0.9) -> void:
	var p := peak(buf)
	if p < 1e-6:
		return
	var gain := target / p
	for i: int in buf.size():
		buf[i] *= gain


## Linear fade on both ends. Any voice baked without this can click.
static func fade_edges(buf: PackedFloat32Array, in_sec: float, out_sec: float,
		rate: int = RATE) -> void:
	var n := buf.size()
	var fade_in := mini(int(round(in_sec * float(rate))), n)
	var fade_out := mini(int(round(out_sec * float(rate))), n)
	for i: int in fade_in:
		buf[i] *= float(i) / float(maxi(1, fade_in))
	for i: int in fade_out:
		var idx := n - 1 - i
		if idx < 0:
			break
		buf[idx] *= float(i) / float(maxi(1, fade_out))


## --- measurement (used by the tests and the preview renderer) --------------

static func peak(buf: PackedFloat32Array) -> float:
	var out := 0.0
	for i: int in buf.size():
		out = maxf(out, absf(buf[i]))
	return out


static func rms(buf: PackedFloat32Array) -> float:
	if buf.is_empty():
		return 0.0
	var sum := 0.0
	for i: int in buf.size():
		sum += buf[i] * buf[i]
	return sqrt(sum / float(buf.size()))


static func dc_offset(buf: PackedFloat32Array) -> float:
	if buf.is_empty():
		return 0.0
	var sum := 0.0
	for i: int in buf.size():
		sum += buf[i]
	return sum / float(buf.size())


## Peak of each of `slices` equal windows — a cheap envelope, enough to assert
## that a percussive voice actually decays instead of sitting flat.
static func envelope(buf: PackedFloat32Array, slices: int = 8) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(maxi(1, slices))
	var width := maxi(1, buf.size() / maxi(1, slices))
	for s: int in out.size():
		var top := 0.0
		for i: int in range(s * width, mini((s + 1) * width, buf.size())):
			top = maxf(top, absf(buf[i]))
		out[s] = top
	return out


## --- baking ----------------------------------------------------------------

## Bakes a float buffer into 16-bit PCM. Not a stream: AudioStreamWAV holds the
## samples in memory, which on a phone is cheaper per voice than decoding Ogg
## and keeps the download at zero bytes of audio.
static func to_wav(buf: PackedFloat32Array, rate: int = RATE,
		loop: bool = false) -> AudioStreamWAV:
	var n := buf.size()
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i: int in n:
		bytes.encode_s16(i * 2, int(round(clampf(buf[i], -1.0, 1.0) * 32767.0)))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = bytes
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = n
	return stream


## The inverse, for tests and the preview renderer.
static func from_wav(stream: AudioStreamWAV) -> PackedFloat32Array:
	var bytes := stream.data
	var n := bytes.size() / 2
	var out := PackedFloat32Array()
	out.resize(n)
	for i: int in n:
		out[i] = float(bytes.decode_s16(i * 2)) / 32767.0
	return out
