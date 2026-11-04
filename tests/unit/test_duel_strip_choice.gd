extends GutTest
## Where the duel is fought: the duel page's STRIP row, what is remembered of
## it in user://duel.cfg and how it falls back, RANDOM, and the match scene
## playing the strip that was saved.
##
## Seen to fail with the strip left out of DuelChoice.save() (the page opened on
## the Tug of War every time) and with a bad `strip` word allowed to cost the
## level.

const PATH := "user://test_duel_strip_choice.cfg"
const SCENE := "res://scenes/duel_select.tscn"
const MATCH := preload("res://scenes/duel_match.tscn")

var _played: Array[String] = []


func before_each() -> void:
	_remove()
	_played.clear()


func after_each() -> void:
	_remove()


func _remove() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func _page() -> DuelSelect:
	var page := (load(SCENE) as PackedScene).instantiate() as DuelSelect
	page.store_path = PATH
	page.play = func(scene: String) -> void: _played.append(scene)
	page.leave = func() -> void: pass
	add_child_autofree(page)
	return page


func _write(lines: String) -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(lines)
	file.close()


func test_the_strip_row_steps_through_every_strip_then_random() -> void:
	var page := _page()
	assert_eq(page.row_title(DuelSelect.STRIP_ROW), "STRIP")
	assert_eq(page.row_value(DuelSelect.STRIP_ROW), "TUG OF WAR", "a first launch: the Tug")
	page.shift_strip(1)
	assert_eq(page.choice().strip, DuelStrips.TUG, "not from another row")
	while page.index() != DuelSelect.STRIP_ROW:
		page.move(1)
	var seen: Array[String] = [page.choice().strip]
	for i: int in 8:
		page.shift_strip(1)
		if not seen.has(page.choice().strip):
			seen.append(page.choice().strip)
	assert_eq(seen, DuelStrips.choices(), "every strip, then RANDOM, and no further")
	assert_eq(page.row_value(DuelSelect.STRIP_ROW), "RANDOM")
	page.shift_strip(-1)
	assert_eq(page.choice().strip, "roofs", "left: back")
	assert_false(FileAccess.file_exists(PATH), "browsing saves nothing")


func test_starting_a_duel_remembers_the_strip_and_jump_on_it_plays_the_way() -> void:
	var page := _page()
	page.move(1) # VS CPU
	page.confirm()
	_played.clear()
	var again := _page()
	while again.index() != DuelSelect.STRIP_ROW:
		again.move(1)
	again.shift_strip(1)
	again.confirm()
	assert_eq(_played, ["res://scenes/duel_match_cpu.tscn"] as Array[String],
		"jump on the strip's row plays the way last played")
	var saved := DuelChoice.open(PATH)
	assert_eq(saved.strip, "well", "and the strip is saved")
	assert_eq(saved.way, 1, "without changing the way")
	assert_eq(_page().row_value(DuelSelect.STRIP_ROW), "CLOCKWORK WELL",
		"and the page opens on it")


func test_the_strip_falls_back_alone() -> void:
	_write("[duel]\nway=\"cpu\"\nlevel=\"hard\"\nstrip=\"atlantis\"\n")
	var choice := DuelChoice.open(PATH)
	assert_eq(choice.strip, DuelStrips.TUG, "a strip that names nothing is the Tug of War")
	assert_eq([choice.way, choice.level], [1, DuelBrain.Difficulty.HARD],
		"and costs the way and the level nothing")
	_write("[duel]\nway=\"sideways\"\nstrip=\"AQUEDUCT\"\n")
	choice = DuelChoice.open(PATH)
	assert_eq(choice.strip, "aqueduct", "a good strip survives a bad way, in any case")
	_write("[duel]\nstrip=4\n")
	assert_eq(DuelChoice.open(PATH).strip, DuelStrips.TUG, "a strip of the wrong type")
	_write("[duel]\nway=\"local\"\nlevel=\"easy\"\n")
	assert_eq(DuelChoice.open(PATH).strip, DuelStrips.TUG,
		"a file from before the strips opens on the Tug of War")
	_write("[duel]\nstrip=\"random\"\n")
	assert_eq(DuelChoice.open(PATH).strip, DuelStrips.RANDOM, "RANDOM is kept as a choice")


func test_random_is_drawn_once_from_the_strips() -> void:
	var drawn := {}
	for seed_value: int in 64:
		var id := DuelStrips.resolve(DuelStrips.RANDOM, seed_value)
		assert_true(DuelStrips.is_strip(id), "%s is a strip" % id)
		drawn[id] = true
	assert_eq(drawn.size(), DuelStrips.IDS.size(), "every strip comes up")
	assert_eq(DuelStrips.resolve("well", 3), "well", "a strip resolves to itself")
	assert_eq(DuelStrips.resolve(DuelStrips.RANDOM, 9), DuelStrips.resolve(DuelStrips.RANDOM, 9),
		"the same seed draws the same strip")


func test_the_match_plays_the_strip_the_page_saved() -> void:
	var choice := DuelChoice.new()
	choice.path = PATH
	choice.strip = "aqueduct"
	assert_eq(choice.save(), OK)
	var scene := MATCH.instantiate()
	scene.set("choice_path", PATH)
	add_child_autofree(scene)
	var fight := scene.get_node(^"World/Match") as DuelMatch
	assert_eq(fight.strip.id, "aqueduct", "the match is on the saved strip")
	assert_gt(fight.stones.size(), 0, "with its stones")
	assert_true(scene.call("use_strip", "well"), "and can be put on another")
	assert_eq(fight.strip.id, "well", "as an online guest's is")
	assert_eq(fight.stones.size(), 0, "and the Well has none")
	assert_false(fight.set_arena("atlantis"), "a strip this build lacks is refused")
	assert_eq(fight.strip.id, "well", "and the match left where it was")
