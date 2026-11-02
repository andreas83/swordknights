class_name Voices
extends RefCounted
## The catalogue: one entry per sound the game can make.
##
## A voice is a name, a recipe (a function below that writes samples with
## Synth) and a spec row that says how loud it should end up and how the
## director is allowed to vary it. AudioDirector bakes all of these into
## AudioStreamWAVs at load; nothing here touches the scene tree, so the
## catalogue can be rendered to .wav or measured in a headless test.
##
## Adding a voice is three edits — a row in `specs()`, a `match` arm in
## `_render()` and a builder function. docs/audio.md walks through it.
##
## Scoring notes. The art direction is a sun-bleached Moorish city at low sun:
## crimson shadow, gold light, hard edges, nothing soft. So:
##
## * no reverb tails anywhere — decays are dry and short, like sound in dusty
##   open air off hard stone;
## * footfalls and scrapes are filtered noise around 1-2 kHz, which reads as
##   grit on sandstone rather than as a boot on a boardwalk;
## * anything metal or precious (sword, relic, exit) is a small stack of
##   inharmonic partials that rings and stops — gold, not shimmer;
## * damage and death are low and crimson: saturated square waves and a drone,
##   not a cartoon splat.
##
## `peak` is a normalisation target, not a limiter: the mix balance between a
## footstep (0.4) and a hard landing (0.95) is baked into the samples, so the
## director's per-event trim and the bus faders are the only other gain stages.


## name -> spec. Keys:
##   peak          normalisation target, 0..1 — the baked mix balance
##   db            constant trim applied at playback (default 0)
##   seed          PRNG seed; fixed per voice so the samples never move
##   rate          mix rate for this voice (defaults to Synth.RATE)
##   loop          bake loop points (ambience only)
##   pitch_jitter  +/- fraction of pitch the director may vary per trigger
##   gain_jitter   +/- dB the director may vary per trigger
##   min_gap       seconds before the same voice may retrigger (anti machine-gun)
##   duck          dB to pull the music down by when this plays
static func specs() -> Dictionary:
	return {
		# --- feet and body ---
		"step_run": {
			"peak": 0.40, "seed": 1101, "pitch_jitter": 0.09, "gain_jitter": 2.5,
			"min_gap": 0.055,
		},
		"step_walk": {
			"peak": 0.26, "seed": 1102, "pitch_jitter": 0.08, "gain_jitter": 2.0,
			"min_gap": 0.09,
		},
		"cloth": {
			"peak": 0.22, "seed": 1103, "pitch_jitter": 0.12, "gain_jitter": 3.0,
			"min_gap": 0.07,
		},
		"jump": {
			"peak": 0.52, "seed": 1104, "pitch_jitter": 0.06, "gain_jitter": 1.5,
			"min_gap": 0.06,
		},
		"land_soft": {
			"peak": 0.62, "seed": 1105, "pitch_jitter": 0.07, "gain_jitter": 1.5,
			"min_gap": 0.05,
		},
		"land_hard": {
			"peak": 0.95, "seed": 1106, "pitch_jitter": 0.05, "gain_jitter": 1.0,
			"min_gap": 0.05, "duck": 4.5,
		},
		"ledge_grab": {
			"peak": 0.60, "seed": 1107, "pitch_jitter": 0.06, "gain_jitter": 1.5,
			"min_gap": 0.1,
		},
		"climb": {
			"peak": 0.46, "seed": 1108, "pitch_jitter": 0.07, "gain_jitter": 1.5,
			"min_gap": 0.2,
		},
		"ladder": {
			"peak": 0.38, "seed": 1109, "pitch_jitter": 0.10, "gain_jitter": 2.5,
			"min_gap": 0.1,
		},

		# --- sword and damage ---
		"sword": {
			"peak": 0.78, "seed": 1201, "pitch_jitter": 0.08, "gain_jitter": 1.5,
			"min_gap": 0.07,
		},
		"sword_hit": {
			"peak": 0.86, "seed": 1202, "pitch_jitter": 0.07, "gain_jitter": 1.5,
			"min_gap": 0.05, "duck": 3.0,
		},
		"guard_hit": {
			"peak": 0.68, "seed": 1203, "pitch_jitter": 0.08, "gain_jitter": 2.0,
			"min_gap": 0.05,
		},
		"hurt": {
			"peak": 0.84, "seed": 1204, "pitch_jitter": 0.05, "gain_jitter": 1.0,
			"min_gap": 0.1, "duck": 5.0,
		},
		"die": {
			"peak": 0.92, "seed": 1205, "pitch_jitter": 0.02, "gain_jitter": 0.0,
			"min_gap": 0.5, "duck": 9.0,
		},

		# --- world ---
		"relic": {
			"peak": 0.70, "seed": 1301, "pitch_jitter": 0.03, "gain_jitter": 1.0,
			"min_gap": 0.08, "duck": 2.0,
		},
		"exit": {
			"peak": 0.72, "seed": 1302, "pitch_jitter": 0.02, "gain_jitter": 0.0,
			"min_gap": 0.4, "duck": 3.0,
		},
		"level_complete": {
			"peak": 0.86, "seed": 1303, "pitch_jitter": 0.0, "gain_jitter": 0.0,
			"min_gap": 1.0, "duck": 8.0,
		},

		# --- interface ---
		"ui_move": {
			"peak": 0.42, "seed": 1401, "pitch_jitter": 0.05, "gain_jitter": 1.0,
			"min_gap": 0.05,
		},
		"ui_confirm": {
			"peak": 0.58, "seed": 1402, "pitch_jitter": 0.02, "gain_jitter": 0.0,
			"min_gap": 0.1,
		},
		"ui_back": {
			"peak": 0.50, "seed": 1403, "pitch_jitter": 0.02, "gain_jitter": 0.0,
			"min_gap": 0.1,
		},
		"pause_in": {
			"peak": 0.58, "seed": 1404, "pitch_jitter": 0.0, "gain_jitter": 0.0,
			"min_gap": 0.15, "duck": 6.0,
		},
		"pause_out": {
			"peak": 0.54, "seed": 1405, "pitch_jitter": 0.0, "gain_jitter": 0.0,
			"min_gap": 0.15,
		},

		# --- ambience ---
		# Half the mix rate: the wind carries nothing above 5 kHz, so this
		# halves the resident memory of the longest sample in the game.
		"wind": {
			"peak": 0.30, "db": -13.0, "seed": 1501, "rate": 11025, "loop": true,
			"pitch_jitter": 0.0, "gain_jitter": 0.0, "min_gap": 0.0,
		},
	}


