class_name DuelStrips
extends RefCounted
## Every strip a duel can be fought on, by its short name, and the one place
## that turns a name into a ZoneStrip.
##
## A name rather than an index travels: it is what user://duel.cfg keeps, what
## the online handshake carries, and what `--strip=` takes, for the reason the
## wardrobe keeps ids -- a list that grows or is reordered moves nobody's
## choice, and two builds that list the strips differently still agree on
## what "well" is. A name a build does not know is refused by name, in a
## sentence, rather than read as some other strip.
##
## Each strip is a place, an hour and one rule that changes how a duel there is
## fought (docs/duel-match.md, "The strips"):
##
## | id | strip | hour | the rule |
## | --- | --- | --- | --- |
## | tug | The Tug of War | afternoon, dusk at the gates | a moat and a spike pit: the original |
## | well | The Clockwork Well | night | scythes on the beat, spike slots on the off-beat |
## | floodgates | The Floodgates | golden hour | the low courts flood on a timer and drain |
## | aqueduct | The Crumbling Aqueduct | sunset | the deck falls where it is stood on, for good |
## | roofs | The Rooftops | dusk | alleys between the roofs, and nothing at the bottom |

const TUG := "tug"
## Not a strip: a choice the page offers, resolved to a strip when a match is
## built, never sent or saved as a strip.
const RANDOM := "random"

const IDS: Array[String] = [TUG, "well", "floodgates", "aqueduct", "roofs"]
const MANIFESTS := {
	"tug": "res://levels/duel_zones.txt",
	"well": "res://levels/strip_well.txt",
	"floodgates": "res://levels/strip_floodgates.txt",
	"aqueduct": "res://levels/strip_aqueduct.txt",
	"roofs": "res://levels/strip_roofs.txt",
}
## What the duel page calls each, in capitals as it sets them: the manifest's
## own name is for the HUD, and is too long for a row's right-hand side.
const LABELS := {
	"tug": "TUG OF WAR",
	"well": "CLOCKWORK WELL",
	"floodgates": "FLOODGATES",
	"aqueduct": "AQUEDUCT",
	"roofs": "ROOFTOPS",
	"random": "RANDOM",
}


## What each does to a duel, for the caption under the page's STRIP row:
## longest phrasing first, as UiFont.fit() takes them.
const CAPTIONS := {
	"tug": ["A MOAT AND A SPIKE PIT  ·  DUSK AT THE GATES", "A MOAT AND A SPIKE PIT"],
	"well": ["SCYTHES ON THE BEAT, SLOTS ON THE OFF-BEAT  ·  NIGHT",
		"BLADES ON THE BEAT"],
	"floodgates": ["THE LOW COURTS FLOOD AND DRAIN  ·  GOLDEN HOUR", "THE COURTS FLOOD"],
	"aqueduct": ["THE DECK FALLS WHERE IT IS STOOD ON  ·  SUNSET", "THE DECK FALLS"],
	"roofs": ["ALLEYS WITH NOTHING AT THE BOTTOM  ·  DUSK", "MIND THE ALLEYS"],
	"random": ["ANY ONE OF THE FIVE, DRAWN AS THE DUEL BEGINS", "ANY ONE OF THE FIVE"],
}


static func caption(id: String) -> Array:
	return CAPTIONS.get(id, [label(id)]) as Array


static func is_strip(id: String) -> bool:
	return MANIFESTS.has(id)


## A strip id or RANDOM: what the duel page may offer and save.
static func is_choice(id: String) -> bool:
	return is_strip(id) or id == RANDOM


static func label(id: String) -> String:
	return String(LABELS.get(id, id.to_upper()))


## The strip `id` names, loaded, with its id set; null (and an error pushed)
## for a name this build does not have.
static func open(id: String) -> ZoneStrip:
	if not is_strip(id):
		push_error("there is no duel strip called '%s'" % id)
		return null
	var strip := ZoneStrip.from_manifest(String(MANIFESTS[id]))
	if strip != null:
		strip.id = id
	return strip


## What a choice plays: itself, or for RANDOM one of the strips, drawn from
## `seed_value`. The draw is made once, where the match is built -- on the
## host for an online duel, which then names the strip it drew -- and never
## on two machines that would have to agree about it.
static func resolve(choice: String, seed_value: int) -> String:
	if is_strip(choice):
		return choice
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return IDS[rng.randi_range(0, IDS.size() - 1)]


## The choice after `choice`, stepping by `by` through the strips and then
## RANDOM, stopping at either end as the page's other values do.
static func step(choice: String, by: int) -> String:
	var order: Array[String] = IDS.duplicate()
	order.append(RANDOM)
	var at := maxi(0, order.find(choice))
	return order[clampi(at + by, 0, order.size() - 1)]


## Whether the file `name` in levels/ belongs to a duel strip: a manifest, or a
## zone one names. The adventure's level checks pass over these -- a manifest
## is a list of files, not a grid, and a zone's flood is the duel's own mark --
## and tests/unit/test_duel_strips.gd holds every one of them to the duel's
## rules instead, which refuse a zone with any parse problem.
static func is_duel_file(name: String) -> bool:
	for id: String in IDS:
		var manifest := String(MANIFESTS[id])
		if manifest.get_file() == name:
			return true
		var file := FileAccess.open(manifest, FileAccess.READ)
		if file == null:
			continue
		for line: String in file.get_as_text().split("\n"):
			if line.strip_edges() == name:
				return true
	return false


## The choices in the order the page steps through them.
static func choices() -> Array[String]:
	var order: Array[String] = IDS.duplicate()
	order.append(RANDOM)
	return order
