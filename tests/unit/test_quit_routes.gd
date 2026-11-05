extends GutTest
## Every screen has a way back, and it works (docs/ui.md, "Ways back").
##
## Two owners on phones asked for a quit path "in general". The audit behind
## this file walked every scene: a level paused into a screen whose only exit
## was SWORD, pressed straight from play; an online match whose PAUSE left at
## once with no question and whose result screen offered a rematch nothing
## answered; a ruin that would not generate stranded the player on a screen
## with no game, no menu and no buttons. Each is held here by going out the
## way a player would -- the pause menu's last row, SWORD on a page, the
## lobby's back -- through the scene's own frame, and seeing it leave.
##
## The guard: every scene in res://scenes must be in ROUTES or EXEMPT, with a
## reason. A new scene in neither fails, so a screen cannot ship as a dead end
## by being forgotten.

const DeathWatch := preload("res://tests/death_watch.gd")
var _store := UserData.at("user://test_quit_routes.cfg")

## Scene -> the test that leaves it.
const ROUTES := {
	"res://scenes/game.tscn": "test_a_level_is_left_from_its_pause_menu",
	"res://scenes/feel_lab.tscn": "test_the_feel_lab_is_left_as_a_level_is",
	"res://scenes/campaign_game.tscn": "test_a_chapter_is_left_for_the_chapters",
	"res://scenes/generated_game.tscn": "test_endless_is_left_from_its_pause_menu",
	"res://scenes/chapter_select.tscn": "test_the_pages_go_back_on_sword",
	"res://scenes/duel_select.tscn": "test_the_pages_go_back_on_sword",
	"res://scenes/wardrobe.tscn": "test_the_pages_go_back_on_sword",
	"res://scenes/pose_lab.tscn": "test_the_pose_lab_is_left_on_sword_and_try_on_pause",
	"res://scenes/duel_match.tscn": "test_a_duel_is_left_from_its_menu",
	"res://scenes/duel_match_cpu.tscn": "test_a_duel_is_left_from_its_menu",
	"res://scenes/duel_match_online.tscn": "test_the_online_duel_leaves_cleanly",
}
## Scenes that are not screens a player can be stranded on, and why.
const EXEMPT := {
	"res://scenes/menu.tscn": "the root: there is nothing behind the title screen",
	"res://scenes/boot.tscn": "passes straight to the title screen",
	"res://scenes/rendezvous.tscn": "a headless relay server, never shown",
	"res://scenes/player.tscn": "a part, instanced by the level scenes",
	"res://scenes/fighter.tscn": "a part, instanced by the duel scenes",
	"res://scenes/touch_controls.tscn": "a part, instanced by the screens",
}

var _left := 0


func before_each() -> void:
	_left = 0


func after_each() -> void:
	for action: String in ["jump", "attack", "pause", "move_down", "move_up"]:
		Input.action_release(action)
	Campaign.reset()
	if FileAccess.file_exists(_store):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_store))


func test_every_scene_has_a_way_back_or_a_reason() -> void:
	var seen := 0
	for file: String in DirAccess.get_files_at("res://scenes"):
		if not file.ends_with(".tscn"):
			continue
		var path := "res://scenes".path_join(file)
		seen += 1
		assert_true(ROUTES.has(path) or EXEMPT.has(path),
			"%s is a screen with no way back tested here, and no reason it needs none" % path)
		if ROUTES.has(path):
			assert_true(has_method(String(ROUTES[path])), "%s's route test exists" % path)
	assert_gte(seen, 16, "the scenes were found")


## --- the levels ---------------------------------------------------------------

func test_a_level_is_left_from_its_pause_menu() -> void:
	var game := await _game("res://scenes/game.tscn")
	await _press("pause")
	assert_true(game.menu.is_open(), "PAUSE opens the menu")
	var ids: Array[StringName] = []
	for row: Dictionary in game.menu.rows():
		ids.append(StringName(row["id"]))
	assert_eq(ids, [&"resume", &"torch", &"restart", &"quit"], "the adventure's four rows")
	assert_false(game.menu.is_enabled(&"torch"), "no torch taken: from the torch is dimmed")
	assert_eq(game.menu.selected(), &"resume", "the cursor starts on RESUME")

	await _press("attack")
	assert_eq(_left, 0, "SWORD on the menu goes back into the game, never out of it")
	await wait_physics_frames(2)
	assert_eq(game.phase, Game.Phase.PLAYING, "and the game plays")

	await _press("pause")
	await _choose(game.menu, 3)
	assert_eq(_left, 1, "QUIT leaves")