## Shorthand the game is allowed to use, so a caller can say `play("land")`
## without knowing that landings come in two weights.
static func aliases() -> Dictionary:
	return {
		"land": "land_soft",
		"step": "step_run",
		"footstep": "step_run",
		"attack": "sword",
		"swing": "sword",
		"hit": "sword_hit",
		"grab": "ledge_grab",
		"mantle": "climb",
		"death": "die",
		"died": "die",
		"pickup": "relic",
		"door": "exit",
		"complete": "level_complete",
		"menu_move": "ui_move",
		"menu_confirm": "ui_confirm",
		"menu_back": "ui_back",
		"pause": "pause_in",
		"unpause": "pause_out",
		"resume": "pause_out",
		"ambience": "wind",
	}


static func names() -> PackedStringArray:
	var out := PackedStringArray()
	for name: String in specs():
		out.append(name)
	return out


## Every string the game may hand to AudioDirector.play(). The test walks this
## list and fails if any of it stops resolving.
static func event_names() -> PackedStringArray:
	var out := names()
	for alias: String in aliases():
		out.append(alias)
	return out


static func resolve(event: String) -> String:
	if specs().has(event):
		return event
	var alias: String = aliases().get(event, "")
	return alias


static func spec(name: String) -> Dictionary:
	var resolved := resolve(name)
	return specs().get(resolved, {})


static func rate_of(name: String) -> int:
	return int(spec(name).get("rate", Synth.RATE))


