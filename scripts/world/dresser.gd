class_name WorldDresser
extends RefCounted
## Turns a level's terrain into architecture.
##
## A terrace is a rectangle of masonry until something tells it that it has a
## lip, a cornice, a balustrade along the edge and an arcade cut into its
## face. That is this file. It runs over every level the game plays — hand
## authored, generated, duelling arena — so none of them has to be rewritten
## to stop looking like coloured blocks.
##
## TWO SOURCES, ONE RESULT.
##   - Marks the author wrote in the ASCII (Tiles.DECOR_LEGEND). These win.
##   - Rules applied to the terrain, below. They fill in everywhere an author
##     did not say otherwise.
##
## NOTHING HERE CAN CHANGE A LEVEL'S DIFFICULTY. Decoration tiles carry no
## collision and no queried kind (tools/build_tileset.gd), and every mark sits
## in a cell the terrain left empty. A level can be dressed, undressed or
## re-dressed and the character's reachable set is identical. That is what
## makes it safe to run automatically over levels this file has never seen.
##
## RESTRAINT IS A RULE, NOT A TASTE. Every rule below has a minimum run width
## and a spacing, because the failure mode of automatic decoration is a screen
## with ornament on every surface. Three arches and one long shadow beat a
## wall of carving.

## { "mid": {...}, "fore": {...}, "props": {...} }, each { Vector2i: Vector2i }:
## cell -> atlas coordinates, split by the plane it is drawn on. "props" is the
## room moods' plane, drawn over "mid"; see the end of this file.

const ARCH_PITCH := 3        ## columns between blind arches in an arcade
const ARCH_MIN_RUN := 5      ## narrower than this and a wall gets no arcade
const LIP_DROP := 3          ## tiles of fall that make a terrace edge a lip
const LIP_MIN_RUN := 3       ## narrower than this and a lip gets no cornice
const BALUSTRADE_MIN_RUN := 6
const BALUSTRADE_SPAN := 4   ## cells of railing inboard from each lip end
const COLONNADE_MIN_RUN := 12 ## narrower than this and a terrace gets no columns
const COLONNADE_PITCH := 6   ## columns between shafts
const COLONNADE_HEIGHT := 4
const FRIEZE_MIN_RUN := 8    ## narrower than this and a wall gets no carved band
const NICHE_PITCH := 5       ## columns between niches on a wall too short to arch
const PLANTER_PITCH := 21
const FORE_PITCH := 23       ## columns between foreground set pieces
const FORE_HEIGHT := 5       ## how tall a foreground archway stands
const CLOTH_PITCH := 7


static func dress(level: AsciiLevel) -> Dictionary:
	var mid := {}
	var fore := {}
	var reserved := _reserved_cells(level)

	_place_authored(level, mid, fore)
	# A frame composed by hand says so with `;! dress authored`, and is
	# dressed with its own marks and nothing else. The rules are for levels
	# nobody composed shot by shot; a still that is a single composition --
	# the dawn's (levels/dawn.txt) -- would have them put a colonnade and a
	# foreground archway into a picture whose subject is one figure on an
	# empty floor.
	if dressed_by_author(level):
		_resolve_runs(mid, "column_shaft", "column_cap", "column_base")
		_resolve_runs(fore, "fore_cloth", "fore_cloth", "fore_cloth_tail")
		return {"mid": mid, "fore": fore, "props": {}}
	# Authored marks are the floor plan; the rules fill in around them.
	# The two planes keep separate books, which is the point of having two:
	# a foreground column is supposed to stand in front of a balustrade.
	var taken_mid := _occupied(mid)
	var taken_fore := _occupied(fore)

	# Foreground first. It is the scarcest thing in a frame and the rule that
	# places it is the fussiest, so it gets first refusal on the open space.
	_rule_foreground(level, fore, taken_fore, reserved)
	_rule_cloth(level, fore, taken_fore, reserved)
	_rule_pit_rail(level, fore, taken_fore, reserved)

	# Colonnade before cornice: a column standing on a terrace is the thing
	# that throws the long shadow across it, and that outranks a moulding.
	_rule_colonnade(level, mid, taken_mid, reserved)
	_rule_planters(level, mid, taken_mid, reserved)
	_rule_arcade(level, mid, taken_mid, reserved)
	_rule_niches(level, mid, taken_mid, reserved)
	_rule_frieze(level, mid, taken_mid, reserved)
	# Cornices last: they run the length of a lip, so anything that wants a
	# cell on that course has to have asked for it first.
	_rule_lips(level, mid, taken_mid, reserved)

	_resolve_runs(mid, "column_shaft", "column_cap", "column_base")
	_resolve_runs(fore, "fore_cloth", "fore_cloth", "fore_cloth_tail")

	# Life last: it fills in around the architecture and never displaces it.
	var props := {}
	_dress_rooms(level, mid, fore, props, reserved)

	# A duelling arena is mirror-symmetric on purpose (levels/zone_03.txt
	# explains why, and tests/zone_strip_test.gd pins it). Decoration carries
	# no collision so it cannot make a match unfair, but a foreground column
	# standing over one seat and not the other looks unfair, which is nearly
	# as bad. So where the terrain is a mirror, the dressing is too. The SUN
	# is not mirrored: it is fixed in the world, and long shadows raking one
	# way across a symmetrical court is the point of having a sun at all.
	if _is_mirror_symmetric(level):
		_mirror_plane(mid, level.cols)
		_mirror_plane(fore, level.cols)
		_mirror_plane(props, level.cols)
	return {"mid": mid, "fore": fore, "props": props}


