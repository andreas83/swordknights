extends GutTest
## On a phone the duel offers only what a thumb can play
## (scripts/ui/duel_select.gd, "On a phone"; scripts/net/lobby.gd).
##
## The duel page opened on ONE KEYBOARD on a first launch, and its scene
## reads the two keyboard seats and has no thumb buttons: on a phone the first
## JUMP started a match nobody could move in. The online lobby offered LOCAL
## TWO-PLAYER, the same scene. Held here with the page and the lobby told
## they are on a phone (their `handheld` seam), and on a desktop for contrast:
## a phone is never offered ONE KEYBOARD, opens on VS CPU, turns a saved ONE
## KEYBOARD into VS CPU, and its lobby has no LOCAL TWO-PLAYER; a desktop
## keeps all of it. And the lobby's wait no longer promises a local game that
## SWORD never started.

var _path := UserData.at("user://test_duel_handheld.cfg")
const SCENE := "res://scenes/duel_select.tscn"
const ONLINE := "res://scenes/duel_match_online.tscn"

var _played: Array[String] = []


func before_each() -> void:
	_remove()
	_played.clear()


func after_each() -> void:
	_remove()


func _remove() -> void:
	if FileAccess.file_exists(_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))


func test_the_test_runner_is_not_a_phone() -> void:
	assert_false(UiLayout.handheld(), "headless on a desktop: the seams below make the phone")


func test_a_phone_is_not_offered_one_keyboard() -> void:
	var page := _page(true)
	assert_false(page.shown().has(DuelSelect.LOCAL_ROW), "no ONE KEYBOARD")
	assert_eq(page.shown(), [DuelSelect.CPU_ROW, 2, DuelSelect.STRIP_ROW] as Array[int],
		"VS CPU, ONLINE and STRIP")
	assert_eq(page.index(), DuelSelect.CPU_ROW, "a first launch opens on VS CPU")
	var seen := {}
	for _step: int in 8:
		page.move(1)
		seen[page.index()] = true
	assert_false(seen.has(DuelSelect.LOCAL_ROW), "the stick never lands on ONE KEYBOARD")
	await wait_process_frames(2)
	assert_false(page.row_rect(DuelSelect.LOCAL_ROW).has_area(), "and no tap can reach it")
	assert_true(page.row_rect(DuelSelect.CPU_ROW).has_area(), "while VS CPU can be tapped")


func test_a_saved_one_keyboard_is_vs_cpu_on_a_phone() -> void:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	file.store_string("[duel]\nway=\"local\"\nlevel=\"hard\"\n")
	file.close()
	var page := _page(true)
	assert_eq(page.index(), DuelSelect.CPU_ROW, "opens on VS CPU")
	page.confirm()
	assert_eq(_played, ["res://scenes/duel_match_cpu.tscn"] as Array[String],
		"and JUMP plays the computer, at the level saved")
	assert_eq(int(page.choice().level), int(DuelBrain.Difficulty.HARD))


func test_a_desktop_keeps_one_keyboard() -> void:
	var page := _page(false)
	assert_true(page.shown().has(DuelSelect.LOCAL_ROW), "ONE KEYBOARD on a desktop")
	assert_eq(page.index(), DuelSelect.LOCAL_ROW, "and a first launch opens on it, as before")


func test_the_lobby_on_a_phone_has_no_local_game() -> void:
	for phone: bool in [true, false]:
		var scene := (load(ONLINE) as PackedScene).instantiate()
		scene.set("wardrobe_path", _path)
		scene.set("leave", func() -> void: pass)
		var lobby := scene.get_node(^"LobbyLayer/Lobby") as DuelLobby
		lobby.handheld = phone
		add_child_autofree(scene)
		await wait_process_frames(2)
		var titles: Array[String] = []
		for button: Button in lobby._buttons:
			titles.append(button.text)
		assert_eq(titles.has("LOCAL TWO-PLAYER"), not phone,
			"LOCAL TWO-PLAYER %s" % ("is not offered on a phone" if phone
				else "is offered on a desktop"))
		assert_true(titles.has("HOST ON THIS WI-FI") or titles.has(
			"HOST ON THIS WI-FI  —  NOT ON WEB"), "the rest of the list is there")
		lobby.show_busy("WAITING")
		assert_false(lobby._hint.contains("LOCAL"), "the wait promises no local game")
		scene.free()


func _page(phone: bool) -> DuelSelect:
	var page := (load(SCENE) as PackedScene).instantiate() as DuelSelect
	page.store_path = _path
	page.handheld = phone
	page.play = func(scene: String) -> void: _played.append(scene)
	page.leave = func() -> void: pass
	add_child_autofree(page)
	return page
