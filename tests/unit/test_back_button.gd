extends GutTest
## Android's Back is a way back on every screen, and losing the screen pauses
## play (docs/ui.md, "Ways back" and "When the app goes away").
##
## Godot quits on Back by default (`application/config/quit_on_go_back`), so
## the phone build closed from every screen -- mid-level, mid-match, from the
## wardrobe -- and a call or a switch to another app left the prince playing
## to nobody. Held here, through the scenes' own frames: Back is PAUSE in
## play, SWORD on a page, the way out of a finished level, and a quit only on
## the title screen; going away opens the pause menu wherever the game can
## stop, and never stops an online match.
##
## The notifications are sent the way the engine sends them, to every node
## from the root down, so a screen that answered twice -- a page and a panel
## on it both stepping back -- would be seen to.
##
## The guard: every scene in res://scenes is in ROUTES or EXEMPT, so a new
## screen cannot ship with Back doing nothing.

var _store := UserData.at("user://test_back_button.cfg")

## Scene -> the test that presses Back on it.
const ROUTES := {
	"res://scenes/menu.tscn": "test_the_title_screen_closes_settings_then_quits",
	"res://scenes/game.tscn": "test_back_is_pause_in_a_level",
	"res://scenes/feel_lab.tscn": "test_back_is_pause_in_a_level",
	"res://scenes/campaign_game.tscn": "test_back_is_pause_in_a_chapter",
	"res://scenes/generated_game.tscn": "test_back_is_pause_in_endless_and_leaves_a_failed_ruin",
	"res://scenes/chapter_select.tscn": "test_the_pages_go_back_one_page",
	"res://scenes/duel_select.tscn": "test_the_pages_go_back_one_page",
	"res://scenes/wardrobe.tscn": "test_the_pages_go_back_one_page",
	"res://scenes/pose_lab.tscn": "test_the_pose_lab_steps_back_from_try_then_leaves",
	"res://scenes/duel_match.tscn": "test_back_is_pause_in_a_duel_on_one_device",
	"res://scenes/duel_match_cpu.tscn": "test_back_is_pause_in_a_duel_on_one_device",
	"res://scenes/duel_match_online.tscn": "test_the_lobby_and_the_online_match_answer_back",
}
## Scenes Back never reaches as a screen of their own, and why.
const EXEMPT := {
	"res://scenes/boot.tscn": "passes straight to the title screen",
	"res://scenes/rendezvous.tscn": "a headless relay server, never shown",
	"res://scenes/player.tscn": "a part, instanced by the level scenes",
	"res://scenes/fighter.tscn": "a part, instanced by the duel scenes",
	"res://scenes/touch_controls.tscn": "a part, instanced by the screens",
}

var _left := 0
var _quits := 0


func before_each() -> void:
	_left = 0
	_quits = 0


func after_each() -> void:
	for action: String in ["jump", "attack", "pause", "move_down", "move_up"]:
		Input.action_release(action)
	Campaign.reset()
	if FileAccess.file_exists(_store):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_store))


func test_back_does_not_quit_the_app() -> void:
	assert_false(bool(ProjectSettings.get_setting("application/config/quit_on_go_back")),
		"tools/configure_project.gd turns the engine's quit-on-Back off")
	assert_false(get_tree().quit_on_go_back, "and the running tree has it off")


func test_every_scene_answers_back_or_says_why() -> void:
	var seen := 0
	for file: String in DirAccess.get_files_at("res://scenes"):
		if not file.ends_with(".tscn"):
			continue
		var path := "res://scenes".path_join(file)
		seen += 1
		assert_true(ROUTES.has(path) or EXEMPT.has(path),
			"%s is a screen whose Back is tested nowhere here, and no reason it needs none"
				% path)
		if ROUTES.has(path):
			assert_true(has_method(String(ROUTES[path])), "%s's Back test exists" % path)
	assert_gte(seen, 16, "the scenes were found")


## --- the title screen ---------------------------------------------------------

