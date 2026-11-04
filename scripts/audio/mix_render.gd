class_name MixRender
extends RefCounted
## A scene's worth of sound mixed offline, the way the director mixes it live,
## and measured the way a phone speaker would play it.
##
## Nobody building this game can listen to it: the machines have no audio
## device. The owner can, on a phone, and said the music was too loud and the
## swords and deaths could not be heard. That is a statement about a *mix* --
## one sound against another, through a small speaker -- and no per-voice
## number in render_previews.gd can confirm or refute it. This can:
##
##     var mix := MixRender.render(MixRender.duel_exchange(), 6.0, {"mood": &"duel"})
##     MixRender.margins(mix)   # each combat cue's dB above the music under it
##
## The music stems, the voices, their spec trims, the faders and the duck are
## the game's own (Music, Voices, AudioSettings, Mix), so the margins are of
## the mixer the game has. What it leaves out is variation, which is random
## by design and would make a test flaky: every cue is mixed at its centre
## pitch and gain.
##
## THE PHONE
## A phone's speaker reproduces next to nothing below a few hundred hertz. So
## every level here is measured after a second-order highpass at PHONE_HZ: the
## drone's bottom octave and a landing's thump count for nothing, which is
## what they count for on the device the owner listened on. A voice that is
## all low end measures as quiet as it sounds there.

const RATE := Synth.RATE
## Where a phone speaker's response has fallen away: two one-pole highpasses
## here are 12 dB per octave below it.
const PHONE_HZ := 400.0
## The director's ducks and fades move once a frame; the render does the same.
const FRAME := 1.0 / 60.0
## A cue's loudness is its loudest window of this length -- long enough to be
## heard as a sound rather than as a click, short enough to be the transient.
const WINDOW := 0.05
## The music a cue is compared against: what is under it for this long after
## it starts, which is how long the ear takes to decide whether it heard it.
const UNDER := 0.3

static var _voices: Dictionary = {}
static var _stems: Array[PackedFloat32Array] = []


## --- the two scenes the owner described --------------------------------------

## A typical exchange in the duel: two thrusts, a clash, a parry, a disarm,
## a kill. [seconds, event, opts] -- the cues the duel's presentation makes.
static func duel_exchange() -> Array:
	return [
		[0.40, "sword", {}],
		[0.62, "sword", {"pitch": 0.94}],
		[0.66, "clash", {}],
		[1.40, "sword", {}],
		[1.55, "clash", {"pitch": 0.9}],
		[2.30, "sword", {"pitch": 1.06}],
		[2.36, "disarm", {}],
		[3.10, "sword", {}],
		[3.16, "kill", {}],
	]


## A guard fought in the adventure: the prince's swing, a wound, the guard's
## cut parried, a hit taken, and the killing blow.
static func guard_fight() -> Array:
	return [
		[0.40, "sword", {}],
		[0.47, "guard_hit", {}],
		[1.20, "sword", {"pitch": 0.78}],
		[1.30, "sword_hit", {"pitch": 1.35}],
		[2.10, "sword", {"pitch": 0.78}],
		[2.20, "hurt", {"pitch": 0.94}],
		[3.00, "sword", {}],
		[3.07, "guard_hit", {}],
		[3.07, "kill", {}],
		[4.40, "die", {}],
	]


## --- rendering ----------------------------------------------------------------

