class_name ZoneStrip
extends DuelWorld
## A tug-of-war level: three to five linked zones, read as one continuous world.
##
## WHY A MANIFEST RATHER THAN A LONGER GRID
## scripts/world/ascii_level.gd parses one grid and still does — nothing in
## scripts/world is touched by this mode. The sequencing lives here, in the mode
## that needs it, and levels/duel_zones.txt lists the zone files in order. A
## 200-column ASCII file would not be reviewable: a diff of one shows a wall of
## unchanged stone around the three cells that moved.
##
## WHAT IS CONTINUOUS AND WHAT IS NOT
## The GEOMETRY is continuous and always complete. `kind_at` takes a strip
## coordinate and answers from whichever zone owns it, and a fighter crossing a
## boundary is not a special case anywhere in this file. Five 40x23 grids are
## about four thousand integers, so there is nothing to gain by paging them and
## everything to lose: a simulation whose collision answers depended on what had
## been loaded would be a simulation that two peers could disagree about.
##
## What IS streamed is the TileMapLayer — the rendering and the physics bodies —
## and that is scripts/duel/zones_view.gd's job, not this file's.
##
## COORDINATES
##   cell     (0,0) is the top-left cell of zone 0; x runs across the whole
##            strip, so cell x=41 is column 1 of zone 1.
##   world    cell * TILE. A fighter's position is at its FEET, so the standing
##            surface of a solid cell at row r is y = r * TILE.
## Out-of-strip columns read as SOLID, the same convention AsciiLevel uses for
## its own edges: the ends of the strip are walled, behind the gates.

const TILE := 16

## The design screen. One zone is exactly one screen wide, which is what makes
## "1.5 screen widths" in the respawn algorithm a world constant rather than a
## property of whatever device is drawing. A match between a phone and a desktop
## has to agree about where a fighter respawns.
##
## 480 px, thirty tiles, because of how big a fighter is on screen. The duel
## camera scales so a fighter stands 8-9% of the screen's height (MatchCamera),
## and at that scale a phone shows between about 506 px (an iPhone) and 600 px
## (a 20:9 Android) of world. A zone has to fit inside the narrowest of those, or
## two fighters at opposite ends of the window are not both on screen -- and
## seeing your opponent at all times is the mode. It was 640 at first, which
## needed a 0.5 zoom and left a fighter at about 6% of the screen.
const SCREEN_WIDTH := 480.0

## A respawn is only ever placed on ground a fighter could be jumped over or
## rolled past: FLAT_RUN cells of unbroken solid floor either side, with
## HEADROOM clear rows above it. See `is_open_ground`.
const FLAT_RUN := 2
const HEADROOM := 5

## How far from the gate cell the innermost legal respawn sits. Five tiles is
## far enough that the leader can clear a fighter standing there with one jump
## and land beyond them, and close enough to read as "directly in front of the
## exit".
const GATE_STANDOFF := 5

## How far either side of the wanted column a respawn may be nudged to find open
## ground. Fourteen tiles is a third of a screen — within "roughly".
const SPAWN_SEARCH := 14

var name: String = "Untitled"
var zones: Array[AsciiLevel] = []
var zone_cols: int = 0
var zone_rows: int = 0

## Cell of each endpoint, read from the 'D' mark in the first and last zone.
## [west, east]; west is player one's goal, east is player two's.
var gates: Array[Vector2i] = [Vector2i.ZERO, Vector2i.ZERO]
## The two marks the match starts from, in strip cells. Authored as one mark in
## the middle zone and mirrored, exactly as levels/zone_03.txt argues for.
var start_cells: Array[Vector2i] = [Vector2i.ZERO, Vector2i.ZERO]
## Torches and other decoration, in strip cells: { kind, cell }.
var props: Array[Dictionary] = []

var _problem := ""


## --- loading ---------------------------------------------------------------

