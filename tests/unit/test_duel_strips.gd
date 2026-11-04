extends GutTest
## Every duel strip against the rules the Tug of War was built to: the shape,
## the mirror, the gates, open ground for every respawn, and -- for the strips
## with hazards -- that no hazard can reach a respawn, every one is told
## before it kills, and the crumbling stone can wear the deck down but never
## cut it.
##
## tests/zone_strip_test.gd holds the Tug of War to its own numbers (five
## zones, more than half the strip open ground). This holds every strip in
## DuelStrips to the rules that are the mode's, so a strip added to the
## catalogue is checked the day it is added. Each rule was seen to fail on a
## broken strip: a slot moved one cell in a mirrored zone, a basin drawn under
## a start mark, a blade with its tell taken out, three slabs in a run.

const TELL := StripHazards.TELL
## Steps a leader takes across the strip when every respawn is asked for.
const STEP := 8


func test_every_strip_loads_with_its_name_and_hour() -> void:
	for id: String in DuelStrips.IDS:
		var strip := DuelStrips.open(id)
		assert_not_null(strip, "%s loads" % id)
		if strip == null:
			continue
		assert_eq(strip.id, id, "%s knows its own name" % id)
		assert_true(TimeOfDay.is_stop(strip.hour), "%s is set at an hour (%s)" % [id, strip.hour])
		assert_ne(strip.name, "Untitled", "%s has a name of its own" % id)


func test_every_zone_is_one_screen_and_the_strip_three_to_five() -> void:
	for id: String in DuelStrips.IDS:
		var strip := DuelStrips.open(id)
		assert_between(strip.zone_count(), ZoneStrip.MIN_ZONES, ZoneStrip.MAX_ZONES, id)
		assert_eq(strip.zone_width(), ZoneStrip.SCREEN_WIDTH, "%s: a zone is a screen" % id)
		assert_eq(strip.zone_rows, 23, "%s: 23 rows" % id)
		for zone: AsciiLevel in strip.zones:
			assert_eq(zone.problems, PackedStringArray(), "%s parses clean" % zone.name)


func test_every_strip_mirrors_tiles_hazards_and_beats() -> void:
	for id: String in DuelStrips.IDS:
		var strip := DuelStrips.open(id)
		var last := strip.cols() - 1
		var breaks := 0
		for x: int in strip.cols():
			for y: int in strip.rows():
				if strip.kind_at(x, y) != strip.kind_at(last - x, y):
					breaks += 1
		assert_eq(breaks, 0, "%s: the tiles mirror" % id)
		assert_eq(_hazard_map(strip, false), _hazard_map(strip, true),
			"%s: every blade, basin and slab has a twin on the same beat" % id)
		assert_eq(strip.gates[0].x + strip.gates[1].x, last, "%s: the gates mirror" % id)
		assert_eq(strip.start_cells[0].x + strip.start_cells[1].x, last,
			"%s: the start marks mirror" % id)


func test_every_respawn_lands_on_open_ground_clear_of_every_hazard() -> void:
	for id: String in DuelStrips.IDS:
		var strip := DuelStrips.open(id)
		var per_zone := PackedInt32Array()
		per_zone.resize(strip.zone_count())
		var band := strip.spawn_columns()
		for x: int in range(band.x, band.y + 1):
			if strip.is_open_ground(x):
				@warning_ignore("integer_division")
				per_zone[x / strip.zone_cols] += 1
		for zone: int in strip.zone_count():
			assert_gte(per_zone[zone], 8, "%s zone %d has room to respawn (%d columns)"
				% [id, zone, per_zone[zone]])
		for slot: int in 2:
			var column := strip.cell_of(strip.start_position(slot)).x
			assert_true(strip.is_open_ground(column), "%s: seat %d starts on open ground"
				% [id, slot])

		var refused := 0
		var cut := 0
		var spots := {}
		for x: int in range(0, int(strip.world_size().x), STEP):
			var found := strip.find_open_ground(float(x), 0.0)
			if not bool(found["ok"]):
				refused += 1
				continue
			spots[found["position"]] = true
		for at: Vector2 in spots:
			# A whole flood cycle, which covers every beat twelve times over.
			var body := Rect2(at.x - 4.5, at.y - 22.0, 9.0, 22.0).grow(16.0)
			if strip.hazards.rect_is_deadly_between(body, 0, StripHazards.FLOOD_PERIOD):
				cut += 1
		assert_eq(refused, 0, "%s: a respawn is found for every place on the strip" % id)
		assert_eq(cut, 0, "%s: no blade or water ever comes within a tile of one (%d spots)"
			% [id, spots.size()])