## Whether `level` asks to be dressed with its own marks only.
static func dressed_by_author(level: AsciiLevel) -> bool:
	var args: PackedStringArray = level.directive("dress").get("args", PackedStringArray())
	return args.size() == 1 and args[0] == "authored"


static func _is_mirror_symmetric(level: AsciiLevel) -> bool:
	if level.cols < 4:
		return false
	for y: int in level.rows:
		for x: int in level.cols / 2:
			if level.kind_at(x, y) != level.kind_at(level.cols - 1 - x, y):
				return false
	return true


## Makes a plane symmetrical by reflecting one half onto the other. The half
## that got the most decoration wins, because the rules place a set piece
## wherever it first fits and that is as likely to be the right as the left —
## reflecting the empty half would simply delete it.
static func _mirror_plane(plane: Dictionary, cols: int) -> void:
	var half := cols / 2
	var left := 0
	for cell: Vector2i in plane:
		if cell.x < half:
			left += 1
	var keep_left := left * 2 >= plane.size()

	for cell: Vector2i in plane.keys():
		if (cell.x < half) != keep_left:
			plane.erase(cell)
	for cell: Vector2i in plane.keys():
		plane[Vector2i(cols - 1 - cell.x, cell.y)] = Tiles.mirror_atlas(plane[cell])


## --- authored marks ---------------------------------------------------------

static func _place_authored(level: AsciiLevel, mid: Dictionary, fore: Dictionary) -> void:
	for mark: Dictionary in level.decorations:
		var cell: Vector2i = mark["cell"]
		match String(mark["id"]):
			"arch":
				# Anchored at the bottom-left of a two-wide, three-tall opening.
				var parts := [
					"arch_top_l", "arch_top_r", "arch_mid_l",
					"arch_mid_r", "arch_leg_l", "arch_leg_r",
				]
				for i: int in parts.size():
					var at := cell + Vector2i(i % 2, i / 2 - 2)
					mid[at] = Tiles.DECOR_ATLAS[parts[i]]
			"fountain":
				mid[cell] = Tiles.DECOR_ATLAS["fountain_l"]
				mid[cell + Vector2i(1, 0)] = Tiles.DECOR_ATLAS["fountain_r"]
			"column":
				mid[cell] = Tiles.DECOR_ATLAS["column_shaft"]
			_:
				var id := String(mark["id"])
				if not Tiles.DECOR_ATLAS.has(id):
					push_warning("WorldDresser: no atlas tile for '%s'" % id)
					continue
				if Tiles.is_foreground(id):
					fore[cell] = Tiles.DECOR_ATLAS[id]
				else:
					mid[cell] = Tiles.DECOR_ATLAS[id]


## A vertical run of `body` gets `head` at the top and `foot` at the bottom —
## a column grows a capital and a base, a hanging cloth grows a fringe.
static func _resolve_runs(plane: Dictionary, body: String, head: String, foot: String) -> void:
	var want: Vector2i = Tiles.DECOR_ATLAS[body]
	# Decide against a snapshot of where the shafts were, never against the
	# dictionary being rewritten: reading back a cell this pass has already
	# changed turns one base into a whole column of bases.
	var shafts := {}
	for cell: Vector2i in plane:
		if plane[cell] == want:
			shafts[cell] = true
	for cell: Vector2i in shafts:
		var top := not shafts.has(cell + Vector2i(0, -1))
		var bottom := not shafts.has(cell + Vector2i(0, 1))
		if bottom:
			plane[cell] = Tiles.DECOR_ATLAS[foot]
		elif top:
			plane[cell] = Tiles.DECOR_ATLAS[head]


## --- what the rules must not cover -----------------------------------------

## Entities, the spawn and everything within a tile of them. A relic hidden
## behind a planter is a bug report, not a composition.
static func _reserved_cells(level: AsciiLevel) -> Dictionary:
	var out := {}
	var marks: Array[Vector2i] = [level.spawn_point]
	for mark: Dictionary in level.entities:
		marks.append(mark["cell"])
	for cell: Vector2i in marks:
		for dy: int in range(-1, 2):
			for dx: int in range(-1, 2):
				out[cell + Vector2i(dx, dy)] = true
	return out


