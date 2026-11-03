class_name ReachModel
extends RefCounted
## How a level's mechanisms change what the character can pass, in the terms
## the reachability proof searches in (scripts/levels/reachability.gd).
##
## ## The state the search carries
##
## Without mechanisms a search state is a cell and a mode -- standing, or on a
## ladder. With them it is also a **channel mask**: one bit per wire a
## mechanism declared here, set when that wire is on. Every cell a mechanism
## controls has a kind for each mask, so the same cell is stone in one state
## and air in another, and stepping somewhere can set a bit. That is the whole
## generic part; each mechanism describes itself in three verbs, from its own
## `static func reach(mark, model)`:
##
## - `switch_cells(cells, channel, off, on)` -- these cells are `off` while
##   the channel is off and `on` while it is on. A gate: SOLID, then EMPTY. A
##   trapdoor: SOLID, then EMPTY, under the floor. A bridge that slides out:
##   EMPTY, then SOLID. A spike trap that is armed: SPIKES, then EMPTY.
## - `latch_on_stand(cells, channel)` -- standing in any of these cells turns
##   the channel on for good. A plate that clicks down and stays down.
## - `fixed_cells(cells, kind)` -- these cells are `kind` in every state:
##   for something the proof should treat as always there, or never.
##
## The proof starts with every channel off: the level as authored, which is
## also what a checkpoint respawn puts back (Game._respawn()). A stand state
## reached under a new mask is checked again under it -- a plate that drops a
## trapdoor beneath the prince drops him -- so a latch can never leave him
## standing on air.
##
## ## What it does not model, and what to do instead
##
## Time. A gate that a plate opens for three seconds, a floor that crumbles a
## moment after it is touched, a lift's journey: none has a clock here. Say
## the conservative thing -- a timed gate that the proof treats as shut, a
## crumbling floor as a latch that drops it the moment it is stood on, a lift
## as a ladder or as nothing -- so the proof never claims a route the player
## cannot take. A level that genuinely needs a timed route has to grow a time
## dimension in the search (frames since the bit was set, carried in the
## state and charged per primitive), and that is the change to make, here and
## in the solver, not a looser model.
##
## Momentary triggers -- a plate that is down only while stood on -- are
## likewise left out: the prince cannot hold a plate and walk through the
## gate it holds, so a momentary plate is modelled as nothing, which is right
## until something else can hold it down.

## The bits a mask has. Thirty would fit beside a cell key; sixteen wires is
## already more than a hand-made level should ever want.
const MAX_CHANNELS := 16

## channel -> bit index.
var _bits: Dictionary = {}
## Each: `{cells: Array[Vector2i], bit: int, off: Tiles.Kind, on: Tiles.Kind}`
var _switched: Array[Dictionary] = []
## cell -> Tiles.Kind, in every state.
var _fixed: Dictionary = {}
## cell -> mask of the bits standing there sets.
var _latches: Dictionary = {}
## Wiring the model could not take: too many channels.
var problems := PackedStringArray()


## The model of `level`: every mark whose registered kind has a reach hook
## describes itself. Empty for a level with no mechanism in it, which is what
## keeps the proof for such a level exactly the search it always was.
static func for_level(level: AsciiLevel) -> ReachModel:
	var model := ReachModel.new()
	if level == null:
		return model
	var kinds := EntityRegistry.kinds()
	for mark: Dictionary in level.entities:
		var script := kinds.get(String(mark["kind"])) as Script
		if script != null and _has_hook(script):
			script.call(&"reach", mark, model)
	return model


## Whether `script` or a script it extends declares the hook. A static method
## is called through an inheriting script but not reported by its
## has_method(), so the chain is walked.
static func _has_hook(script: Script) -> bool:
	var at := script
	while at != null:
		if at.has_method(&"reach"):
			return true
		at = at.get_base_script()
	return false


func is_empty() -> bool:
	return _switched.is_empty() and _fixed.is_empty() and _latches.is_empty()


## The bit for `channel`, allocated on first use; -1 past MAX_CHANNELS.
func bit(channel: StringName) -> int:
	if _bits.has(channel):
		return int(_bits[channel])
	if _bits.size() >= MAX_CHANNELS:
		problems.append("more than %d channels: '%s' is not modelled" % [MAX_CHANNELS, channel])
		return -1
	_bits[channel] = _bits.size()
	return int(_bits[channel])


func channel_count() -> int:
	return _bits.size()


## --- what a mechanism can say ----------------------------------------------------

## `cells` are `off` while `channel` is off and `on` while it is on.
func switch_cells(cells: Array[Vector2i], channel: StringName, off: Tiles.Kind,
		on: Tiles.Kind) -> void:
	var index := bit(channel)
	if index < 0:
		fixed_cells(cells, off)
		return
	_switched.append({"cells": cells.duplicate(), "bit": index, "off": off, "on": on})


## Standing in any of `cells` turns `channel` on for good.
func latch_on_stand(cells: Array[Vector2i], channel: StringName) -> void:
	var index := bit(channel)
	if index < 0:
		return
	for cell: Vector2i in cells:
		_latches[cell] = int(_latches.get(cell, 0)) | (1 << index)


## `cells` are `kind` in every state.
func fixed_cells(cells: Array[Vector2i], kind: Tiles.Kind) -> void:
	for cell: Vector2i in cells:
		_fixed[cell] = kind


## --- what the search asks ------------------------------------------------------

## The mask after standing in `cell` with `mask`.
func after_standing(mask: int, cell: Vector2i) -> int:
	return mask | int(_latches.get(cell, 0))


## Every cell the model gives a kind to under `mask`: cell -> Tiles.Kind.
func kinds_for(mask: int) -> Dictionary:
	var out := _fixed.duplicate()
	for entry: Dictionary in _switched:
		var on := mask & (1 << int(entry["bit"])) != 0
		var kind: Tiles.Kind = entry["on"] if on else entry["off"]
		for cell: Vector2i in entry["cells"]:
			out[cell] = kind
	return out


## Every cell the model ever gives a kind to, for a guard that checks nothing
## outside them moves.
func touched_cells() -> Array[Vector2i]:
	var seen := {}
	for cell: Vector2i in _fixed:
		seen[cell] = true
	for entry: Dictionary in _switched:
		for cell: Vector2i in entry["cells"]:
			seen[cell] = true
	var out: Array[Vector2i] = []
	for cell: Vector2i in seen:
		out.append(cell)
	return out
