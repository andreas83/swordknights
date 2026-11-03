extends GutTest
## The contract between .github/scripts/stamp_version.sh and the app: what CI
## stamps is a script the engine can load, and it says what the update check
## needs it to say.
##
## The stamp is sed over a GDScript file, so the failure it invites is a quote
## or a missed line that nobody sees until a phone runs the build: a dev APK
## that thinks it is build 1 offers every update forever, and one that fails
## to parse never boots. This runs the real script on copies of the two real
## files, then compiles the result.

const SCRIPT := "res://.github/scripts/stamp_version.sh"
const SHA := "4f2c9e1aabbccddeeff00112233445566778899a"
const FEED := "https://github.com/o/r/releases/download/dev/version.json"

var _dir := ""


func before_each() -> void:
	_dir = OS.get_cache_dir().path_join("swordknights-stamp-test-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(_dir)
	for source: String in ["res://export_presets.cfg", "res://scripts/core/build_stamp.gd"]:
		var copy := FileAccess.open(_dir.path_join(source.get_file()), FileAccess.WRITE)
		copy.store_string(FileAccess.get_file_as_string(source))
		copy.close()


func after_each() -> void:
	for name: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(name))
	DirAccess.remove_absolute(_dir)


func _stamp(args: Array[String]) -> int:
	var argv := PackedStringArray([
		"BUILD_STAMP=" + _dir.path_join("build_stamp.gd"), "GITHUB_OUTPUT=",
		"bash", ProjectSettings.globalize_path(SCRIPT),
	])
	argv.append_array(PackedStringArray(args))
	argv.append(_dir.path_join("export_presets.cfg"))
	var output: Array = []
	var code := OS.execute("env", argv, output, true)
	gut.p("stamp_version.sh %s -> %d\n%s" % [" ".join(args), code, "".join(output)])
	return code


## The stamped build_stamp.gd, compiled, as a constant map; {} if it does not
## compile.
func _constants() -> Dictionary:
	var script := GDScript.new()
	script.source_code = FileAccess.get_file_as_string(_dir.path_join("build_stamp.gd"))
	if script.reload() != OK:
		return {}
	return script.get_script_constant_map()


func _android_option(key: String) -> Variant:
	var presets := ConfigFile.new()
	presets.load(_dir.path_join("export_presets.cfg"))
	for section: String in presets.get_sections():
		if presets.get_value(section, "name", "") == "Android":
			return presets.get_value(section + ".options", key)
	return null


func test_a_dev_stamp_is_a_build_that_checks_its_feed() -> void:
	assert_eq(_stamp(["--dev", "57", SHA, FEED] as Array[String]), 0, "the stamp succeeds")
	var stamped := _constants()
	assert_false(stamped.is_empty(), "the stamped file compiles")
	assert_eq(stamped.get("CODE"), 57)
	assert_eq(stamped.get("NAME"), "0.1.0-dev+4f2c9e1", "the name carries the short commit")
	assert_eq(stamped.get("SHA"), SHA)
	assert_eq(stamped.get("FEED"), FEED)
	assert_true(DevUpdate.should_check(true, String(stamped.get("CHANNEL")),
		String(stamped.get("FEED"))), "a debug export of it asks the feed")
	assert_eq(_android_option("version/code"), 57, "Android gets the same code")
	assert_eq(_android_option("version/name"), stamped.get("NAME"), "and the same name")


func test_a_release_stamp_is_a_build_that_never_checks() -> void:
	assert_eq(_stamp(["v1.2.3"] as Array[String]), 0)
	var stamped := _constants()
	assert_eq(stamped.get("CODE"), 10203)
	assert_eq(stamped.get("NAME"), "1.2.3")
	assert_eq(stamped.get("CHANNEL"), "release")
	assert_false(DevUpdate.should_check(true, String(stamped.get("CHANNEL")),
		String(stamped.get("FEED"))), "even a debug export of a release does not ask")
	assert_eq(_android_option("version/code"), 10203)


func test_a_bad_argument_stamps_nothing() -> void:
	var before := FileAccess.get_file_as_string(_dir.path_join("build_stamp.gd"))
	# No feed with a quote in it: OS.execute re-tokenises its arguments and
	# strips quotes before bash sees them, so that case can only be tried from
	# a shell. The sed delimiter and a wrong scheme survive the trip.
	for args: Array[String] in [
		["--dev", "57", "not-a-sha", FEED] as Array[String],
		["--dev", "0", SHA, FEED] as Array[String],
		["--dev", "57", SHA, "https://x/a|b"] as Array[String],
		["--dev", "57", SHA, "ftp://x/version.json"] as Array[String],
		["1.2"] as Array[String],
	]:
		assert_ne(_stamp(args), 0, "rejected: %s" % " ".join(args))
	assert_eq(FileAccess.get_file_as_string(_dir.path_join("build_stamp.gd")), before,
		"and the file is as it was")
