extends GutTest
## The Last Light's catalogue (scripts/campaign/campaign.gd) and the way into
## it from the title screen.
##
## Held here: chapter I is the Sun Terrace exactly as it ships; every entry
## has a stable id, a numeral in order, an hour the grade knows and the
## campaign's titles, with the Eclipse as a finale after chapter V; an entry
## that is built is a level that parses clean and is set at the hour the
## catalogue says, so the chapter select cannot promise dusk and play noon;
## an entry not yet built is never playable; and ADVENTURE opens the chapter
## select.

const NUMERALS: Array[String] = ["I", "II", "III", "IV", "V"]


func after_each() -> void:
	Campaign.reset()


func test_chapter_one_is_the_sun_terrace() -> void:
	var first := Campaign.entry(0)
	assert_eq(first["file"], "res://levels/level_01.txt")
	assert_eq(first["title"], "The Sun Terrace")
	assert_eq(first["numeral"], "I")
	assert_eq(first["time"], "afternoon", "the look the game has always had")
	assert_true(Campaign.is_built(0))


func test_every_entry_is_whole_and_in_order() -> void:
	var ids := {}
	var numerals: Array[String] = []
	for index: int in Campaign.count():
		var entry := Campaign.entry(index)
		var id := String(entry["id"])
		assert_ne(id, "", "entry %d has an id" % index)
		assert_false(ids.has(id), "%s is the only entry with its id" % id)
		ids[id] = true
		assert_ne(String(entry["title"]), "", "%s has a title" % id)
		assert_true(TimeOfDay.is_stop(String(entry["time"])), "%s is set at a stop" % id)
		if bool(entry["finale"]):
			assert_eq(entry["numeral"], "", "a finale has no numeral of its own")
			assert_gt(index, 0, "and comes after a chapter")
		else:
			numerals.append(String(entry["numeral"]))
	assert_eq(numerals, NUMERALS, "five chapters, numbered in order")
	var last := Campaign.count() - 1
	assert_eq(Campaign.entry(last)["title"], "The Eclipse", "the finale is last")
	assert_true(bool(Campaign.entry(last)["finale"]))
	assert_eq(Campaign.numeral_of(last), "V", "and carries chapter V's numeral")


func test_a_built_entry_is_a_clean_level_at_the_catalogues_hour() -> void:
	var built := 0
	for index: int in Campaign.count():
		if not Campaign.is_built(index):
			continue
		built += 1
		var entry := Campaign.entry(index)
		var file := String(entry["file"])
		assert_true(FileAccess.file_exists(file), "%s exists" % file)
		var level := AsciiLevel.from_file(file)
		assert_eq(level.problems, PackedStringArray(), "%s parses clean" % file)
		assert_eq(EntityRegistry.problems_in(level), PackedStringArray(), "and is wired")
		assert_eq(TimeOfDay.stop_of(level), String(entry["time"]),
			"%s is set at the hour the chapter select shows" % file)
		assert_true(bool(LevelReachability.verify(level)["ok"]), "%s can be finished" % file)
	assert_gt(built, 0, "the campaign has at least chapter I to play")


func test_an_entry_still_being_built_is_never_playable() -> void:
	var progress := CampaignProgress.new()
	progress.path = UserData.at("user://test_catalogue_progress.cfg")
	for index: int in Campaign.count():
		progress.record_clear(index, 60.0, 0, 0, 0, 0)
	for index: int in Campaign.count():
		assert_true(progress.is_unlocked(index), "everything is open after clearing it all")
		assert_eq(progress.is_playable(index), Campaign.is_built(index),
			"but only what is built can be played")


func test_adventure_opens_the_chapter_select() -> void:
	var adventure := {}
	for mode: Dictionary in ModeRegistry.modes():
		if String(mode["id"]) == "adventure":
			adventure = mode
	assert_eq(adventure.get("scene"), CampaignGame.CHAPTER_SELECT,
		"ADVENTURE goes to the chapter select")
	assert_eq(String(adventure.get("subtitle")), ChapterSelect.TITLE,
		"under the campaign's name")
	var scene := load(String(adventure["scene"])) as PackedScene
	assert_not_null(scene, "which loads")
	var page := scene.instantiate() as ChapterSelect
	assert_not_null(page, "and is the chapter select")
	page.store_path = UserData.at("user://test_catalogue_progress.cfg")
	add_child_autofree(page)
	assert_eq(page.row_title(0), "CONTINUE", "CONTINUE first")
