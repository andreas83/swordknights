extends GutTest
## The guard against the eighth way of being unreliable: a test that reads or
## writes the player's real files under user://, or another run's.
##
## Several tests wrote the real progress, audio, assist and wardrobe files --
## some by naming them, most by saving to a class's default without naming a
## file at all -- and every test that named a file of its own named the same
## one in every run. Two suites side by side, or a suite and the game, then
## read what the other had just written: a test went red or green by what
## another process saved a moment before. Every save now goes through one
## seam, UserData.at() (scripts/core/user_data.gd), which keeps a test run's
## files in a directory of that run's own. This holds the seam in place:
##
## - the run is sandboxed, and every save's default lands inside the sandbox;
## - no test names a `user://` file but through UserData.at(), so the file a
##   test writes, reads and removes is the one the code under test used;
## - no test names a save's real path constant but through UserData.at();
## - every save in the game resolves its path through UserData.at().

const SCANNED_TESTS := "res://tests"
const SCANNED_GAME := "res://scripts"
## A string literal that is a user:// path.
const LITERAL := "\"user://[^\"]*\""
## A reference to one of the game's real save paths by its constant.
const REAL_PATH := "\\b(CampaignProgress|AudioSettings|Wardrobe|DuelChoice|Assist)\\.PATH\\b" \
	+ "|\\bFlow\\.SETTINGS_PATH\\b"


func test_the_run_keeps_its_files_in_a_sandbox() -> void:
	assert_true(UserData.is_sandboxed(), "the run is sandboxed (run_tests.sh or the GUT hook)")
	var root := UserData.root()
	assert_ne(root, "", "in a directory of its own")
	# Each save's default, against the real file it would be in the game.
	var defaults := {
		CampaignProgress.new().path: CampaignProgress.PATH,
		AudioSettings.new().path: AudioSettings.PATH,
		Wardrobe.open().path: Wardrobe.PATH,
		DuelChoice.open().path: DuelChoice.PATH,
		UserData.at(Assist.PATH): Assist.PATH,
		UserData.at(Flow.SETTINGS_PATH): Flow.SETTINGS_PATH,
	}
	for path: String in defaults:
		assert_true(path.begins_with(root), "the default is in the sandbox: %s" % path)
		assert_ne(path, String(defaults[path]), "and is not the real file")
	assert_eq(UserData.at("res://levels/level_01.txt"), "res://levels/level_01.txt",
		"and nothing that is not user:// moves")


func test_no_test_names_a_user_file_but_through_the_seam() -> void:
	var found := _offences(SCANNED_TESTS, _bare_literals)
	assert_eq(found, PackedStringArray(),
		"a user:// file in a test is named as UserData.at(\"user://...\")")


func test_no_test_names_a_real_save_path_but_through_the_seam() -> void:
	var found := _offences(SCANNED_TESTS, _bare_real_paths)
	assert_eq(found, PackedStringArray(),
		"a real save path in a test is only ever UserData.at(Class.PATH)")


func test_every_save_in_the_game_goes_through_the_seam() -> void:
	var found := PackedStringArray()
	var files := _scripts(SCANNED_GAME)
	var saves := 0
	for path: String in files:
		if path.ends_with("core/user_data.gd"):
			continue # the seam itself
		var text := FileAccess.get_file_as_string(path)
		var names := _path_constants(text)
		for name: String in names:
			saves += 1
			for line: String in _code_lines(text):
				if line.begins_with("const "):
					continue
				for use: String in _uses_outside_seam(line, name):
					found.append("%s: %s used bare: %s" % [path, name, use])
	found.append_array(_offences(SCANNED_GAME, _bare_real_paths))
	assert_gt(saves, 5, "the scan found the game's saves (it is reading the files)")
	assert_eq(found, PackedStringArray(), "every user:// constant is resolved by UserData.at()")


## The scan proves it can see what it guards against.
func test_the_scan_catches_what_it_is_for() -> void:
	assert_eq(_bare_literals("\tAssist.load_saved(\"user://x.cfg\")").size(), 1,
		"a bare literal")
	assert_eq(_bare_literals("\tAssist.load_saved(UserData.at(\"user://x.cfg\"))").size(), 0,
		"through the seam")
	assert_eq(_bare_real_paths("\tvar p := CampaignProgress.PATH").size(), 1, "a real path")
	assert_eq(_bare_real_paths("\tvar p := UserData.at(CampaignProgress.PATH)").size(), 0,
		"a real path through the seam")
	assert_eq(_uses_outside_seam("\tfile.save(PATH)", "PATH").size(), 1, "a save that bypasses it")
	assert_eq(_uses_outside_seam("\tfile.save(UserData.at(PATH))", "PATH").size(), 0,
		"a save that does not")


## --- the scan --------------------------------------------------------------------

func _offences(dir: String, check: Callable) -> PackedStringArray:
	var found := PackedStringArray()
	for path: String in _scripts(dir):
		if path.ends_with("test_user_data_sandbox.gd"):
			continue
		var number := 0
		for line: String in FileAccess.get_file_as_string(path).split("\n"):
			number += 1
			if line.strip_edges().begins_with("#"):
				continue
			for hit: String in check.call(line):
				found.append("%s:%d: %s" % [path, number, hit])
	return found


func _bare_literals(line: String) -> PackedStringArray:
	return _outside_seam(line, LITERAL)


func _bare_real_paths(line: String) -> PackedStringArray:
	return _outside_seam(line, REAL_PATH)


## What `pattern` matches in `line` that is not the argument of UserData.at().
func _outside_seam(line: String, pattern: String) -> PackedStringArray:
	var out := PackedStringArray()
	var regex := RegEx.create_from_string(pattern)
	for hit: RegExMatch in regex.search_all(line):
		if not line.substr(0, hit.get_start()).ends_with("UserData.at("):
			out.append(hit.get_string())
	return out


## Uses of the constant `name` in `line` that UserData.at() does not wrap.
func _uses_outside_seam(line: String, name: String) -> PackedStringArray:
	var out := PackedStringArray()
	var regex := RegEx.create_from_string("(?<![\\w.])%s\\b" % name)
	for hit: RegExMatch in regex.search_all(line):
		var before := line.substr(0, hit.get_start())
		if not before.ends_with("UserData.at("):
			out.append(line.strip_edges())
	return out


## The `const NAME := "user://..."` declarations in a script.
func _path_constants(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var regex := RegEx.create_from_string("(?m)^const ([A-Z_]+) := \"user://")
	for hit: RegExMatch in regex.search_all(text):
		out.append(hit.get_string(1))
	return out


## Lines of code: comments dropped, so a docstring may name a path.
func _code_lines(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	for line: String in text.split("\n"):
		var code := line.strip_edges()
		if code == "" or code.begins_with("#"):
			continue
		out.append(code)
	return out


func _scripts(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var listing := DirAccess.open(dir)
	if listing == null:
		return out
	for name: String in listing.get_files():
		if name.ends_with(".gd"):
			out.append(dir.path_join(name))
	for sub: String in listing.get_directories():
		out.append_array(_scripts(dir.path_join(sub)))
	return out
