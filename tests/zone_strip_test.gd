extends SceneTree
## The tug-of-war strip: the manifest, the geometry, the fairness, and the claim
## that crossing a zone boundary builds nothing.
##
##     godot --headless --script tests/zone_strip_test.gd
##
## FIVE CLAIMS
## 1. The manifest loads, and every zone is the same size and exactly one
##    screen wide. A zone that is not one screen breaks the respawn algorithm,
##    which is written in screen widths.
## 2. The strip is mirror-symmetric about the centre of the middle zone, cell
##    for cell. Neither seat can be handed the better route, which is the same
##    argument levels/zone_03.txt makes about its single spawn mark.
## 3. Both gates exist, in the first and last zones, and mirror each other.
## 4. Open ground — the predicate the pacifist line rests on — exists densely
##    enough that the respawn algorithm can always place a fighter.
## 5. The streaming window is bounded, always covers what is on screen, and
##    never writes a cell while the view is crossing a zone boundary.

const Support := preload("res://tests/duel_support.gd")
const MANIFEST := "res://levels/duel_zones.txt"

## Builds happen when the window is half way across a zone, so no build may
## land within this share of a zone's width of a seam. A fraction rather than
## pixels: it was 256 px, which was four tenths of a 640 px zone and more than
## half of a 480 px one -- at which point every build looked like a seam build.
const SEAM_GUARD_SHARE := 0.4

var _s := Support.new()


func _initialize() -> void:
	var strip := ZoneStrip.from_manifest(MANIFEST)
	if not _s.check(strip != null, "the manifest loads"):
		quit(_s.report("zone_strip"))
		return

	print("  ", strip.describe())
	_shape(strip)
	_symmetry(strip)
	_gates(strip)
	_open_ground(strip)
	_streaming(strip)
	quit(_s.report("zone_strip"))


## --- 1. shape --------------------------------------------------------------

func _shape(strip: ZoneStrip) -> void:
	_s.equal(strip.zone_count(), 5, "five zones")
	_s.equal(strip.zone_cols, 30, "a zone is 30 cells wide")
	_s.equal(strip.zone_rows, 23, "a zone is 23 cells tall")
	_s.equal(strip.zone_width(), ZoneStrip.SCREEN_WIDTH, "one zone is one screen")
	_s.equal(strip.cols(), 5 * strip.zone_cols, "the strip is five zones wide")
	_s.equal(
		strip.world_size(), Vector2(5.0 * ZoneStrip.SCREEN_WIDTH, 368.0),
		"the strip is five design screens wide and 23 tiles tall"
	)

	# Past either end is wall, not void: the gates are the only way out.
	_s.equal(strip.kind_at(-1, 20), Tiles.Kind.SOLID, "west of the strip is wall")
	_s.equal(strip.kind_at(200, 20), Tiles.Kind.SOLID, "east of the strip is wall")
	_s.equal(strip.kind_at(5, -1), Tiles.Kind.EMPTY, "above the strip is sky")

	# A zone boundary is not a special case for the geometry.
	_s.equal(
		strip.kind_at(29, 22), strip.kind_at(30, 22),
		"the ground runs through the seam between zone 0 and zone 1"
	)


## --- 2. fairness -----------------------------------------------------------

func _symmetry(strip: ZoneStrip) -> void:
	var last := strip.cols() - 1
	var mismatches := 0
	var first_at := Vector2i(-1, -1)
	for x: int in strip.cols():
		for y: int in strip.rows():
			if strip.kind_at(x, y) == strip.kind_at(last - x, y):
				continue
			mismatches += 1
			if first_at.x < 0:
				first_at = Vector2i(x, y)
	_s.equal(
		mismatches, 0,
		"the strip mirrors about its centre (first break at %s)" % str(first_at)
	)

	# The one asymmetry is deliberate and is not a tile: a single spawn mark,
	# mirrored by the match rather than authored twice.
	var marks: Array[Vector2i] = strip.start_cells
	_s.equal(marks[0].y, marks[1].y, "both start marks are on the same row")
	_s.equal(
		marks[0].x + marks[1].x, last,
		"the two start marks mirror each other"
	)
	@warning_ignore("integer_division")
	var middle: int = strip.zone_count() / 2
	_s.equal(
		strip.zone_of_x(strip.start_position(0).x), middle,
		"seat one starts in the middle zone"
	)
	_s.equal(
		strip.zone_of_x(strip.start_position(1).x), middle,
		"seat two starts in the middle zone"
	)


## --- 3. the gates ----------------------------------------------------------

func _gates(strip: ZoneStrip) -> void:
	var west: Vector2i = strip.gates[0]
	var east: Vector2i = strip.gates[1]
	_s.equal(strip.zone_of_x(west.x * ZoneStrip.TILE), 0, "the west gate is in zone 0")
	_s.equal(
		strip.zone_of_x(east.x * ZoneStrip.TILE), strip.zone_count() - 1,
		"the east gate is in the last zone"
	)
	_s.equal(
		west.x + east.x, strip.cols() - 1, "the two gates mirror each other"
	)
	_s.check(
		strip.goal_x(0) < strip.goal_x(1),
		"seat one's goal is west of seat two's"
	)
	_s.equal(ZoneStrip.goal_direction(0), -1, "seat one pushes west")
	_s.equal(ZoneStrip.goal_direction(1), 1, "seat two pushes east")