## The finished sample buffer for one voice, after normalisation. Tests and the
## preview renderer measure this; `build()` wraps it for playback.
static func build_buffer(name: String) -> PackedFloat32Array:
	var resolved := resolve(name)
	var row: Dictionary = specs().get(resolved, {})
	if row.is_empty():
		push_warning("Voices: unknown voice '%s'" % name)
		return PackedFloat32Array()

	var rate := int(row.get("rate", Synth.RATE))
	var buf := _render(resolved, rate, int(row.get("seed", 1)))
	Synth.remove_dc(buf)
	# A 35 Hz highpass on everything. Nothing in this game is meant to be felt
	# rather than heard, a phone speaker reproduces none of it, and infrasonic
	# energy from an asymmetric square or a swept membrane only eats headroom
	# that normalisation would then take out of the audible part.
	Synth.one_pole(buf, 35.0, true, rate)
	# Stacked layers can poke past full scale; saturate the transient rather
	# than let normalisation pull the whole voice down around one spike.
	Synth.soft_clip(buf, 1.15)
	# Fades before normalisation, so the declared peak is the peak the baked
	# sample actually has even when the loudest moment is the first transient.
	if not bool(row.get("loop", false)):
		Synth.fade_edges(buf, 0.0008, 0.004, rate)
	Synth.normalize(buf, float(row.get("peak", 0.8)))
	return buf


static func build(name: String) -> AudioStreamWAV:
	var resolved := resolve(name)
	var row: Dictionary = specs().get(resolved, {})
	if row.is_empty():
		return null
	var buf := build_buffer(resolved)
	return Synth.to_wav(buf, int(row.get("rate", Synth.RATE)),
		bool(row.get("loop", false)))


## --- recipes ---------------------------------------------------------------

static func _render(name: String, rate: int, seed_value: int) -> PackedFloat32Array:
	match name:
		"step_run": return _step(rate, seed_value, 1.0)
		"step_walk": return _step(rate, seed_value, 0.55)
		"cloth": return _cloth(rate, seed_value)
		"jump": return _jump(rate, seed_value)
		"land_soft": return _land(rate, seed_value, false)
		"land_hard": return _land(rate, seed_value, true)
		"ledge_grab": return _ledge_grab(rate, seed_value)
		"climb": return _climb(rate, seed_value)
		"ladder": return _ladder(rate, seed_value)
		"sword": return _sword(rate, seed_value)
		"sword_hit": return _sword_hit(rate, seed_value)
		"guard_hit": return _guard_hit(rate, seed_value)
		"hurt": return _hurt(rate, seed_value)
		"die": return _die(rate, seed_value)
		"relic": return _relic(rate, seed_value)
		"exit": return _exit(rate, seed_value)
		"level_complete": return _level_complete(rate, seed_value)
		"ui_move": return _ui_move(rate, seed_value)
		"ui_confirm": return _ui_arpeggio(rate, seed_value, true)
		"ui_back": return _ui_arpeggio(rate, seed_value, false)
		"pause_in": return _pause(rate, seed_value, true)
		"pause_out": return _pause(rate, seed_value, false)
		"wind": return _wind(rate, seed_value)
		_: return PackedFloat32Array()


## A boot on hot stone: a narrow band of grit with a very short decay over a
## soft low thump for the body weight. `weight` scales walk down from run.
static func _step(rate: int, seed_value: int, weight: float) -> PackedFloat32Array:
	var buf := Synth.buffer(0.085, rate)
	Synth.add_noise(buf, {
		"rate": rate, "len": 0.075, "cutoff": 1900.0 * (0.8 + 0.2 * weight),
		"cutoff_end": 820.0, "q": 1.3, "decay": 0.05, "curve": 3.2,
		"amp": 0.5 * weight, "seed": seed_value,
	})
	# Fine sand on top of the scuff — the only "bright" part of a footstep.
	Synth.add_noise(buf, {
		"rate": rate, "len": 0.03, "cutoff": 4200.0, "band": "high", "q": 0.6,
		"decay": 0.022, "curve": 2.0, "amp": 0.1 * weight, "seed": seed_value + 7,
	})
	Synth.add_tone(buf, {
		"rate": rate, "len": 0.07, "freq": 128.0, "freq_end": 74.0,
		"decay": 0.055, "curve": 2.4, "amp": 0.22 * weight, "attack": 0.002,
	})
	return buf


