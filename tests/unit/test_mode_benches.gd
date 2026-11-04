extends GutTest
## The feel lab is a tuning bench, and a bench is not on the title screen of
## a build anyone plays (scripts/core/mode_registry.gd, shows_benches()).
##
## FEEL LAB sat on the title screen of every build, the phone's included,
## between DUEL and WARDROBE: a door into a test level with no game in it.
## Held here: a bench is listed only when asked for, the title screen asks
## exactly when the registry says to, and the registry says so only on the
## editor's own binary -- not on a debug build, which the CI-built APK on the
## owner's phone is.

const MENU := preload("res://scenes/menu.tscn")


func test_a_bench_is_listed_only_when_asked_for() -> void:
	assert_true(_ids(ModeRegistry.modes(true)).has("feel_lab"), "asked for, it is there")
	assert_false(_ids(ModeRegistry.modes(false)).has("feel_lab"), "otherwise it is not")
	for id: String in ["adventure", "endless", "duel"]:
		assert_true(_ids(ModeRegistry.modes(false)).has(id), "%s is always listed" % id)


func test_benches_follow_the_editor_binary_not_the_debug_flag() -> void:
	assert_eq(ModeRegistry.shows_benches(), OS.has_feature("editor"),
		"an export template lacks `editor` whatever it is stamped; a debug APK is a "
			+ "debug build, so is_debug_build() would have shown it on the phone")


func test_the_title_screen_lists_no_bench_in_a_build_that_shows_none() -> void:
	for benches: bool in [false, true]:
		var menu := MENU.instantiate() as MenuScene
		menu.benches = benches
		menu.quit_app = func() -> void: pass
		add_child_autofree(menu)
		var ids: Array[String] = []
		for row: Dictionary in menu.rows():
			ids.append(String(row["id"]))
		assert_eq(ids.has("feel_lab"), benches,
			"FEEL LAB %s" % ("listed where benches are" if benches else "absent"))
		assert_true(ids.has("settings") and ids.has("wardrobe"), "the rest of the list stands")
		menu.free()


func _ids(modes: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for mode: Dictionary in modes:
		out.append(String(mode["id"]))
	return out