static func _occupied(plane: Dictionary) -> Dictionary:
	var out := {}
	for cell: Vector2i in plane:
		out[cell] = true
	return out


static func _free(level: AsciiLevel, cell: Vector2i, taken: Dictionary,
		reserved: Dictionary) -> bool:
	if cell.x < 0 or cell.x >= level.cols or cell.y < 0 or cell.y >= level.rows:
		return false
	if taken.has(cell) or reserved.has(cell):
		return false
	return level.kind_at(cell.x, cell.y) == Tiles.Kind.EMPTY


static func _put(plane: Dictionary, taken: Dictionary, cell: Vector2i, id: String) -> void:
	plane[cell] = Tiles.DECOR_ATLAS[id]
	taken[cell] = true


## --- rule: blind arcades on tall wall faces ---------------------------------

## A wall face is solid stone with more solid above it — the front of a
## terrace rather than the top of one. Arches are cut into those and nowhere
## else, so a floor never grows an arch.
static func _is_face(level: AsciiLevel, x: int, y: int) -> bool:
	return level.is_solid(x, y) and level.is_solid(x, y - 1)


static func _rule_arcade(level: AsciiLevel, mid: Dictionary, taken: Dictionary,
		reserved: Dictionary) -> void:
	var run_start := -1
	for x: int in range(level.cols + 1):
		var anchor := _arch_anchor(level, x) if x < level.cols else -1
		if anchor >= 0:
			if run_start < 0:
				run_start = x
			continue
		if run_start >= 0 and x - run_start >= ARCH_MIN_RUN:
			_fill_arcade(level, mid, taken, reserved, run_start, x - 1)
		run_start = -1


## The row an arch's feet stand on in this column, or -1 if none fits. The
## arch is cut into the lowest three rows of the face that still leave a
## course of stone above the crown and one below the feet.
static func _arch_anchor(level: AsciiLevel, x: int) -> int:
	var bottom := -1
	for y: int in range(level.rows - 1, -1, -1):
		if _is_face(level, x, y):
			bottom = y
			break
	if bottom < 0:
		return -1
	var anchor := bottom - 1
	# Three rows of opening, one course of lintel above it.
	for y: int in range(anchor - 3, anchor + 1):
		if not _is_face(level, x, y):
			return -1
	return anchor


static func _fill_arcade(level: AsciiLevel, mid: Dictionary, taken: Dictionary,
		reserved: Dictionary, from_x: int, to_x: int) -> void:
	# Centre the arcade in its run so a wall is not arched flush to one end.
	var width := to_x - from_x + 1
	var count := (width - 2) / ARCH_PITCH + 1
	if count <= 0:
		return
	var used := count * ARCH_PITCH - 1
	var x := from_x + (width - used) / 2
	for _i: int in count:
		var anchor := _arch_anchor(level, x)
		var anchor_right := _arch_anchor(level, x + 1)
		if anchor >= 0 and anchor == anchor_right:
			_place_arch(mid, taken, reserved, Vector2i(x, anchor))
		x += ARCH_PITCH


static func _place_arch(mid: Dictionary, taken: Dictionary, reserved: Dictionary,
		anchor: Vector2i) -> void:
	var parts := [
		"arch_top_l", "arch_top_r", "arch_mid_l", "arch_mid_r", "arch_leg_l", "arch_leg_r",
	]
	var cells: Array[Vector2i] = []
	for i: int in parts.size():
		var at := anchor + Vector2i(i % 2, i / 2 - 2)
		if taken.has(at) or reserved.has(at):
			return
		cells.append(at)
	for i: int in parts.size():
		_put(mid, taken, cells[i], parts[i])


## --- rule: a colonnade standing on a wide terrace ---------------------------

## This is the rule that puts the light back into the composition. A flat
## terrace has nothing standing on it, so the sun has nothing to throw, and
## the whole top of the level reads as one unbroken plate of gold. A row of
## columns turns it into alternating bands of gold and shade.
static func _rule_colonnade(level: AsciiLevel, mid: Dictionary, taken: Dictionary,
		reserved: Dictionary) -> void:
	for run: Vector3i in _surface_runs(level):
		var width := run.y - run.x + 1
		if width < COLONNADE_MIN_RUN:
			continue
		var count := (width - 2) / COLONNADE_PITCH
		if count < 2:
			continue
		var span := (count - 1) * COLONNADE_PITCH
		var x := run.x + (width - span) / 2
		for _i: int in count:
			# Nudge off a torch or a relic rather than dropping the column:
			# an arcade with a tooth missing reads as a mistake.
			for offset: int in [0, 1, -1, 2, -2]:
				var at := x + offset
				if at > run.x and at < run.y and _raise_column(
						level, mid, taken, reserved, at, run.z):
					break
			x += COLONNADE_PITCH


