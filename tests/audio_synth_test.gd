extends SceneTree
## Pins the synthesis: determinism, level, length and shape.
##
## Nobody can listen to this project's audio on a build machine — there is no
## audio device, Godot falls back to its dummy driver — so the checks a human
## ear would make are made numerically here instead. A footstep that becomes
## two seconds long, a voice that clips at full scale, a buffer that comes out
## silent or railed to DC: all of those are caught without speakers.
##
##     godot --headless --script tests/audio_synth_test.gd

## Longest a voice may be, in seconds. These are sound-design budgets, not
## technical limits: a footstep has to be over before the next one starts at
## full sprint (about 0.2 s apart), and nothing but the music may ring on.
const MAX_SECONDS := {
	"step_run": 0.18, "step_walk": 0.18, "cloth": 0.2, "ui_move": 0.15,
	"ladder": 0.2, "jump": 0.3, "land_soft": 0.35, "ledge_grab": 0.4,
	"guard_hit": 0.4, "sword": 0.45, "hurt": 0.5, "climb": 0.5,
	"land_hard": 0.6, "sword_hit": 0.6, "pause_in": 0.5, "pause_out": 0.5,
	"ui_confirm": 0.5, "ui_back": 0.5, "relic": 0.9, "exit": 1.5,
	"die": 2.0, "level_complete": 2.5, "wind": 6.0,
	"secret": 1.4, "masonry": 1.0, "chain": 0.2, "hoot": 0.6,
	"sun_gather": 1.0, "sunrise": 3.0,
	"clash": 0.4, "disarm": 0.8, "kill": 0.9,
	"hiss": 0.3, "yowl": 0.5,
	"glass_charge": 0.6, "shatter": 0.7,
}

## Nothing shorter than this is a sound; it is a click.
const MIN_SECONDS := 0.02

## Full scale is 1.0. A baked voice that reaches it is either clipping or one
## sample away from it, and the mix has no headroom left for two at once.
const CEILING := 0.98

var _failures := 0


func _initialize() -> void:
	_check_every_voice()
	_check_determinism()
	_check_loop_points()
	_check_music_loop()
	_check_previews_match_the_code()

	if _failures > 0:
		printerr("audio_synth_test: %d failure(s)" % _failures)
		quit(1)
		return
	print("audio_synth_test: ok")
	quit(0)


func _check_every_voice() -> void:
	for name: String in Voices.names():
		var spec := Voices.spec(name)
		var rate := Voices.rate_of(name)
		var buf := Voices.build_buffer(name)
		if buf.is_empty():
			_fail("%s: empty buffer" % name)
			continue

		var seconds := float(buf.size()) / float(rate)
		var limit := float(MAX_SECONDS.get(name, 1.0))
		_true(seconds <= limit,
			"%s: %.3f s is longer than its %.2f s budget" % [name, seconds, limit])
		_true(seconds >= MIN_SECONDS, "%s: %.4f s is too short to be a sound" % [name, seconds])

		var peak := Synth.peak(buf)
		var target := float(spec.get("peak", 0.0))
		_true(peak <= CEILING, "%s: peak %.4f is at or over the ceiling" % [name, peak])
		_true(absf(peak - target) < 0.01,
			"%s: peak %.4f does not match its declared %.2f" % [name, peak, target])

		# Silence and near-silence are the failure modes a peak check misses:
		# one loud sample over a dead buffer passes the peak test.
		var rms := Synth.rms(buf)
		_true(rms > 0.004, "%s: rms %.5f — effectively silent" % [name, rms])
		_true(rms < peak, "%s: rms %.4f is not below peak %.4f" % [name, rms, peak])

		# A railed filter shows up as DC, which is inaudible on a phone and
		# eats the headroom of everything mixed with it.
		var dc := Synth.dc_offset(buf)
		_true(absf(dc) < 0.002, "%s: DC offset %+.5f" % [name, dc])

		# Percussion has to decay. The ambience is the one voice that may not.
		if name != "wind":
			var env := Synth.envelope(buf, 8)
			_true(env[7] < env[0] * 0.5,
				"%s: tail %.3f has not decayed from the attack %.3f" % [name, env[7], env[0]])

		var stream := Voices.build(name)
		_true(stream != null, "%s: no stream" % name)
		if stream == null:
			continue
		_equal(stream.mix_rate, float(rate), "%s: stream mix rate" % name)
		_equal(stream.stereo, false, "%s: stream is mono" % name)
		_equal(stream.format, AudioStreamWAV.FORMAT_16_BITS, "%s: stream format" % name)
		_equal(stream.data.size(), buf.size() * 2, "%s: stream byte length" % name)


