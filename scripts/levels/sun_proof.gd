class_name SunProof
extends RefCounted
## The reachability proof's view of the sun mirrors and sun-seals: which
## settings of the mirrors open which doors, from where, and behind which
## other doors -- and the checks that keep that claim honest
## (docs/campaign.md, "Sun mirrors and sun-seals" and "Proving a draft").
##
## ## What the search is told
##
## A door is stone until its wire is on and air after (ReachModel's
## switch_cells), and what turns its wire on is a setting of the mirrors. The
## mirrors that can light one another are one **puzzle** -- found by tracing
## every face of every mirror with every door open, which is as far as light
## can ever go -- and the bible keeps a puzzle to three mirrors, so every
## setting of one is at most 4^3 = 64. For each setting, under each state of
## the doors its light can meet, the level's light is traced exactly as the
## game traces it (SunLight.network()), and wherever a traced beam comes to
## rest on a shut door the search is told:
##
##     standing where a changed mirror of this setting can be struck,
##     with these doors already open, this door's wire latches.
##
## That is a guarded latch (ReachModel.latch_on_stand(..., needs)): still a
## latch, so the checkpoint proof's argument -- every bit is a latch -- holds.
## Mirrors themselves are no bits at all. They reset at a respawn and turn
## back as easily as forward, so a bit for "mirror A faces east" could not be
## a latch, and seven mirrors of four faces would multiply the search by
## sixteen thousand. The latch is placed where the prince strikes, and the
## rest of the setting is held to the standard below instead.
##
## ## What keeps it honest
##
## The latch says "from here the prince can make this setting", which is true
## only if every mirror of the puzzle can be reached from here and back
## again with the doors as they are: he may have left one of them turned the
## wrong way, or need to turn a second before the first. `audit()` proves it:
## for every rule, under every mask the search can stand at its strike cells
## with the door still shut, the strike cells of every mirror in the puzzle
## are mutually reachable with the mask held fixed. A puzzle that fails it is
## one the player can wreck -- a mirror turned the wrong way behind a door he
## cannot pass back through -- and the level is refused rather than trusted.
##
## The audit also holds what the bible asks of a draft: at most three mirrors
## to a puzzle; every door and sun-sealed secret openable from where it is
## shut; the latch's guard honest (a door lit with some doors open stays lit
## with more open); and every beam the proof traced kept clear of anything the
## dresser stands in it. Whether the dressed mask agrees with the bare terrain
## about each mirror is a question for the renderer, so a test asks it with
## `sun_states()` (tests/unit/test_mirrors.gd).
##
## ## The sun, without the dressing
##
## The proof runs before anything is drawn, many times a load, so it cannot
## read the dressed mask. It solves the bare one instead -- the same sweep,
## over the level without its architecture (bare_mask()) -- and the only
## difference left between what the proof assumes and what the player sees is
## the dressing, which the bible warns can shade a mirror the bare terrain
## does not. A test holds the two equal for every mirror in every state of
## its doors (tests/unit/test_mirrors.gd).

## The bible's limit, and the one that keeps the enumeration to 64 settings.
const MAX_MIRRORS := 3
## How far round a puzzle's strike cells the locality walk may go, in tiles.
const LOCAL_MARGIN := 8
const MIRROR := "sun_mirror"
const DOOR := "sun_seal"
const SECRET := "sun_secret"

## level signature -> analyse()'s result.
static var _cache: Dictionary = {}
## level signature -> its bare shadow mask (bare_mask()).
static var _masks: Dictionary = {}
## A wire whose doors are described as never opening, while the audit asks
## where the prince can stand with them shut (_shut_model()).
static var _withheld: StringName = &"__none__"


## --- for SunSeal.reach() ----------------------------------------------------

