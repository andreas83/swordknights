class_name EntityRegistry
extends RefCounted
## Every kind of thing a level places, by the name its mark spawns.
##
## The single integration point for a new kind: a script, one line in
## `kinds()`, and its glyph in Tiles.ENTITY_LEGEND. Nothing in Game names a
## kind. `Game._spawn_entities()` places whatever the
## marks say through this table, and `Game._resolve_interactions()` meets
## every entity the same way. Kept a plain list for the reason ModeRegistry
## is: several people and agents add to it at once, and a one-line addition
## should never conflict with another.
##
## ## The protocol a registered script keeps
##
## - `place(site: EntitySite) -> void`, required. Called once, after `new()`
##   and before the node enters the tree: take the position, the level, the
##   post, the parameters, whatever the kind needs from where it was put.
## - `meet(contact: Contact) -> void`, optional. Called every playing frame,
##   in the level's order, with the prince as entities see him. A foe hands
##   itself back to Game here (scripts/entities/foe.gd); everything else
##   decides for itself what touching it means, and asks Game for the
##   consequence through the contact.
## - `signal cue(voice: StringName, options: Dictionary)` and
##   `signal impact(at: Vector2, frames: int, shake: float, weight: float)`,
##   optional. Game connects whichever a kind declares, so its sounds go
##   through GameAudio.cue and its weight through Game's one impact budget.
## - `static func reach(mark: Dictionary, model: ReachModel) -> void`,
##   optional: how the kind changes what the character can pass, for the
##   reachability proof (scripts/levels/reach_model.gd). Mechanism declares a
##   default that says nothing; a mechanism that opens or closes a way must
##   say so.
##
## A kind with no glyph of its own is placed by a `;! mark` declaration in the
## level that uses it, which is also how mechanisms are wired (docs/world.md,
## "Directives and wiring").
##
## What happens to a kind at a checkpoint respawn is decided by what it is,
## not listed here: a Foe goes back to its post unless it was cut down, a
## FoeProjectile is gone, a Mechanism is put back as authored, and everything
## else keeps the state it was in -- a relic taken stays taken.
##
## `tests/unit/test_entity_registry.gd` holds the legend and this table
## together, and checks that every script here keeps the protocol.

## Glyphs in Tiles.ENTITY_LEGEND that the registry does not place, and who
## does. A legend kind in neither list spawns nothing, silently -- so the
## registry test fails on one.
const ELSEWHERE := {
	"spawn": "AsciiLevel.spawn_point: where the prince starts, not an entity",
	"inscription": "SecretKeeper.furnish(): words only a found room shows",
}

## Kinds a test has registered for itself. See add_for_test().
static var _for_tests: Dictionary = {}


## The registry. kind -> script: one line per kind.
static func kinds() -> Dictionary:
	var out := {
		"relic": Relic,
		"exit": ExitDoor,
		"torch": Torch,
		"patrol": Patrol,
	}
	out.merge(_for_tests)
	return out


static func has_kind(kind: String) -> bool:
	return kinds().has(kind)


## The script registered for `kind`, or null.
static func script_for(kind: String) -> Script:
	return kinds().get(kind) as Script


## A new, unplaced entity of `kind`, or null for a kind nothing registered.
static func make(kind: String) -> Node:
	var script := script_for(kind)
	if script == null:
		return null
	return script.new() as Node


## Test seam: registers a kind that exists only in a test -- a toy mechanism,
## a toy foe -- so that Game and the reachability proof treat it like a real
## one. Pair every call with remove_for_test(), or the kind outlives the test.
static func add_for_test(kind: String, script: Script) -> void:
	_for_tests[kind] = script


static func remove_for_test(kind: String) -> void:
	_for_tests.erase(kind)
