extends GutTest
## The audio settings read field by field: one bad value falls back to its own
## default and takes nothing else with it (scripts/audio/audio_settings.gd).
##
## The case that matters: `music` saved as something that is not a number.
## Through a bare float() it read as 0.0, which is the music silenced with no
## way for the player to tell why. A file from an older build that lacks a key
## must keep every key it has.
##
## Seen to fail: with load_from_disk() back on float(file.get_value(...)),
## the first test reads the music as 0.

var _path := UserData.at("user://test_audio_settings_fallback.cfg")


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))


func _write(values: Dictionary) -> void:
	var file := ConfigFile.new()
	for key: String in values:
		file.set_value(AudioSettings.SECTION, key, values[key])
	assert_eq(file.save(_path), OK, "wrote the test file")


func _load() -> AudioSettings:
	var settings := AudioSettings.new()
	settings.path = _path
	assert_true(settings.load_from_disk(), "the file loads")
	return settings


func test_a_bad_value_falls_back_alone() -> void:
	_write({"master": 0.3, "music": "quiet", "sfx": 0.7, "muted": "yes"})
	var settings := _load()
	var defaults := AudioSettings.new()
	assert_eq(settings.music, defaults.music, "a word is not a volume: the default")
	assert_eq(settings.muted, defaults.muted, "nor a switch")
	assert_almost_eq(settings.master, 0.3, 0.0001, "master kept")
	assert_almost_eq(settings.sfx, 0.7, 0.0001, "sfx kept")


func test_a_missing_key_keeps_the_rest() -> void:
	_write({"music": 0.2})
	var settings := _load()
	var defaults := AudioSettings.new()
	assert_almost_eq(settings.music, 0.2, 0.0001, "music read")
	assert_eq(settings.master, defaults.master, "master defaulted")
	assert_eq(settings.sfx, defaults.sfx, "sfx defaulted")


func test_a_whole_number_is_a_volume() -> void:
	_write({"music": 1, "sfx": 0})
	var settings := _load()
	assert_eq(settings.music, 1.0, "an int is read as a level")
	assert_eq(settings.sfx, 0.0, "including zero, which is a choice, not a fault")


func test_the_music_round_trips_through_its_own_file() -> void:
	var settings := AudioSettings.new()
	settings.path = _path
	settings.music = 0.3
	assert_eq(settings.save(), OK, "saved")
	assert_almost_eq(_load().music, 0.3, 0.0001, "and read back")