## Mixes `events` over `seconds` of music. `context` understands:
##   music, sfx    the faders, linear 0..1 (AudioSettings' defaults)
##   intensity     0..1, the drive stem (default 0), capped by the mood
##   mood          a Mix mood (default Mix.MOOD_DEFAULT)
##   offset        where in the loop the music starts, in seconds (default 0)
## Returns {music, sfx, mix} as buffers at RATE, plus `cues`: one entry per
## event with its voice, start and gain, for margins().
static func render(events: Array, seconds: float, context: Dictionary = {}) -> Dictionary:
	var defaults := AudioSettings.new()
	var music_fader := float(context.get("music", defaults.music))
	var sfx_fader := float(context.get("sfx", defaults.sfx))
	var n := int(ceil(seconds * float(RATE)))

	var sfx := PackedFloat32Array()
	sfx.resize(n)
	var cues: Array[Dictionary] = []
	var specs := Voices.specs()
	for event: Array in events:
		var voice := Voices.resolve(String(event[1]))
		if voice == "":
			continue
		var opts: Dictionary = event[2] if event.size() > 2 else {}
		var spec: Dictionary = specs[voice]
		var gain_db := float(spec.get("db", 0.0)) + float(opts.get("volume_db", 0.0))
		var gain := db_to_linear(gain_db) * sfx_fader
		var buf := pitched(voice, float(opts.get("pitch", 1.0)))
		Synth.mix_into(sfx, buf, float(event[0]), gain, RATE)
		cues.append({
			"voice": voice, "event": String(event[1]), "at": float(event[0]),
			"gain": gain, "pitch": float(opts.get("pitch", 1.0)),
			"duck": float(spec.get("duck", 0.0)),
		})

	var music := music_bed(context, n)
	_apply_ducks(music, cues, linear_to_db(maxf(music_fader, 0.0001)),
		Mix.mood_db(StringName(context.get("mood", Mix.MOOD_DEFAULT))))

	var mix := PackedFloat32Array()
	mix.resize(n)
	for i: int in n:
		mix[i] = music[i] + sfx[i]
	return {"music": music, "sfx": sfx, "mix": mix, "cues": cues, "context": context}


## The music as the director plays it before any duck: the bed, and the drive
## at the context's intensity, from `offset` into the loop, `n` samples long.
static func music_bed(context: Dictionary, n: int) -> PackedFloat32Array:
	var stems := _music()
	var mood := StringName(context.get("mood", Mix.MOOD_DEFAULT))
	var intensity := minf(float(context.get("intensity", 0.0)), Mix.mood_intensity_cap(mood))
	var drive := db_to_linear(Mix.drive_db(intensity))
	var offset := float(context.get("offset", 0.0))
	var out := PackedFloat32Array()
	out.resize(n)
	var bed: PackedFloat32Array = stems[0]
	var lift: PackedFloat32Array = stems[1]
	var size := bed.size()
	var step := float(Music.RATE) / float(RATE)
	var at := offset * float(Music.RATE)
	for i: int in n:
		var pos := fposmod(at + float(i) * step, float(size))
		var j := int(pos)
		var k := (j + 1) % size
		var f := pos - float(j)
		out[i] = (lerpf(bed[j], bed[k], f) + lerpf(lift[j], lift[k], f) * drive)
	return out


## A voice resampled to `pitch`, the way AudioStreamPlayer.pitch_scale plays
## it, at RATE.
static func pitched(voice: String, pitch: float) -> PackedFloat32Array:
	var key := "%s@%.4f" % [voice, pitch]
	if _voices.has(key):
		return _voices[key]
	var raw := Voices.build_buffer(voice)
	var step := pitch * float(Voices.rate_of(voice)) / float(RATE)
	var out := PackedFloat32Array()
	out.resize(int(float(raw.size()) / step))
	for i: int in out.size():
		var pos := float(i) * step
		var j := int(pos)
		var f := pos - float(j)
		var a := raw[mini(j, raw.size() - 1)]
		var b := raw[mini(j + 1, raw.size() - 1)]
		out[i] = lerpf(a, b, f)
	_voices[key] = out
	return out


static func _music() -> Array[PackedFloat32Array]:
	if _stems.is_empty():
		_stems.append(Music.build_bed())
		_stems.append(Music.build_drive())
	return _stems


## The music bus, frame by frame: every cue with a `duck` in its spec pulls it
## down as it starts, and Mix lets it back. The fader, the trim and the mood
## are applied here too.
static func _apply_ducks(music: PackedFloat32Array, cues: Array[Dictionary],
		fader_db: float, mood_trim_db: float) -> void:
	var per_frame := int(round(FRAME * float(RATE)))
	var depth := 0.0
	var hold := 0.0
	var frame := 0
	var start := 0
	while start < music.size():
		var t0 := float(frame) * FRAME
		for cue: Dictionary in cues:
			var at := float(cue["at"])
			if at >= t0 and at < t0 + FRAME and float(cue["duck"]) > 0.0:
				depth = maxf(depth, float(cue["duck"]))
				hold = Mix.DUCK_HOLD
		var gain := db_to_linear(Mix.music_db(fader_db, mood_trim_db, depth))
		for i: int in range(start, mini(start + per_frame, music.size())):
			music[i] *= gain
		var next := Mix.duck_step(depth, hold, FRAME)
		depth = next.x
		hold = next.y
		frame += 1
		start += per_frame