## Cloak movement. Band-limited noise swept up and back down, quiet enough to
## sit under everything else; the director retriggers it constantly.
static func _cloth(rate: int, seed_value: int) -> PackedFloat32Array:
	var buf := Synth.buffer(0.14, rate)
	Synth.add_noise(buf, {
		"rate": rate, "len": 0.12, "cutoff": 760.0, "cutoff_end": 2100.0,
		"sweep_curve": 0.7, "q": 0.9, "attack": 0.02, "decay": 0.1, "curve": 1.6,
		"amp": 0.42, "seed": seed_value,
	})
	return buf


## The push-off: cloth lifting plus a short low body impulse. No "boing".
static func _jump(rate: int, seed_value: int) -> PackedFloat32Array:
	var buf := Synth.buffer(0.2, rate)
	Synth.add_noise(buf, {
		"rate": rate, "len": 0.16, "cutoff": 480.0, "cutoff_end": 2600.0,
		"sweep_curve": 0.8, "q": 1.0, "attack": 0.012, "decay": 0.14, "curve": 2.0,
		"amp": 0.38, "seed": seed_value,
	})
	Synth.add_tone(buf, {
		"rate": rate, "len": 0.1, "freq": 150.0, "freq_end": 88.0,
		"decay": 0.08, "curve": 2.2, "amp": 0.3,
	})
	Synth.add_noise(buf, {
		"rate": rate, "len": 0.05, "cutoff": 1500.0, "cutoff_end": 900.0,
		"q": 1.2, "decay": 0.04, "curve": 3.0, "amp": 0.22, "seed": seed_value + 3,
	})
	return buf


## Landing. The soft and hard weights are the same instrument at different
## scales so a scaled-by-impact landing reads as one event, not two sounds.
static func _land(rate: int, seed_value: int, hard: bool) -> PackedFloat32Array:
	var length := 0.42 if hard else 0.22
	var buf := Synth.buffer(length, rate)
	var thump_f := 178.0 if hard else 142.0
	Synth.add_tone(buf, {
		"rate": rate, "len": 0.3 if hard else 0.16, "freq": thump_f,
		"freq_end": 44.0 if hard else 62.0, "sweep_curve": 0.6,
		"decay": 0.26 if hard else 0.13, "curve": 2.2,
		"amp": 0.85 if hard else 0.5, "attack": 0.0015,
	})
	Synth.add_noise(buf, {
		"rate": rate, "len": 0.12 if hard else 0.07, "cutoff": 1500.0,
		"cutoff_end": 520.0, "q": 1.1, "decay": 0.1 if hard else 0.06,
		"curve": 2.8, "amp": 0.46 if hard else 0.26, "seed": seed_value,
	})
	if hard:
		# Stone cracking under the heel, and a short rumble that is gone before
		# the player can act again.
		Synth.add_noise(buf, {
			"rate": rate, "len": 0.03, "cutoff": 5200.0, "band": "high",
			"q": 0.7, "decay": 0.02, "curve": 1.6, "amp": 0.3, "seed": seed_value + 11,
		})
		Synth.add_noise(buf, {
			"rate": rate, "start": 0.012, "len": 0.34, "cutoff": 210.0,
			"band": "low", "q": 0.8, "attack": 0.004, "decay": 0.3, "curve": 2.6,
			"amp": 0.5, "seed": seed_value + 19,
		})
	return buf


## Hands catching an edge: a scuff that starts bright and shuts down fast,
## with a dull knock of knuckles and a little cloth.
static func _ledge_grab(rate: int, seed_value: int) -> PackedFloat32Array:
	var buf := Synth.buffer(0.26, rate)
	Synth.add_noise(buf, {
		"rate": rate, "len": 0.1, "cutoff": 2900.0, "cutoff_end": 700.0,
		"sweep_curve": 1.4, "q": 1.1, "decay": 0.085, "curve": 3.0,
		"amp": 0.5, "seed": seed_value,
	})
	Synth.add_tone(buf, {
		"rate": rate, "len": 0.1, "freq": 96.0, "freq_end": 70.0,
		"decay": 0.09, "curve": 2.0, "amp": 0.34,
	})
	Synth.add_noise(buf, {
		"rate": rate, "start": 0.03, "len": 0.16, "cutoff": 900.0,
		"cutoff_end": 1700.0, "q": 0.8, "attack": 0.02, "decay": 0.14,
		"curve": 1.8, "amp": 0.16, "seed": seed_value + 5,
	})
	return buf


