class_name StripHazards
extends RefCounted
## What on a strip can kill besides the other fighter and the tiles: blades on
## the beat, water on a timer, and stone that gives way. The definitions, read
## once from the zones, and every rule about them as a pure function.
##
## ## Two kinds of moving hazard, and why only one has state
##
## A blade and a flood are **pure functions of the match frame**. Whether a
## scythe is cutting on frame 3,117 is `(3117 - phase) mod 100`, and where the
## water stands is a piecewise line in the same number. The frame is in the
## snapshot and the checksum already, so these hazards add nothing to either:
## two peers that agree on the frame agree on every blade, a rewind to a
## snapshot rewinds them, and a replay replays them, byte for byte, because
## there is nothing to replay. This is the adventure's own choice for its Well
## (BeatBlade cuts on "physics frame 100k + its phase, every time, on every
## device -- never on the music's clock"), made here for the same reason.
##
## Crumbling stone is the exception, because what it remembers is who stood on
## it -- an input, not a clock. Its state is one byte a slab (`stones`, kept by
## DuelMatch), in the snapshot and the checksum like a fighter's. This class
## owns the rule that advances those bytes and never holds them: the strip is
## the level, which no input changes, and the computer opponent is handed the
## strip whole (DuelView). A strip that carried the live stones would be a
## window onto the present that the brain is not allowed.
##
## ## Authored in the adventure's own glyphs
##
## A duel zone places its hazards with the marks the campaign uses for the same
## things (scripts/world/tiles.gd, MECHANISM_LEGEND), so `i` means a spike slot
## and `,` crumbling stone in both modes:
##
##   i  a spike slot: the air cell over a floor stone, lethal while up
##   z  a scythe: a run hanging from a beam; its LOWEST cell is the cut, at
##      head height, and the cells above it are the arm
##   ,  crumbling stone: a floor slab, one cell each
##   u  a flood basin, declared per zone with `;! mark u flood phase=N`: the
##      run's bounding box is where the water stands at its highest
##
## A slot or scythe is wired by a mason's mark (a digit cut in the stone it
## touches) to a `;! channel N beat P` line, exactly as in the Well, and P is
## its phase in frames. An unwired blade has no clock and refuses the strip.
##
## ## Told before it kills
##
## Every hazard here kills only after a tell of at least TELL frames -- the
## blade's ratchet, the sluice's gush, the slab's shudder -- which is the
## adventure's one telegraph length (Patrol.WINDUP_TIME, 27 frames). None of
## them reads the LONGER WARNINGS assist, unlike the campaign's: two phones
## with different settings would step different matches.

## The game's telegraph, in frames: Patrol.WINDUP_TIME at 60 Hz.
const TELL := 27
## Two beats at 72 BPM. At 60 Hz a beat is exactly 50 frames, so a blade's
## period of 100 with a phase of 0 or 50 lands on the beat or the off-beat.
const PERIOD := 100
const BEAT := 50
## A slot's spikes stay up this long: the Well's own number (SpikeSlot.UP).
const SLOT_LIVE := 30
## A scythe's cut: one swing through the lane. A runner crosses a one-tile
## lane in 13 frames, so a swing this long has to be ducked, rolled or waited
## out -- not outrun.
const SCYTHE_LIVE := 16

## The flood's cycle, in frames. Twenty seconds: nine dry, two and a half to
## rise, six high, two and a half to drain. The dry part is the low route's
## turn, the high part the high route's.
const FLOOD_PERIOD := 1200
const FLOOD_DRY := 540
const FLOOD_RISE := 150
const FLOOD_HIGH := 360
const FLOOD_DRAIN := 150
## The sluices gush this long before the water moves: the flood's tell. Longer
## than TELL because what it warns of is a room, not a lane.
const SLUICE_TELL := 90
## Water this deep over the feet is still a wade. The rise covers it in 28
## frames, so the moment the water starts to climb is itself a second tell.
const WADE := 6.0

## A slab burns this long after a foot first finds it, then drops. Longer than
## the campaign's 27: a duellist stands still to fence, where the prince runs.
const FUSE := 36
## A dropped slab lights its run-neighbours to drop this much later, so a slab
## falls with the one beside it, as the Aqueduct's do.
const CHAIN := 15
## The byte of a slab that has fallen. Kept for the rest of the match.
const FALLEN := 255

enum Kind { SLOT, SCYTHE }

const TILE := 16

