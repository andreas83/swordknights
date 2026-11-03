extends GutTest
## DUEL VS CPU as a mode: the menu's row and its three levels, and the scene
## the row opens -- the player on the shared actions in seat one, the computer
## in seat two at the level chosen, the names on the screen, the wardrobe's
## second look on the computer, and the phone's buttons (scripts/ui/menu.gd,
## scripts/duel/match_cpu.gd, scripts/duel/match_hud.gd).
##
## The scene is stepped by its own _physics_process here, as in the game: a
## test that called its step by hand would pass with the scene wired wrong.

const MENU := preload("res://scenes/menu.tscn")
const SCENE := preload("res://scenes/duel_match_cpu.tscn")
const MODE := "duel_cpu"
## Never the real save: the scene reads the looks from here.
const WARDROBE := "user://test_duel_cpu_mode_wardrobe.cfg"


func before_each() -> void:
	ModeRegistry.choose(MODE, 0)


func after_each() -> void:
	for action: String in ["move_left", "move_right"]:
		Input.action_release(action)
	ModeRegistry.choose(MODE, 0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WARDROBE))


func test_the_menu_offers_the_computer_at_three_levels() -> void:
	var menu := MENU.instantiate() as MenuScene
	add_child_autofree(menu)
	var at := _row(menu, MODE)
	assert_gte(at, 0, "the menu has a DUEL VS CPU row")
	if at < 0:
		return
	var row := menu.rows()[at]
	assert_eq(String(row["title"]), "DUEL VS CPU")
	assert_eq(row["choices"], PackedStringArray(["EASY", "MEDIUM", "HARD"]))
	assert_eq(int(row["choice"]), 0, "it opens on EASY, the gentlest")
	assert_true(ResourceLoader.exists(String(row["scene"])), "and points at a scene")

	# Left and right step the level on that row, stop at the ends, and the
	# scene the row opens reads what they chose.
	menu.shift_choice(1)
	assert_eq(ModeRegistry.chosen(MODE), 0, "not while another row is selected")
	for _step: int in menu.rows().size():
		if menu.index() == at:
			break
		menu.move(1)
	assert_eq(menu.index(), at, "selected")
	menu.shift_choice(1)
	assert_eq(ModeRegistry.chosen(MODE), 1, "right: MEDIUM")
	menu.shift_choice(1)
	menu.shift_choice(1)
	assert_eq(ModeRegistry.chosen(MODE), 2, "right twice more: HARD, and no further")
	menu.shift_choice(-1)
	assert_eq(int(menu.rows()[at]["choice"]), 1, "left: back to MEDIUM")


func test_left_and_right_do_nothing_on_a_row_without_choices() -> void:
	var menu := MENU.instantiate() as MenuScene
	add_child_autofree(menu)
	var at := _row(menu, "adventure")
	assert_eq(menu.index(), at, "the menu opens on ADVENTURE")
	menu.shift_choice(1)
	assert_eq(menu.index(), at, "the selection did not move")
	assert_eq(ModeRegistry.chosen("adventure", -1), -1, "and nothing was chosen")
	assert_eq(ModeRegistry.chosen(MODE), 0, "nor for the computer")


func test_the_scene_seats_the_player_and_the_computer() -> void:
	var two := CharacterLook.new()
	two.take_ids({"figure": "heroine", "accent": "pale", "hair": "henna", "skin": "copper"})
	var wardrobe := Wardrobe.open(WARDROBE)
	wardrobe.set_look(Wardrobe.PLAYER_TWO, two)
	assert_eq(wardrobe.save(), OK, "the test wardrobe was written")

	ModeRegistry.choose(MODE, DuelBrain.Difficulty.HARD)
	var scene := SCENE.instantiate()
	scene.set("wardrobe_path", WARDROBE)
	add_child_autofree(scene)

	assert_eq(scene.get("level"), DuelBrain.Difficulty.HARD, "the level the menu chose")
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

	assert_not_null(scene.get_node_or_null(^"TouchControls"), "the stick, JUMP and SWORD")
	var throw := scene.get_node_or_null(^"ThrowLayer/ThrowButton")
	assert_not_null(throw, "and THROW")
	if throw != null:
		assert_eq(String(throw.get("action")), "throw")


## Played by the scene's own physics frames: the computer closes on a player
## who stands still, and the player walks when the shared action is held.
func test_the_scene_steps_both_seats() -> void:
	ModeRegistry.choose(MODE, DuelBrain.Difficulty.MEDIUM)
	var scene := SCENE.instantiate()
	scene.set("wardrobe_path", WARDROBE)
	add_child_autofree(scene)
	var fight := scene.get_node(^"World/Match") as DuelMatch
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


func _row(menu: MenuScene, id: String) -> int:
	for i: int in menu.rows().size():
		if String(menu.rows()[i]["id"]) == id:
			return i
	return -1