## The mantle: a longer boot-and-forearm scrape over the lip, with the grain
## of the stone in the amplitude rather than a smooth swell.
static func _climb(rate: int, seed_value: int) -> PackedFloat32Array:
	var buf := Synth.buffer(0.34, rate)
	var rng := Synth.Rng.new(seed_value)
	for i: int in 5:
		Synth.add_noise(buf, {
			"rate": rate, "start": 0.02 + float(i) * 0.055,
			"len": 0.09, "cutoff": 1100.0 + rng.unit() * 1400.0,
			"cutoff_end": 620.0, "q": 1.2, "attack": 0.008, "decay": 0.07,
			"curve": 2.4, "amp": 0.2 + rng.unit() * 0.16, "seed": seed_value + i * 13,
		})
	Synth.add_tone(buf, {
		"rate": rate, "start": 0.24, "len": 0.1, "freq": 120.0, "freq_end": 82.0,
		"decay": 0.09, "curve": 2.2, "amp": 0.3,
	})
	return buf


## A wooden rung: a hard, heavily damped pluck, which is a tap with a pitch.
static func _ladder(rate: int, seed_value: int) -> PackedFloat32Array:
	var buf := Synth.buffer(0.1, rate)
	Synth.add_pluck(buf, {
		"rate": rate, "len": 0.095, "freq": 392.0, "decay": 0.075,
		"brightness": 0.85, "amp": 0.5, "seed": seed_value, "release": 0.03,
	})
	Synth.add_noise(buf, {
		"rate": rate, "len": 0.02, "cutoff": 2600.0, "q": 0.8, "decay": 0.016,
		"curve": 2.0, "amp": 0.22, "seed": seed_value + 3,
	})
	return buf


## The sword. A pitched sweep falling 2.6 kHz -> 700 Hz is the blade moving
## air; the noise transient on the front is the hand committing to it; two
## inharmonic partials give the steel somewhere to ring.
static func _sword(rate: int, seed_value: int) -> PackedFloat32Array:
	var buf := Synth.buffer(0.3, rate)
	Synth.add_noise(buf, {
		"rate": rate, "len": 0.025, "cutoff": 3400.0, "band": "high", "q": 0.7,
		"decay": 0.018, "curve": 1.8, "amp": 0.45, "seed": seed_value,
	})
	Synth.add_noise(buf, {
		"rate": rate, "len": 0.2, "cutoff": 2600.0, "cutoff_end": 700.0,
		"sweep_curve": 1.3, "q": 2.6, "attack": 0.006, "decay": 0.18,
		"curve": 2.0, "amp": 0.5, "seed": seed_value + 9,
	})
	Synth.add_tone(buf, {
		"rate": rate, "len": 0.18, "freq": 2550.0, "freq_end": 760.0,
		"sweep_curve": 1.3, "shape": Synth.SHAPE_TRIANGLE, "attack": 0.004,
		"decay": 0.16, "curve": 2.4, "amp": 0.3,
	})
	Synth.add_tone(buf, {
		"rate": rate, "start": 0.004, "len": 0.16, "freq": 1910.0,
		"freq_end": 1180.0, "decay": 0.14, "curve": 3.0, "amp": 0.12,
	})
	return buf


