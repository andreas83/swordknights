class_name Campaign
extends RefCounted
## The Adventure -- *The Last Light* -- as an ordered list of entries.
##
## Each entry is a level file played in order: a title, the numeral and
## epigraph on its card, the hour it is set at, and where it lives. The list
## is the single place a chapter is added (docs/architecture.md, "Adding a
## chapter"): a level file and one line in `entries()`. Like ModeRegistry it
## stays a plain list, because several people add to it at once.
##
## ## What an entry is
##
## - `id` keys the saved progress (CampaignProgress). It never changes once a
##   build with the entry has shipped, so an entry can be retitled, or moved,
##   without anybody's record moving with it.
## - `file` is empty until the level is built. Such an entry is shown "still
##   being built", never played; the campaign works with only chapter I.
## - `time` is the stop of the time-of-day grade the chapter is set at. The
##   level file says it too, with `;! time`, and the level is what the grade
##   reads; this is what the chapter select shows, and a test holds the two
##   together for every entry that has a file.
## - `finale` marks an entry that is the end of the chapter before it rather
##   than a chapter of its own: no numeral of its own, and the select draws it
##   under its chapter. The Eclipse is one. Its own entry -- not a phase of
##   Chapter V's level -- because its checkpoint has to be inside the arena
##   and the boss's won phases have to outlive a death (docs/campaign.md,
##   "Decided by the owner"); a respawn is per level, and the arena is its
##   own level. Six entries, then, not five with a sub-entry: progress,
##   unlocking and CONTINUE need no second kind of thing.
##
## - `tower` is how far away the Mirror Tower stands in the chapter's sky,
##   from 1 on the far skyline toward 0 (ParallaxSky.tower). One number per
##   entry, kept in TOWER beside the list rather than in each line of it, so
##   the entries stay one line each. It only ever comes nearer: a test holds
##   it to that, chapter by chapter.
##
## After the last entry comes the ending card, ENDING, and then the chapter
## select.

## The card after the last entry.
const ENDING := {"title": "Dawn", "epigraph": "The sun remembers"}

## How far away the Mirror Tower stands in each entry's sky, by id
## (docs/campaign.md, "Story without words": it "grows nearer each chapter
## until you are on it"): on the far skyline from the Sun Terrace, over the
## plaza's roofs at the end of the Long Arcade, across the ravine the
## Aqueduct crosses toward it -- and then 0, on it. Chapter IV is its west
## face and Chapter V is under its foot, so a tower in their skies would be a
## second one standing behind the first. The steps shrink as it nears, the
## way a landmark you walk toward grows. An id not here has no tower.
const TOWER := {
	"sun_terrace": 1.0,
	"long_arcade": 0.72,
	"aqueduct": 0.46,
	"mirror_tower": 0.0,
	"sun_well": 0.0,
	"eclipse": 0.0,
}

## Which entry CampaignGame plays: set by the chapter select before it
## changes scene, and moved on by CampaignGame as chapters chain.
static var selected := 0

static var _for_tests: Array[Dictionary] = []


## Every entry, in the order they are played. One line each.
static func entries() -> Array[Dictionary]:
	if not _for_tests.is_empty():
		return _for_tests.duplicate(true)
	return [
		_entry("sun_terrace", "I", "The Sun Terrace", "The last hour of light",
			"afternoon", "res://levels/level_01.txt"),
		_entry("long_arcade", "II", "The Long Arcade", "The gates are falling", "golden"),
		_entry("aqueduct", "III", "The Aqueduct", "The old stone is tired", "sunset"),
		_entry("mirror_tower", "IV", "The Mirror Tower", "Catch the last light", "dusk"),
		_entry("sun_well", "V", "The Sun Well", "What the city kept", "night"),
		_entry("eclipse", "", "The Eclipse", "", "night", "", true),
	]


static func count() -> int:
	return entries().size()


## Entry `index`, or an empty dictionary past either end.
static func entry(index: int) -> Dictionary:
	var all := entries()
	if index < 0 or index >= all.size():
		return {}
	return all[index]


## Whether entry `index` has a level to play (unlocking is the progress's).
static func is_built(index: int) -> bool:
	return String(entry(index).get("file", "")) != ""


## The numeral an entry's card and row carry: its own, or for a finale the
## chapter's it ends.
static func numeral_of(index: int) -> String:
	var all := entries()
	for at: int in range(clampi(index, 0, all.size() - 1), -1, -1):
		if String(all[at]["numeral"]) != "":
			return String(all[at]["numeral"])
	return ""


## What entry `index`'s title card says (Hud.show_card()): its numeral, its
## title and its epigraph -- or, for a finale, its title alone and the mark
## of a finale where the numeral would be (docs/campaign.md, "Story without
## words"). Empty past either end.
static func card(index: int) -> Dictionary:
	var at := entry(index)
	if at.is_empty():
		return {}
	return {
		"numeral": String(at.get("numeral", "")),
		"title": String(at.get("title", "")),
		"epigraph": String(at.get("epigraph", "")),
		"finale": bool(at.get("finale", false)),
	}


## Test seam: plays `list` instead of the real campaign until reset().
static func use_for_test(list: Array[Dictionary]) -> void:
	_for_tests = list.duplicate(true)
	selected = 0


static func reset() -> void:
	_for_tests.clear()
	selected = 0


## An entry, built by name rather than as a literal so every line of
## entries() has every field.
static func _entry(id: String, numeral: String, title: String, epigraph: String,
		time: String, file: String = "", finale: bool = false) -> Dictionary:
	return {
		"id": id, "numeral": numeral, "title": title, "epigraph": epigraph,
		"time": time, "file": file, "finale": finale, "tower": float(TOWER.get(id, 0.0)),
	}
