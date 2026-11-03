class_name EntitySite
extends RefCounted
## Where one entity is put, and what the level knows about that place: handed
## to the entity's `place()` once, after `new()` and before it enters the tree.
##
## A site is everything a mark in the ASCII says, resolved: the cell and the
## world position of the feet in it, the parameters a `;! mark` declaration
## gave the glyph, and the facts only the whole level can answer, like whether
## a torch here is proved to lead to the door.
##
## It also carries the two hooks that are about the level's tally rather than
## about the prince, so they are wired once at placement and not looked up
## every frame: a relic counts itself toward the total and connects its own
## `collected` to the take (scripts/entities/relic.gd). See Contact for the
## hooks that are about the prince.

## The registry name of what is placed here: "relic", "patrol", ...
var kind := ""
## The mark's cell. For a declared run of cells, its bottom-left one.
var cell := Vector2i.ZERO
## Every cell of the mark: one for a legend glyph, the whole connected run for
## a declared one (a gate three cells tall is one gate).
var cells: Array[Vector2i] = []
## The bottom centre of `cell` in world units: where feet stand in it.
var at := Vector2.ZERO
## `key=value` pairs from the glyph's `;! mark` declaration, as strings.
var params: Dictionary = {}
## Stable across a restart and a respawn, so a foe cut down at this post can be
## remembered as down: the kind and the cell, `patrol@38,11`.
var post := ""
## How many marks of the same kind come before this one in the level's order
## (reading order: top to bottom, left to right). The third torch is 2.
var ordinal := 0
var level: Level
## True when a checkpoint here is proved to lead to the exit
## (Game.checkpoint_cells()); only a torch asks.
var checkpoint := false
## The level's mechanism wiring (scripts/mechanisms/channel_bus.gd).
var bus: ChannelBus

## Bound by Game: a relic taken. Connect `collected` to it.
var relic_taken := Callable()
## Bound by Game: one more relic in the level's total.
var relic_counted := Callable()
## Bound by Game: `(at: Vector2) -> void`, a way out stands at `at`.
var exit_declared := Callable()


static func post_of(kind_name: String, at_cell: Vector2i) -> String:
	return "%s@%d,%d" % [kind_name, at_cell.x, at_cell.y]


## Counts this entity toward the level's relic total, which the HUD and the
## complete screen show and the campaign keeps a best of.
func count_relic() -> void:
	if relic_counted.is_valid():
		relic_counted.call()


## Declares a way out here. The level is run toward it, so a checkpoint
## further from it than the one held is not progress (Game._progress()).
func declare_exit() -> void:
	if exit_declared.is_valid():
		exit_declared.call(at)


## A parameter from the mark's declaration, or `fallback`.
func param(key: String, fallback: String = "") -> String:
	return String(params.get(key, fallback))
