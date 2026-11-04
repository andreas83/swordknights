extends GutTest
## DUEL VS CPU as a mode: the scene the duel page's VS CPU row opens -- the
## player on the shared actions in seat one, the computer in seat two at the
## level the page saved, the names on the screen, the wardrobe's second look on
## the computer, and the phone's buttons (scripts/duel/match_cpu.gd,
## scripts/duel/match_hud.gd). The page itself, its levels and what it
## remembers are tests/unit/test_duel_select.gd.
##
## The scene is stepped by its own _physics_process here, as in the game: a
## test that called its step by hand would pass with the scene wired wrong.

const SCENE := preload("res://scenes/duel_match_cpu.tscn")
## The seed the scene-stepping test pins the computer to.
const SEED := 7
## Never the real saves: the scene reads the looks and the level from here.
var _wardrobe := UserData.at("user://test_duel_cpu_mode_wardrobe.cfg")
var _choice := UserData.at("user://test_duel_cpu_mode_choice.cfg")


func after_each() -> void:
	for action: String in ["move_left", "move_right"]:
		Input.action_release(action)
	for path: String in [_wardrobe, _choice]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## What the duel page saves when VS CPU is started at `level`.
func _choose(level: DuelBrain.Difficulty) -> void:
	var choice := DuelChoice.new()
	choice.path = _choice
	choice.way = 1
	choice.level = level
	assert_eq(choice.save(), OK, "the test's choice was written")


func _open() -> Node:
	var scene := SCENE.instantiate()
	scene.set("wardrobe_path", _wardrobe)
	scene.set("choice_path", _choice)
	assert_eq(scene.get("choice_path"), _choice, "the scene took the test's choice file")
	add_child_autofree(scene)
	return scene


func test_with_nothing_saved_the_computer_is_easy() -> void:
	var scene := _open()
	assert_eq(scene.get("level"), DuelBrain.Difficulty.EASY, "the gentlest")


func test_the_scene_seats_the_player_and_the_computer() -> void:
	var two := CharacterLook.new()
	two.take_ids({"figure": "heroine", "accent": "pale", "hair": "henna", "skin": "copper"})
	var wardrobe := Wardrobe.open(_wardrobe)
	wardrobe.set_look(Wardrobe.PLAYER_TWO, two)
	assert_eq(wardrobe.save(), OK, "the test wardrobe was written")

	_choose(DuelBrain.Difficulty.HARD)
	var scene := _open()

	assert_eq(scene.get("level"), DuelBrain.Difficulty.HARD, "the level the page saved")
	var cpu := scene.get("cpu") as DuelCpu
	assert_not_null(cpu, "a computer opponent")
	if cpu == null:
		return
	assert_eq(cpu.seat, 1, "in seat two")
	assert_eq(cpu.brain.level, DuelBrain.Difficulty.HARD, "at HARD")
	assert_eq(scene.call("look_for", 1).to_ids(), two.to_ids(),
		"wearing player two's look from the wardrobe")

	var hud := scene.get_node(^"HudLayer/Hud") as MatchHud
	assert_eq(hud.your_slot, 0, "the screen is the player's, seat one")
	assert_eq(hud.seat_tags, [PackedStringArray(["YOU"]),
		PackedStringArray(["CPU", "HARD"])] as Array[PackedStringArray], "who is who")
	assert_eq(hud.seat_name(1), "CPU")
	assert_eq(scene.call("_down", 0), "YOU ARE DOWN", "the band speaks to the player")
	assert_eq(scene.call("_down", 1), "CPU DOWN")

	var controls := scene.get_node_or_null(^"TouchControls") as TouchControls
	assert_not_null(controls, "the stick, JUMP and SWORD")
	if controls != null:
		assert_true(controls.throw_button, "and THROW, in the same hit test as the rest")


## Played by the scene's own physics frames: the computer closes on a player
## who stands still, and the player walks when the shared action is held.
func test_the_scene_steps_both_seats() -> void:
	_choose(DuelBrain.Difficulty.MEDIUM)
	var scene := _open()
	var fight := scene.get_node(^"World/Match") as DuelMatch
	# The scene seeds the computer from the clock unless told otherwise, and an
	# unlucky seed could have it hold its ground: pin one, so the test measures
	# the seat and not the dice.
	var cpu := scene.get("cpu") as DuelCpu
	assert_not_null(cpu, "the scene has a computer seat")
	cpu.reset(SEED)
	cpu.watch(fight)
	var start_cpu := fight.fighter_position(1)
	var start_you := fight.fighter_position(0)
	await wait_physics_frames(150)
	assert_eq(fight.phase, DuelMatch.Phase.FIGHTING, "past the countdown")
	assert_lt(fight.fighter_position(1).x, start_cpu.x - 16.0,
		"the computer came west, toward the player")
	assert_almost_eq(fight.fighter_position(0).x, start_you.x, 1.0,
		"the player, pressing nothing, stood")
	var stood := fight.fighter_position(0).x
	Input.action_press("move_left")
	await wait_physics_frames(20)
	Input.action_release("move_left")
	assert_lt(fight.fighter_position(0).x, stood - 16.0, "and walked when told to")