static func _raise_column(level: AsciiLevel, mid: Dictionary, taken: Dictionary,
		reserved: Dictionary, x: int, surface: int) -> bool:
	var cells: Array[Vector2i] = []
	for i: int in COLONNADE_HEIGHT:
		var cell := Vector2i(x, surface - 1 - i)
		if not _free(level, cell, taken, reserved):
			return false
		cells.append(cell)
	for cell: Vector2i in cells:
		_put(mid, taken, cell, "column_shaft")
	return true


## Maximal runs of equal surface height, as (from_x, to_x, row).
static func _surface_runs(level: AsciiLevel) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var x := 0
	while x < level.cols:
		var y := _surface_row(level, x)
		if y < 0:
			x += 1
			continue
		var end := x
		while end + 1 < level.cols and _surface_row(level, end + 1) == y:
			end += 1
		out.append(Vector3i(x, end, y))
		x = end + 1
	return out


## --- rule: niches in walls too short for an arcade --------------------------

## An arch needs four courses of face to cut into. Shorter walls get a single
## carved recess instead, which is the same idea at the size that fits.
static func _rule_niches(level: AsciiLevel, mid: Dictionary, taken: Dictionary,
		reserved: Dictionary) -> void:
	var x := 0
	while x < level.cols:
		if _arch_anchor(level, x) >= 0 or not _is_face(level, x, _niche_row(level, x)):
			x += 1
			continue
		var row := _niche_row(level, x)
		var cell := Vector2i(x, row)
		if _is_face(level, x, row - 1) and not taken.has(cell) and not reserved.has(cell):
			_put(mid, taken, cell, "niche")
			x += NICHE_PITCH
		else:
			x += 1


## The course a niche would be carved into: one up from the bottom of the
## column's lowest wall face, so it is never cut half into the ground.
static func _niche_row(level: AsciiLevel, x: int) -> int:
	for y: int in range(level.rows - 1, -1, -1):
		if _is_face(level, x, y):
			return y - 1
	return -1


## --- rule: a carved band under the lip of a long wall -----------------------

## One course of relief directly under the gold cap. Cheap, and it is the
## difference between a wall and a quarry face.
static func _rule_frieze(level: AsciiLevel, mid: Dictionary, taken: Dictionary,
		reserved: Dictionary) -> void:
	for run: Vector3i in _surface_runs(level):
		if run.y - run.x + 1 < FRIEZE_MIN_RUN:
			continue
		if not _has_lip(level, run.x, run.y, run.z):
			continue
		var band := run.z + 1
		if not _is_face(level, run.x, band + 2):
			continue
		for x: int in range(run.x, run.y + 1):
			var cell := Vector2i(x, band)
			if _is_face(level, x, band) and not taken.has(cell) and not reserved.has(cell):
				_put(mid, taken, cell, "frieze")


## --- rule: planters, sparingly ----------------------------------------------

## The only green in the terrain set, so one every twenty-odd columns and no
## more. Living things are an accent, not a texture.
static func _rule_planters(level: AsciiLevel, mid: Dictionary, taken: Dictionary,
		reserved: Dictionary) -> void:
	var next_x := 0
	for run: Vector3i in _surface_runs(level):
		if run.y - run.x + 1 < 6:
			continue
		var x := maxi(run.x + 2, next_x)
		while x <= run.y - 2:
			var cell := Vector2i(x, run.z - 1)
			if _free(level, cell, taken, reserved):
				_put(mid, taken, cell, "planter")
				next_x = x + PLANTER_PITCH
			x = maxi(x + 1, next_x)


## --- rule: cornices and balustrades along terrace lips ----------------------

## The exposed surface row in a column, or -1 where the column is open sky.
static func _surface_row(level: AsciiLevel, x: int) -> int:
	for y: int in level.rows:
		if level.is_solid(x, y):
			return y
	return -1


static func _rule_lips(level: AsciiLevel, mid: Dictionary, taken: Dictionary,
		reserved: Dictionary) -> void:
	var x := 0
	while x < level.cols:
		var y := _surface_row(level, x)
		if y < 0:
			x += 1
			continue
		var end := x
		while end + 1 < level.cols and _surface_row(level, end + 1) == y:
			end += 1
		if end - x + 1 >= LIP_MIN_RUN and _has_lip(level, x, end, y):
			_dress_lip(level, mid, taken, reserved, x, end, y)
		x = end + 1