## Blades: { kind: Kind, cut: Array[Vector2i] (the lethal cells), arm:
## Array[Vector2i] (drawn, never lethal), rect: Rect2 (the cut's), phase: int }.
var blades: Array[Dictionary] = []
## Flood basins: { rect: Rect2 (the water at its highest), phase: int,
## cells: Array[Vector2i] }.
var floods: Array[Dictionary] = []
## Crumbling slabs, one cell each, in reading order across the strip.
var stones: Array[Vector2i] = []
## Each slab's run-neighbours, as indices into `stones`.
var _chain: Array[PackedInt32Array] = []
## cell -> index into `stones`.
var _stone_at: Dictionary = {}

## Why the last read refused, for ZoneStrip to report.
var problem := ""


## --- reading the zones -------------------------------------------------------

## Every hazard of `zone`, offset by `offset_cols` into strip coordinates.
## Returns false with `problem` set if a mark cannot be played.
func read_zone(zone: AsciiLevel, offset_cols: int) -> bool:
	var shift := Vector2i(offset_cols, 0)
	for mark: Dictionary in zone.entities:
		var kind := String(mark["kind"])
		if not is_hazard_kind(kind):
			continue
		var cells: Array[Vector2i] = []
		for cell: Vector2i in mark.get("cells", [mark["cell"]]):
			cells.append(cell + shift)
		match kind:
			"spike_slot", "scythe":
				var phase := _beat_phase(zone, mark)
				if phase < 0:
					return false
				_add_blade(Kind.SLOT if kind == "spike_slot" else Kind.SCYTHE, cells, phase)
			"crumbling":
				var run := PackedInt32Array()
				for cell: Vector2i in cells:
					run.append(stones.size())
					_stone_at[cell] = stones.size()
					stones.append(cell)
					_chain.append(PackedInt32Array())
				_link_run(run)
			"flood":
				var params: Dictionary = mark.get("params", {})
				var said := String(params.get("phase", "0"))
				if not said.is_valid_int():
					problem = "a flood at %s has phase '%s', not frames" % [mark["cell"], said]
					return false
				floods.append({
					"rect": _bounds(cells), "phase": posmod(int(said), FLOOD_PERIOD),
					"cells": cells,
				})
	return true


static func is_hazard_kind(kind: String) -> bool:
	return kind in ["spike_slot", "scythe", "crumbling", "flood"]


func is_empty() -> bool:
	return blades.is_empty() and floods.is_empty() and stones.is_empty()


func _beat_phase(zone: AsciiLevel, mark: Dictionary) -> int:
	var params: Dictionary = mark.get("params", {})
	var wire := String(params.get("channel", ""))
	var spec: Dictionary = zone.channels.get(wire, {})
	if wire == "" or String(spec.get("mode", "")) != "beat":
		problem = "the %s at %s has no beat: cut a mason's mark beside it and give " \
			% [mark["kind"], mark["cell"]] + "its channel a `;! channel N beat P` line"
		return -1
	if int(spec.get("period", PERIOD)) != PERIOD:
		problem = "the %s at %s beats every %d frames; the duel's blades beat every %d" \
			% [mark["kind"], mark["cell"], int(spec["period"]), PERIOD]
		return -1
	return posmod(int(spec["phase"]), PERIOD)


func _add_blade(kind: Kind, cells: Array[Vector2i], phase: int) -> void:
	var cut: Array[Vector2i] = []
	var arm: Array[Vector2i] = []
	if kind == Kind.SLOT:
		cut = cells
	else:
		# The run hangs from its beam; only its foot swings through the lane.
		var low := cells[0].y
		for cell: Vector2i in cells:
			low = maxi(low, cell.y)
		for cell: Vector2i in cells:
			if cell.y == low:
				cut.append(cell)
			else:
				arm.append(cell)
	blades.append({
		"kind": kind, "cut": cut, "arm": arm, "rect": _bounds(cut), "phase": phase,
	})


## Slabs side by side in one run light each other when they drop.
func _link_run(run: PackedInt32Array) -> void:
	for i: int in run:
		for j: int in run:
			if i == j:
				continue
			var gap := stones[i] - stones[j]
			if absi(gap.x) + absi(gap.y) == 1:
				_chain[i].append(j)


static func _bounds(cells: Array[Vector2i]) -> Rect2:
	var out := Rect2(Vector2(cells[0] * TILE), Vector2(TILE, TILE))
	for cell: Vector2i in cells:
		out = out.merge(Rect2(Vector2(cell * TILE), Vector2(TILE, TILE)))
	return out


## --- blades: a pure function of the frame -----------------------------------

