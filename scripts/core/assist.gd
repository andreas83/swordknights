class_name Assist
extends RefCounted
## What the player can ask the game to give them. Today, one thing: LONGER
## WARNINGS.
##
## ## Longer warnings
##
## Off by default; the numbers in docs/campaign.md and every foe's tuning are
## the unassisted ones. On, every foe's tell and every timed window that
## stands between the prince and a death lasts LONGER times as long -- the
## sentinel's raise, a crumbling slab's fuse, a blade's draw before its cut --
## and nothing else changes: not the cut itself, not the opening after it, not
## the prince. It buys reading time, which is what a death in this game is
## about, and leaves the answer to be given exactly as before.
##
## Read through one API so no foe can forget it: `Foe.warn()` in the foe
## contract (scripts/entities/foe.gd), and `Mechanism.warn()` for a trap with
## a clock in it. Both ask warning_scale() here; nothing else should.
##
## ## The file
##
## user://assist.cfg, one section, read forgivingly like the wardrobe: a
## missing or broken file, or a value of the wrong type, is the default for
## exactly what is missing. It is loaded once, at boot (scripts/core/boot.gd),
## not on first use -- so a test, the trace tool or anything else that never
## boots the game plays unassisted whatever a developer last chose in it.

const PATH := "user://assist.cfg"
const SECTION := "assist"
## How much longer a warning lasts. Half as long again: the sentinel's raise
## goes from 27 frames to 41, longer than a slow reaction twice over, while
## the rhythm of a fight -- raise, cut, opening -- still reads as one.
const LONGER := 1.5

static var _longer_warnings := false
static var _path := PATH


## The factor every warning is multiplied by: 1.0 unless the player asked for
## longer ones.
static func warning_scale() -> float:
	return LONGER if _longer_warnings else 1.0


static func longer_warnings() -> bool:
	return _longer_warnings


## Turns the assist on or off and saves it at once, so a phone that kills the
## app from the background never loses the choice.
static func set_longer_warnings(on: bool) -> Error:
	_longer_warnings = on
	var file := ConfigFile.new()
	file.set_value(SECTION, "longer_warnings", on)
	return file.save(_path)


## Reads the saved assists from `at` (and saves there from now on). False
## when there was nothing usable, which leaves every assist off.
static func load_saved(at: String = PATH) -> bool:
	_path = at
	_longer_warnings = false
	var file := ConfigFile.new()
	if file.load(at) != OK:
		return false
	var value: Variant = file.get_value(SECTION, "longer_warnings", false)
	if typeof(value) != TYPE_BOOL:
		return false
	_longer_warnings = bool(value)
	return true


## Test seam: every assist off, saving to the real path again.
static func reset() -> void:
	_longer_warnings = false
	_path = PATH
