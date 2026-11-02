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

signal changed()

const PATH := "user://audio.cfg"
const SECTION := "audio"
## Below this a bus is silenced outright rather than left at -60 dB.
const SILENCE_DB := -60.0

var master: float = 0.9:
	set(value):
		master = clampf(value, 0.0, 1.0)
		changed.emit()
var music: float = 0.65:
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
	if file.load(PATH) != OK:
		return false
	master = float(file.get_value(SECTION, "master", master))
	music = float(file.get_value(SECTION, "music", music))
	sfx = float(file.get_value(SECTION, "sfx", sfx))
	muted = bool(file.get_value(SECTION, "muted", muted))
	return true


func save() -> Error:
	var file := ConfigFile.new()
	# Keep whatever else lives in the file; this is the shared settings path.
	file.load(PATH)
	for key: String in as_dictionary():
		file.set_value(SECTION, key, as_dictionary()[key])
	return file.save(PATH)