## Frames since `blade`'s last cut began, 0 to PERIOD - 1.
static func beat_of(blade: Dictionary, frame: int) -> int:
	return posmod(frame - int(blade["phase"]), PERIOD)


static func live_frames(blade: Dictionary) -> int:
	return SLOT_LIVE if int(blade["kind"]) == Kind.SLOT else SCYTHE_LIVE


## Cutting on `frame`. Never before a whole tell has been shown: a blade on
## phase 0 would otherwise cut on the match's first frame unannounced.
static func is_live(blade: Dictionary, frame: int) -> bool:
	var t := beat_of(blade, frame)
	return t < live_frames(blade) and frame - t >= TELL


## In the TELL frames before a cut.
static func is_telling(blade: Dictionary, frame: int) -> bool:
	return beat_of(blade, frame) >= PERIOD - TELL and frame >= 0


## 0 as the tell begins, 1 on the cut, 0 outside the tell.
static func tell_progress(blade: Dictionary, frame: int) -> float:
	if not is_telling(blade, frame):
		return 0.0
	return float(beat_of(blade, frame) - (PERIOD - TELL)) / float(TELL)


## --- floods: a pure function of the frame -------------------------------------

## How full a basin is on `frame`, 0 dry to 1 brim-full.
static func fill_of(flood: Dictionary, frame: int) -> float:
	var t := posmod(frame - int(flood["phase"]), FLOOD_PERIOD)
	if t < FLOOD_DRY:
		return 0.0
	t -= FLOOD_DRY
	if t < FLOOD_RISE:
		return float(t) / float(FLOOD_RISE)
	t -= FLOOD_RISE
	if t < FLOOD_HIGH:
		return 1.0
	t -= FLOOD_HIGH
	return 1.0 - float(t) / float(FLOOD_DRAIN)


## The y of the water's surface on `frame`; the basin's floor when it is dry.
static func surface_of(flood: Dictionary, frame: int) -> float:
	var rect: Rect2 = flood["rect"]
	return rect.end.y - rect.size.y * fill_of(flood, frame)


## The sluices are gushing: the water is about to move. True through the
## SLUICE_TELL frames before the rise.
static func is_gushing(flood: Dictionary, frame: int) -> bool:
	var t := posmod(frame - int(flood["phase"]), FLOOD_PERIOD)
	return t >= FLOOD_DRY - SLUICE_TELL and t < FLOOD_DRY


## The part of the basin that kills on `frame`: water deeper than a wade.
static func deadly_water(flood: Dictionary, frame: int) -> Rect2:
	var rect: Rect2 = flood["rect"]
	var top := surface_of(flood, frame) + WADE
	if top >= rect.end.y:
		return Rect2()
	return Rect2(rect.position.x, top, rect.size.x, rect.end.y - top)


## --- what kills, on a frame -----------------------------------------------------

## Whether a body occupying `rect` dies to a blade or the water on `frame`.
## Crumbling stone kills nobody itself; it takes the floor away.
func rect_is_deadly(rect: Rect2, frame: int) -> bool:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return false
	for blade: Dictionary in blades:
		if is_live(blade, frame) and (blade["rect"] as Rect2).intersects(rect):
			return true
	for flood: Dictionary in floods:
		var water := deadly_water(flood, frame)
		if water.size.y > 0.0 and water.intersects(rect):
			return true
	return false


## Whether `rect` is deadly on any frame in [from, to]. Each hazard is asked
## only if its footprint touches the rect, and a blade only over one period:
## its cut repeats.
func rect_is_deadly_between(rect: Rect2, from: int, to: int) -> bool:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0 or to < from:
		return false
	for blade: Dictionary in blades:
		if not (blade["rect"] as Rect2).intersects(rect):
			continue
		for f: int in range(from, mini(to, from + PERIOD) + 1):
			if is_live(blade, f):
				return true
	for flood: Dictionary in floods:
		if not (flood["rect"] as Rect2).intersects(rect):
			continue
		# The water only rises in one stretch a cycle, and a rect it reaches at
		# all it reaches by the end of the high water: two frames apart is fine
		# enough for a rise of a fifth of a pixel a frame.
		for f: int in range(from, to + 1, 2):
			var water := deadly_water(flood, f)
			if water.size.y > 0.0 and water.intersects(rect):
				return true
		var last := deadly_water(flood, to)
		if last.size.y > 0.0 and last.intersects(rect):
			return true
	return false