## Reads a manifest: one zone file name per line, ';' comments, first comment is
## the strip's name. Returns null and pushes an error if the strip is not
## playable, which is a load-time failure rather than something to discover in
## the fourth zone.
static func from_manifest(path: String) -> ZoneStrip:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("could not open zone manifest %s (%d)"
			% [path, FileAccess.get_open_error()])
		return null
	var text := file.get_as_text()
	file.close()

	var strip := ZoneStrip.new()
	var directory := path.get_base_dir()
	for raw: String in text.split("\n", true):
		var line := raw.trim_suffix("\r").strip_edges()
		if line == "":
			continue
		if AsciiLevel.is_comment(line):
			var stripped := line.lstrip("; ").strip_edges()
			if strip.name == "Untitled" and stripped != "":
				strip.name = stripped
			continue
		var zone := AsciiLevel.from_file(
			line if line.begins_with("res://") else "%s/%s" % [directory, line]
		)
		if zone == null:
			push_error("zone manifest %s names a zone that will not load: %s"
				% [path, line])
			return null
		strip.zones.append(zone)

	if not strip._finish():
		push_error("zone strip %s is not playable: %s" % [path, strip._problem])
		return null
	return strip


const MIN_ZONES := 3
const MAX_ZONES := 5


## Derives everything the match reads, and refuses a strip that cannot be
## played. Returns false with `_problem` set.
func _finish() -> bool:
	if zones.size() < MIN_ZONES or zones.size() > MAX_ZONES:
		_problem = "%d zones; wanted %d to %d" % [zones.size(), MIN_ZONES, MAX_ZONES]
		return false

	zone_cols = zones[0].cols
	zone_rows = zones[0].rows
	for i: int in zones.size():
		if zones[i].cols != zone_cols or zones[i].rows != zone_rows:
			_problem = "zone %d is %dx%d, zone 0 is %dx%d" % [
				i, zones[i].cols, zones[i].rows, zone_cols, zone_rows,
			]
			return false

	if float(zone_cols * TILE) != SCREEN_WIDTH:
		_problem = "a zone is %d px wide; one zone must be one %d px screen" % [
			zone_cols * TILE, int(SCREEN_WIDTH),
		]
		return false

	props.clear()
	var west := Vector2i(-1, -1)
	var east := Vector2i(-1, -1)
	for i: int in zones.size():
		for entity: Dictionary in zones[i].entities:
			var cell: Vector2i = entity["cell"] + Vector2i(i * zone_cols, 0)
			if String(entity["kind"]) == "exit":
				if i == 0:
					west = cell
				elif i == zones.size() - 1:
					east = cell
				continue
			props.append({"kind": entity["kind"], "cell": cell})

	if west.x < 0 or east.x < 0:
		_problem = "the first and last zone each need a 'D' gate mark"
		return false
	gates = [west, east]

	# One mark in the middle zone, mirrored within that zone for the other seat.
	var middle := zones.size() / 2
	var mark: Vector2i = zones[middle].spawn_point
	var mirrored := Vector2i(zone_cols - 1 - mark.x, mark.y)
	var offset := Vector2i(middle * zone_cols, 0)
	start_cells = [mark + offset, mirrored + offset]
	return true


## --- the grid --------------------------------------------------------------

func zone_count() -> int:
	return zones.size()


func cols() -> int:
	return zones.size() * zone_cols


func rows() -> int:
	return zone_rows


func world_size() -> Vector2:
	return Vector2(cols() * TILE, rows() * TILE)


func zone_width() -> float:
	return float(zone_cols * TILE)


func kind_at(x: int, y: int) -> Tiles.Kind:
	if y < 0 or y >= zone_rows:
		return Tiles.Kind.EMPTY
	if x < 0 or x >= cols():
		# The ends of the strip are walled, behind the gates. Same convention as
		# AsciiLevel's own edges.
		return Tiles.Kind.SOLID
	@warning_ignore("integer_division")
	var zone := x / zone_cols
	return zones[zone].kind_at(x - zone * zone_cols, y)


func is_solid(x: int, y: int) -> bool:
	return kind_at(x, y) == Tiles.Kind.SOLID