func test_the_pause_menu_restarts_and_respawns() -> void:
	var game := await _game("res://scenes/game.tscn")
	game.elapsed = 12.0
	await _press("pause")
	await _choose(game.menu, 2)
	await _until(func() -> bool: return game.phase == Game.Phase.PLAYING and not Flow.busy())
	assert_lt(game.elapsed, 1.0, "RESTART starts the level from nothing")

	var torch := game.level.spawn_world_position() + Vector2(64.0, 0.0)
	game.checkpoint = torch
	game.elapsed = 12.0
	await _press("pause")
	assert_true(game.menu.is_enabled(&"torch"), "with a torch held, it can be chosen")
	await _choose(game.menu, 1)
	await _until(func() -> bool: return game.phase == Game.Phase.PLAYING and not Flow.busy())
	assert_almost_eq(game.player.global_position.x, torch.x, 1.0, "back at the torch")
	assert_gt(game.elapsed, 11.0, "and the clock kept, as a death keeps it")


func test_a_resume_does_not_jump() -> void:
	var game := await _game("res://scenes/game.tscn")
	await _press("pause")
	Input.action_press("jump")
	await wait_physics_frames(4)
	Input.action_release("jump")
	await wait_physics_frames(2)
	assert_eq(game.phase, Game.Phase.PLAYING, "JUMP on RESUME resumes")
	assert_true(game.player.is_grounded(), "and the press that chose it was not a jump")


func test_the_complete_screen_says_how_to_leave() -> void:
	var game := await _game("res://scenes/game.tscn")
	game._complete()
	assert_string_contains(game._overlay_subtitle(), "SWORD TO QUIT")
	await _press("attack")
	assert_eq(_left, 1, "and SWORD leaves")


func test_the_feel_lab_is_left_as_a_level_is() -> void:
	var game := await _game("res://scenes/feel_lab.tscn")
	await _press("pause")
	await _choose(game.menu, 3)
	assert_eq(_left, 1, "the feel lab's pause menu leaves")


func test_a_chapter_is_left_for_the_chapters() -> void:
	Campaign.selected = 0
	var campaign := (load("res://scenes/campaign_game.tscn") as PackedScene).instantiate()
	campaign.progress_path = _store
	campaign.leave = func() -> void: _left += 1
	add_child_autofree(campaign)
	await _until(func() -> bool: return not Flow.busy())
	var game := (campaign as CampaignGame).game()
	await _press("pause")
	assert_eq(String(game.menu.rows()[2]["title"]), "RESTART CHAPTER")
	assert_eq(String(game.menu.rows()[3]["title"]), "QUIT TO CHAPTERS")
	await _choose(game.menu, 3)
	assert_eq(_left, 1, "QUIT TO CHAPTERS leaves for them")


func test_endless_is_left_from_its_pause_menu() -> void:
	var endless := GeneratedGame.new()
	endless.seed_override = 7
	endless.leave = func() -> void: _left += 1
	add_child_autofree(endless)
	await _until(func() -> bool: return not Flow.busy())
	var game := endless.get_child(endless.get_child_count() - 1) as Game
	assert_not_null(game, "a ruin is playing")
	await _press("pause")
	assert_eq(String(game.menu.rows()[2]["title"]), "RESTART RUIN", "the same ruin, again")
	await _choose(game.menu, 3)
	assert_eq(_left, 1, "and QUIT leaves")


## --- the pages ----------------------------------------------------------------

func test_the_pages_go_back_on_sword() -> void:
	for path: String in ["res://scenes/chapter_select.tscn", "res://scenes/duel_select.tscn",
			"res://scenes/wardrobe.tscn"]:
		_left = 0
		var page := (load(path) as PackedScene).instantiate()
		page.set("store_path", _store)
		page.set("leave", func() -> void: _left += 1)
		add_child_autofree(page)
		await wait_frames(2)
		Input.action_press("attack")
		await wait_frames(2)
		Input.action_release("attack")
		await wait_frames(1)
		assert_eq(_left, 1, "%s goes back on SWORD" % path)
		page.free()


