extends GutTest
## The thumb buttons say what they do on every screen (TouchControls,
## "What the buttons say"; docs/ui.md).
##
## They always said JUMP and SWORD -- over the pause screen, the complete
## screen, every page -- where JUMP meant choose and SWORD meant leave. Held
## here, screen by screen, through each screen's own frame: the words it
## puts on the two buttons, that every word shown fits inside its ring, and
## that a word too wide for the ring falls back to a shorter one rather than
## running over it.
##
## And the guard that keeps it true: every scene that carries thumb buttons
## must be visited here (`VISITED`). A new screen with buttons and no entry
## fails, so it cannot ship lettered JUMP and SWORD by default.

const DeathWatch := preload("res://tests/death_watch.gd")
const GAME := "res://scenes/game.tscn"
const CHAPTERS := "res://scenes/chapter_select.tscn"
const DUELS := "res://scenes/duel_select.tscn"
const WARDROBE := "res://scenes/wardrobe.tscn"
const MENU := "res://scenes/menu.tscn"
const CPU := "res://scenes/duel_match_cpu.tscn"
const ONLINE := "res://scenes/duel_match_online.tscn"
const CAMPAIGN := "res://scenes/campaign_game.tscn"
const GENERATED := "res://scenes/generated_game.tscn"
const FEEL_LAB := "res://scenes/feel_lab.tscn"
var _store := UserData.at("user://test_touch_labels.cfg")
const THUMBS := preload("res://scenes/touch_controls.tscn")

## Every scene with a TouchControls in it, and the test below that letters
## it. The campaign and Endless carry theirs through res://scenes/game.tscn.
const VISITED := {
	"res://scenes/game.tscn": "test_the_game_letters_every_phase",
	"res://scenes/feel_lab.tscn": "test_the_feel_lab_is_the_game",
	"res://scenes/menu.tscn": "test_the_title_screen_and_settings",
	"res://scenes/chapter_select.tscn": "test_the_pages",
	"res://scenes/duel_select.tscn": "test_the_pages",
	"res://scenes/wardrobe.tscn": "test_the_pages",
	"res://scenes/duel_match_cpu.tscn": "test_the_duel_letters_its_menu_and_its_end",
	"res://scenes/duel_match_online.tscn": "test_the_lobby_letters_its_pages",
}


func after_each() -> void:
	for action: String in ["jump", "attack", "pause", "move_down", "move_up"]:
		Input.action_release(action)
	Campaign.reset()
	if FileAccess.file_exists(_store):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_store))


## --- the rule ---------------------------------------------------------------

func test_a_word_too_wide_for_its_ring_gives_way() -> void:
	var jump := TouchControls.JUMP_RADIUS
	var sword := TouchControls.SWORD_RADIUS
	assert_true(TouchControls.label_fits("JUMP", jump), "the play words fit")
	assert_true(TouchControls.label_fits("SWORD", sword), "SWORD, just")
	assert_false(TouchControls.label_fits("CONTINUE", jump), "CONTINUE does not")
	assert_eq(TouchControls.fit_label("CONTINUE|NEXT", jump), "NEXT", "so it says NEXT")
	assert_eq(TouchControls.fit_label("RESUME", sword), "", "and a word with no fallback "
		+ "that does not fit says nothing rather than run over the ring")


func test_the_rings_are_on_screen_at_both_widths() -> void:
	var controls := THUMBS.instantiate()
	add_child_autofree(controls)
	await wait_physics_frames(1)
	var surface := controls.get_node(^"Surface") as Control
	for wide: float in [320.0, 440.0]:
		surface.size = Vector2(wide, 180.0)
		controls._layout()
		for button: Dictionary in controls._buttons:
			var at: Vector2 = button["at"]
			var r: float = button["r"]
			assert_true(Rect2(0.0, 0.0, wide, 180.0).encloses(
				Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0)),
				"%s's ring is inside a %d-unit screen" % [button["id"], wide])


## --- the guard --------------------------------------------------------------