## Which atlas tile a strip cell draws with.
##
## Deliberately not AsciiLevel.atlas_for: that one reads its neighbours inside
## one zone and treats everything past its own edge as solid, so a block running
## up to a zone boundary would be drawn capped and unlit on one side of the seam
## and buried on the other. Computed in strip coordinates, the seams vanish.
func atlas_for(x: int, y: int) -> Vector2i:
	var kind := kind_at(x, y)
	match kind:
		Tiles.Kind.SOLID:
			var capped := kind_at(x, y - 1) != Tiles.Kind.SOLID
			var lit := kind_at(x - 1, y) != Tiles.Kind.SOLID
			if capped:
				return Tiles.ATLAS_SOLID_CAPPED_LIT if lit else Tiles.ATLAS_SOLID_CAPPED
			return Tiles.ATLAS_SOLID_BURIED_LIT if lit else Tiles.ATLAS_SOLID_BURIED
		Tiles.Kind.PLATFORM:
			return Tiles.ATLAS_PLATFORM
		Tiles.Kind.SPIKES:
			return Tiles.ATLAS_SPIKES
		Tiles.Kind.WATER:
			return Tiles.ATLAS_WATER
		Tiles.Kind.LADDER:
			return Tiles.ATLAS_LADDER
		Tiles.Kind.BACKDROP:
			return Tiles.ATLAS_BACKDROP
		_:
			return Vector2i(-1, -1)


func cell_of(world_position: Vector2) -> Vector2i:
	return Vector2i(floori(world_position.x / TILE), floori(world_position.y / TILE))


## True if any tile of one of `kinds` overlaps the rect. Same shape as
## Level.rect_has_kind, in strip coordinates.
func rect_has_kind(rect: Rect2, kinds: Array) -> bool:
	var x0 := floori(rect.position.x / TILE)
	var x1 := floori((rect.position.x + rect.size.x - 0.001) / TILE)
	var y0 := floori(rect.position.y / TILE)
	var y1 := floori((rect.position.y + rect.size.y - 0.001) / TILE)
	for y: int in range(y0, y1 + 1):
		for x: int in range(x0, x1 + 1):
			if kinds.has(kind_at(x, y)):
				return true
	return false


func rect_is_deadly(rect: Rect2) -> bool:
	return rect_has_kind(rect, [Tiles.Kind.SPIKES, Tiles.Kind.WATER])


func rect_hits_solid(rect: Rect2) -> bool:
	return rect_has_kind(rect, [Tiles.Kind.SOLID])


## --- zones and goals -------------------------------------------------------

## Which zone a strip x belongs to.
func zone_of_x(x: float) -> int:
	return clampi(int(floorf(x / zone_width())), 0, zones.size() - 1)


## The x of the left edge of a zone.
func zone_left(index: int) -> float:
	return float(clampi(index, 0, zones.size() - 1)) * zone_width()


## The world position of a seat's goal: the mouth of its gate.
## Seat 0 (player one) runs west, seat 1 (player two) runs east.
func goal_x(seat: int) -> float:
	var cell: Vector2i = gates[0] if seat == 0 else gates[1]
	return cell.x * TILE + TILE * 0.5


## Which direction a seat pushes: -1 west for seat 0, +1 east for seat 1.
static func goal_direction(seat: int) -> int:
	return -1 if seat == 0 else 1


## The column band a respawn may be placed in: never behind a gate, and never
## so close to one that the leader has no room to go over the top of it.
func spawn_columns() -> Vector2i:
	return Vector2i(
		gates[0].x + GATE_STANDOFF, gates[1].x - GATE_STANDOFF
	)


func start_position(seat: int) -> Vector2:
	var cell: Vector2i = start_cells[clampi(seat, 0, 1)]
	return Vector2(cell.x * TILE + TILE * 0.5, (cell.y + 1) * TILE)


## --- standing room ---------------------------------------------------------

## The row of the floor of the running lane in this column: the top of the
## lowest unbroken stack of solid rock, or -1 if the column has none.
##
## Scanned from the BOTTOM up, which is the whole point. Scanning down from the
## sky finds the first thing you could stand on, and that is a balcony — so
## every column under the zone's architecture would be reported as having its
## floor six rows up in the air, and the respawn would refuse to use the lane it
## is supposed to use. A bench standing on the ground still reports its own top,
## because the rock below it is continuous with it.
func ground_row(x: int) -> int:
	if x < 0 or x >= cols():
		return -1
	for y: int in range(zone_rows - 1, -1, -1):
		if kind_at(x, y) != Tiles.Kind.SOLID:
			continue
		if kind_at(x, y - 1) != Tiles.Kind.SOLID:
			return y
	return -1