## True if either end of a surface run falls away far enough to read as an
## edge. A floor that just continues at the same height is not a terrace.
static func _has_lip(level: AsciiLevel, from_x: int, to_x: int, y: int) -> bool:
	return _drop_at(level, from_x - 1, y) >= LIP_DROP or _drop_at(level, to_x + 1, y) >= LIP_DROP


static func _drop_at(level: AsciiLevel, x: int, y: int) -> int:
	if x < 0 or x >= level.cols:
		return 0
	var neighbour := _surface_row(level, x)
	return level.rows if neighbour < 0 else neighbour - y


static func _dress_lip(level: AsciiLevel, mid: Dictionary, taken: Dictionary,
		reserved: Dictionary, from_x: int, to_x: int, y: int) -> void:
	for x: int in range(from_x, to_x + 1):
		var cell := Vector2i(x, y - 1)
		if _free(level, cell, taken, reserved):
			_put(mid, taken, cell, "cornice")

	if to_x - from_x + 1 < BALUSTRADE_MIN_RUN:
		return
	# Railing only where the ground actually falls away, and only a few cells
	# in from that edge: a balustrade down the whole terrace is a fence.
	var spans: Array[Vector2i] = []
	if _drop_at(level, from_x - 1, y) >= LIP_DROP:
		spans.append(Vector2i(from_x, mini(to_x, from_x + BALUSTRADE_SPAN - 1)))
	if _drop_at(level, to_x + 1, y) >= LIP_DROP:
		spans.append(Vector2i(maxi(from_x, to_x - BALUSTRADE_SPAN + 1), to_x))
	for span: Vector2i in spans:
		for x: int in range(span.x, span.y + 1):
			var cell := Vector2i(x, y - 2)
			if _free(level, cell, taken, reserved):
				_put(mid, taken, cell, "balustrade")


## --- rule: the foreground plane ---------------------------------------------

## A pair of columns with an arch between them, standing in front of
## everything including the player. This is the depth cue the game had none
## of; one every FORE_PITCH columns is enough to sell it.
static func _rule_foreground(level: AsciiLevel, fore: Dictionary, taken: Dictionary,
		reserved: Dictionary) -> void:
	var x := FORE_PITCH / 2
	while x + 3 < level.cols:
		if _try_fore_arch(level, fore, taken, reserved, x):
			x += FORE_PITCH
		else:
			x += 1


static func _try_fore_arch(level: AsciiLevel, fore: Dictionary, taken: Dictionary,
		reserved: Dictionary, x: int) -> bool:
	var floor_row := _surface_row(level, x)
	if floor_row < 0 or _surface_row(level, x + 3) != floor_row:
		return false
	var top := floor_row - FORE_HEIGHT
	if top < 0:
		return false

	for dx: int in range(0, 4):
		for y: int in range(top, floor_row):
			if not _free(level, Vector2i(x + dx, y), taken, reserved):
				return false

	# The shafts run on up until something stops them, usually straight out
	# of the top of the frame. A column that ends in mid-air reads as a post;
	# one that leaves the picture reads as a building.
	for shaft_x: int in [x, x + 3]:
		var y := floor_row - 1
		while y >= 0 and _free(level, Vector2i(shaft_x, y), taken, reserved):
			_put(fore, taken, Vector2i(shaft_x, y), "fore_column")
			y -= 1
	_put(fore, taken, Vector2i(x + 1, top), "fore_soffit_l")
	_put(fore, taken, Vector2i(x + 2, top), "fore_soffit_r")
	return true


## A railing in front of a pit. Where the ground drops away between two
## higher shoulders the player is looking into a cistern, and a rail across
## the near side is both what would be built there and the one piece of
## foreground that is certain to have the character pass behind it.
static func _rule_pit_rail(level: AsciiLevel, fore: Dictionary, taken: Dictionary,
		reserved: Dictionary) -> void:
	var x := 0
	while x < level.cols:
		var y := _surface_row(level, x)
		if y < 0:
			x += 1
			continue
		var end := x
		while end + 1 < level.cols and _surface_row(level, end + 1) == y:
			end += 1
		var sunk_left := _drop_at(level, x - 1, y) <= -LIP_DROP
		var sunk_right := _drop_at(level, end + 1, y) <= -LIP_DROP
		if sunk_left and sunk_right and end - x + 1 >= 3:
			for rail_x: int in range(x, end + 1):
				var cell := Vector2i(rail_x, y - 1)
				if _free(level, cell, taken, reserved):
					_put(fore, taken, cell, "fore_rail")
		x = end + 1


