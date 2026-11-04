# Audio

No audio files. The terrain atlas is generated from the palette, the skyline
from a seed, the character from polygons — and every sound in the game is
computed from numbers at load time. There is no `.wav`, `.ogg` or `.mp3`
anywhere in the build, no importer settings for audio, and no
`default_bus_layout.tres`.

```
scripts/audio/
  synth.gd ............ oscillators, filtered noise, plucked strings, envelopes
  voices.gd ........... the catalogue: one entry per sound the game can make
  steel_voices.gd ..... the catalogue's fight recipes: clash, disarm, kill, the blow
  music.gd ............ the procedural loop, in two stems
  audio_director.gd ... autoload: buses, player pool, variation, ducking
  player_audio.gd ..... the character's body — footsteps, cloth, sword, damage
  fighter_audio.gd .... a duellist's body — the thrust, the clash, the disarm, the kill
  mix.gd .............. the gain law: music trim, mood, duck, drive (read by both below)
  mix_render.gd ....... the mix rendered offline and measured as a phone plays it
  audio_settings.gd ... volumes and mute, persisted to user://
  render_previews.gd .. writes and measures docs/audio/*.wav (a tool, not a build input)
```

## Playing a sound

```gdscript
AudioDirector.play("land", {"pitch": 1.2})
AudioDirector.play("relic")
AudioDirector.set_intensity(0.8)   # raises the music
AudioDirector.duck(6.0)            # pull the music down for a moment
```

