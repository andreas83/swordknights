extends GutTest
## The duel's second step (scripts/ui/duel_select.gd) and what it remembers
## (scripts/ui/duel_choice.gd).
##
## Held here: the title screen has one DUEL row and it opens this page; the
## page offers ONE KEYBOARD, VS CPU and ONLINE, each opening its own scene;
## left and right set VS CPU's level and nothing else, stopping at the ends;
## starting a duel saves the way and the level, and the page opens on both
## next time; the file falls back field by field; a tap selects, plays, or
## steps the level; the rows keep clear of the thumb buttons; sword goes back.

const PATH := "user://test_duel_select.cfg"
const SCENE := "res://scenes/duel_select.tscn"
const MENU := "res://scenes/menu.tscn"

var _played: Array[String] = []
var _left := 0


func before_each() -> void:
	_remove()
	_played.clear()
	_left = 0


func after_each() -> void:
	_remove()


func _remove() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func _page() -> DuelSelect:
	var page := (load(SCENE) as PackedScene).instantiate() as DuelSelect
	page.store_path = PATH
	page.play = func(scene: String) -> void: _played.append(scene)
	page.leave = func() -> void: _left += 1
	add_child_autofree(page)
	return page


func _write(lines: String) -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(lines)
	file.close()


func test_the_title_screen_has_one_duel_row_and_it_opens_this_page() -> void:
	var menu := (load(MENU) as PackedScene).instantiate() as MenuScene
	add_child_autofree(menu)
	var duels: Array[String] = []
	for row: Dictionary in menu.rows():
		if String(row["title"]).begins_with("DUEL"):
			duels.append(String(row["id"]))
	assert_eq(duels, ["duel"] as Array[String], "one DUEL row, not one per way")
	for row: Dictionary in menu.rows():
		if String(row["id"]) == "duel":
			assert_eq(String(row["scene"]), SCENE, "and it opens the duel page")


func test_three_ways_each_to_its_own_scene() -> void:
	var page := _page()
	assert_eq(page.row_title(0), "ONE KEYBOARD")
	assert_eq(page.row_title(1), "VS CPU")
	assert_eq(page.row_title(2), "ONLINE")
	assert_eq(page.index(), 0, "a first launch opens on ONE KEYBOARD")
	assert_eq(page.row_value(1), "EASY", "and the computer at its gentlest")
	for row: int in 3:
		while page.index() != row:
			page.move(1)
		page.confirm()
	assert_eq(_played, [
		"res://scenes/duel_match.tscn",
		"res://scenes/duel_match_cpu.tscn",
		"res://scenes/duel_match_online.tscn",
	] as Array[String])
	for scene: String in _played:
		assert_true(ResourceLoader.exists(scene), "%s exists" % scene)


func test_left_and_right_set_the_level_on_its_row_only() -> void:
	var page := _page()
	page.shift_level(1)
	assert_eq(page.row_value(DuelSelect.CPU_ROW), "EASY", "not from ONE KEYBOARD")
	page.move(1)
	assert_eq(page.index(), DuelSelect.CPU_ROW)
	page.shift_level(1)
	assert_eq(page.row_value(DuelSelect.CPU_ROW), "MEDIUM", "right: MEDIUM")
	page.shift_level(1)
	page.shift_level(1)
	assert_eq(page.row_value(DuelSelect.CPU_ROW), "HARD", "and HARD, and no further")
	page.shift_level(-1)
	assert_eq(page.row_value(DuelSelect.CPU_ROW), "MEDIUM", "left: back")
	assert_false(FileAccess.file_exists(PATH), "browsing saves nothing")


func test_starting_a_duel_remembers_the_way_and_the_level() -> void:
	var page := _page()
	page.move(1)
	page.shift_level(2)
	page.confirm()
	var saved := DuelChoice.open(PATH)
	assert_eq(saved.way, 1, "VS CPU was saved")
	assert_eq(saved.level, DuelBrain.Difficulty.HARD, "at HARD")

	var again := _page()
	assert_eq(again.index(), DuelSelect.CPU_ROW, "the page opens on VS CPU")
	assert_eq(again.row_value(DuelSelect.CPU_ROW), "HARD", "at HARD")
	again.move(1)
	again.confirm()
	assert_eq(DuelChoice.open(PATH).way, 2, "then ONLINE")
	assert_eq(DuelChoice.open(PATH).level, DuelBrain.Difficulty.HARD,
		"without forgetting the level")