## Same parameters, same samples — always. The previews committed under
## docs/audio/ are only documentation if this holds, and the whole measurement
## approach collapses without it.
func _check_determinism() -> void:
	for name: String in Voices.names():
		var first := Voices.build(name)
		var second := Voices.build(name)
		if first == null or second == null:
			_fail("%s: could not build twice" % name)
			continue
		_true(first.data == second.data,
			"%s: two builds produced different samples" % name)

	# And the primitives themselves, independent of the catalogue.
	var a := Synth.buffer(0.05)
	var b := Synth.buffer(0.05)
	var cfg := {"len": 0.05, "cutoff": 1400.0, "cutoff_end": 400.0, "seed": 7}
	Synth.add_noise(a, cfg)
	Synth.add_noise(b, cfg)
	_true(a == b, "add_noise is not deterministic for a fixed seed")

	var c := Synth.buffer(0.05)
	Synth.add_noise(c, {"len": 0.05, "cutoff": 1400.0, "cutoff_end": 400.0, "seed": 8})
	_true(a != c, "add_noise ignores its seed")


func _check_loop_points() -> void:
	for name: String in Voices.names():
		var stream := Voices.build(name)
		if stream == null:
			continue
		var loops := bool(Voices.spec(name).get("loop", false))
		if not loops:
			_equal(stream.loop_mode, AudioStreamWAV.LOOP_DISABLED,
				"%s: should not loop" % name)
			continue
		_equal(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD, "%s: loop mode" % name)
		_equal(stream.loop_begin, 0, "%s: loop begin" % name)
		_equal(stream.loop_end, stream.data.size() / 2, "%s: loop end" % name)


func _check_music_loop() -> void:
	var bars := float(Music.BARS * Music.BEATS_PER_BAR) * Music.beat_seconds()
	_true(absf(Music.loop_seconds() - bars) < 1e-6, "music loop is a whole number of bars")
	_equal(Music.loop_samples(), int(round(Music.loop_seconds() * float(Music.RATE))),
		"music loop sample count")

	var stems := Music.build_stems()
	_equal(stems.size(), 2, "music has a bed and a drive stem")
	for i: int in stems.size():
		var stream := stems[i]
		_equal(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD, "stem %d loops" % i)
		# Both stems must be the same length to the sample, or the drum walks
		# away from the oud after a few passes.
		_equal(stream.data.size() / 2, Music.loop_samples(), "stem %d length" % i)
		var buf := Synth.from_wav(stream)
		_true(Synth.peak(buf) <= CEILING, "stem %d peak %.3f" % [i, Synth.peak(buf)])
		_true(Synth.rms(buf) > 0.01, "stem %d is not silent" % i)
		_true(absf(Synth.dc_offset(buf)) < 0.002, "stem %d DC offset" % i)

		# A loop whose ends do not meet clicks once per pass. The step across
		# the seam has to look like ordinary content, not like an edit.
		var seam := absf(buf[0] - buf[buf.size() - 1])
		_true(seam < 0.08, "stem %d seam step %.4f would click" % [i, seam])

	# The intensity stem is the quieter one; if it were not, raising the
	# intensity would swamp the melody rather than lift it.
	_true(Synth.rms(Synth.from_wav(stems[1])) < Synth.rms(Synth.from_wav(stems[0])),
		"the drive stem is not quieter than the bed")


## The .wav files under docs/audio/ are how a human finally judges this, so a
## synthesis change that is not re-rendered leaves the documentation lying.
## Re-render with:
##     godot --headless --script scripts/audio/render_previews.gd
func _check_previews_match_the_code() -> void:
	for name: String in Voices.names():
		var path := "res://docs/audio/%s.wav" % name
		var pcm := _wav_pcm(path)
		if pcm.is_empty():
			_fail("%s: no preview at %s — run render_previews.gd" % [name, path])
			continue
		var stream := Voices.build(name)
		_true(pcm == stream.data,
			"%s: the preview no longer matches the synthesis — re-render it" % name)


## Minimal RIFF reader: returns the bytes of the `data` chunk.
func _wav_pcm(path: String) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var bytes := file.get_buffer(file.get_length())
	if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return PackedByteArray()
	var at := 12
	while at + 8 <= bytes.size():
		var id := bytes.slice(at, at + 4).get_string_from_ascii()
		var size := bytes.decode_u32(at + 4)
		if id == "data":
			return bytes.slice(at + 8, mini(at + 8 + size, bytes.size()))
		at += 8 + size + (size & 1)
	return PackedByteArray()


func _equal(actual: Variant, expected: Variant, what: String) -> void:
	if actual == expected:
		return
	_fail("%s: expected %s, got %s" % [what, str(expected), str(actual)])


func _true(condition: bool, what: String) -> void:
	if not condition:
		_fail(what)


func _fail(message: String) -> void:
	_failures += 1
	printerr("  FAIL  " + message)