## Steel on steel: three partials that are not a chord, plus a bright crack.
static func _sword_hit(rate: int, seed_value: int) -> PackedFloat32Array:
	var buf := Synth.buffer(0.4, rate)
	var partials := [1240.0, 1867.0, 2631.0, 3910.0]
	var gains := [0.5, 0.34, 0.22, 0.12]
	for i: int in partials.size():
		Synth.add_tone(buf, {
			"rate": rate, "len": 0.34, "freq": float(partials[i]),
			"freq_end": float(partials[i]) * 0.985, "decay": 0.3 - 0.05 * float(i),
			"curve": 2.6, "amp": float(gains[i]), "attack": 0.001,
		})
	Synth.add_noise(buf, {
		"rate": rate, "len": 0.04, "cutoff": 4600.0, "band": "high", "q": 0.8,
		"decay": 0.03, "curve": 2.0, "amp": 0.4, "seed": seed_value,
	})
	Synth.add_tone(buf, {
		"rate": rate, "len": 0.09, "freq": 190.0, "freq_end": 110.0,
		"decay": 0.08, "curve": 2.2, "amp": 0.26,
	})
	return buf


## Sword into a guard: cloth and body, no ring. Deliberately duller than
## sword_hit so the two read as different materials.
static func _guard_hit(rate: int, seed_value: int) -> PackedFloat32Array:
	var buf := Synth.buffer(0.26, rate)
	Synth.add_tone(buf, {
		"rate": rate, "len": 0.18, "freq": 165.0, "freq_end": 82.0,
		"sweep_curve": 0.7, "decay": 0.16, "curve": 2.4, "amp": 0.6,
	})
	Synth.add_noise(buf, {
		"rate": rate, "len": 0.12, "cutoff": 1150.0, "cutoff_end": 420.0,
		"q": 1.0, "decay": 0.1, "curve": 2.6, "amp": 0.4, "seed": seed_value,
	})
	Synth.add_noise(buf, {
		"rate": rate, "len": 0.05, "cutoff": 2400.0, "q": 0.7, "decay": 0.04,
		"curve": 2.2, "amp": 0.14, "seed": seed_value + 5,
	})
	return buf


## Taking a hit: a saturated square dropping a minor third, which is the mode's
## own colour used as pain, plus breath.
static func _hurt(rate: int, seed_value: int) -> PackedFloat32Array:
	var buf := Synth.buffer(0.34, rate)
	Synth.add_tone(buf, {
		"rate": rate, "len": 0.26, "freq": 330.0, "freq_end": 176.0,
		"sweep_curve": 0.5, "shape": Synth.SHAPE_SQUARE, "duty": 0.42,
		"attack": 0.003, "decay": 0.24, "curve": 2.2, "amp": 0.45,
	})
	Synth.add_tone(buf, {
		"rate": rate, "len": 0.2, "freq": 110.0, "freq_end": 88.0,
		"decay": 0.18, "curve": 2.0, "amp": 0.35,
	})
	Synth.add_noise(buf, {
		"rate": rate, "len": 0.14, "cutoff": 1700.0, "cutoff_end": 600.0,
		"q": 0.9, "decay": 0.12, "curve": 2.4, "amp": 0.3, "seed": seed_value,
	})
	return buf


## Death: the Hijaz tetrachord walked downwards on a saturated reed, under a
## tonic drone that outlives it. 1.5 s, which fits inside Game.DEATH_HOLD.
static func _die(rate: int, seed_value: int) -> PackedFloat32Array:
	var buf := Synth.buffer(1.5, rate)
	# D4, Db4, Bb3, A3 — the descent that ends an Andalusian phrase.
	var steps := [293.66, 277.18, 233.08, 220.0]
	for i: int in steps.size():
		Synth.add_tone(buf, {
			"rate": rate, "start": 0.02 + float(i) * 0.17, "len": 0.5,
			"freq": float(steps[i]), "shape": Synth.SHAPE_SQUARE, "duty": 0.3,
			"attack": 0.01, "decay": 0.42, "curve": 2.6,
			"amp": 0.3 - 0.03 * float(i), "vibrato_hz": 5.5, "vibrato_cents": 22.0,
		})
	Synth.add_tone(buf, {
		"rate": rate, "len": 1.45, "freq": 73.42, "freq_end": 69.3,
		"shape": Synth.SHAPE_SAW, "attack": 0.02, "decay": 1.4, "curve": 1.6,
		"amp": 0.4,
	})
	Synth.add_noise(buf, {
		"rate": rate, "start": 0.0, "len": 0.5, "cutoff": 900.0,
		"cutoff_end": 260.0, "q": 0.8, "attack": 0.01, "decay": 0.46,
		"curve": 2.0, "amp": 0.3, "seed": seed_value,
	})
	Synth.add_noise(buf, {
		"rate": rate, "start": 0.72, "len": 0.6, "cutoff": 420.0,
		"cutoff_end": 180.0, "q": 0.7, "attack": 0.08, "decay": 0.5,
		"curve": 1.8, "amp": 0.14, "seed": seed_value + 3,
	})
	return buf