## Cloth hangs from an overhang — a solid cell with open air under it — which
## is exactly where an awning or a curtain would be.
static func _rule_cloth(level: AsciiLevel, fore: Dictionary, taken: Dictionary,
		reserved: Dictionary) -> void:
	for x: int in range(0, level.cols, CLOTH_PITCH):
		for y: int in range(1, level.rows - 2):
			if not level.is_solid(x, y):
				continue
			var head := Vector2i(x, y + 1)
			var tail := Vector2i(x, y + 2)
			if not _free(level, head, taken, reserved) or not _free(level, tail, taken, reserved):
				continue
			if not _free(level, tail + Vector2i(0, 1), taken, reserved):
				continue
			_put(fore, taken, head, "fore_cloth")
			_put(fore, taken, tail, "fore_cloth_tail")
			break


## --- room moods: wear, growth and the things people leave about ------------
##
## Architecture alone made every room the same room: the same arcade, the same
## cornice, the same colonnade, repeated for as long as the level is long. A
## lived-in city differs street by street, so the level is cut into rooms
## ROOM_COLS wide and each room is given ONE mood:
##
##   GARDEN  ivy over the parapets, grass along the lips, a potted palm, the
##           planters in flower
##   STORE   urns and jars stacked against the walls
##   RUIN    cracked and spalled stone, rubble at the foot of the walls
##   COURT   latticed windows, lanterns under the overhangs, a rug over a rail
##
## One mood per room, not a little of each everywhere, is the restraint rule
## applied to life: a room reads as "the garden" or "the store" the way a
## street does. The order the moods come in is shuffled per level from its
## name, so consecutive rooms never repeat and two levels do not share an
## order.
##
## Everything here goes on the PROPS plane, a second mid-ground layer over the
## architecture (scripts/world/level.gd), so an urn can stand in front of a
## cornice and ivy can hang over a frieze without taking the cell from it. The
## safety argument is the same as for every other mark: no collision, no
## queried kind, never on a reserved cell. Wear, ivy, moss and windows lie over
## stone the terrain already has; everything else stands in a cell the terrain
## left empty.

const ROOM_COLS := 20
enum Mood { GARDEN, STORE, RUIN, COURT }
const IVY_PITCH := 5
const IVY_LONGEST := 4
const WINDOW_PITCH := 4
## Courses of sheer face below a window row that make a wall a building.
const TALL_WALL := 7
const STOREY := 3
const LANTERN_PITCH := 5
## How often a face cracks: in a ruin, and everywhere else.
const WEAR_RUIN := 0.16
const WEAR_ELSEWHERE := 0.02
const GRASS_SHARE := 0.4

## Ids a floor prop may stand in front of. Anything else in the cell -- a
## column, a balustrade, a planter -- is already standing there.
const BEHIND_PROPS := ["cornice"]
## Ids that ivy may hang over. A carved band under vines is a ruin's best
## look; an arch or a niche under them is a mess.
const BEHIND_IVY := ["frieze"]


## The mood of the room column `x` falls in.
static func mood_at(level: AsciiLevel, x: int) -> Mood:
	var order := _mood_order(level)
	return order[posmod(x / ROOM_COLS, order.size())]


static func _mood_order(level: AsciiLevel) -> Array[Mood]:
	var order: Array[Mood] = [Mood.GARDEN, Mood.STORE, Mood.RUIN, Mood.COURT]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(level.name)
	for i: int in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var keep := order[i]
		order[i] = order[j]
		order[j] = keep
	return order


## A fixed, cheap hash of a cell, in [0, 1). Not a RandomNumberGenerator:
## a cell's answer must not depend on how many cells were asked before it.
static func _noise(x: int, y: int, salt: int) -> float:
	var h := (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(posmod(h, 1000)) / 1000.0


static func _dress_rooms(level: AsciiLevel, mid: Dictionary, fore: Dictionary,
		props: Dictionary, reserved: Dictionary) -> void:
	_rule_moss(level, mid, props, reserved)
	_rule_ivy(level, mid, props, reserved)
	_rule_windows(level, mid, props, reserved)
	_rule_wear(level, mid, props, reserved)
	_rule_floor_props(level, mid, props, reserved)
	_rule_lanterns(level, fore, props, reserved)
	_rule_room_variants(level, mid)


static func _put_prop(props: Dictionary, cell: Vector2i, id: String) -> void:
	props[cell] = Tiles.DECOR_ATLAS[id]


static func _mid_is(mid: Dictionary, cell: Vector2i, ids: Array) -> bool:
	if not mid.has(cell):
		return true
	for id: String in ids:
		if mid[cell] == Tiles.DECOR_ATLAS[id]:
			return true
	return false


## Stone that stands in water grows moss, whatever the room.
static func _rule_moss(level: AsciiLevel, mid: Dictionary, props: Dictionary,
		reserved: Dictionary) -> void:
	for y: int in level.rows:
		for x: int in level.cols:
			if level.kind_at(x, y) != Tiles.Kind.WATER:
				continue
			for d: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1),
					Vector2i(-1, 1), Vector2i(1, 1)]:
				var cell := Vector2i(x, y) + d
				if level.is_solid(cell.x, cell.y) and not mid.has(cell) \
						and not props.has(cell) and not reserved.has(cell):
					_put_prop(props, cell, "moss")


