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
## One more verb is for a floor that gives way a moment after it is stood on
## -- crumbling stone (docs/campaign.md, "Crumbling stone"):
##
## - `fuse_on_stand(cells, channel)` -- standing in these cells is
##   **transient**: any move may leave them, nothing may wait in them, and
##   the channel is on from the moment they are left. The search expands such
##   a stand under the mask it arrived with (the floor still there) and lands
##   every move it makes under the mask with the channel on (the floor gone
##   behind it) -- the jump straight up included, which is how the proof
##   stays on a slab: it comes down where the slab was and falls through.
##   Pair it with `switch_cells(cells below, channel, SOLID, EMPTY)`.
##
## And one word about a respawn: `resets_on_respawn(channel)` says a wire is
## a trap, put back as authored behind the death wipe -- a fallen slab is
## whole again -- rather than a deed that is kept. The checkpoint proof clears
## such bits from every mask before it proves a torch under it
## (respawn_mask()), because that is the state a death actually comes back to.
##
## The proof starts with every channel off: the level as authored. A stand
## state reached under a new mask is checked again under it -- a plate that
## drops a trapdoor beneath the prince drops him -- so a latch can never leave
## him standing on air. A checkpoint respawn keeps the latches (Game's
## checkpoint notes), so a torch is proved from every mask he can stand on it
## under (ReachSearch.prove_checkpoints()); that is sound because these verbs
## set bits only by latching, or by a fuse on a wire that resets_on_respawn()
## says the respawn clears. A mechanism that sets a bit any other way -- a
## hold, once the search has a clock -- has to change that proof too.
##
## ## What it does not model, and what to do instead
##
## Time, mostly. A floor that crumbles a moment after it is touched, a lift's
## journey: neither has a clock here. Say the conservative thing -- a
## crumbling floor as a latch that drops it the moment it is stood on, a lift
## as a ladder or as nothing -- so the proof never claims a route the player
## cannot take. The one timed route the proof does make is the race against a
## held gate: `race_on_stand()` marks the plate, and ReachRace charges the run
## from it in frames and offers wherever it beats the hold, with the gate shut
## again on arrival (scripts/levels/reach_race.gd). It sets no bit.
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
## cell -> mask of the bits leaving there sets: a transient stand.
var _fuses: Dictionary = {}
## The bits a checkpoint respawn clears: traps, not deeds.
var _resets := 0
## Wiring the model could not take: too many channels.
var problems := PackedStringArray()
## channel -> `{mode, seconds, phase, period}`, the level's `;! channel` lines,
## for a reach hook to ask what its wire does (channel_mode()).
var channels: Dictionary = {}
## The level the model describes, for an extension that searches it on its
## own terms (ReachRace builds a timed solver over it).
var level: AsciiLevel
## Per-level scratch for search extensions, so what they cache lives and dies
## with the model.
var extras: Dictionary = {}
## cell -> the channels whose race standing there starts (race_on_stand()).
var _races: Dictionary = {}


## The model of `level`: every mark whose registered kind has a reach hook
## describes itself. Empty for a level with no mechanism in it, which is what
## keeps the proof for such a level exactly the search it always was.
static func for_level(level: AsciiLevel) -> ReachModel:
	var model := ReachModel.new()
	if level == null:
		return model
	model.channels = level.channels.duplicate(true)
	model.level = level
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
	return _switched.is_empty() and _fixed.is_empty() and _latches.is_empty() \
		and _fuses.is_empty()


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


## What `channel` does when pressed: "momentary" (no `;! channel` line),
## "latch", "hold" or "beat". A plate's hook latches a latch and races a hold
## (race_on_stand()); a momentary wire it says nothing about.
func channel_mode(channel: StringName) -> String:
	return String((channels.get(String(channel), {}) as Dictionary).get("mode", "momentary"))


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


## Standing in any of `cells` presses `channel`, a held wire: a race against
## its hold, which ReachRace times. Sets no bit.
func race_on_stand(cells: Array[Vector2i], channel: StringName) -> void:
	bit(channel)
	for cell: Vector2i in cells:
		if not _races.has(cell):
			_races[cell] = [] as Array[StringName]
		if not (_races[cell] as Array[StringName]).has(channel):
			(_races[cell] as Array[StringName]).append(channel)


## Standing in any of `cells` is transient, and leaving turns `channel` on
## for good (above).
func fuse_on_stand(cells: Array[Vector2i], channel: StringName) -> void:
	var index := bit(channel)
	if index < 0:
		return
	for cell: Vector2i in cells:
		_fuses[cell] = int(_fuses.get(cell, 0)) | (1 << index)


## `channel` is a trap: a checkpoint respawn puts it back off.
func resets_on_respawn(channel: StringName) -> void:
	var index := bit(channel)
	if index >= 0:
		_resets |= 1 << index


## --- what the search asks ------------------------------------------------------

## The mask after standing in `cell` with `mask`.
func after_standing(mask: int, cell: Vector2i) -> int:
	return mask | int(_latches.get(cell, 0))


## The mask once a stand in `cell` under `mask` is left: its fuses burnt.
## The same mask for any cell that is not a transient stand.
func after_leaving(mask: int, cell: Vector2i) -> int:
	return mask | int(_fuses.get(cell, 0))


## `mask` as a checkpoint respawn leaves it: every trap put back.
func respawn_mask(mask: int) -> int:
	return mask & ~_resets


## Whether every wire here is a trap, so that every respawn is into the
## authored state and no flood is needed to say which masks it can be.
func only_traps() -> bool:
	return _bits.size() > 0 and _resets == (1 << _bits.size()) - 1


## Every cell the model gives a kind to under `mask`: cell -> Tiles.Kind.
func kinds_for(mask: int) -> Dictionary:
	var out := _fixed.duplicate()
	for entry: Dictionary in _switched:
		var on := mask & (1 << int(entry["bit"])) != 0
		var kind: Tiles.Kind = entry["on"] if on else entry["off"]
		for cell: Vector2i in entry["cells"]:
			out[cell] = kind
	return out


## The races standing in `cell` starts: their channels.
func races_at(cell: Vector2i) -> Array[StringName]:
	if not _races.has(cell):
		return [] as Array[StringName]
	return _races[cell]


func has_races() -> bool:
	return not _races.is_empty()


## Every cell a race starts from, in reading order.
func race_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell: Vector2i in _races:
		out.append(cell)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x))
	return out


## A held wire's hold, in physics frames.
func hold_frames(channel: StringName) -> int:
	var spec := channels.get(String(channel), {}) as Dictionary
	return roundi(float(spec.get("seconds", 0.0)) * 60.0)


## The cells switched by `channel`: its gate, for a race's far side.
func switched_cells(channel: StringName) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var index := int(_bits.get(channel, -1))
	for entry: Dictionary in _switched:
		if int(entry["bit"]) == index:
			for cell: Vector2i in entry["cells"]:
				out.append(cell)
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
