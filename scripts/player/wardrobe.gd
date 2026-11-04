class_name Wardrobe
extends RefCounted
## The two saved looks, persisted to user://wardrobe.cfg.
##
## Player one is the adventure's figure -- the Adventure, Endless and the feel
## lab all dress their player from it -- and the crimson seat of a local duel.
## Player two is the sea-green seat. Online, a phone is one player, so it is
## player one's look that a phone shows on its own seat and sends to the
## other phone in the handshake (docs/netplay.md, "The looks").
##
## ## The file
##
## A ConfigFile with one section per player and the options as ids:
##
##     [player_one]
##     figure="heroine"
##     outfit="crimson"
##     ...
##
## Ids rather than indices because a settings file is something a player may
## open, and because the option lists in CharacterLook may grow or be
## reordered without moving anyone's choice. Reading is forgiving to the
## field: a missing file, a file that does not parse, a section that is not
## there or an id that names nothing all fall back to the default for exactly
## what is missing, and never to an error a player would see. The default is
## the prince in crimson and gold, which is what the game drew before there was
## a wardrobe.
##
## Kept apart from the editor, like AudioSettings is from the settings page, so
## a test can round-trip it against its own path without touching the real one.

const PATH := "user://wardrobe.cfg"
const PLAYER_ONE := 0
const PLAYER_TWO := 1
const SECTIONS: Array[String] = ["player_one", "player_two"]

var path := UserData.at(PATH)
var _looks: Array[CharacterLook] = [CharacterLook.new(), CharacterLook.new()]


## The saved wardrobe at `at`, or the defaults if there is nothing usable
## there.
static func open(at: String = "") -> Wardrobe:
	var wardrobe := Wardrobe.new()
	wardrobe.path = at if at != "" else UserData.at(PATH)
	wardrobe.load_from_disk()
	return wardrobe


## The look `player` wears, as a copy. Change it through set_look(), so a
## change is saved rather than lost on the next open().
func look(player: int) -> CharacterLook:
	return _looks[clampi(player, 0, _looks.size() - 1)].duplicate_look()


func set_look(player: int, value: CharacterLook) -> void:
	_looks[clampi(player, 0, _looks.size() - 1)] = value.duplicate_look()


## False when there was no usable file, which leaves every look at its
## default. A file that parses but carries nonsense still counts as loaded:
## the nonsense is what fell back, field by field.
func load_from_disk() -> bool:
	for i: int in _looks.size():
		_looks[i] = CharacterLook.new()
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return false
	for i: int in SECTIONS.size():
		if not file.has_section(SECTIONS[i]):
			continue
		var ids := {}
		for key: String in file.get_section_keys(SECTIONS[i]):
			ids[key] = file.get_value(SECTIONS[i], key)
		_looks[i].take_ids(ids)
	return true


func save() -> Error:
	var file := ConfigFile.new()
	for i: int in SECTIONS.size():
		var ids := _looks[i].to_ids()
		for key: String in ids:
			file.set_value(SECTIONS[i], key, ids[key])
	return file.save(path)