## A relic: struck brass. Two plucks a fifth apart with a bright inharmonic
## partial on top — gold catching the light, over in half a second.
static func _relic(rate: int, seed_value: int) -> PackedFloat32Array:
	var buf := Synth.buffer(0.6, rate)
	Synth.add_pluck(buf, {
		"rate": rate, "len": 0.58, "freq": 880.0, "decay": 0.8,
		"brightness": 0.9, "amp": 0.4, "seed": seed_value, "release": 0.12,
	})
	Synth.add_pluck(buf, {
		"rate": rate, "start": 0.07, "len": 0.5, "freq": 1318.5, "decay": 0.6,
		"brightness": 0.95, "amp": 0.3, "seed": seed_value + 1, "release": 0.12,
	})
	Synth.add_tone(buf, {
		"rate": rate, "len": 0.4, "freq": 2637.0, "freq_end": 2610.0,
		"attack": 0.002, "decay": 0.36, "curve": 3.0, "amp": 0.13,
	})
	Synth.add_noise(buf, {
		"rate": rate, "len": 0.02, "cutoff": 5000.0, "band": "high", "q": 0.7,
		"decay": 0.016, "curve": 2.0, "amp": 0.16, "seed": seed_value + 2,
	})
	return buf


## The door: stone grinding open, then light. A low rising band of noise under
## a bell-like pluck on the tonic.
static func _exit(rate: int, seed_value: int) -> PackedFloat32Array:
	var buf := Synth.buffer(1.1, rate)
	Synth.add_noise(buf, {
		"rate": rate, "len": 0.6, "cutoff": 180.0, "cutoff_end": 620.0,
		"q": 1.0, "attack": 0.06, "decay": 0.55, "curve": 1.8, "amp": 0.45,
		"seed": seed_value,
	})
	Synth.add_tone(buf, {
		"rate": rate, "len": 0.7, "freq": 73.42, "freq_end": 110.0,
		"shape": Synth.SHAPE_SAW, "attack": 0.05, "decay": 0.65, "curve": 1.6,
		"amp": 0.3,
	})
	Synth.add_pluck(buf, {
		"rate": rate, "start": 0.3, "len": 0.75, "freq": 587.33, "decay": 0.7,
		"brightness": 0.75, "amp": 0.34, "seed": seed_value + 4, "release": 0.2,
	})
	Synth.add_pluck(buf, {
		"rate": rate, "start": 0.42, "len": 0.6, "freq": 880.0, "decay": 0.55,
		"brightness": 0.8, "amp": 0.2, "seed": seed_value + 5, "release": 0.2,
	})
	return buf


## Escaped: three notes of Hijaz on D (D, Eb, F#) answered by the octave, on
## the same plucked instrument the music uses, so it lands as a cadence.
static func _level_complete(rate: int, seed_value: int) -> PackedFloat32Array:
	var buf := Synth.buffer(1.9, rate)
	var notes := [293.66, 311.13, 369.99, 587.33]
	var times := [0.0, 0.16, 0.32, 0.56]
	for i: int in notes.size():
		Synth.add_pluck(buf, {
			"rate": rate, "start": float(times[i]), "len": 1.9 - float(times[i]),
			"freq": float(notes[i]), "decay": 0.9 if i < 3 else 1.5,
			"brightness": 0.78, "amp": 0.34, "seed": seed_value + i,
			"release": 0.4,
		})
	Synth.add_tone(buf, {
		"rate": rate, "start": 0.52, "len": 1.3, "freq": 146.83,
		"shape": Synth.SHAPE_SAW, "attack": 0.03, "decay": 1.25, "curve": 1.7,
		"amp": 0.26,
	})
	# A frame-drum accent, the only percussion outside the music.
	Synth.add_tone(buf, {
		"rate": rate, "start": 0.56, "len": 0.2, "freq": 92.0, "freq_end": 58.0,
		"decay": 0.18, "curve": 2.2, "amp": 0.2,
	})
	return buf


