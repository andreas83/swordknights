extends GutTest
## The death watch (tests/death_watch.gd) is installed, and goes red.
##
## The watch guards against a scene test that is green because the checkpoint
## respawn put a dead prince back on his feet. A guard that is not installed,
## or that never fires, would leave every such test as unguarded as before
## while looking like protection, so this file proves three things:
##
## - the run has it: GUT loaded it as the pre-run hook. In the editor's GUT
##   panel this fails until the panel's pre-run hook is set to the same file.
## - it fires: a second watch, reporting into this test rather than failing
##   it, sees a death the respawn hides completely, and stays quiet for one
##   that was announced -- and speaks up for an announced one that never came.
## - its reach covers the standalone phase too. Those SceneTree scripts are
##   outside GUT and so outside the hook; the one that plays a Game counts its
##   own deaths, and a new one that plays a Game without doing so is refused.

const DeathWatch := preload("res://tests/death_watch.gd")
const GAME_SCENE := "res://scenes/game.tscn"

## Open floor, nobody about, nothing that could kill him by itself.
const OPEN := """; Open Floor








 @              D
###################
###################
"""

var _game: Game
var _probe: DeathWatch
var _heard: Array[String] = []


func before_each() -> void:
	_heard.clear()
	_probe = DeathWatch.new()
	_probe.attach(get_tree(), func(text: String) -> void: _heard.append(text))


func after_each() -> void:
	_probe.detach()


func _play() -> void:
	var data := AsciiLevel.new()
	data.parse(OPEN)
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Game
	_game.level_source = data
	add_child_autofree(_game)
	await wait_physics_frames(4)


## Kills the prince and waits until the checkpoint has him back.
func _die_and_return() -> void:
	_game.player.kill()
	for _frame: int in 120:
		await wait_physics_frames(1)
		if _game.phase == Game.Phase.PLAYING and _game.player.is_alive():
			break
	await wait_physics_frames(2)


func test_the_run_has_the_watch_installed() -> void:
	assert_true(DeathWatch.is_installed(), "GUT ran tests/death_watch.gd as its pre-run hook")
	var hook: Object = gut.get_pre_run_script_instance()
	assert_not_null(hook, "there is a pre-run hook")
	if hook != null:
		assert_eq(hook.get_script(), DeathWatch, "and it is the death watch")


func test_a_death_nobody_announced_is_reported_though_nothing_else_can_tell() -> void:
	await _play()
	var floor_y := _game.player.position.y
	DeathWatch.expect_deaths(1) # for the installed watch; the probe is not told
	await _die_and_return()
	# Exactly the state the respawn leaves behind, and exactly why the guard
	# is needed: alive, whole, standing on the floor where he started.
	assert_true(_game.player.is_alive(), "the respawn brought him back")
	assert_eq(_game.player.health, Tuning.MAX_HEALTH, "whole")
	assert_almost_eq(_game.player.position.y, floor_y, 0.5, "on the floor")
	assert_eq(_heard.size(), 1, "and the watch reported the death all the same")
	if _heard.size() == 1:
		assert_string_contains(_heard[0], "Open Floor", "naming the level")
		assert_string_contains(_heard[0], "expect_deaths", "and how to announce one")
	assert_eq(DeathWatch.deaths_so_far(), 1, "the installed watch counted it too")


func test_an_announced_death_is_not_reported() -> void:
	await _play()
	DeathWatch.expect_deaths(1)
	_probe.expect(1)
	await _die_and_return()
	assert_eq(_probe.seen(), 1, "the death was seen")
	_probe.close_test()
	assert_eq(_heard, [] as Array[String], "and, being announced, not reported")


func test_one_death_more_than_announced_is_reported() -> void:
	await _play()
	DeathWatch.expect_deaths(2)
	_probe.expect(1)
	await _die_and_return()
	await _die_and_return()
	assert_eq(_heard.size(), 1, "the second death was one too many")


func test_an_announced_death_that_never_came_is_reported() -> void:
	await _play()
	_probe.expect(1)
	await wait_physics_frames(10)
	_probe.close_test()
	assert_eq(_heard.size(), 1, "a test that meant him to die and did not kill him is wrong")
	_heard.clear()
	_probe.close_test()
	assert_eq(_heard, [] as Array[String], "and the count starts again for the next test")


## The standalone `*_test.gd` scripts run outside GUT, so the hook cannot
## watch them. Any that plays a scene holding a Game must count the deaths
## itself (character_traversal_test.gd fails on any). A Game-holding scene is
## found by its text, not listed, so a new one is covered as it is written.
func test_a_standalone_test_that_plays_a_game_counts_its_deaths() -> void:
	var scenes: Array[String] = []
	for name: String in DirAccess.get_files_at("res://scenes"):
		if name.get_extension() != "tscn":
			continue
		var text := FileAccess.get_file_as_string("res://scenes".path_join(name))
		if text.contains("scripts/core/game.gd") or text.contains("scenes/game.tscn"):
			scenes.append("res://scenes".path_join(name))
	assert_has(scenes, GAME_SCENE, "found the scenes that hold a Game")

	var playing := 0
	var blind: Array[String] = []
	for name: String in DirAccess.get_files_at("res://tests"):
		if not name.ends_with("_test.gd"):
			continue
		var text := FileAccess.get_file_as_string("res://tests".path_join(name))
		var plays := false
		for scene: String in scenes:
			plays = plays or text.contains(scene)
		if not plays:
			continue
		playing += 1
		if not text.contains(".died.connect("):
			blind.append(name)
	assert_gt(playing, 0, "found the standalone tests that play a Game")
	assert_eq(blind, [] as Array[String],
		"these play a Game without counting deaths, and the respawn hides them")