func test_every_scene_with_thumbs_is_lettered_here() -> void:
	var checked := 0
	for file: String in DirAccess.get_files_at("res://scenes"):
		if not file.ends_with(".tscn") or file == "touch_controls.tscn":
			continue
		var path := "res://scenes".path_join(file)
		var text := FileAccess.get_file_as_string(path)
		if not text.contains("touch_controls.tscn"):
			continue
		checked += 1
		assert_true(VISITED.has(path), "%s has thumb buttons: letter it in this test" % path)
		if VISITED.has(path):
			assert_true(has_method(String(VISITED[path])),
				"%s is lettered by %s, which exists" % [path, VISITED[path]])
	assert_gte(checked, 7, "the scenes with thumbs were found")


## --- the screens ------------------------------------------------------------

func test_the_game_letters_every_phase() -> void:
	var game := await _game(GAME)
	var controls := TouchControls.of(game)
	assert_true(controls.is_play(), "in play: JUMP and SWORD")

	await _press("pause")
	assert_eq(game.phase, Game.Phase.PAUSED)
	_says(controls, "SELECT", "BACK", "the pause menu: JUMP chooses, SWORD goes back")
	await _press("pause")
	assert_true(controls.is_play(), "and play again")

	DeathWatch.expect_deaths(1)
	game.player.damage(Tuning.MAX_HEALTH, game.player.global_position.x - 8.0)
	await wait_physics_frames(1)
	assert_eq(game.phase, Game.Phase.DYING)
	_says(controls, "RETRY", "", "the death beat: JUMP skips it to the torch")
	await _until(func() -> bool: return game.phase == Game.Phase.PLAYING)

	game._complete()
	await wait_physics_frames(1)
	_says(controls, "REPLAY", "QUIT", "the complete screen, on its own")


func test_the_feel_lab_is_the_game() -> void:
	var game := await _game(FEEL_LAB)
	await _press("pause")
	_says(TouchControls.of(game), "SELECT", "BACK", "the feel lab pauses as the game does")


func test_a_chapter_goes_on_with_a_word_that_fits() -> void:
	var game := await _game(GAME)
	game.advance = func() -> void: pass
	for said: Array in [["CONTINUE", "NEXT"], ["DESCEND", "NEXT"], ["CHAPTERS", "DONE"],
			["DAWN", "DAWN"]]:
		game.advance_label = said[0]
		game._complete()
		await wait_physics_frames(1)
		_says(TouchControls.of(game), said[1], "QUIT", "JUMP TO %s" % said[0])
		game._set_phase(Game.Phase.PLAYING)


func test_the_title_screen_and_settings() -> void:
	var menu := (load(MENU) as PackedScene).instantiate() as MenuScene
	add_child_autofree(menu)
	await wait_frames(2)
	var controls := TouchControls.of(menu)
	_says(controls, "OPEN", "OPEN", "the title screen: both buttons open the row")
	menu._open_settings()
	await wait_frames(2)
	_says(controls, "LOUDER", "BACK", "settings, on a gauge")
	var panel := menu.get_node(^"SettingsPanel") as SettingsPanel
	panel.move(3)
	await wait_frames(2)
	_says(controls, "SWITCH", "BACK", "settings, on MUTE")


func test_the_pages() -> void:
	Campaign.use_for_test([
		{"id": "alpha", "numeral": "I", "title": "Alpha", "epigraph": "", "time": "afternoon",
			"file": "res://levels/level_01.txt", "finale": false},
		{"id": "beta", "numeral": "II", "title": "Beta", "epigraph": "", "time": "afternoon",
			"file": "res://levels/level_01.txt", "finale": false},
	])
	var chapters := await _page(CHAPTERS)
	_says(TouchControls.of(chapters), "PLAY", "BACK", "the chapter select, on an open row")
	chapters.move(2)
	await wait_frames(2)
	_says(TouchControls.of(chapters), "", "BACK", "on a locked row JUMP does nothing")
	_says(TouchControls.of(await _page(DUELS)), "PLAY", "BACK", "the duel page")
	_says(TouchControls.of(await _page(WARDROBE)), "NEXT", "BACK", "the wardrobe")