## Ivy comes over the parapet of a garden terrace and down its face.
static func _rule_ivy(level: AsciiLevel, mid: Dictionary, props: Dictionary,
		reserved: Dictionary) -> void:
	for run: Vector3i in _surface_runs(level):
		var x := run.x + 1 + int(_noise(run.x, run.z, 7) * IVY_PITCH)
		while x <= run.y - 1:
			if mood_at(level, x) == Mood.GARDEN:
				_hang_ivy(level, mid, props, reserved, x, run.z + 1)
			x += IVY_PITCH


static func _hang_ivy(level: AsciiLevel, mid: Dictionary, props: Dictionary,
		reserved: Dictionary, x: int, top: int) -> void:
	var want := 2 + int(_noise(x, top, 3) * float(IVY_LONGEST - 1))
	var cells: Array[Vector2i] = []
	for y: int in range(top, top + want):
		var cell := Vector2i(x, y)
		if not _is_face(level, x, y) or props.has(cell) or reserved.has(cell) \
				or not _mid_is(mid, cell, BEHIND_IVY):
			break
		cells.append(cell)
	if cells.size() < 2:
		return
	for i: int in cells.size():
		var id := "ivy"
		if i == 0:
			id = "ivy_top"
		elif i == cells.size() - 1:
			id = "ivy_end"
		_put_prop(props, cells[i], id)


## Latticed windows two courses under the cap. A court has them on every
## wall; anywhere else only a wall tall enough to be a building gets a storey
## of them, because a sheer face that high with nothing in it is the
## placeholder the art direction warns about.
static func _rule_windows(level: AsciiLevel, mid: Dictionary, props: Dictionary,
		reserved: Dictionary) -> void:
	for run: Vector3i in _surface_runs(level):
		# Storeys every STOREY courses, staggered, for as long as the wall
		# is still a building below them; a court gets the first storey on
		# any wall at all.
		var storey := 0
		var row := run.z + 2
		while storey == 0 or _face_depth(level, (run.x + run.y) / 2, row) >= TALL_WALL:
			var x := run.x + 2 + (storey % 2) * (WINDOW_PITCH / 2)
			while x <= run.y - 2:
				var cell := Vector2i(x, row)
				var wanted := (storey == 0 and mood_at(level, x) == Mood.COURT) \
					or _face_depth(level, x, row) >= TALL_WALL
				if wanted and _is_face(level, x, row) and _is_face(level, x, row + 1) \
						and not mid.has(cell) and not props.has(cell) \
						and not reserved.has(cell):
					_put_prop(props, cell, "window")
				x += WINDOW_PITCH
			storey += 1
			row += STOREY


## How many courses of wall face run down from `row` before the stone ends or
## an arcade begins.
static func _face_depth(level: AsciiLevel, x: int, row: int) -> int:
	var depth := 0
	while _is_face(level, x, row + depth):
		depth += 1
	return depth


## Cracks and spalled blocks: thick in a ruin, rare anywhere else, never two
## touching.
static func _rule_wear(level: AsciiLevel, mid: Dictionary, props: Dictionary,
		reserved: Dictionary) -> void:
	for y: int in level.rows:
		for x: int in level.cols:
			var cell := Vector2i(x, y)
			if not _is_face(level, x, y) or mid.has(cell) or props.has(cell) \
					or reserved.has(cell):
				continue
			if props.has(cell + Vector2i(-1, 0)) or props.has(cell + Vector2i(0, -1)):
				continue
			var n := _noise(x, y, 1)
			var ruin := mood_at(level, x) == Mood.RUIN
			if n < (WEAR_RUIN if ruin else WEAR_ELSEWHERE):
				_put_prop(props, cell, "worn" if ruin and n < WEAR_RUIN * 0.4 else "crack")


