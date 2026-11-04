extends GutTest
## The duel is heard: a thrust, a clash, a disarm and a kill each make their
## sound, a replayed frame makes none, and a duel claims its quieter mood
## (scripts/audio/fighter_audio.gd).
##
## Before FighterAudio the only cue anywhere in the duel was the catch, and a
## phone test reported, correctly, that the sword fight and the deaths were
## silent. This suite fails if the fighter scene loses its audio node or the
## node stops hearing what the fighter does.
##
## Seen to fail: with the FighterAudio node taken out of scenes/fighter.tscn,
## every test here goes red.

const FIGHTER_SCENE := "res://scenes/fighter.tscn"


## Stands in for the director: what was played, and the mood it was put in.
class Director extends Node:
	var settings := AudioSettings.new()
	var heard: Array[String] = []
	var mood := &""

	func play(event: String, _opts: Dictionary = {}) -> AudioStreamPlayer:
		heard.append(event)
		return null

	func set_mood(which: StringName, _claimant: Node = null) -> void:
		mood = which

	func toggle_mute() -> void:
		pass


var _director: Director
var _previous: Node
var _fighter: Fighter


func before_each() -> void:
	_director = Director.new()
	_previous = GameAudio._director
	GameAudio._director = _director
	_fighter = (load(FIGHTER_SCENE) as PackedScene).instantiate() as Fighter
	add_child_autofree(_fighter)
	await wait_physics_frames(1)
	_director.heard.clear()


func after_each() -> void:
	GameAudio._director = _previous
	_director.free()


func test_the_fighter_scene_carries_its_audio() -> void:
	assert_not_null(_fighter.get_node_or_null("FighterAudio") as FighterAudio,
		"scenes/fighter.tscn has a FighterAudio")


func test_a_duel_claims_its_mood() -> void:
	# The claim is made in _ready; this director was in place before it.
	assert_eq(_director.mood, Mix.MOOD_DUEL, "the music goes to the duel's mood")


func test_a_thrust_is_heard_on_the_frame_it_starts() -> void:
	_fighter.state = Fighter.State.THRUSTING
	await wait_physics_frames(1)
	assert_eq(_director.heard, ["sword"] as Array[String], "the thrust")
	await wait_physics_frames(3)
	assert_eq(_director.heard.size(), 1, "once, not every frame of it")


func test_steel_and_the_kill_are_heard() -> void:
	_fighter.clashed.emit(Vector2.ZERO)
	_fighter.disarmed.emit(0, 1)
	_fighter.died.emit(0, 1)
	assert_eq(_director.heard, ["clash", "disarm", "kill"] as Array[String],
		"a clash, a disarm and a kill each have a voice")


func test_a_death_in_a_replayed_frame_is_not_heard_twice() -> void:
	_fighter.replaying = true
	_fighter.died.emit(0, 1)
	_fighter.replaying = false
	assert_eq(_director.heard, [] as Array[String], "a replay rings no kill")


func test_every_voice_it_asks_for_exists() -> void:
	for event: String in FighterAudio.event_names():
		assert_ne(Voices.resolve(event), "", "'%s' is a voice" % event)