## --- measuring ----------------------------------------------------------------

## `buf` as a phone speaker plays it: a second-order highpass at PHONE_HZ.
static func phone(buf: PackedFloat32Array) -> PackedFloat32Array:
	var out := buf.duplicate()
	Synth.one_pole(out, PHONE_HZ, true, RATE)
	Synth.one_pole(out, PHONE_HZ, true, RATE)
	return out


static func db(value: float) -> float:
	return linear_to_db(maxf(value, 1e-6))


## RMS of `buf` between two times, in seconds.
static func rms_between(buf: PackedFloat32Array, from: float, to: float) -> float:
	var a := clampi(int(from * float(RATE)), 0, buf.size())
	var b := clampi(int(to * float(RATE)), a, buf.size())
	return Synth.rms(buf.slice(a, b))


## The loudest WINDOW of `buf`, as RMS.
static func loudest(buf: PackedFloat32Array) -> float:
	var width := maxi(1, int(WINDOW * float(RATE)))
	var hop := maxi(1, width / 5)
	var best := 0.0
	var at := 0
	while at < buf.size():
		best = maxf(best, Synth.rms(buf.slice(at, mini(at + width, buf.size()))))
		at += hop
	return best


## How a cue reads on a phone: its loudest window at the gain it was played
## at, and how long it stays within 20 dB of that.
static func cue_level(voice: String, pitch: float, gain: float) -> Dictionary:
	var buf := phone(pitched(voice, pitch))
	var top := loudest(buf) * gain
	var width := maxi(1, int(WINDOW * float(RATE)))
	var audible := 0
	var at := 0
	while at < buf.size():
		var level := Synth.rms(buf.slice(at, mini(at + width, buf.size()))) * gain
		if level >= top * 0.1:
			audible += mini(width, buf.size() - at)
		at += width
	return {"db": db(top), "audible": float(audible) / float(RATE)}


## Every cue of a render against the music under it, on a phone. `margin` is
## the duck included -- what the player hears; `dry_margin` is against the
## music as it would be without one.
static func margins(result: Dictionary) -> Array[Dictionary]:
	var music := phone(result["music"] as PackedFloat32Array)
	var context: Dictionary = result.get("context", {})
	var gain := music_gain(context)
	var bed := phone(music_bed(context, (result["music"] as PackedFloat32Array).size()))
	var out: Array[Dictionary] = []
	for cue: Dictionary in result["cues"] as Array[Dictionary]:
		var at := float(cue["at"])
		var level := cue_level(String(cue["voice"]), float(cue["pitch"]), float(cue["gain"]))
		var under := db(rms_between(music, at, at + UNDER))
		var dry := db(rms_between(bed, at, at + UNDER) * gain)
		out.append({
			"event": cue["event"], "voice": cue["voice"], "at": at,
			"level": level["db"], "audible": level["audible"],
			"under": under, "margin": float(level["db"]) - under,
			"dry_margin": float(level["db"]) - dry,
		})
	return out


## Peak and RMS of each stream, full band and on a phone.
static func levels(result: Dictionary) -> Dictionary:
	var out := {}
	for stream: String in ["music", "sfx", "mix"]:
		var buf: PackedFloat32Array = result[stream]
		var small := phone(buf)
		out[stream] = {
			"peak": db(Synth.peak(buf)), "rms": db(Synth.rms(buf)),
			"phone_peak": db(Synth.peak(small)), "phone_rms": db(Synth.rms(small)),
		}
	return out


## The music bed alone over one whole loop, on a phone, in dB RMS: the level
## every combat cue has to stand above.
static func bed_level(context: Dictionary = {}) -> float:
	var n := int(Music.loop_seconds() * float(RATE))
	var bed := phone(music_bed(context, n))
	return db(Synth.rms(bed) * music_gain(context))


## The music bus's gain in `context` with no duck: fader, trim and mood.
static func music_gain(context: Dictionary) -> float:
	var defaults := AudioSettings.new()
	var fader := float(context.get("music", defaults.music))
	var mood := StringName(context.get("mood", Mix.MOOD_DEFAULT))
	return db_to_linear(Mix.music_db(linear_to_db(maxf(fader, 0.0001)), Mix.mood_db(mood), 0.0))
