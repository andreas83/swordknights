extends GutTest
## Every round opens with a beat of its own: ROUND n, or FINAL ROUND, the score,
## and how the LOW guard and the duck are held on this screen's controls
## (scripts/duel/match_hud.gd, THE ROUND; scripts/duel/match_scene.gd).
##
## The match has rung `round_started` since the series came in, and nothing
## listened: the next round simply began on the marks. Seen to fail with the
## scene's connection to it taken out (the second test), and with the hint
## left unset (the first).

const SCENE := preload("res://scenes/duel_match.tscn")
const CPU_SCENE := preload("res://scenes/duel_match_cpu.tscn")
const MatchScene := preload("res://scripts/duel/match_scene.gd")

var _wardrobe := UserData.at("user://test_duel_round_beat_wardrobe.cfg")
var _choice := UserData.at("user://test_duel_round_beat_choice.cfg")


func after_each() -> void:
	for path: String in [_wardrobe, _choice]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _open(packed: PackedScene) -> Node:
	var scene := packed.instantiate()
	scene.set("wardrobe_path", _wardrobe)
	scene.set("choice_path", _choice)
	scene.set("leave", func() -> void: pass)
	add_child_autofree(scene)
	return scene


func test_the_first_round_opens_with_the_guard_hint() -> void:
	var scene := _open(SCENE)
	var hud: MatchHud = scene.get("hud")
	assert_true(hud.is_announcing(), "the match opens on its round's plate")
	assert_eq(hud.round_title(), "ROUND 1")
	assert_eq(hud.stance_hint, MatchScene.HINT_PAIR, "one keyboard: both seats' keys")
	assert_string_contains(hud.stance_hint, "LOW")
	assert_string_contains(hud.stance_hint, "DUCK")


func test_the_next_round_is_announced() -> void:
	var scene := _open(SCENE)
	var hud: MatchHud = scene.get("hud")
	var fight: DuelMatch = scene.get("fight")
	hud.announce_round(0)
	assert_false(hud.is_announcing(), "no plate up")
	fight.series = PackedInt32Array([1, 0])
	fight.round_started.emit(2)
	assert_true(hud.is_announcing(), "round_started puts the plate up")
	assert_eq(hud.round_title(), "ROUND 2")
	fight.series = PackedInt32Array([1, 1])
	fight.round_started.emit(3)
	assert_eq(hud.round_title(), "FINAL ROUND", "one gate each: the next decides it")
	await wait_seconds(MatchHud.ROUND_TIME + 0.2)
	assert_false(hud.is_announcing(), "and it goes as the fight starts")


func test_against_the_computer_the_hint_is_the_shared_keys() -> void:
	var scene := _open(CPU_SCENE)
	var hud: MatchHud = scene.get("hud")
	var want := MatchScene.HINT_STICK if UiLayout.handheld() else MatchScene.HINT_KEYS
	assert_eq(hud.stance_hint, want, "the shared actions' hint, for this device")


## Each hint fits the narrowest screen a duel is played on, a line at a time.
func test_every_hint_fits_a_narrow_screen() -> void:
	var room := 320.0 - UiLayout.GUTTER * 2.0
	var hints := {"pair": MatchScene.HINT_PAIR, "keys": MatchScene.HINT_KEYS,
		"stick": MatchScene.HINT_STICK}
	for name: String in hints:
		var hint: String = hints[name]
		for line: String in hint.split(MatchHud.HINT_BREAK, false):
			assert_lte(UiFont.width(line, UiFont.Cut.MICRO), room,
				"%s: '%s' fits at 320 units" % [name, line])
