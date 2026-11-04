extends GutTest
## The combat sounds stand clear of the music, on a phone, and the music keeps
## out of their way.
##
## A phone test of the game reported the music annoying and the swords and
## deaths inaudible. Measured with MixRender (scripts/audio/mix_render.gd),
## that was true: a wound on a guard stood 1.3 dB above the music through a
## phone speaker's response, a swing 13 dB, and the duel made no combat sound
## at all. docs/audio.md, "The mix", has the before and after tables. This
## suite holds the after: every combat voice at least MIN_MARGIN_DB above the
## loudest the music bed gets in a fight, both offline scenes cue only voices
## that exist, and a duck dips the music and gives it back.
##
## Seen to fail: with the guard's wound restored to its old body-only recipe,
## or Mix.MUSIC_TRIM_DB raised to +12, the first test goes red.

## How far above the music bed a combat voice's loudest 50 ms must stand on a
## phone. The swing, the quietest thing a fight has to be heard through, was
## 13 dB over the old bed and is 25 over the new one; 15 is the line between.
const MIN_MARGIN_DB := 15.0

## Every voice a fight has to be heard through, in either mode.
const COMBAT := ["sword", "sword_hit", "guard_hit", "clash", "disarm", "hurt", "kill", "die"]


## The loudest bed a fight plays over: the adventure's drum at the most a
## fight can raise it, at the default faders.
func _fight_bed() -> float:
	return MixRender.bed_level({
		"mood": Mix.MOOD_ADVENTURE,
		"intensity": PlayerAudio.combat_intensity(1.0, 1.0),
	})


func test_every_combat_voice_stands_above_the_loudest_fight_bed() -> void:
	var bed := _fight_bed()
	for voice: String in COMBAT:
		assert_ne(Voices.resolve(voice), "", "%s is a voice" % voice)
		var level := float(MixRender.cue_level(voice, 1.0, 1.0)["db"])
		assert_gt(level - bed, MIN_MARGIN_DB,
			"%s at %.1f dB is %.1f dB over the bed at %.1f (a phone, no duck)"
				% [voice, level, level - bed, bed])


func test_each_scene_cues_only_voices_that_exist() -> void:
	# The render drops an event it cannot resolve. A scene whose cues did not
	# exist would then measure the music alone and pass every margin -- which
	# is how the duel would have measured before it had any voices.
	for scene: Array in [MixRender.duel_exchange(), MixRender.guard_fight()]:
		var result := MixRender.render(scene, 5.0)
		assert_eq((result["cues"] as Array).size(), scene.size(), "every cue resolved")
	for event: String in FighterAudio.event_names():
		assert_ne(Voices.resolve(event), "", "the duel's '%s' is a voice" % event)


func test_in_both_scenes_every_cue_clears_the_music_under_it() -> void:
	var scenes := {
		"duel": [MixRender.duel_exchange(), {"mood": Mix.MOOD_DUEL}],
		"guard": [MixRender.guard_fight(), {
			"mood": Mix.MOOD_ADVENTURE,
			"intensity": PlayerAudio.combat_intensity(1.0 / 3.0, 1.0),
		}],
	}
	for name: String in scenes:
		var pair: Array = scenes[name]
		var margins := MixRender.margins(MixRender.render(pair[0], 6.0, pair[1]))
		assert_eq(margins.size(), (pair[0] as Array).size(), "%s: every cue measured" % name)
		for m: Dictionary in margins:
			assert_gt(float(m["margin"]), MIN_MARGIN_DB,
				"%s: %s at %.2f s clears the music by %.1f dB"
					% [name, m["event"], m["at"], m["margin"]])


func test_the_duel_is_quieter_than_the_adventure_and_has_no_drum() -> void:
	var fight := _fight_bed()
	var duel := MixRender.bed_level({"mood": Mix.MOOD_DUEL, "intensity": 1.0})
	assert_lt(duel, fight + Mix.mood_db(Mix.MOOD_DUEL) + 0.5,
		"the duel's bed (%.1f) sits a mood's trim under the fight's (%.1f)" % [duel, fight])
	assert_eq(Mix.mood_intensity_cap(Mix.MOOD_DUEL), 0.0, "no drive stem in a duel")


func test_the_music_is_quieter_than_it_was() -> void:
	# The music bus at the default fader, over a whole loop, full band. It
	# measured -18 dBFS RMS before (docs/audio.md); the line is 6 dB under.
	var n := int(Music.loop_seconds() * float(MixRender.RATE))
	var context := {"mood": Mix.MOOD_ADVENTURE, "intensity": 0.0}
	var bed := MixRender.music_bed(context, n)
	var level := MixRender.db(Synth.rms(bed) * MixRender.music_gain(context))
	assert_lt(level, -24.0, "the music at rest is %.1f dBFS RMS" % level)


func test_a_kill_ducks_the_music_and_lets_it_back() -> void:
	var context := {"mood": Mix.MOOD_DEFAULT}
	var quiet := MixRender.render([], 3.0, context)
	var killed := MixRender.render([[0.5, "kill", {}]], 3.0, context)
	var before: PackedFloat32Array = quiet["music"]
	var after: PackedFloat32Array = killed["music"]
	var depth := float(Voices.spec("kill")["duck"])
	var during := MixRender.db(MixRender.rms_between(after, 0.52, 0.6)) \
		- MixRender.db(MixRender.rms_between(before, 0.52, 0.6))
	assert_almost_eq(during, -depth, 0.5, "the kill pulls the music down by its duck")
	var later := MixRender.db(MixRender.rms_between(after, 2.4, 2.9)) \
		- MixRender.db(MixRender.rms_between(before, 2.4, 2.9))
	assert_almost_eq(later, 0.0, 0.1, "and two seconds on it is back")


func test_a_duck_holds_then_recovers_at_the_documented_rate() -> void:
	var state := Mix.duck_step(6.0, Mix.DUCK_HOLD, 0.05)
	assert_eq(state.x, 6.0, "held")
	state = Mix.duck_step(state.x, 0.0, 0.1)
	assert_almost_eq(state.x, 6.0 - Mix.DUCK_RECOVERY * 0.1, 0.001, "recovering")
	assert_eq(Mix.duck_step(0.5, 0.0, 1.0), Vector2.ZERO, "and gone")