## Whatever stands on a floor: jars in a store, rubble in a ruin, a palm and
## grass in a garden. Stacked against walls first, because that is where
## people put things and where rubble falls.
static func _rule_floor_props(level: AsciiLevel, mid: Dictionary, props: Dictionary,
		reserved: Dictionary) -> void:
	for run: Vector3i in _surface_runs(level):
		for end: int in [run.x, run.y]:
			var step := 1 if end == run.x else -1
			var wall := _surface_row(level, end - step)
			var against_wall := wall >= 0 and wall < run.z
			if not against_wall:
				continue
			match mood_at(level, end):
				Mood.STORE:
					_place_floor(level, mid, props, reserved, end, run.z, "urn")
					_place_floor(level, mid, props, reserved, end + step, run.z, "jars")
				Mood.RUIN:
					_place_floor(level, mid, props, reserved, end, run.z, "rubble")
		if run.y - run.x + 1 < 6:
			continue
		var mood := mood_at(level, (run.x + run.y) / 2)
		if mood == Mood.GARDEN:
			var palm_x := run.x + 2 + int(_noise(run.x, run.z, 11) * float(run.y - run.x - 3))
			_place_palm(level, mid, props, reserved, palm_x, run.z)
			for x: int in range(run.x, run.y + 1):
				if _noise(x, run.z, 13) < GRASS_SHARE and mood_at(level, x) == Mood.GARDEN \
						and not props.has(Vector2i(x - 1, run.z - 1)):
					_place_floor(level, mid, props, reserved, x, run.z, "grass")
		elif mood == Mood.STORE:
			# One stack in the open as well as against the walls: a store
			# room whose terraces all end in drops would otherwise be empty.
			var x := run.x + 1 + int(_noise(run.y, run.z, 23) * float(run.y - run.x - 2))
			if _place_floor(level, mid, props, reserved, x, run.z, "urn"):
				_place_floor(level, mid, props, reserved, x + 1, run.z, "jars")
		elif mood == Mood.RUIN and _noise(run.x, run.z, 17) < 0.5:
			var x := run.x + 1 + int(_noise(run.y, run.z, 19) * float(run.y - run.x - 1))
			_place_floor(level, mid, props, reserved, x, run.z, "rubble")


static func _floor_free(level: AsciiLevel, mid: Dictionary, props: Dictionary,
		reserved: Dictionary, cell: Vector2i) -> bool:
	return level.kind_at(cell.x, cell.y) == Tiles.Kind.EMPTY \
		and level.is_solid(cell.x, cell.y + 1) and not props.has(cell) \
		and not reserved.has(cell) and _mid_is(mid, cell, BEHIND_PROPS) \
		and cell.x >= 0 and cell.x < level.cols and cell.y >= 0


static func _place_floor(level: AsciiLevel, mid: Dictionary, props: Dictionary,
		reserved: Dictionary, x: int, surface: int, id: String) -> bool:
	var cell := Vector2i(x, surface - 1)
	if not _floor_free(level, mid, props, reserved, cell):
		return false
	_put_prop(props, cell, id)
	return true


static func _place_palm(level: AsciiLevel, mid: Dictionary, props: Dictionary,
		reserved: Dictionary, x: int, surface: int) -> void:
	var pot := Vector2i(x, surface - 1)
	var crown := Vector2i(x, surface - 2)
	if not _floor_free(level, mid, props, reserved, pot):
		return
	if level.kind_at(crown.x, crown.y) != Tiles.Kind.EMPTY or mid.has(crown) \
			or props.has(crown) or reserved.has(crown) or crown.y < 0:
		return
	_put_prop(props, pot, "palm_pot")
	_put_prop(props, crown, "palm_top")


## A court hangs lanterns under its overhangs, where the foreground's hanging
## cloth has not already taken the spot.
static func _rule_lanterns(level: AsciiLevel, fore: Dictionary, props: Dictionary,
		reserved: Dictionary) -> void:
	var next_x := -LANTERN_PITCH
	for x: int in level.cols:
		if x < next_x or mood_at(level, x) != Mood.COURT:
			continue
		for y: int in range(1, level.rows - 2):
			var cell := Vector2i(x, y)
			if not level.is_solid(x, y - 1) or level.kind_at(x, y) != Tiles.Kind.EMPTY:
				continue
			if level.kind_at(x, y + 1) != Tiles.Kind.EMPTY or fore.has(cell) \
					or props.has(cell) or reserved.has(cell):
				continue
			_put_prop(props, cell, "lantern")
			next_x = x + LANTERN_PITCH
			break


## Swaps a few existing architecture tiles for their lived-in variants: the
## garden's planters bloom, and a court airs one rug per railing.
static func _rule_room_variants(level: AsciiLevel, mid: Dictionary) -> void:
	var planter: Vector2i = Tiles.DECOR_ATLAS["planter"]
	var rail: Vector2i = Tiles.DECOR_ATLAS["balustrade"]
	for cell: Vector2i in mid.keys():
		var mood := mood_at(level, cell.x)
		if mid[cell] == planter and mood == Mood.GARDEN:
			mid[cell] = Tiles.DECOR_ATLAS["planter_bloom"]
		elif mid[cell] == rail and mood == Mood.COURT:
			# The second post of a run, so the rug hangs inside the railing
			# rather than off its end.
			var left := cell + Vector2i(-1, 0)
			var none := Vector2i(-1, -1)
			if mid.get(left, none) == rail and mid.get(left + Vector2i(-1, 0), none) != rail:
				mid[cell] = Tiles.DECOR_ATLAS["balustrade_rug"]