## A door: stone until its wire is on, and its wire latched from wherever a
## setting of the mirrors that lights it can be struck.
static func describe_seal(mark: Dictionary, model: ReachModel) -> void:
	if String(mark["kind"]) != DOOR:
		return
	var cells := Mechanism.mark_cells(mark)
	var wire := _wire_of(mark)
	model.switch_cells(cells, wire, Tiles.Kind.SOLID, Tiles.Kind.EMPTY)
	if model.level == null or wire == _withheld:
		return
	for rule: Dictionary in rules_for(model.level, mark):
		model.latch_on_stand(rule["strikes"], wire, rule["needs"])


## Every way to open the door placed by `mark`:
## `[{strikes: Array[Vector2i], needs: Array[StringName], changed: Array[Vector2i],
## puzzle: int}]`.
static func rules_for(level: AsciiLevel, mark: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var analysis := analyse(level)
	var anchor: Vector2i = mark["cell"]
	for rule: Dictionary in analysis["rules"]:
		if rule["seal"] == anchor:
			out.append(rule)
	return out


## --- the analysis -------------------------------------------------------------

## Everything the proof and the audit need about a level's light, traced
## once per distinct level: `{mirrors, seals, puzzles, rules, problems,
## states}`. `rules` are door rules and secret rules alike (a secret rule's
## `needs` are the doors its light passes).
static func analyse(level: AsciiLevel) -> Dictionary:
	var key := _signature(level)
	if _cache.has(key):
		return _cache[key]
	var result := _analyse(level)
	_cache[key] = result
	return result


static func _analyse(level: AsciiLevel) -> Dictionary:
	var mirrors: Array[Vector2i] = []
	var great := {}
	var seals: Array[Dictionary] = []
	var problems := PackedStringArray()
	for mark: Dictionary in level.entities:
		match String(mark["kind"]):
			MIRROR:
				# Touching glyphs of one kind are one mark (AsciiLevel), so two
				# mirrors side by side would be one mirror and a silent cell.
				if Mechanism.mark_cells(mark).size() > 1:
					problems.append("the mirrors at %s touch: each mirror must stand alone"
						% str(Mechanism.mark_cells(mark)))
				mirrors.append(mark["cell"])
				var params: Dictionary = mark.get("params", {})
				if String(params.get("great", "")) not in ["", "0", "false"]:
					great[mark["cell"]] = true
			DOOR, SECRET:
				seals.append({
					"cell": mark["cell"], "cells": Mechanism.mark_cells(mark),
					"wire": _wire_of(mark) if String(mark["kind"]) == DOOR else &"",
					"secret": String(mark["kind"]) == SECRET,
				})
	var light := TimeOfDay.light_of(level)
	var puzzles := _puzzles(level, mirrors, seals)
	var rules: Array[Dictionary] = []
	var states: Array[Dictionary] = []
	for index: int in puzzles.size():
		var puzzle: Array[Vector2i] = puzzles[index]
		if puzzle.size() > MAX_MIRRORS:
			problems.append("the mirrors at %s are one puzzle of %d; the most a puzzle may have is %d"
				% [str(puzzle), puzzle.size(), MAX_MIRRORS])
			continue
		_solve_puzzle(level, light, index, puzzle, great, seals, rules, states)
	return {
		"mirrors": mirrors, "great": great, "seals": seals, "puzzles": puzzles,
		"rules": _minimal(rules), "problems": problems, "states": states,
	}


## Mirrors that can light one another, in groups: a union of every mirror
## with the mirror each of its faces reaches with every door open -- the
## furthest light can ever go.
static func _puzzles(level: AsciiLevel, mirrors: Array[Vector2i],
		seals: Array[Dictionary]) -> Array:
	var open := {}
	for seal: Dictionary in seals:
		if not bool(seal["secret"]):
			open[seal["wire"]] = true
	var blocks := blocks(level, seals, open)
	var at_mirror := {}
	for cell: Vector2i in mirrors:
		at_mirror[cell] = true
	var parent := {}
	for cell: Vector2i in mirrors:
		parent[cell] = cell
	for cell: Vector2i in mirrors:
		for face: int in 4:
			var beam := SunLight.trace(cell, face, level.cols, level.rows, blocks, at_mirror)
			if String(beam["ends"]) == SunLight.ENDS_MIRROR:
				_union(parent, cell, beam["end"])
	var groups := {}
	for cell: Vector2i in mirrors:
		var root: Vector2i = _find(parent, cell)
		if not groups.has(root):
			groups[root] = [] as Array[Vector2i]
		(groups[root] as Array[Vector2i]).append(cell)
	var out: Array = []
	for root: Vector2i in groups:
		var group: Array[Vector2i] = groups[root]
		group.sort_custom(SunLight.reading_order)
		out.append(group)
	out.sort_custom(func(a: Array, b: Array) -> bool:
		return SunLight.reading_order(a[0], b[0]))
	return out


## Every setting of one puzzle's mirrors, under every state of the doors its
## light can meet: a rule for each shut seal the light comes to rest on.
static func _solve_puzzle(level: AsciiLevel, light: Dictionary, index: int,
		puzzle: Array[Vector2i], great: Dictionary, seals: Array[Dictionary],
		rules: Array[Dictionary], states: Array[Dictionary]) -> void:
	var wires := _wires_met(level, light, puzzle, seals)
	var settings := 1 << (2 * puzzle.size())
	for open_bits: int in 1 << wires.size():
		var open := {}
		for i: int in wires.size():
			if open_bits & (1 << i) != 0:
				open[wires[i]] = true
		var sun := {}
		for cell: Vector2i in puzzle:
			sun[cell] = bare_sun_reaches(level, SunLight.pivot(cell), light,
				_door_kinds(seals, open))
			states.append({"cell": cell, "open": open.keys(), "lit": sun[cell]})
		for setting: int in settings:
			var faces := {}
			var changed: Array[Vector2i] = []
			for i: int in puzzle.size():
				var face := (setting >> (2 * i)) & 3
				faces[puzzle[i]] = face
				if face != SunLight.Face.UP:
					changed.append(puzzle[i])
			var mirrors := {}
			for cell: Vector2i in puzzle:
				mirrors[cell] = {"face": faces[cell], "turning": false, "sun": sun[cell]}
			var network := SunLight.network(mirrors, level.cols, level.rows,
				blocks(level, seals, open))
			var struck: Dictionary = network["struck"]
			for seal: Dictionary in seals:
				var shut := bool(seal["secret"]) or not open.has(seal["wire"])
				if not shut or not _any(struck, seal["cells"]):
					continue
				var strikes: Array[Vector2i] = []
				for cell: Vector2i in changed:
					strikes.append_array(strike_cells(level, cell, great.has(cell)))
				var needs: Array[StringName] = []
				for wire: StringName in open:
					needs.append(wire)
				needs.sort()
				rules.append({
					"seal": seal["cell"], "secret": seal["secret"], "puzzle": index,
					"changed": changed, "strikes": strikes, "needs": needs,
					"faces": faces, "beams": network["beams"],
					"carriers": _carriers(network, changed),
				})


## The mirrors a rule depends on: the ones it turns, and the ones that carry
## its light -- lit in its trace, so left facing some other way they would
## send it elsewhere. A mirror the trace never lights cannot change where the
## light goes, whichever way it faces.
static func _carriers(network: Dictionary, changed: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = changed.duplicate()
	for cell: Vector2i in network["lit"]:
		if not out.has(cell):
			out.append(cell)
	out.sort_custom(SunLight.reading_order)
	return out


## The doors whose cells a puzzle's light can meet: on some face's path with
## every door open, or in some mirror's lane back to the sun.
static func _wires_met(level: AsciiLevel, light: Dictionary, puzzle: Array[Vector2i],
		seals: Array[Dictionary]) -> Array[StringName]:
	var open := {}
	for seal: Dictionary in seals:
		if not bool(seal["secret"]):
			open[seal["wire"]] = true
	var blocks := blocks(level, seals, open)
	var touched := {}
	var at_mirror := {}
	for cell: Vector2i in puzzle:
		at_mirror[cell] = true
	for cell: Vector2i in puzzle:
		for face: int in 4:
			var beam := SunLight.trace(cell, face, level.cols, level.rows, blocks, at_mirror)
			for at: Vector2i in beam["cells"]:
				touched[at] = true
			touched[beam["end"]] = true
		for at: Vector2i in SunLight.sun_lane(SunLight.pivot(cell), float(light["reach"])):
			touched[at] = true
	var out: Array[StringName] = []
	for seal: Dictionary in seals:
		if bool(seal["secret"]) or out.has(seal["wire"]):
			continue
		if _any(touched, seal["cells"]):
			out.append(seal["wire"])
	out.sort()
	return out


## Keeps the rules a search needs: a rule another rule for the same seal
## does with fewer mirrors changed or fewer doors open adds nothing, and of
## two that are the same, the first is kept. A rule that changes no mirror --
## a seal the mirrors light as they start -- is left out: the search has no
## cell to latch it at, so it proves nothing that leans on it.
static func _minimal(rules: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in rules.size():
		var rule := rules[i]
		if (rule["changed"] as Array).is_empty():
			continue
		var redundant := false
		for j: int in rules.size():
			var other := rules[j]
			if i == j or other["seal"] != rule["seal"] or (other["changed"] as Array).is_empty():
				continue
			if not (_subset(other["changed"], rule["changed"])
					and _subset(other["needs"], rule["needs"])):
				continue
			var fewer := (other["changed"] as Array).size() < (rule["changed"] as Array).size() \
				or (other["needs"] as Array).size() < (rule["needs"] as Array).size()
			if fewer or j < i:
				redundant = true
				break
		if not redundant:
			out.append(rule)
	return out


## --- geometry ------------------------------------------------------------------

## Standing cells from which a standing swing reaches the disc of the mirror
## in `cell`: the cells beside it, facing it, measured with the prince's own
## numbers (Tuning) rather than assumed. A swing from the mirror's own cell,
## an air slash and a plunge can strike it too; the proof leans on none of
## them, which is the conservative side.
static func strike_cells(level: AsciiLevel, cell: Vector2i, great: bool) -> Array[Vector2i]:
	var radius := SunMirror.GREAT_R if great else SunMirror.DISC_R
	var disc := Rect2(SunLight.pivot(cell) - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
	var out: Array[Vector2i] = []
	for side: int in [-1, 1]:
		var at := cell + Vector2i(side, 0)
		if at.x < 0 or at.x >= level.cols:
			continue
		var feet := Vector2(float(at.x) * Tuning.TILE + Tuning.TILE * 0.5,
			float(at.y + 1) * Tuning.TILE)
		if swing_rect(feet, -side).intersects(disc):
			out.append(at)
	return out


## The standing swing's live rect for feet at `feet` facing `facing`: the
## numbers Player.attack_rect() uses, so a retune moves the proof with it.
static func swing_rect(feet: Vector2, facing: int) -> Rect2:
	var half := Tuning.BODY_WIDTH * 0.5
	var x := feet.x + half if facing > 0 else feet.x - half - Tuning.ATTACK_REACH
	return Rect2(x, feet.y - Tuning.BODY_HEIGHT + 3.0, Tuning.ATTACK_REACH, Tuning.ATTACK_HEIGHT)


## Whether the sun reaches `at` (world pixels) in the bare terrain, with
## `kinds` overriding cells -- shut doors as stone.
##
## The bare terrain is the shadow solve itself (SunShadow.build()), run once
## per level on the level as it is drawn, without its dressing: the same
## sweep the world shader's mask comes from, so a thick roof that uses up a
## shadow's reach inside its own stone lights the room under it here exactly
## as it does on screen. What the static mask cannot know is a door shut in
## the lane back to the sun -- doors are mechanisms and cast nothing -- so a
## shut door within the shadow's reach puts `at` in shade, which is the rule
## a mirror in play applies too (SunMirror.sun_reaches()). Where there is no
## atlas to solve against, the lane is read cell by cell instead: anything
## that casts within reach is shade.
static func bare_sun_reaches(level: AsciiLevel, at: Vector2, light: Dictionary,
		kinds: Dictionary = {}) -> bool:
	if not bool(light["sun"]):
		return false
	var lane := SunLight.sun_lane(at, float(light["reach"]))
	var mask := bare_mask(level)
	var lit := false
	if mask != null:
		var px := Vector2i(at.floor())
		if px.x >= 0 and px.y >= 0 and px.x < mask.get_width() and px.y < mask.get_height():
			lit = mask.get_pixelv(px).r < 0.5
	else:
		lit = _lane_is_clear(level, at, light, lane)
	if not lit:
		return false
	for cell: Vector2i in lane:
		var kind: Tiles.Kind = kinds.get(cell, Tiles.Kind.EMPTY)
		if kind == Tiles.Kind.SOLID or kind == Tiles.Kind.PLATFORM:
			return false
	return true


## The level's shadow mask without its dressing, solved once per level; null
## where no atlas can be read. The solve's own record of the last mask -- the
## one the world is drawn with, which mirrors and dust read -- is put back
## afterwards, so proving a level never changes how it looks.
static func bare_mask(level: AsciiLevel) -> Image:
	var key := _signature(level)
	if _masks.has(key):
		return _masks[key]
	var atlas := Level.atlas_image()
	if atlas == null or level.cols * Level.TILE > SunShadow.MAX_MASK_PX \
			or level.rows * Level.TILE > SunShadow.MAX_MASK_PX:
		return null
	var kept := SunShadow.last_mask
	var timings := SunShadow.timings.duplicate()
	var seen := level.facade() if not level.secrets.is_empty() else level
	SunShadow.build(seen, {}, Level.TILE, atlas)
	var mask := SunShadow.last_mask
	SunShadow.last_mask = kept
	SunShadow.timings = timings
	_masks[key] = mask
	return mask


static func _lane_is_clear(level: AsciiLevel, at: Vector2, light: Dictionary,
		lane: Array[Vector2i]) -> bool:
	var horizon := int(light["horizon"])
	if horizon >= 0 and at.y >= float(horizon * Tuning.TILE):
		return false
	for cell: Vector2i in lane:
		if cell.x < 0 or cell.y < 0 or cell.x >= level.cols or cell.y >= level.rows:
			continue
		if _casts(level.kind_at(cell.x, cell.y)):
			return false
	return true


## What casts in the shadow solve: anything but air, backdrop and water.
static func _casts(kind: Tiles.Kind) -> bool:
	return kind != Tiles.Kind.EMPTY and kind != Tiles.Kind.BACKDROP and kind != Tiles.Kind.WATER


## Shut doors as stone; open doors and everything else as the level has it.
static func _door_kinds(seals: Array[Dictionary], open: Dictionary) -> Dictionary:
	var out := {}
	for seal: Dictionary in seals:
		if bool(seal["secret"]):
			continue
		var kind := Tiles.Kind.EMPTY if open.has(seal["wire"]) else Tiles.Kind.SOLID
		for cell: Vector2i in seal["cells"]:
			out[cell] = kind
	return out


## `(cell) -> bool` for what stops light with `open` doors open.
static func blocks(level: AsciiLevel, seals: Array[Dictionary], open: Dictionary) -> Callable:
	var kinds := _door_kinds(seals, open)
	return func(cell: Vector2i) -> bool:
		var kind: Tiles.Kind = kinds.get(cell, level.kind_at(cell.x, cell.y))
		return SunField.stops_light_at(level, cell, kind)


## --- the audit -----------------------------------------------------------------

## What the bible holds a draft to, beyond the route: `{ok, reason, checks,
## lines: PackedStringArray}`. `checks` counts what was checked, so a level
## with no light in it cannot pass by checking nothing.
static func audit(level: AsciiLevel) -> Dictionary:
	var analysis := analyse(level)
	var lines := PackedStringArray()
	var checks := 0
	var problems: PackedStringArray = analysis["problems"]
	if not problems.is_empty():
		return _refuse(problems[0], checks, lines)
	var rules: Array[Dictionary] = analysis["rules"]

	# Every seal can be opened from where it is shut: by light of its own, or
	# -- a door on a wire another seal latches, like the great door -- by the
	# light that opens that seal. "Where it is shut" is asked of a model in
	# which its wire never comes on, so the door can never be the way to its
	# own key.
	for seal: Dictionary in analysis["seals"]:
		checks += 1
		var opened := false
		for rule: Dictionary in rules:
			var other := _seal_at(analysis, rule["seal"])
			var same: bool = other == seal or (not bool(seal["secret"])
				and not bool(other["secret"]) and other["wire"] == seal["wire"])
			if not same:
				continue
			var shut := _shut_model(level, other)
			if not _openable(shut[1], level, shut[0], other, rule):
				continue
			opened = true
			lines.append("seal at %s opens: %s turned, with %s open, struck from %s%s"
				% [str(seal["cell"]), str(rule["changed"]), str(rule["needs"]),
					str(rule["strikes"]),
					"" if other == seal else ", through wire %s" % seal["wire"]])
			break
		if not opened:
			return _refuse("the seal at %s cannot be opened from anywhere it is shut"
				% str(seal["cell"]), checks, lines)

	# Every rule's puzzle can be set from where its rule strikes.
	for rule: Dictionary in rules:
		checks += 1
		var shut := _shut_model(level, _seal_at(analysis, rule["seal"]))
		var broken := _locality(shut[1], level, shut[0], analysis, rule)
		if broken != "":
			return _refuse(broken, checks, lines)

	# A guard is honest: what is lit with some doors open stays lit with more.
	for rule: Dictionary in rules:
		checks += 1
		if not _monotone(level, analysis, rule):
			return _refuse("the seal at %s goes dark when more doors open: a guard the "
				% str(rule["seal"]) + "search cannot lean on", checks, lines)

	# Nothing the dresser stands is in a beam the proof traced.
	var dressing := WorldDresser.dress(level.facade())
	var standing := Tiles.standing_atlas_coords()
	for rule: Dictionary in rules:
		for beam: Dictionary in rule["beams"]:
			checks += 1
			for cell: Vector2i in beam["cells"]:
				for plane: String in ["mid", "props"]:
					var at: Variant = (dressing[plane] as Dictionary).get(cell)
					if at != null and standing.has(at):
						return _refuse("a standing decoration at %s is in the beam from %s"
							% [str(cell), str(beam["from"])], checks, lines)
	return {"ok": true, "reason": "%d checks" % checks, "checks": checks, "lines": lines}


## `[model, solver]` for `level` with `seal`'s wire never coming on -- the
## level as it is for a prince who has not opened it yet. A secret is no wire,
## so its model is the level's own.
static func _shut_model(level: AsciiLevel, seal: Dictionary) -> Array:
	_withheld = &"__none__" if bool(seal["secret"]) else StringName(seal["wire"])
	var model := ReachModel.for_level(level)
	_withheld = &"__none__"
	return [model, LevelReachability.Solver.new(level, model)]


## Some mask the flood from the spawn stands at one of `rule`'s strike cells
## under has the seal shut and the rule's doors open.
static func _openable(solver: LevelReachability.Solver, level: AsciiLevel,
		model: ReachModel, seal: Dictionary, rule: Dictionary) -> bool:
	for mask: int in _claims(solver, level, rule["strikes"]):
		if _mask_fits(model, mask, seal, rule):
			return true
	return false


## The masks the flood from the spawn stands at any of `cells` under.
static func _claims(solver: LevelReachability.Solver, level: AsciiLevel,
		cells: Array) -> Array[int]:
	var wanted: Array[Vector2i] = []
	for cell: Vector2i in cells:
		wanted.append(cell)
	var flood := ReachSearch.standing_masks(solver, level.spawn_point, wanted)
	var out: Array[int] = []
	if not bool(flood["ok"]):
		return out
	for cell: Vector2i in flood["masks"]:
		for mask: int in flood["masks"][cell]:
			if not out.has(mask):
				out.append(mask)
	return out


## `mask` has the seal still shut and every door the rule needs open.
static func _mask_fits(model: ReachModel, mask: int, seal: Dictionary,
		rule: Dictionary) -> bool:
	if not bool(seal["secret"]) and mask & (1 << model.bit(seal["wire"])) != 0:
		return false
	for wire: StringName in rule["needs"]:
		if mask & (1 << model.bit(wire)) == 0:
			return false
	return true


## Under every mask the search can strike from with the seal shut, every
## mirror the rule depends on (`_carriers()`) can be reached and come back from
## with the doors held as they are. "" when it holds; the failure, said, when not.
##
## The walk is held to the puzzle's own neighbourhood (LOCAL_MARGIN tiles
## round its strike cells): a puzzle is a room's worth of mirrors, and a way
## back that has to leave the room is not one a player looking at the room
## would take. Dropping the moves that leave it can only lose ways round, so
## a puzzle passed here passes in the whole level too.
static func _locality(solver: LevelReachability.Solver, level: AsciiLevel,
		model: ReachModel, analysis: Dictionary, rule: Dictionary) -> String:
	var puzzle: Array = rule["carriers"]
	var seal := _seal_at(analysis, rule["seal"])
	var targets: Array = []
	var box := Rect2i()
	for cell: Vector2i in puzzle:
		var strikes := strike_cells(level, cell, (analysis["great"] as Dictionary).has(cell))
		if strikes.is_empty():
			return "the mirror at %s cannot be struck from anywhere it can be stood beside" \
				% str(cell)
		targets.append(strikes)
		for at: Vector2i in strikes:
			box = Rect2i(at, Vector2i.ONE) if box.size == Vector2i.ZERO \
				else box.merge(Rect2i(at, Vector2i.ONE))
	box = box.grow(LOCAL_MARGIN)
	var flood := ReachSearch.standing_masks(solver, level.spawn_point, rule["strikes"])
	if not bool(flood["ok"]):
		return "the flood from the spawn ran out of budget"
	for cell: Vector2i in flood["masks"]:
		for mask: int in flood["masks"][cell]:
			if not _mask_fits(model, mask, seal, rule):
				continue
			var both := _both_ways(solver, cell, mask, box)
			for strikes: Array in targets:
				var met := false
				for target: Vector2i in strikes:
					if both.has(target):
						met = true
						break
				if not met:
					return ("with the doors as mask %d has them, the mirror struck from %s "
						+ "cannot be reached from %s and back: the puzzle can be left broken") \
						% [mask, str(strikes), str(cell)]
	return ""


## The standing cells that can be reached from `start` and can reach it back,
## with `mask` held fixed -- no latch fires, because a mirror struck is a
## choice and the question is what the prince can do without making one --
## and every move kept inside `box`. One walk out recording each move, then
## one walk back along them.
static func _both_ways(solver: LevelReachability.Solver, start: Vector2i, mask: int,
		box: Rect2i) -> Dictionary:
	solver.use_mask(mask)
	var first := solver.cell_key(LevelReachability.MODE_STAND, start.x, start.y)
	var incoming := {first: []}
	var queue: Array[int] = [first]
	var head := 0
	var next: Array[int] = []
	while head < queue.size():
		var key: int = queue[head]
		head += 1
		solver.expand(key, next)
		for low: int in next:
			var at := Vector2i((low >> 1) % solver.cols, (low >> 1) / solver.cols)
			if not box.has_point(at):
				continue
			if not incoming.has(low):
				incoming[low] = []
				queue.append(low)
			(incoming[low] as Array).append(key)
	var back := {first: true}
	var walk: Array[int] = [first]
	head = 0
	while head < walk.size():
		for previous: int in incoming[walk[head]]:
			if not back.has(previous):
				back[previous] = true
				walk.append(previous)
		head += 1
	var cells := {}
	for key: int in back:
		if key & 1 == LevelReachability.MODE_STAND:
			cells[Vector2i((key >> 1) % solver.cols, (key >> 1) / solver.cols)] = true
	return cells


## The rule's setting, traced again under every larger set of open doors,
## still lights its seal.
static func _monotone(level: AsciiLevel, analysis: Dictionary, rule: Dictionary) -> bool:
	var light := TimeOfDay.light_of(level)
	var seals: Array[Dictionary] = []
	seals.assign(analysis["seals"])
	var puzzle: Array[Vector2i] = []
	puzzle.assign(analysis["puzzles"][int(rule["puzzle"])])
	var wires := _wires_met(level, light, puzzle, seals)
	var seal := {}
	for each: Dictionary in seals:
		if each["cell"] == rule["seal"]:
			seal = each
	for open_bits: int in 1 << wires.size():
		var open := {}
		for i: int in wires.size():
			if open_bits & (1 << i) != 0:
				open[wires[i]] = true
		if not _subset(rule["needs"], open.keys()):
			continue
		if not bool(seal["secret"]) and open.has(seal["wire"]):
			continue
		var mirrors := {}
		var kinds := _door_kinds(seals, open)
		for cell: Vector2i in puzzle:
			mirrors[cell] = {"face": rule["faces"][cell], "turning": false,
				"sun": bare_sun_reaches(level, SunLight.pivot(cell), light, kinds)}
		var network := SunLight.network(mirrors, level.cols, level.rows,
			blocks(level, seals, open))
		if not _any(network["struck"], seal["cells"]):
			return false
	return true


## For the renderer's half of the sun check: every mirror under every state
## of the doors in its lane, with the bare terrain's answer --
## `[{cell, open: Array, lit: bool}]`.
static func sun_states(level: AsciiLevel) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(analyse(level)["states"])
	return out


static func _seal_at(analysis: Dictionary, cell: Vector2i) -> Dictionary:
	for seal: Dictionary in analysis["seals"]:
		if seal["cell"] == cell:
			return seal
	return {}


static func _refuse(reason: String, checks: int, lines: PackedStringArray) -> Dictionary:
	return {"ok": false, "reason": reason, "checks": checks, "lines": lines}


## --- small things -------------------------------------------------------------

## The wire a door latches: its mason's mark's, or its own.
static func _wire_of(mark: Dictionary) -> StringName:
	var wire := Mechanism.mark_channel(mark)
	if wire != &"":
		return wire
	return SunSeal.implicit_channel(Mechanism.mark_cells(mark))


static func _any(cells_set: Dictionary, cells: Array) -> bool:
	for cell: Vector2i in cells:
		if cells_set.has(cell):
			return true
	return false


static func _subset(small: Array, big: Array) -> bool:
	for item: Variant in small:
		if not big.has(item):
			return false
	return true


static func _find(parent: Dictionary, cell: Vector2i) -> Vector2i:
	var at := cell
	while parent[at] != at:
		at = parent[at]
	return at


static func _union(parent: Dictionary, a: Vector2i, b: Vector2i) -> void:
	if not parent.has(b):
		return
	parent[_find(parent, a)] = _find(parent, b)


## Identifies a level for the cache: its size, every cell's kind, its marks
## and the hour, which sets the sun's reach and horizon.
static func _signature(level: AsciiLevel) -> String:
	var bytes := PackedByteArray()
	bytes.resize(level.cols * level.rows)
	for y: int in level.rows:
		for x: int in level.cols:
			bytes[y * level.cols + x] = level.kind_at(x, y)
	var marks := PackedStringArray()
	for mark: Dictionary in level.entities:
		if String(mark["kind"]) in [MIRROR, DOOR, SECRET]:
			marks.append("%s%s%s" % [mark["kind"], str(mark.get("cells", mark["cell"])),
				str(mark.get("params", {}))])
	return ("%dx%d|%s|%s|%s" % [level.cols, level.rows, bytes.hex_encode(), ",".join(marks),
		str(TimeOfDay.light_of(level))]).md5_text()