func test_the_title_screen_closes_settings_then_quits() -> void:
	var menu := (load("res://scenes/menu.tscn") as PackedScene).instantiate() as MenuScene
	menu.quit_app = func() -> void: _quits += 1
	add_child_autofree(menu)
	await wait_process_frames(2)
	var settings := menu.get_node(^"SettingsPanel") as SettingsPanel
	menu._open_settings()
	_send(NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_false(settings.visible, "Back closes the settings page")
	assert_eq(_quits, 0, "and only that: one press, one step back")
	_send(NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_eq(_quits, 1, "on the title screen itself, the root, Back closes the app")


## --- the pages ----------------------------------------------------------------

func test_the_pages_go_back_one_page() -> void:
	for path: String in ["res://scenes/chapter_select.tscn", "res://scenes/duel_select.tscn",
			"res://scenes/wardrobe.tscn"]:
		_left = 0
		var page := (load(path) as PackedScene).instantiate()
		page.set("store_path", _store)
		page.set("leave", func() -> void: _left += 1)
		add_child_autofree(page)
		await wait_process_frames(2)
		_send(NOTIFICATION_WM_GO_BACK_REQUEST)
		assert_eq(_left, 1, "%s goes back one page on Back, once" % path)
		page.free()


func test_the_pose_lab_steps_back_from_try_then_leaves() -> void:
	var lab := (load("res://scenes/pose_lab.tscn") as PackedScene).instantiate() as PoseLab
	lab.wardrobe_path = _store
	lab.leave = func() -> void: _left += 1
	add_child_autofree(lab)
	await wait_process_frames(2)
	lab.open_try()
	await wait_process_frames(2)
	_send(NOTIFICATION_WM_GO_BACK_REQUEST)
	await wait_process_frames(2)
	assert_eq(lab.page, PoseLab.Page.BROWSE, "Back on TRY is back to the poses")
	assert_eq(_left, 0, "and only that: one press, one step back")
	_send(NOTIFICATION_WM_GO_BACK_REQUEST)
	await wait_process_frames(2)
	assert_eq(_left, 1, "Back on the poses goes back to the title screen, once")
	lab.free()


## --- the levels ---------------------------------------------------------------

func test_back_is_pause_in_a_level() -> void:
	for path: String in ["res://scenes/game.tscn", "res://scenes/feel_lab.tscn"]:
		var game := await _game(path)
		await _back()
		assert_true(game.menu.is_open(), "%s: Back opens the pause menu" % path)
		assert_eq(game.phase, Game.Phase.PAUSED, "%s: and the level stops" % path)
		await _back()
		assert_false(game.menu.is_open(), "%s: Back again closes it" % path)
		assert_eq(game.phase, Game.Phase.PLAYING, "%s: back into play" % path)
		assert_eq(_left, 0, "%s: Back never leaves a level from play" % path)
		game.free()


func test_back_on_the_complete_screen_leaves() -> void:
	var game := await _game("res://scenes/game.tscn")
	game._complete()
	await _back()
	assert_eq(_left, 1, "the complete screen's way out is SWORD, and Back is it too")


func test_back_behind_a_wipe_waits_for_play() -> void:
	var game := await _game("res://scenes/game.tscn")
	Flow.wipe(game, func() -> void: pass)
	_send(NOTIFICATION_WM_GO_BACK_REQUEST)
	await wait_physics_frames(1)
	assert_false(game.menu.is_open(), "nothing opens while a wipe owns the screen")
	await _until(func() -> bool: return not Flow.busy())
	await wait_physics_frames(2)
	assert_true(game.menu.is_open(), "and the menu asked for opens when it lifts")


func test_back_is_pause_in_a_chapter() -> void:
	Campaign.selected = 0
	var campaign := (load("res://scenes/campaign_game.tscn") as PackedScene).instantiate()
	campaign.progress_path = _store
	campaign.leave = func() -> void: _left += 1
	add_child_autofree(campaign)
	await _until(func() -> bool: return not Flow.busy())
	await wait_physics_frames(2)
	var game := (campaign as CampaignGame).game()
	await _back()
	assert_true(game.menu.is_open(), "Back opens the chapter's pause menu")
	assert_eq(_left, 0, "and does not leave for the chapters")


func test_back_is_pause_in_endless_and_leaves_a_failed_ruin() -> void:
	var endless := GeneratedGame.new()
	endless.seed_override = 7
	endless.leave = func() -> void: _left += 1
	add_child_autofree(endless)
	await _until(func() -> bool: return not Flow.busy())
	var game := endless.get_child(endless.get_child_count() - 1) as Game
	assert_not_null(game, "a ruin is playing")
	await _back()
	assert_true(game.menu.is_open(), "Back opens the ruin's pause menu")
	assert_eq(_left, 0)

	var failed := GeneratedGame.new()
	failed.leave = func() -> void: _left += 1
	add_child_autofree(failed)
	failed._strand()
	_send(NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_eq(_left, 1, "a ruin that would not generate is left on Back, as on its buttons")


func test_the_dawn_is_left_on_back_once_read() -> void:
	var card := EndingCard.new()
	var done := [0]
	card.done.connect(func() -> void: done[0] += 1)
	add_child_autofree(card)
	_send(NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_eq(done[0], 0, "not before it has been up for its hold")
	card._time = EndingCard.HOLD
	_send(NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_eq(done[0], 1, "then Back returns to the chapters")


## --- the duels ----------------------------------------------------------------

func test_back_is_pause_in_a_duel_on_one_device() -> void:
	for path: String in ["res://scenes/duel_match.tscn", "res://scenes/duel_match_cpu.tscn"]:
		var scene := await _duel(path)
		var menu := scene.get("menu") as PauseMenu
		var fight := scene.get("fight") as DuelMatch
		await _back()
		assert_true(menu.is_open(), "%s: Back opens the menu" % path)
		var frame := fight.frame
		await wait_physics_frames(5)
		assert_eq(fight.frame, frame, "%s: and the match stops under it" % path)
		await _back()
		assert_false(menu.is_open(), "%s: Back again closes it" % path)
		fight.phase = DuelMatch.Phase.MATCH_OVER
		await _back()
		assert_eq(_left, 1, "%s: a finished match is left on Back, as on PAUSE" % path)
		_left = 0
		scene.free()


func test_the_lobby_and_the_online_match_answer_back() -> void:
	var scene := await _duel("res://scenes/duel_match_online.tscn")
	var lobby := scene.get_node(^"LobbyLayer/Lobby") as DuelLobby
	lobby._on_join_direct()
	assert_ne(lobby.page, DuelLobby.Page.MENU, "on a text page")
	await _back()
	assert_eq(lobby.page, DuelLobby.Page.MENU, "Back steps from a text page to the list")
	assert_eq(_left, 0, "and no further")
	await _back()
	assert_eq(_left, 1, "from the list, Back is a step back to the duel page")

	_left = 0
	_go_online(scene)
	var menu := scene.get("menu") as PauseMenu
	await _back()
	assert_true(menu.is_open(), "in an online match, Back opens the menu")
	assert_eq(menu.title, "THE MATCH GOES ON", "the one that does not stop it")
	assert_not_null(scene.get("session"), "and the match is still on")
	await _back()
	assert_false(menu.is_open(), "Back again closes it")
	assert_eq(_left, 0)


## --- going away ---------------------------------------------------------------

func test_losing_the_screen_pauses_a_level() -> void:
	for what: int in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		var game := await _game("res://scenes/game.tscn")
		_send(what)
		await wait_physics_frames(2)
		assert_true(game.menu.is_open(), "notification %d opens the pause menu" % what)
		_send(what)
		await wait_physics_frames(2)
		assert_true(game.menu.is_open(), "and going away again does not close it")
		game.free()


func test_losing_the_screen_pauses_a_duel_on_one_device() -> void:
	var scene := await _duel("res://scenes/duel_match_cpu.tscn")
	var menu := scene.get("menu") as PauseMenu
	var fight := scene.get("fight") as DuelMatch
	_send(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await wait_physics_frames(2)
	assert_true(menu.is_open(), "the computer's duel stops for a call")
	var frame := fight.frame
	await wait_physics_frames(4)
	assert_eq(fight.frame, frame, "and stays stopped")


func test_losing_the_screen_never_stops_an_online_match() -> void:
	var scene := await _duel("res://scenes/duel_match_online.tscn")
	_go_online(scene)
	var menu := scene.get("menu") as PauseMenu
	_send(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await wait_physics_frames(3)
	assert_false(menu.is_open(), "online, going away opens nothing: the host's match goes on")
	await _back()
	assert_true(menu.is_open(), "and a later Back is still Back, not a stale menu toggle")


## --- helpers ------------------------------------------------------------------

## As the engine delivers it: to every node, from the root down.
func _send(what: int) -> void:
	get_tree().root.propagate_notification(what)


func _back() -> void:
	_send(NOTIFICATION_WM_GO_BACK_REQUEST)
	await wait_physics_frames(2)


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
	scene.set("choice_path", _store)
	scene.set("leave", func() -> void: _left += 1)
	add_child_autofree(scene)
	await wait_physics_frames(3)
	return scene


## An online scene seated on a loopback pair, as test_quit_routes.gd does it.
func _go_online(scene: Node) -> NetSession:
	var ends := LoopbackTransport.pair()
	var session := NetSession.new()
	session.local_input = scene.get("_local_bits")
	session.start(ends[0], scene.get("fight") as DuelMatch, true)
	scene.set("session", session)
	scene.set("_online", true)
	scene.get_node(^"LobbyLayer/Lobby").visible = false
	return session


func _until(done: Callable, frames: int = 240) -> void:
	for _frame: int in frames:
		if done.call():
			return
		await wait_physics_frames(1)