## --- 4. the pacifist line's foundation -------------------------------------

func _open_ground(strip: ZoneStrip) -> void:
	var band := strip.spawn_columns()
	_s.check(band.x > strip.gates[0].x, "no respawn behind the west gate")
	_s.check(band.y < strip.gates[1].x, "no respawn behind the east gate")

	var open := 0
	var per_zone := PackedInt32Array()
	per_zone.resize(strip.zone_count())
	per_zone.fill(0)
	for x: int in range(band.x, band.y + 1):
		if not strip.is_open_ground(x):
			continue
		open += 1
		@warning_ignore("integer_division")
		var zone: int = x / strip.zone_cols
		per_zone[zone] += 1

	print("  open ground per zone: ", per_zone, " of %d columns" % strip.zone_cols)
	for zone: int in strip.zone_count():
		_s.check(
			per_zone[zone] >= 8,
			"zone %d has room to respawn in (%d columns)" % [zone, per_zone[zone]]
		)
	_s.check(
		open > (band.y - band.x) / 2,
		"most of the strip is open ground (%d of %d columns)"
			% [open, band.y - band.x + 1]
	)

	# The cistern is a hazard and must never be chosen.
	for x: int in range(band.x, band.y + 1):
		if not strip.is_open_ground(x):
			continue
		var row := strip.ground_row(x)
		if not _s.equal(
			strip.kind_at(x, row), Tiles.Kind.SOLID,
			"open ground at column %d stands on solid rock" % x
		):
			break

	# Whatever the algorithm asks for, somewhere is found.
	var failures := 0
	for x: int in range(0, int(strip.world_size().x), 8):
		if not bool(strip.find_open_ground(float(x), 0.0)["ok"]):
			failures += 1
	_s.equal(failures, 0, "a respawn is found for every position on the strip")

	# Both start marks are themselves open ground: the match opens on a line
	# the pacifist can already be played on.
	for slot: int in 2:
		var column := strip.cell_of(strip.start_position(slot)).x
		_s.check(
			strip.is_open_ground(column),
			"seat %d's start mark is open ground" % slot
		)


## --- 5. streaming ----------------------------------------------------------

## Walks the view's window from one end of the strip to the other in four-pixel
## steps and watches every cell it writes.
func _streaming(strip: ZoneStrip) -> void:
	var view := ZoneView.new()
	view.name = "ZoneView"
	root.add_child(view)
	view.setup(strip)

	var width := strip.zone_width()
	var last := int(float(strip.zone_count() - 1) * width)
	var worst_set := 0
	var seam_builds := 0
	var build_positions := PackedFloat32Array()
	var uncovered := 0

	for step: int in range(0, last + 1, 4):
		var at := float(step)
		# Both fighters inside the window, which is the ordinary case.
		var interests := PackedFloat32Array([at + 40.0, at + width - 40.0])
		view.focus(at, interests)

		worst_set = maxi(worst_set, view.realized.size())
		if view.built_last_focus:
			build_positions.append(at)
			# The first focus realises the opening window from nothing; every
			# build after it is one the view chose when to do.
			if step > 0 and absf(fposmod(at, width) - width * 0.5) \
					> width * 0.5 - width * SEAM_GUARD_SHARE:
				seam_builds += 1

		# Everything on screen has to be standable.
		for x: float in [at + 1.0, at + width * 0.5, at + width - 1.0]:
			if not view.is_realized(strip.zone_of_x(x)):
				uncovered += 1

	print("  streaming: %d builds at %s, worst working set %d zones" % [
		view.builds, str(build_positions), worst_set,
	])
	_s.equal(uncovered, 0, "every zone on screen is always realised")
	_s.equal(seam_builds, 0, "nothing is ever built near a zone boundary")
	_s.check(worst_set <= 3, "the working set stays within three zones (%d)" % worst_set)
	_s.check(view.builds >= strip.zone_count(), "every zone was realised at some point")
	_s.check(view.releases > 0, "zones behind the view are released again")

	# A revisit must not cost more than the first visit: the window goes back
	# the way it came and the same zones come back.
	var before := view.cells_written
	for step: int in range(last, -1, -4):
		view.focus(float(step), PackedFloat32Array([float(step) + 40.0]))
	_s.check(
		view.cells_written - before <= before,
		"walking back realises no more than walking out did"
	)

	# A respawn a screen and a half ahead is given ground to stand on even
	# though it is outside the window — that is what the interests are for.
	view.focus(0.0, PackedFloat32Array([0.0 + 1.5 * width]))
	_s.check(
		view.is_realized(strip.zone_of_x(1.5 * width)),
		"a respawn ahead of the window is standing on a realised zone"
	)

	view.free()
