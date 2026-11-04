class_name DuelChoice
extends RefCounted
## Which duel the player last chose, how hard the computer was, and where they
## fought: persisted to user://duel.cfg, so DUEL opens on the way they play.
##
## ## The file
##
##     [duel]
##     way="cpu"
##     level="medium"
##     strip="well"
##
## Words rather than indices, for the reason Wardrobe gives: a settings file is
## something a player may open, and the list of ways or of levels may grow or
## be reordered without moving anyone's choice. Reading is forgiving to the
## field: a missing file, a file that does not parse, a key that is not there,
## a value of the wrong type or a word that names nothing falls back for
## exactly what is missing -- ONE KEYBOARD, EASY and the Tug of War, the
## gentlest and the first -- and never to an error a player would see. A broken
## `way` does not cost the `level` or the `strip`, nor any of them the others.
## A file from before the strips has no `strip` and opens on the Tug of War,
## which is the duel it was saved from. `strip` may also be "random", which is
## a choice and not a strip: DuelStrips.resolve() draws one when a match is
## built.
##
## Kept apart from the page, as Wardrobe is from its editor, so a test can
## round-trip it against its own path without touching the real one -- which is
## shared, on a developer's machine, with every other checkout of the game.

const PATH := "user://duel.cfg"
const SECTION := "duel"

## The three ways to duel, in the order the page lists them, with the scene
## each one opens.
const WAYS: Array[String] = ["local", "cpu", "online"]
const SCENES: Array[String] = [
	"res://scenes/duel_match.tscn",
	"res://scenes/duel_match_cpu.tscn",
	"res://scenes/duel_match_online.tscn",
]

var path := UserData.at(PATH)
## Index into WAYS.
var way := 0
## A DuelBrain.Difficulty.
var level: DuelBrain.Difficulty = DuelBrain.Difficulty.EASY
## A DuelStrips id, or DuelStrips.RANDOM.
var strip: String = DuelStrips.TUG


## The saved choice at `at`, or the defaults if there is nothing usable there.
static func open(at: String = "") -> DuelChoice:
	var choice := DuelChoice.new()
	choice.path = at if at != "" else UserData.at(PATH)
	choice.load_from_disk()
	return choice


## False when there was no usable file, which leaves both at their defaults.
## A file that parses but carries nonsense still counts as loaded: the
## nonsense is what fell back, field by field.
func load_from_disk() -> bool:
	way = 0
	level = DuelBrain.Difficulty.EASY
	strip = DuelStrips.TUG
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return false
	var said: Variant = file.get_value(SECTION, "way", "")
	if said is String and WAYS.has(String(said).to_lower()):
		way = WAYS.find(String(said).to_lower())
	var hard: Variant = file.get_value(SECTION, "level", "")
	if hard is String and DuelBrain.LEVEL_NAMES.has(String(hard).to_upper()):
		level = DuelBrain.LEVEL_NAMES.find(String(hard).to_upper()) as DuelBrain.Difficulty
	var where: Variant = file.get_value(SECTION, "strip", "")
	if where is String and DuelStrips.is_choice(String(where).to_lower()):
		strip = String(where).to_lower()
	return true


func save() -> Error:
	var file := ConfigFile.new()
	file.set_value(SECTION, "way", WAYS[clampi(way, 0, WAYS.size() - 1)])
	file.set_value(SECTION, "level", String(DuelBrain.level_name(level)).to_lower())
	file.set_value(SECTION, "strip", strip if DuelStrips.is_choice(strip) else DuelStrips.TUG)
	return file.save(path)


func scene() -> String:
	return SCENES[clampi(way, 0, SCENES.size() - 1)]