`play()` takes `pitch`, `volume_db`, `vary` (set `false` to defeat the random
variation) and `force` (ignore the voice's minimum gap). It returns the player,
or `null` when the sound was deliberately dropped — muted, throttled, still
baking, or waiting for a browser gesture. Dropping is normal; never assume a
return value.

Event names are the voice names in `Voices.specs()`, plus the shorthand in
`Voices.aliases()` (`land`, `step`, `attack`, `hit`, `grab`, `death`, `pickup`,
`door`, `complete`, `menu_move`, `menu_confirm`, `menu_back`, `pause`,
`unpause`, `ambience`). `tests/audio_director_test.gd` fails if any of them
stops resolving.

## The synthesis approach

Four primitives in `synth.gd`, all writing float samples into a
`PackedFloat32Array`:

| Primitive | What it is | What it buys |
| --- | --- | --- |
| `add_tone` | oscillator (sine/triangle/square/saw) with an exponential pitch sweep, vibrato and an AD or ASR envelope | bodies, thumps, drones, the sword's falling whistle |
| `add_noise` | white noise through a resonant zero-delay-feedback state variable filter whose cutoff can sweep | every footstep, scrape, gust and cloth movement |
| `add_pluck` | Karplus–Strong: a noise-filled delay line, averaged and damped as it circulates | the oud, wooden ticks, struck brass |
| envelopes | `env_ad` (percussive) and `env_asr` (held) | the difference between a step and a drone |

A voice is a handful of those stacked at offsets, then put through one fixed
chain in `Voices.build_buffer()`: remove DC, highpass at 35 Hz, `tanh`
saturation, fade the edges, normalise to the voice's declared peak. Baking with
`Synth.to_wav()` produces a mono 16-bit `AudioStreamWAV` held in memory — not
a stream. A phone decodes nothing, seeks nothing, and the download carries no
audio at all.

Three rules make this work as engineering rather than as noise:

**Determinism.** Noise comes from `Synth.Rng`, a seeded xorshift32, never from
`randf()`. The same parameters always produce byte-identical samples. Without
that, the committed previews would be fiction and nothing could be tested.

**Explicit levels.** `normalize()` is called once per voice with the `peak`
from its spec row. The mix balance — a footstep at 0.40, a hard landing at
0.95 — is therefore baked into the samples, and the only other gain stages are
the director's per-event trim and the bus faders.

**Variation at playback, not at bake.** One sample per voice, played with a
small random pitch and gain offset from its spec. A run cycle fires five
footsteps a second; the identical sample five times a second is a buzz, not
footsteps.

### The sound design

The art direction is a sun-bleached Moorish city at low sun: crimson shadow,
gold light, hard edges, nothing soft or gradient. In audio terms:

* **No reverb anywhere.** Decays are dry and short, the way sound behaves in
  dusty open air off hard stone. Nothing is allowed to bloom.
* **Grit, not thud.** Feet, hands and scrapes are narrow bands of noise around
  1–2 kHz, which reads as sandstone rather than as a boot on a boardwalk.
* **Gold is metal that stops.** The sword, the relic and the door are small
  stacks of *inharmonic* partials — 1240 / 1867 / 2631 Hz, not a chord — that
  ring briefly and quit. No shimmer, no sparkle tails.
* **Damage is crimson and low.** Saturated square waves and a drone, not a
  cartoon impact.
* **Pitch carries the mode.** The death figure walks the Hijaz tetrachord down
  (D, Db, Bb, A) and the level-complete flourish answers it, so the sound
  effects and the music are in the same world.

### The music

`music.gd` bakes an Andalusian cadence — i / VII / VI / V, two bars each: Dm, C,
B flat, A — under a melody in **Hijaz on D** (D Eb F# G A Bb C), the
Phrygian-dominant colour with the augmented second between Eb and F#. The last
two bars switch to Hijaz on A so the C sharp pulls the cadence back to the top.
Eight bars at 72 BPM is a **26.7 second loop**, written as fourteen lines of
note data: short in code, long in loop.

The ensemble is a tonic drone that never moves (two saws four cents apart), a
moving root and fifth per section — both lowpassed at 420 Hz before they are
mixed — a plucked oud with grace notes a semitone below the long notes, a
frame drum (`dum` on 1 and the second half of 3, `tek` on 4), and a reed that
doubles the melody, at pitch, over the last two bars.

It is baked as **two stems of identical length**, not two mixes:

* `bed` — drone and oud, always playing;
* `drive` — frame drum and reed.

**Why it is this sparse.** The first score was played on a phone and called
annoying. Measured (below, "The mix"), it was also simply loud: within a
decibel of the sound effects' RMS over a fight. What changed, and why:

| Was | Is | Why |
| --- | --- | --- |
| 27 melody notes, eighth-note ornaments in every bar, top note D5 | 15 notes, mostly long, nothing above the C sharp | a busy phrase every 27 s is learned by the third pass and heard as a nag from then on; the gaps are where the swords are heard |
| raw saw drone and root | the same saws lowpassed at 420 Hz (`Music.DRONE_LOWPASS`) | a saw's harmonics run through the band a phone plays: on the device the drone was a buzz, not a floor |
| shaker on every eighth, 4–5 kHz | gone | the loudest, most tiring thing in the loop on a phone speaker, and it ticked whenever the prince moved |
| `tek` on 2, 4 and 4& | `tek` on 4 | the drum says "a fight" without competing with the exchange's own rhythm |
| reed an octave up in four bars | at pitch, two bars | the octave put it at 600–1200 Hz, exactly where a phone is loudest and where the sword lives |
| drive resting at 0.28 and rising to ~0.9 in a fight | silent at rest, at most 0.5 in a fight (`PlayerAudio.combat_intensity`); still zero while anything in `PlayerAudio.HUSH` is in the tree (the Eclipse) | the old law made the drum loudest exactly when the swords had to be heard |
| music fader default 0.65 (−3.7 dB) | 0.5 under a fixed −4 dB trim (`Mix.MUSIC_TRIM_DB`) | the trim is under the fader, so a settings file saved at the old default still gets the quieter bed |
| one level everywhere | a duel is 5 dB quieter and has no drum (`Mix.MOODS`) | a duel is two people listening for steel |

`AudioDirector.set_intensity(0..1)` cross-fades the drive over 2.5 seconds,
capped by the mood's ceiling.
Raising the tension costs a volume ramp, not a re-bake, and because both stems
are one loop long and start in the same frame they stay sample-locked.
`PlayerAudio` drives the intensity from the character's state — wounded and in
combat — so the game gets this for free. `FighterAudio` claims the duel's mood
(`GameAudio.set_mood(Mix.MOOD_DUEL, self)`); the claim lasts while the fighter
is in the tree, so leaving a duel can never leave the menu in its mood.

The loop joins seamlessly: notes are rendered into a buffer three seconds
longer than the loop and the tail is then **folded back onto the head**
(`Synth.fold_tail`), so a pluck ringing past the end rings into the start of
the next pass. The wind, which has no note structure, is crossfaded instead
(`Synth.crossfade_loop`). The tests assert the step across the seam is small
enough not to click.

Music runs at 16 kHz and the wind at 11 kHz, both mono. They are the largest
resident samples in the game and neither carries anything above 5 kHz, so the
full 22 kHz the sound effects use would be about a megabyte of headroom spent
on nothing.

## Buses

Created from code in `AudioDirector._ensure_buses()` — there is no bus layout
resource to keep in sync:

| Bus | Index | Sends to | Carries |
| --- | --- | --- | --- |
| `Master` | 0 | — | the mute, master volume, a hard limiter at −0.3 dB |
| `Music` | 1 | Master | the two music stems; the trim, the mood and the duck are applied here |
| `SFX` | 2 | Master | the one-shot pool and the ambience bed |

Adding a bus is idempotent by name, so reloading a scene or instantiating a
second director in a test cannot stack duplicates.

Twelve `AudioStreamPlayer`s make up the one-shot pool. Overlapping one-shots
are the normal case in a platformer — a footstep under a sword swing under a
relic pickup — so a single player would cut them off; the pool hands out the
longest-idle player and only steals a busy one when all twelve are in use.

**Ducking.** A voice with a `duck` value in its spec pulls the music bus down
by that many dB when it plays; the bus climbs back at 11 dB/s after a 180 ms
hold (`Mix.DUCK_HOLD`, long enough to cover the body of a blow). Every combat
voice ducks: a swing 2.5 dB, a wound or a steel-on-steel hit 4, a clash 5, a
disarm or a hurt 6, a kill 10, the prince's death 12. A hard landing takes 4.5.

**The limiter.** A killing blow is the wound and the kill on the same frame;
offline that sums to +4.5 dBFS before the master fader. A hard limiter on
Master rounds it instead of letting a phone's DAC square it off.

## The mix

The owner played on a phone and said the music was too annoying, the sword
fighting could not be heard and nor could a death. That is a claim about one
sound against another through a small speaker, which no per-voice number can
check, so `MixRender` (`scripts/audio/mix_render.gd`) mixes a scene offline
with the game's own stems, voices, spec trims, faders, mood and duck (all read
from `Mix`, as the director reads them), and measures it **as a phone plays
it**: through a second-order highpass at 400 Hz, below which a phone speaker
reproduces next to nothing. A cue's level is its loudest 50 ms window at the
gain it was played at; the music under it is the 300 ms after it starts.

Two scenes: a duel exchange (thrusts, two clashes, a disarm, a kill) and an
adventure guard fight (swing, wound, the guard's cut parried, a hit taken, the
killing blow, the prince's death). Rendered at the default faders, from 3 s
into the loop.

**Before** (main at d2db068). The duel cued nothing but the catch, so its
exchange was the music alone; the duel rows below are what the existing
voices *would* have measured had anything cued them.

| Scene | Music RMS (full) | Music RMS (phone) | SFX RMS (phone) | Bed, whole loop (phone) |
| --- | --- | --- | --- | --- |
| duel exchange | −17.9 dBFS | −27.4 | silent | −28.5 |
| guard fight (drive 0.71) | −18.1 dBFS | −27.1 | −23.1 | −26.8 |

| Cue | Level (phone) | Music under | Margin |
| --- | --- | --- | --- |
| `sword` (swing) | −13.4 | −26.9 | +13.5 |
| `guard_hit` (wound on a guard) | −25.6 | −26.9 | **+1.3** |
| `sword_hit` (parry) | −11.0 | −29.1 | +18.1 |
| `hurt` | −15.6 | −30.8 | +15.2 |
| `die` | −14.1 | −32.4 | +18.3 |
| a foe's death | — | — | no voice: only the wound |
| duel clash / disarm / kill | — | — | no voice at all |

The wound on a guard — the sound of the prince's blow landing — was all body
(165 Hz and a low band of noise), which on a phone is nothing: it stood 1.3 dB
over the music. Octave bands said the same: `guard_hit` peaked at 125 Hz and
was at the music's level from 1 kHz up.

**After.**

| Scene | Music RMS (full) | Music RMS (phone) | SFX RMS (phone) | Bed, whole loop (phone) |
| --- | --- | --- | --- | --- |
| duel exchange (mood `duel`) | −31.4 dBFS | −45.8 | −22.9 | −45.3 |
| guard fight (drive 0.35) | −26.9 dBFS | −41.2 | −22.9 | −39.9 |

| Cue | Level (phone) | Margin, duck included | Margin, no duck |
| --- | --- | --- | --- |
| `sword` (duel / adventure) | −13.4 | +33 / +29 | +30 / +25 |
| `clash` | −11.6 | +37 | +33 |
| `disarm` | −10.6 | +39 | +33 |
| `kill` (duel / adventure) | −14.9 | +39 / +33 | +29 / +24 |
| `guard_hit` | −20.6 | +22 | +19 |
| `sword_hit` (parry) | −11.0 | +32 | +28 |
| `hurt` | −15.6 | +29 | +24 |
| `die` | −14.6 | +37 | +27 |

`tests/unit/test_mix_margins.gd` holds this: every combat voice at least
15 dB over the loudest bed a fight plays over (the adventure's drum at the
most a fight raises it), every cue of both scenes 15 dB over the music under
it, the duel's bed a mood's trim under the adventure's, the music at rest
under −24 dBFS RMS, and a kill's duck dipping by its spec and recovering. The
line is 15 because the swing — the quietest thing a fight has to be heard
through — was 13 over the old bed and is 25 over the new one. The suite also
fails if a scene cues a voice that does not exist: the render drops an event
it cannot resolve, and a scene of missing voices would otherwise measure the
music alone and pass.

The two scenes as wav (mix, music and SFX separately) come from a scratch tool
that calls `MixRender.render()` and `Synth.to_wav()`; nothing in the build
needs them.

## Adding a voice

Three edits in `scripts/audio/voices.gd`:

1. A row in `specs()` — the peak to normalise to, a fixed `seed`, and how the
   director may vary it (`pitch_jitter`, `gain_jitter`, `min_gap`, `duck`).
2. A `match` arm in `_render()`.
3. The builder itself: stack `Synth.add_*` calls into a buffer and return it.

```gdscript
"torch": {
    "peak": 0.3, "seed": 1601, "pitch_jitter": 0.1,
    "gain_jitter": 2.0, "min_gap": 0.2,
},
```

```gdscript
static func _torch(rate: int, seed_value: int) -> PackedFloat32Array:
    var buf := Synth.buffer(0.3, rate)
    Synth.add_noise(buf, {
        "rate": rate, "len": 0.3, "cutoff": 700.0, "cutoff_end": 1500.0,
        "q": 1.1, "attack": 0.05, "decay": 0.28, "amp": 0.4,
        "seed": seed_value,
    })
    return buf
```

Then add a length budget to `MAX_SECONDS` in `tests/audio_synth_test.gd`,
re-render the previews and listen:

```bash
godot --headless --path . --script scripts/audio/render_previews.gd
godot --headless --path . --script tests/audio_synth_test.gd
```

The synth test compares the committed `.wav` files against freshly synthesised
samples, so a change that is not re-rendered fails rather than leaving the
documentation lying.

## Verifying without ears

Build machines here have no audio device: ALSA fails, Godot falls back to its
dummy driver, and nobody — human or agent — can listen. So the checks a pair of
ears would make are made numerically.

`render_previews.gd` prints length, mix rate, peak, RMS and DC offset for every
voice, and `tests/audio_synth_test.gd` turns those into assertions: a per-voice
length budget, peak within 0.01 of the declared target and never above 0.98,
RMS above a silence floor and below the peak, |DC| under 0.002, and an
eight-window envelope whose tail has dropped to under half the attack. The
music stems additionally have to be the same length to the sample, and the step
across the loop seam has to stay below 0.08.

That catches the failures that matter without listening: a two-second footstep,
a voice clipping at full scale, a buffer that came out silent, a filter railed
to DC, a loop that clicks, a stem pair that drifts apart.

Two real bugs were found exactly this way and are worth knowing about:

* The first `add_noise` used a naive Chamberlin state variable filter, which is
  only stable while the cutoff stays well below Nyquist. The 4–5 kHz bands that
  give the footsteps their grit blew it up into a DC rail — inaudible on a
  phone, and a measured DC offset of −0.27 on a voice whose other samples were
  tiny. It is now a zero-delay-feedback topology, stable at any cutoff.
* Karplus–Strong circulates whatever DC its excitation had, because the
  averaging filter in the loop has unity gain at DC. Every pluck carried a
  thump under the pitch until the delay line was centred before plucking.

**Known cosmetic artifact.** Godot reports `ObjectDB instances leaked at exit`
whenever an `AudioStreamPlayer` still holds a live playback as the engine shuts
down: `stop()` only queues the playback for removal on the AudioServer's next
mix, and at shutdown that mix never comes. Two places hit it, neither of them a
defect:

* the game at exit, with three playbacks — the two music stems and the wind,
  which are playing by design. It reproduces with nothing but a bare
  `AudioStreamPlayer` and a looping stream, so no amount of cleanup in
  `_exit_tree` prevents it. The director stops its players and drops its
  streams there anyway.
* `tests/audio_director_test.gd`, which fires several dozen one-shots inside a
  two-frame headless run. The test says so on its last line.

### The previews

`docs/audio/` holds one `.wav` per voice, the two music stems, and a 42-second
excerpt of the music with the intensity ramped from the bed alone up to the
full ensemble. They are **documentation for a human ear, not build inputs**:
the directory carries a `.gdignore` so Godot never imports them, and nothing in
the game loads anything from there.

```
| voice | s | rate | peak | rms | dc | file kB |
| --- | --- | --- | --- | --- | --- | --- |
| step_run | 0.085 | 22050 | 0.400 | 0.0671 | -0.00015 | 3 |
| step_walk | 0.085 | 22050 | 0.260 | 0.0377 | -0.00009 | 3 |
| cloth | 0.140 | 22050 | 0.220 | 0.0442 | -0.00000 | 6 |
| jump | 0.200 | 22050 | 0.520 | 0.0998 | -0.00003 | 8 |
| land_soft | 0.220 | 22050 | 0.620 | 0.1406 | -0.00001 | 9 |
| land_hard | 0.420 | 22050 | 0.950 | 0.2248 | +0.00022 | 18 |
| ledge_grab | 0.260 | 22050 | 0.600 | 0.0820 | +0.00000 | 11 |
| climb | 0.340 | 22050 | 0.460 | 0.0612 | +0.00002 | 14 |
| ladder | 0.100 | 22050 | 0.380 | 0.0453 | -0.00006 | 4 |
| sword | 0.300 | 22050 | 0.780 | 0.1128 | -0.00002 | 12 |
| sword_hit | 0.400 | 22050 | 0.860 | 0.1604 | +0.00012 | 17 |
| guard_hit | 0.260 | 22050 | 0.800 | 0.1515 | +0.00065 | 11 |
| hurt | 0.340 | 22050 | 0.840 | 0.2013 | -0.00071 | 14 |
| die | 1.500 | 22050 | 0.950 | 0.1851 | +0.00046 | 64 |
| clash | 0.300 | 22050 | 0.920 | 0.1397 | +0.00008 | 12 |
| disarm | 0.620 | 22050 | 0.900 | 0.1251 | -0.00006 | 26 |
| kill | 0.720 | 22050 | 0.950 | 0.1472 | +0.00001 | 31 |
| relic | 0.600 | 22050 | 0.700 | 0.0594 | -0.00003 | 25 |
| exit | 1.100 | 22050 | 0.720 | 0.1160 | +0.00033 | 47 |
| level_complete | 1.900 | 22050 | 0.860 | 0.1104 | +0.00014 | 81 |
| secret | 1.200 | 22050 | 0.740 | 0.0920 | -0.00002 | 51 |
| masonry | 0.800 | 22050 | 0.880 | 0.1207 | +0.00001 | 34 |
| chain | 0.120 | 22050 | 0.550 | 0.0545 | -0.00018 | 5 |
| hiss | 0.260 | 22050 | 0.460 | 0.1005 | -0.00006 | 11 |
| yowl | 0.420 | 22050 | 0.620 | 0.1844 | -0.00067 | 18 |
| glass_charge | 0.470 | 22050 | 0.400 | 0.1583 | -0.00000 | 20 |
| shatter | 0.550 | 22050 | 0.600 | 0.0391 | -0.00002 | 23 |
| ui_move | 0.075 | 22050 | 0.420 | 0.0416 | -0.00001 | 3 |
| ui_confirm | 0.360 | 22050 | 0.580 | 0.0428 | -0.00003 | 15 |
| ui_back | 0.360 | 22050 | 0.500 | 0.0423 | -0.00002 | 15 |
| pause_in | 0.340 | 22050 | 0.580 | 0.0789 | -0.00000 | 14 |
| pause_out | 0.340 | 22050 | 0.540 | 0.0571 | -0.00001 | 14 |
| sun_gather | 0.900 | 22050 | 0.620 | 0.1856 | -0.00002 | 38 |
| sunrise | 2.800 | 22050 | 0.800 | 0.1930 | +0.00011 | 120 |
| wind | 3.500 | 11025 | 0.300 | 0.0595 | -0.00001 | 75 |
| music_excerpt | 42.000 | 16000 | 0.920 | 0.1139 | -0.00005 | 1312 |
| music_bed | 26.667 | 16000 | 0.800 | 0.1745 | -0.00007 | 833 |
| music_drive | 26.667 | 16000 | 0.780 | 0.0933 | -0.00003 | 833 |
```

## The character

`PlayerAudio` is a node under `Player`, the same shape as `PlayerArt`: it reads
the parent's state, owns one concern, and nothing in gameplay reads it back.
Remove it and the game is silent but otherwise identical. It needs no changes
to `player.gd` — everything hangs off the existing signals and public state.

Footsteps are **not on a timer**. `PlayerArt` swings the legs with
`sin(state_time * 16)` when running and `sin(state_time * 9)` when walking, so
a foot lands every half cycle of that same wave. `PlayerAudio` watches
`state_time` cross each multiple of π and fires there: 5.09 steps a second
running, 2.87 walking, and a state change restarts the cadence instead of
landing a step mid-stride. Step volume also scales with the actual
`velocity.x`, so the first strides out of idle are lighter than full sprint.

| Event | Sound |
| --- | --- |
| `RUN` / `WALK` cadence | `step_run` / `step_walk`, with cloth every other stride |
| `LADDER` cadence, while moving | `ladder` (a wooden rung) |
| `jumped` | `jump` |
| `landed(impact)` | `land_soft` or `land_hard` above `Tuning.HARD_LAND_SPEED`, with volume from −15 dB and pitch from 1.14 scaled by impact |
| `landed` from a fatal fall (`Player.is_fallen()`) | `land_hard` at pitch 0.68 and +2 dB, `masonry` at 0.6 and −8 dB under it, `cloth` at −1 dB; then `died` adds `die`. Every survivable landing from five tiles down hits at the same speed and sounds the same at 0.92, so this one is pitched apart from all of them |
| `grabbed_ledge` | `ledge_grab` |
| entering `CLIMB_UP` | `climb` |
| `attacked` | `sword` |
| `hurt(remaining)` | `hurt`, pitched down as health drops |
| `died` | `die`, which now opens on the same blow as `kill` |
| entering JUMP/FALL/TURN/CROUCH/LAND/HANG/CLIMB_UP/ATTACK | `cloth`, at a per-state trim |

A foe's death is not the character's to sound: `Bloodshed`
(`scripts/world/bloodshed.gd`) hears every foe's `defeated` and plays `kill`
with the blood, on top of the wound `Game` already plays for the blow.

## The duel

`FighterAudio` is the duel's `PlayerAudio`: a child of `Fighter` in
`scenes/fighter.tscn`, reading the fighter and writing nothing. Before it the
only cue anywhere in `scripts/duel/` was the catch.

| Event | Sound |
| --- | --- |
| entering `THRUSTING` | `sword` |
| entering `DIVEKICK` / `SWEEP` / `POUND` / `ROLLING` / `SNATCH` | `jump` low, `sword` low and soft, `cloth` |
| `clashed` | `clash` (both fighters emit it; the voice's min gap plays it once) |
| `disarmed` | `disarm`: the clash, a lower ring, the blade landing on stone |
| `knocked_down` | `guard_hit` at 0.85 |
| `blade_thrown` | `sword` at 0.7 |
| `died`, unless `replaying` | `kill` |

Seat two is pitched a whole tone under seat one, so two thrusts in the air are
still two people. The presentation signals are already silent while the match
replays a mispredicted frame; `died` is not, so it is heard only when the
fighter is not `replaying`, exactly as `FighterArt`'s flash is.
`tests/unit/test_fighter_audio.gd`.

A landing below 40 px/s is silent — stepping off a kerb should not thud — and
the soft and hard voices are the same instrument at two scales, so a landing
scaled by impact reads as one event rather than as two different sounds.

The autoload is resolved with `get_node_or_null("/root/AudioDirector")`, so the
character scene still works in a test or a tool with no autoloads registered.

## Settings

`AudioSettings` keeps master / music / SFX volume as linear 0–1 values and a
mute flag in `user://audio.cfg`, and converts to the bus faders itself
(`linear_to_db`, with anything at or below 0.001 going to −60 dB). A settings
screen can read and write it without touching the mixer. The music defaults to
0.5.

The file is read **field by field**: a key that is missing, not a number, or
not finite falls back to its own default and takes nothing else with it.
Before, `music = "quiet"` read as 0.0 through `float()` — the music silenced
with no way to tell why. `tests/unit/test_audio_settings_fallback.gd`.

A music fader at zero is music off: the director stops the stems rather than
playing them at −60 dB, and starts them from the top when it comes back up.

```gdscript
AudioDirector.set_volume(&"Music", 0.4)   # saves immediately
AudioDirector.toggle_mute()
AudioDirector.settings.music              # 0..1, for a slider
```

`audio_mute` is bound to **M** in `tools/configure_project.gd`, in a function
of its own (`_apply_audio()`), along with the autoload registration. The
director handles the action itself, so mute works from anywhere.

The settings page (`scripts/ui/settings_panel.gd`) has a gauge each for
MASTER, MUSIC and SWORDS (the SFX bus) and a MUTE switch; the MUSIC gauge is
the separate music volume, and run down to empty it is music off.

## Startup cost

Synthesising every voice plus the two music stems is roughly 2.3 seconds of
GDScript on a desktop CPU, which would be a visible freeze at load. The
director therefore bakes on a `Thread` (`OS.has_feature("threads")`), gameplay
voices first and the music last, and `play()` is simply a no-op for a voice
that has not been baked yet — counted in `warmup_drops()`. Platforms without
thread support, such as a single-threaded web export, fall back to baking one
item per frame.

The obvious next step if this ever matters on a low-end phone is to cache the
baked PCM to `user://` keyed by a synthesis version, turning a few seconds of
CPU per launch into a few milliseconds of file read per install. Nothing in the
build would change.

## Web

Browsers refuse to start an audio context until the player has interacted with
the page, so the first tap arrives *before* any sound can be made and would
normally be swallowed. On web the director holds the most recent request and
fires it as soon as a key, click or touch unlocks the context, and it does not
start the music or the ambience until then.

## What is weak

Honest list, from code that nobody here has been able to hear:

* **The music is the most likely thing to be wrong.** The notes are
  hand-written data and the cadence is real, but 26.7 seconds is a short loop
  for a mode this static, and the oud is a Karplus–Strong string without any
  of the slides or finger noise that make the instrument. Expect it to read as
  "procedural" rather than as a player.
* **The reed in the drive stem is thin.** A ney is mostly breath; a triangle
  with vibrato and a band of noise is a sketch of one. It may sound synthetic
  enough to want cutting at low intensity.
* **The wind may be pointless.** It is eleven overlapping gusts of filtered
  noise at −13 dB, which is honest hot-rooftop air with nothing to say. If it
  reads as tape hiss on a phone speaker, delete `wind` from `specs()` and call
  `set_ambience(false)`; nothing else depends on it.
* **`climb` is a sequence of five scrapes and may read as a stutter** rather
  than as one continuous movement over the lip.
* **The music was measured, not heard, after its rewrite.** The margins above
  say combat now cuts through on a phone; whether the sparser loop is *less
  annoying* is a judgement only a listener can make. If it still is, the next
  lever is length: a sixteen-bar loop with a second, emptier half costs one
  more stem's worth of memory (about 0.85 MB per stem).
* **`hurt` and `die` use saturated squares,** which is the most chiptune-ish
  corner of the whole set and sits slightly apart from the noise-and-pluck
  palette everywhere else.
* **Everything is mono and unpositioned.** There is no panning from the
  character's position relative to the camera, which on headphones is a missed
  opportunity on a game this wide.
* **Nothing is heard below about 300 Hz on a phone speaker.** The low thump of
  a landing, the frame drum's `dum` and the drone's bottom octave are all for
  headphones; the voices are stacked so they still read without them, but that
  is an assumption, not a measurement.