func test_the_dawn_letters_its_way_back() -> void:
	var card := EndingCard.new()
	var controls := THUMBS.instantiate()
	add_child_autofree(controls)
	card.controls = controls
	add_child_autofree(card)
	await wait_frames(2)
	_says(controls, "", "", "nothing leaves the dawn before it has been read")
	card._time = EndingCard.HOLD
	await wait_frames(2)
	_says(controls, "RETURN", "BACK", "then either button returns to the chapters")


func test_the_duel_letters_its_menu_and_its_end() -> void:
	var scene := (load(CPU) as PackedScene).instantiate()
	scene.set("wardrobe_path", _store)
	scene.set("choice_path", _store)
	scene.set("leave", func() -> void: pass)
	add_child_autofree(scene)
	await wait_physics_frames(3)
	var controls := TouchControls.of(scene)
	assert_true(controls.is_play(), "in the match: JUMP and SWORD")
	assert_true(controls._shown(_throw(controls)), "and THROW")
	await _press("pause")
	_says(controls, "SELECT", "BACK", "the duel's menu")
	assert_false(controls._shown(_throw(controls)), "THROW is no menu verb")
	await _press("pause")
	var fight := scene.get("fight") as DuelMatch
	fight.winner = 0
	fight.phase = DuelMatch.Phase.MATCH_OVER
	await wait_physics_frames(2)
	_says(controls, "AGAIN", "QUIT", "the result: REMATCH does not fit, AGAIN does")


func test_the_lobby_letters_its_pages() -> void:
	var scene := (load(ONLINE) as PackedScene).instantiate()
	scene.set("wardrobe_path", _store)
	scene.set("leave", func() -> void: pass)
	add_child_autofree(scene)
	await wait_physics_frames(3)
	var controls := TouchControls.of(scene)
	_says(controls, "SELECT", "BACK", "the lobby's list")
	var lobby := scene.get_node(^"LobbyLayer/Lobby") as DuelLobby
	lobby.show_busy("WAITING")
	await wait_physics_frames(2)
	_says(controls, "", "LOCAL", "waiting: SWORD gives up and plays on this phone")


func test_a_ruin_that_would_not_generate_letters_its_way_back() -> void:
	var endless := GeneratedGame.new()
	endless.leave = func() -> void: pass
	add_child_autofree(endless)
	endless._strand()
	_says(TouchControls.of(endless), "BACK", "BACK", "a failed ruin says only how to leave")


## --- helpers ----------------------------------------------------------------

func _throw(controls: TouchControls) -> Dictionary:
	for button: Dictionary in controls._buttons:
		if String(button["id"]) == "throw":
			return button
	assert_true(false, "the layout has a THROW")
	return {"id": "throw"}


## Both buttons' words as shown -- the first phrasing that fits -- and that
## a word is shown wherever one was asked for.
func _says(controls: TouchControls, jump: String, sword: String, what: String) -> void:
	assert_not_null(controls, "%s: the screen has its thumb buttons" % what)
	if controls == null:
		return
	assert_eq(controls.label_of("jump"), jump, "%s (JUMP)" % what)
	assert_eq(controls.label_of("attack"), sword, "%s (SWORD)" % what)
	for id: String in TouchControls.LABELLED:
		if controls.labels_of(id) != "":
			assert_ne(controls.label_of(id), "", "%s: %s's word fits its ring" % [what, id])


func _game(path: String) -> Game:
	var game := (load(path) as PackedScene).instantiate() as Game
	game.leave = func() -> void: pass
	add_child_autofree(game)
	await _until(func() -> bool: return not Flow.busy())
	await wait_physics_frames(2)
	return game


func _page(path: String) -> Node:
	var page := (load(path) as PackedScene).instantiate()
	page.set("store_path", _store)
	page.set("leave", func() -> void: pass)
	add_child_autofree(page)
	await wait_frames(2)
	return page


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
