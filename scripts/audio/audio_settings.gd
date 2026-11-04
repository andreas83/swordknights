class_name AudioSettings
extends RefCounted
## Master / music / SFX volume and a mute flag, persisted to user://.
##
## Plain linear 0..1 values on disk — a settings file is something a player may
## open, and decibels are not a number anyone wants to hand-edit. The
## conversion to the bus faders happens here, once, in `db_for()`.
##
## Kept separate from AudioDirector so a settings screen can read and write it
## without touching the mixer, and so the test can round-trip it.
##
## Read field by field: a value that is missing, of the wrong type or not a
## number falls back to its own default and takes nothing else with it. A file
## hand-edited to `music = "quiet"` would otherwise read as 0.0 -- silence --
## through `float()`, and a file from an older build that lacks a key keeps
## every key it does have.

signal changed()

const PATH := "user://audio.cfg"
const SECTION := "audio"
## Below this a bus is silenced outright rather than left at -60 dB.
const SILENCE_DB := -60.0

## Where the settings live. A test seam: a test reads and writes its own file,
## never the player's.
var path := PATH

var master: float = 0.9:
	set(value):
		master = clampf(value, 0.0, 1.0)
		changed.emit()
## Lower than the 0.65 it was: the music sits under Mix.MUSIC_TRIM_DB as well,
## and a phone test found it loud enough to be the thing the player heard.
var music: float = 0.5:
	set(value):
		music = clampf(value, 0.0, 1.0)
		changed.emit()
var sfx: float = 1.0:
	set(value):
		sfx = clampf(value, 0.0, 1.0)
		changed.emit()
var muted: bool = false:
	set(value):
		muted = value
		changed.emit()


func linear_for(bus: StringName) -> float:
	match String(bus):
		"Music":
			return music
		"SFX":
			return sfx
		_:
			return master


## Bus fader value. A linear slider maps to decibels so that halfway sounds
## halfway, which `linear_to_db` gives us for free.
func db_for(bus: StringName) -> float:
	var value := linear_for(bus)
	if value <= 0.001:
		return SILENCE_DB
	return maxf(SILENCE_DB, linear_to_db(value))


func as_dictionary() -> Dictionary:
	return {"master": master, "music": music, "sfx": sfx, "muted": muted}


func apply(values: Dictionary) -> void:
	master = float(values.get("master", master))
	music = float(values.get("music", music))
	sfx = float(values.get("sfx", sfx))
	muted = bool(values.get("muted", muted))


func load_from_disk() -> bool:
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return false
	master = _level(_read(file, "master"), master)
	music = _level(_read(file, "music"), music)
	sfx = _level(_read(file, "sfx"), sfx)
	var mute: Variant = _read(file, "muted")
	if mute is bool:
		muted = mute
	return true


## The stored value, or null for a key the file does not have. ConfigFile
## reports a missing key with no default as an error; a missing key is normal.
static func _read(file: ConfigFile, key: String) -> Variant:
	return file.get_value(SECTION, key) if file.has_section_key(SECTION, key) else null


## `value` as a 0..1 level, or `fallback` when it is not a finite number.
static func _level(value: Variant, fallback: float) -> float:
	if not (value is float or value is int):
		return fallback
	var number := float(value)
	return number if is_finite(number) else fallback


func save() -> Error:
	var file := ConfigFile.new()
	# Keep whatever else lives in the file; this is the shared settings path.
	file.load(path)
	for key: String in as_dictionary():
		file.set_value(SECTION, key, as_dictionary()[key])
	return file.save(path)