func test_every_blade_and_every_tide_is_told_before_it_kills() -> void:
	for id: String in DuelStrips.IDS:
		var hazards := DuelStrips.open(id).hazards
		for blade: Dictionary in hazards.blades:
			for f: int in range(0, 3 * StripHazards.PERIOD):
				if StripHazards.is_live(blade, f) and not StripHazards.is_live(blade, f - 1):
					for k: int in range(1, TELL + 1):
						if not StripHazards.is_telling(blade, f - k):
							fail_test("%s: a blade cuts on %d untold %d frames before" % [id, f, k])
							return
		for flood: Dictionary in hazards.floods:
			for f: int in range(1, 2 * StripHazards.FLOOD_PERIOD):
				var now := StripHazards.deadly_water(flood, f).size.y > 0.0
				var before := StripHazards.deadly_water(flood, f - 1).size.y > 0.0
				if not now or before:
					continue
				var told := 0
				for k: int in range(1, TELL + 1):
					var moving := StripHazards.fill_of(flood, f - k) > 0.0
					if StripHazards.is_gushing(flood, f - k) or moving:
						told += 1
				assert_eq(told, TELL, "%s: the water comes over a wade on %d, told" % [id, f])
	assert_gte(StripHazards.FUSE, TELL, "a slab burns at least a tell before it drops")
	assert_gte(StripHazards.SLUICE_TELL, TELL, "the sluices gush at least a tell")


func test_crumbling_stone_wears_the_deck_down_and_never_cuts_it() -> void:
	for id: String in DuelStrips.IDS:
		var strip := DuelStrips.open(id)
		var hazards := strip.hazards
		var widest := 0
		for cell: Vector2i in hazards.stones:
			var run := 1
			while hazards.stone_index(cell + Vector2i(run, 0)) >= 0:
				run += 1
			widest = maxi(widest, run)
			var below := cell + Vector2i.DOWN
			assert_false(strip.is_solid(below.x, below.y), "%s: a slab at %s has air under it"
				% [id, cell])
		assert_lte(widest, 2, "%s: no run of cracked stone is wider than a jump" % id)


func test_the_hazards_are_in_the_handshake_hash() -> void:
	var seen := {}
	for id: String in DuelStrips.IDS:
		var identity := DuelStrips.open(id).identity()
		assert_false(seen.has(identity), "%s has a hash of its own" % id)
		seen[identity] = true
	var well := DuelStrips.open("well")
	var before := well.identity()
	well.hazards.blades[0]["phase"] = int(well.hazards.blades[0]["phase"]) + 1
	assert_ne(well.identity(), before, "a blade on another beat is another strip")


func test_a_strip_that_breaks_the_rules_is_refused() -> void:
	var zone := AsciiLevel.new()
	zone.parse("   i\n####\n")
	var hazards := StripHazards.new()
	assert_false(hazards.read_zone(zone, 0), "a slot with no beat is refused")
	assert_string_contains(hazards.problem, "no beat")


## Every hazard cell -> what it is and its beat, mirrored if asked.
func _hazard_map(strip: ZoneStrip, mirrored: bool) -> Dictionary:
	var last := strip.cols() - 1
	var out := {}
	var flip := func(cell: Vector2i) -> Vector2i:
		return Vector2i(last - cell.x, cell.y) if mirrored else cell
	for blade: Dictionary in strip.hazards.blades:
		for cell: Vector2i in blade["cut"]:
			out[flip.call(cell)] = "blade %d @%d" % [blade["kind"], blade["phase"]]
	for flood: Dictionary in strip.hazards.floods:
		for cell: Vector2i in flood["cells"]:
			out[flip.call(cell)] = "flood @%d" % flood["phase"]
	for cell: Vector2i in strip.hazards.stones:
		out[flip.call(cell)] = "stone"
	return out