## THE PACIFIST LINE, as a predicate.
##
## A leader who killed and ran must be able to get past the respawn rather than
## being forced to fight it — over the top with a jump, or under the blade with
## a roll. Both need the same thing from the level: unbroken flat solid floor
## either side of the spawn, and clear air above it.
##
##   FLAT_RUN=2    five columns of floor at one height. A jump covers about
##                 three tiles at running speed, so there is ground to leave
##                 from and ground to land on, on both sides.
##   HEADROOM=5    eighty pixels of clear air. A standing fighter is 22 px and
##                 a jump apexes 35 to 45 px above the floor, so the jumper
##                 passes over a standing opponent with their own head still
##                 well under the ceiling.
##
## A one-way platform is never the floor: a respawn must never be put on a
## stepping stone over a hazard, so the cistern's columns have no floor at all
## as far as this predicate is concerned. Ladders and background niches do not
## block the air — they are not solid, and the gate's own arch is a niche.
func is_open_ground(x: int) -> bool:
	var row := ground_row(x)
	if row < HEADROOM:
		return false
	for k: int in range(-FLAT_RUN, FLAT_RUN + 1):
		if kind_at(x + k, row) != Tiles.Kind.SOLID:
			return false
		if ground_row(x + k) != row:
			return false
		for j: int in range(1, HEADROOM + 1):
			if _blocks_the_air(kind_at(x + k, row - j)):
				return false
	return true


static func _blocks_the_air(kind: Tiles.Kind) -> bool:
	match kind:
		Tiles.Kind.EMPTY, Tiles.Kind.BACKDROP, Tiles.Kind.LADDER:
			return false
		_:
			return true


## Finds the respawn nearest `wanted_x` that satisfies `is_open_ground`.
##
## `away_from_x` breaks the tie between two equally near columns in favour of
## the one further from that point — the leader's position, so the respawning
## fighter is given the deeper side of the gap rather than being dropped on top
## of them. Deterministic: no randomness, and the same answer on both peers.
##
## Returns { ok, position, column, row }.
func find_open_ground(wanted_x: float, away_from_x: float) -> Dictionary:
	var band := spawn_columns()
	var wanted := clampi(int(floorf(wanted_x / TILE)), band.x, band.y)
	var bias := 1 if wanted_x >= away_from_x else -1

	for radius: int in range(0, SPAWN_SEARCH + 1):
		# Nearer side first; the leader's far side wins a tie.
		for step: int in ([0] if radius == 0 else [bias * radius, -bias * radius]):
			var column: int = clampi(wanted + step, band.x, band.y)
			if not is_open_ground(column):
				continue
			var row := ground_row(column)
			return {
				"ok": true,
				"column": column,
				"row": row,
				"position": Vector2(column * TILE + TILE * 0.5, row * TILE),
			}
	return {"ok": false, "column": wanted, "row": -1, "position": Vector2.ZERO}


## --- identity --------------------------------------------------------------

## The hash both peers compare in the handshake. Covers every cell of every
## zone, in order, plus the marks the match reads: a strip with the same tiles
## in a different order, or with a gate moved, is a different strip.
func identity() -> int:
	var words := PackedInt32Array()
	words.append(zones.size())
	words.append(zone_cols)
	words.append(zone_rows)
	for cell: Vector2i in gates:
		words.append(cell.x)
		words.append(cell.y)
	for cell: Vector2i in start_cells:
		words.append(cell.x)
		words.append(cell.y)
	for x: int in cols():
		for y: int in zone_rows:
			words.append(int(kind_at(x, y)))
	return DuelSim.fnv1a(words)


func describe() -> String:
	return "%s — %d zones, %dx%d cells each" % [
		name, zones.size(), zone_cols, zone_rows,
	]