## Menu cursor: a wooden tick. Short enough to hold a key down against.
static func _ui_move(rate: int, seed_value: int) -> PackedFloat32Array:
	var buf := Synth.buffer(0.075, rate)
	Synth.add_pluck(buf, {
		"rate": rate, "len": 0.07, "freq": 660.0, "decay": 0.055,
		"brightness": 0.7, "amp": 0.5, "seed": seed_value, "release": 0.025,
	})
	Synth.add_noise(buf, {
		"rate": rate, "len": 0.012, "cutoff": 3200.0, "band": "high", "q": 0.7,
		"decay": 0.01, "curve": 2.0, "amp": 0.12, "seed": seed_value + 1,
	})
	return buf


## Confirm rises a fourth, back falls one. Same instrument, inverted gesture.
static func _ui_arpeggio(rate: int, seed_value: int, rising: bool) -> PackedFloat32Array:
	var buf := Synth.buffer(0.36, rate)
	var notes := [440.0, 587.33] if rising else [587.33, 392.0]
	for i: int in notes.size():
		Synth.add_pluck(buf, {
			"rate": rate, "start": float(i) * 0.075, "len": 0.34 - float(i) * 0.075,
			"freq": float(notes[i]), "decay": 0.3, "brightness": 0.8,
			"amp": 0.42 if i == 0 else 0.36, "seed": seed_value + i,
			"release": 0.12,
		})
	return buf


## Pause: a swept band of noise plus a dull wooden thunk. Reversed for resume,
## so the two bracket the pause rather than repeating.
static func _pause(rate: int, seed_value: int, closing: bool) -> PackedFloat32Array:
	var buf := Synth.buffer(0.34, rate)
	Synth.add_noise(buf, {
		"rate": rate, "len": 0.26,
		"cutoff": 2400.0 if closing else 420.0,
		"cutoff_end": 320.0 if closing else 2200.0,
		"q": 1.4, "attack": 0.012, "decay": 0.24, "curve": 2.0, "amp": 0.4,
		"seed": seed_value,
	})
	Synth.add_pluck(buf, {
		"rate": rate, "start": 0.16 if closing else 0.0, "len": 0.18,
		"freq": 196.0 if closing else 293.66, "decay": 0.1,
		"brightness": 0.5, "amp": 0.45, "seed": seed_value + 2, "release": 0.05,
	})
	return buf


## Hot wind over a rooftop: overlapping gusts of band-passed noise at drifting
## cutoffs, over a steady low bed, then crossfaded into a seamless loop. No
## oscillator anywhere, so it never reads as a pad.
static func _wind(rate: int, seed_value: int) -> PackedFloat32Array:
	var raw := 4.4
	var buf := Synth.buffer(raw, rate)
	var rng := Synth.Rng.new(seed_value)

	for i: int in 11:
		var start := rng.unit() * (raw - 1.3)
		var length := 0.7 + rng.unit() * 0.9
		var base := 320.0 + rng.unit() * 900.0
		Synth.add_noise(buf, {
			"rate": rate, "start": start, "len": length, "cutoff": base,
			"cutoff_end": base * (0.55 + rng.unit() * 1.1), "q": 1.1,
			"attack": length * 0.45, "decay": length, "curve": 1.2,
			"amp": 0.18 + rng.unit() * 0.22, "seed": seed_value + 17 * (i + 1),
		})
	# The bed: a wide, almost static low band so the gaps between gusts are
	# not silence.
	Synth.add_noise(buf, {
		"rate": rate, "len": raw, "cutoff": 260.0, "band": "low", "q": 0.7,
		"env": "asr", "attack": 0.4, "release": 0.4, "amp": 0.3,
		"seed": seed_value + 101,
	})
	return Synth.crossfade_loop(buf, 0.9, rate)