func test_the_file_falls_back_field_by_field() -> void:
	assert_false(DuelChoice.new().load_from_disk(), "no file: the defaults")
	_write("[duel]\nway=\"sideways\"\nlevel=\"hard\"\n")
	var choice := DuelChoice.open(PATH)
	assert_eq(choice.way, 0, "a way that names nothing is ONE KEYBOARD")
	assert_eq(choice.level, DuelBrain.Difficulty.HARD, "and costs the level nothing")
	_write("[duel]\nway=\"online\"\nlevel=7\n")
	choice = DuelChoice.open(PATH)
	assert_eq(choice.way, 2, "a good way survives")
	assert_eq(choice.level, DuelBrain.Difficulty.EASY, "a level of the wrong type is EASY")
	_write("[duel]\nlevel=\"medium\"\n")
	choice = DuelChoice.open(PATH)
	assert_eq([choice.way, choice.level], [0, DuelBrain.Difficulty.MEDIUM],
		"a missing way is ONE KEYBOARD, the level kept")
	_write("this is not [ a config file\n")
	choice = DuelChoice.open(PATH)
	assert_eq([choice.way, choice.level], [0, DuelBrain.Difficulty.EASY],
		"a file that does not parse is the defaults")


func test_a_tap_selects_plays_and_steps_the_level() -> void:
	var page := _page()
	await wait_process_frames(2)
	var cpu := page.row_rect(DuelSelect.CPU_ROW)
	assert_true(cpu.has_area(), "the rows were drawn")
	assert_true(page.tap(Vector2(cpu.position.x + 20.0, cpu.get_center().y)),
		"the tap landed on VS CPU")
	assert_eq(page.index(), DuelSelect.CPU_ROW, "and selected it")
	assert_eq(_played, [] as Array[String], "without playing it")
	await wait_process_frames(1)
	var level := page.level_rect()
	page.tap(Vector2(level.end.x - 2.0, level.get_center().y))
	assert_eq(page.row_value(DuelSelect.CPU_ROW), "MEDIUM", "its level's right side steps up")
	page.tap(Vector2(level.position.x + 2.0, level.get_center().y))
	assert_eq(page.row_value(DuelSelect.CPU_ROW), "EASY", "its left side steps down")
	assert_eq(_played, [] as Array[String], "and neither plays")
	page.tap(Vector2(cpu.position.x + 20.0, cpu.get_center().y))
	assert_eq(_played, ["res://scenes/duel_match_cpu.tscn"] as Array[String],
		"a second tap on the row plays it")
	assert_false(page.tap(Vector2(-50.0, -50.0)), "a tap off the list is not a row")


func test_the_rows_stay_clear_of_the_thumb_buttons() -> void:
	var page := _page()
	var surface := page.get_node(^"TouchControls/Surface") as Control
	surface.visible = true
	page.queue_redraw()
	await wait_process_frames(2)
	var safe := UiLayout.safe(page.size)
	# TouchControls: JUMP at (right - 34, bottom - 34) r 24, SWORD at
	# (right - 82, bottom - 22) r 19, each with HIT_PADDING around it.
	var buttons: Array[Vector3] = [
		Vector3(safe.end.x - 34.0, safe.end.y - 34.0, 24.0 + TouchControls.HIT_PADDING),
		Vector3(safe.end.x - 82.0, safe.end.y - 22.0, 19.0 + TouchControls.HIT_PADDING),
	]
	for row: int in DuelSelect.ROWS.size():
		var rect := page.row_rect(row)
		assert_true(rect.has_area(), "row %d was drawn" % row)
		for b: Vector3 in buttons:
			var near := Vector2(clampf(b.x, rect.position.x, rect.end.x),
				clampf(b.y, rect.position.y, rect.end.y))
			assert_gt(near.distance_to(Vector2(b.x, b.y)), b.z,
				"row %d %s is clear of a thumb button" % [row, rect])


func test_sword_goes_back() -> void:
	var page := _page()
	page.back()
	assert_eq(_left, 1)