## Whether a flood basin's footprint touches `rect`: somewhere the water can
## come, whatever it is doing now.
func in_a_basin(rect: Rect2) -> bool:
	for flood: Dictionary in floods:
		if (flood["rect"] as Rect2).intersects(rect):
			return true
	return false


## Every cell a blade or a basin can ever take, for the respawn's clearance: a
## respawn never lands where either reaches, however the clock stands. Slabs
## are not here: a slab is not solid rock, so ZoneStrip.is_open_ground already
## refuses to stand a respawn on or beside one, and a slab further off that
## falls leaves a gap, which is the moat's rule and not a blade's.
func clearance_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for blade: Dictionary in blades:
		out.append_array(blade["cut"] as Array[Vector2i])
	for flood: Dictionary in floods:
		out.append_array(flood["cells"] as Array[Vector2i])
	return out


## --- crumbling stone: a rule over bytes someone else keeps ---------------------

func stone_count() -> int:
	return stones.size()


func stone_index(cell: Vector2i) -> int:
	return int(_stone_at.get(cell, -1))


## A fresh strip's stones: every slab whole.
func fresh_stones() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(stones.size())
	out.fill(0)
	return out


static func is_whole(byte: int) -> bool:
	return byte == 0


static func is_burning(byte: int) -> bool:
	return byte > 0 and byte != FALLEN


static func has_fallen(byte: int) -> bool:
	return byte == FALLEN


## Whether slab `index` still holds a foot: whole or burning.
static func holds(byte: int) -> bool:
	return byte != FALLEN


## One frame of the stones. `feet` holds, per living fighter on the ground, the
## [left, right] x of its feet and the y they stand at. Lights every whole slab
## a foot is on, burns every lit one a frame, drops the ones whose fuse has
## run out and lights their neighbours. Returns the indices that dropped.
func step_stones(state: PackedByteArray, feet: Array[Vector3]) -> PackedInt32Array:
	var dropped := PackedInt32Array()
	for i: int in stones.size():
		var byte := state[i]
		if byte == FALLEN:
			continue
		if byte > 0:
			byte += 1
			if byte > FUSE:
				byte = FALLEN
				dropped.append(i)
			state[i] = byte
	for i: int in dropped:
		for j: int in _chain[i]:
			if state[j] == 0:
				state[j] = FUSE - CHAIN + 1
	for foot: Vector3 in feet:
		for i: int in _under(foot):
			if state[i] == 0:
				state[i] = 1
	return dropped


## The slabs under feet spanning [x, y] at height z.
func _under(foot: Vector3) -> PackedInt32Array:
	var out := PackedInt32Array()
	var row := roundi(foot.z / TILE)
	if absf(foot.z - row * TILE) > 0.5:
		return out
	for column: int in range(floori(foot.x / TILE), floori((foot.y - 0.001) / TILE) + 1):
		var at := stone_index(Vector2i(column, row))
		if at >= 0:
			out.append(at)
	return out


## Whether a whole or burning slab overlaps `rect`: what a loose sword lands on
## and a roll stands up under (MatchGround).
func rect_hits_stone(rect: Rect2, state: PackedByteArray) -> bool:
	if stones.is_empty():
		return false
	var x0 := floori(rect.position.x / TILE)
	var x1 := floori((rect.end.x - 0.001) / TILE)
	var y0 := floori(rect.position.y / TILE)
	var y1 := floori((rect.end.y - 0.001) / TILE)
	for y: int in range(y0, y1 + 1):
		for x: int in range(x0, x1 + 1):
			var at := stone_index(Vector2i(x, y))
			if at >= 0 and at < state.size() and holds(state[at]):
				return true
	return false


## --- identity ---------------------------------------------------------------

## Words for the strip's handshake hash: two strips whose tiles agree and whose
## blades beat differently are different strips.
func identity_words(words: PackedInt32Array) -> void:
	words.append(blades.size())
	for blade: Dictionary in blades:
		words.append(int(blade["kind"]))
		words.append(int(blade["phase"]))
		for cell: Vector2i in blade["cut"]:
			words.append(cell.x)
			words.append(cell.y)
	words.append(floods.size())
	for flood: Dictionary in floods:
		var rect: Rect2 = flood["rect"]
		words.append(int(flood["phase"]))
		words.append(int(rect.position.x))
		words.append(int(rect.position.y))
		words.append(int(rect.size.x))
		words.append(int(rect.size.y))
	words.append(stones.size())
	for cell: Vector2i in stones:
		words.append(cell.x)
		words.append(cell.y)