## The pose lab is a page with a page inside it: SWORD leaves the poses, and on
## TRY, where SWORD is the fighter's, PAUSE is the way back to them.
func test_the_pose_lab_is_left_on_sword_and_try_on_pause() -> void:
	var lab := (load("res://scenes/pose_lab.tscn") as PackedScene).instantiate() as PoseLab
	lab.wardrobe_path = _store
	lab.leave = func() -> void: _left += 1
	add_child_autofree(lab)
	await wait_process_frames(2)
	lab.open_try()
	await wait_process_frames(2)
	await _press("attack")
	assert_eq(lab.page, PoseLab.Page.TRY, "on TRY, SWORD is a thrust, not a way out")
	assert_eq(_left, 0)
	await _press("pause")
	await wait_process_frames(2)
	assert_eq(lab.page, PoseLab.Page.BROWSE, "PAUSE goes back to the poses")
	await _press("attack")
	await wait_process_frames(2)
	assert_eq(_left, 1, "and SWORD there leaves the lab")
	lab.free()


## --- the duels ----------------------------------------------------------------

func test_a_duel_is_left_from_its_menu() -> void:
	for path: String in ["res://scenes/duel_match.tscn", "res://scenes/duel_match_cpu.tscn"]:
		_left = 0
		var scene := await _duel(path)
		var menu := scene.get("menu") as PauseMenu
		var fight := scene.get("fight") as DuelMatch
		await _press("pause")
		assert_true(menu.is_open(), "%s: PAUSE opens the menu" % path)
		var frame := fight.frame
		await wait_physics_frames(5)
		assert_eq(fight.frame, frame, "%s: the match stops under it" % path)
		await _choose(menu, 2)
		assert_eq(_left, 1, "%s: LEAVE MATCH leaves" % path)
		scene.free()


func test_the_online_duel_leaves_cleanly() -> void:
	var scene := await _duel("res://scenes/duel_match_online.tscn")
	# In the lobby: SWORD on its list is a step back to the duel page.
	await _press("attack")
	assert_eq(_left, 1, "the lobby goes back on SWORD")

	# In a match: the menu does not stop it, and leaving says goodbye.
	_left = 0
	var ends := LoopbackTransport.pair()
	var heard: Array[Dictionary] = []
	(ends[1] as LoopbackTransport).received.connect(func(bytes: PackedByteArray) -> void:
		heard.append(NetProtocol.decode(bytes)))
	var session := NetSession.new()
	session.local_input = scene.get("_local_bits")
	session.start(ends[0], scene.get("fight") as DuelMatch, true)
	scene.set("session", session)
	scene.set("_online", true)
	scene.get_node(^"LobbyLayer/Lobby").visible = false
	var menu := scene.get("menu") as PauseMenu
	await _press("pause")
	assert_true(menu.is_open(), "PAUSE opens the menu online too")
	assert_eq(menu.rows().size(), 2, "KEEP FIGHTING and LEAVE MATCH")
	Input.action_press("move_right")
	assert_eq(int(session.local_input.call()), 0, "and this phone sends nothing while it is up")
	Input.action_release("move_right")
	await _choose(menu, 1)
	for _poll: int in 4:
		(ends[1] as LoopbackTransport).poll()
	var byes := heard.filter(func(message: Dictionary) -> bool:
		return int(message.get("type", -1)) == NetProtocol.Type.BYE)
	assert_eq(byes.size(), 1, "LEAVE MATCH tells the other phone, once")
	assert_null(scene.get("session"), "the session is torn down")
	assert_eq(_left, 1, "and the scene leaves")


## --- helpers ------------------------------------------------------------------

func _game(path: String) -> Game:
	var game := (load(path) as PackedScene).instantiate() as Game
	game.leave = func() -> void: _left += 1
	add_child_autofree(game)
	await _until(func() -> bool: return not Flow.busy())
	await wait_physics_frames(2)
	return game


func _duel(path: String) -> Node:
	var scene := (load(path) as PackedScene).instantiate()
	scene.set("wardrobe_path", _store)
	if path.contains("cpu"):
		scene.set("choice_path", _store)
	scene.set("leave", func() -> void: _left += 1)
	add_child_autofree(scene)
	await wait_physics_frames(3)
	return scene


## Walks the menu's cursor down to `row` with the stick and chooses it with
## JUMP, as a thumb would.
func _choose(menu: PauseMenu, row: int) -> void:
	await wait_physics_frames(30)
	while menu.index() < row:
		var before := menu.index()
		Input.action_press("move_down")
		await _until(func() -> bool: return menu.index() != before, 60)
		Input.action_release("move_down")
		await wait_physics_frames(1)
	await _press("jump")


func _press(action: String) -> void:
	Input.action_press(action)
	await wait_physics_frames(1)
	Input.action_release(action)
	await wait_physics_frames(1)


func _until(done: Callable, frames: int = 240) -> void:
	for _frame: int in frames:
		if done.call():
			return
		await wait_physics_frames(1)
