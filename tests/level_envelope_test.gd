extends SceneTree
## Pins the reachability verifier to the tuning it claims to be derived from,
## and proves each movement primitive is actually load-bearing.
##
## The verifier is only worth anything if its reach matches the character's.
## So rather than trusting the arithmetic, this measures what the simulation
## achieves on synthetic levels and compares that against Tuning's own
## helpers. A retune that moves hop_tiles(), platform_step_tiles() or
## grab_tiles() has to move the measured envelope with it, or this fails.
##
##     godot --headless --script tests/level_envelope_test.gd

const Asserts := preload("res://tests/level_asserts.gd")

var _check := Asserts.new("level_envelope_test")


func _initialize() -> void:
	_check_legend_matches_tiles()
	_check_measured_envelope()
	_check_tier_ordering()
	_check_ladder_is_required()
	_check_drop_through_is_required()
	_check_grab_wall_is_grabbable()
	_check_hazards_are_fatal()
	_check_hand_authored_level_verifies()
	quit(0 if _check.report() else 1)


## The ground truth for the whole verifier: levels/level_01.txt is a level a
## person designed and played, so a model that cannot find a route through it
## is too conservative to be worth running — it would reject good generated
## levels for the rest of time. Level 01 uses every primitive this search
## claims to have, the 4-tile ledge-grab wall included.
func _check_hand_authored_level_verifies() -> void:
	var level := AsciiLevel.from_file("res://levels/level_01.txt")
	if level == null:
		_check.fail("could not load levels/level_01.txt")
		return
	var report := LevelReachability.verify(level)
	_check.is_true(bool(report["ok"]),
		"the hand-authored level 01 verifies as solvable: %s"
			% String(report.get("reason", "")))


## The grammar writes glyphs by hand; this is what stops them drifting away
## from the legend the parser reads.
func _check_legend_matches_tiles() -> void:
	var expected := {
		LevelGrammar.SOLID: Tiles.Kind.SOLID,
		LevelGrammar.PLATFORM: Tiles.Kind.PLATFORM,
		LevelGrammar.SPIKES: Tiles.Kind.SPIKES,
		LevelGrammar.WATER: Tiles.Kind.WATER,
		LevelGrammar.LADDER: Tiles.Kind.LADDER,
		LevelGrammar.BACKDROP: Tiles.Kind.BACKDROP,
		LevelGrammar.EMPTY: Tiles.Kind.EMPTY,
	}
	for glyph: String in expected:
		_check.equal(Tiles.LEGEND.get(glyph), expected[glyph],
			"glyph '%s' means what the grammar thinks" % glyph)

	for glyph: String in [LevelGrammar.SPAWN, LevelGrammar.RELIC, LevelGrammar.EXIT,
			LevelGrammar.TORCH, LevelGrammar.PATROL]:
		_check.is_true(Tiles.ENTITY_LEGEND.has(glyph),
			"glyph '%s' is an entity mark" % glyph)


## The heart of it: what the simulation really reaches, against what Tuning
## says it should.
func _check_measured_envelope() -> void:
	var measured := LevelReachability.measure_reach()

	_check.equal(measured["hop"], Tuning.hop_tiles(),
		"simulated hop reach matches Tuning.hop_tiles()")
	_check.equal(measured["grab"], Tuning.grab_tiles(),
		"simulated ledge-grab reach matches Tuning.grab_tiles()")
	# Gaps are the one tier that is not an exact equality. The hop and the grab
	# land on a tile boundary, so they can be derived exactly; a gap is crossed
	# from wherever the character happens to be standing, and the authored
	# limit deliberately assumes a comfortable takeoff rather than a perfect
	# one. So the declared limit must sit inside the measured envelope — and
	# no more than a tile inside it, or the generator has quietly become so
	# cautious that a retune has stopped reaching the levels it authors.
	var measured_gap := int(measured["gap"])
	var declared_gap := LevelGrammar.max_gap_tiles()
	_check.is_true(declared_gap <= measured_gap,
		"the declared gap limit (%d) is inside the measured envelope (%d)"
			% [declared_gap, measured_gap])
	_check.is_true(declared_gap >= measured_gap - 1,
		"the declared gap limit (%d) is not needlessly far inside the measured envelope (%d)"
			% [declared_gap, measured_gap])

	# And the grammar must not author anything past what was measured.
	_check.is_true(LevelGrammar.safe_gap_tiles() <= int(measured["gap"]),
		"the authored gap limit is inside the measured envelope")
	_check.is_true(LevelGrammar.grab_rise() <= int(measured["grab"]),
		"the grab-wall rise is inside the measured envelope")
	_check.is_true(LevelGrammar.hop_rise() <= int(measured["hop"]),
		"the hop rise is inside the measured envelope")


## The three tiers have to stay distinct and in order, or the grammar's whole
## vocabulary collapses into one move.
func _check_tier_ordering() -> void:
	_check.is_true(LevelGrammar.hop_rise() < LevelGrammar.step_rise(),
		"a platform step is taller than a hop")
	_check.is_true(LevelGrammar.step_rise() <= LevelGrammar.grab_rise(),
		"a ledge grab reaches at least as high as a platform step")
	_check.greater(Tuning.jump_airtime(), 0.0, "airtime is positive")

	# The engine integrates the arc at a fixed 60 Hz, which loses a little rise
	# and a little reach against the continuous solution. Checking the discrete
	# arc stays under the continuous one is what catches a sign or a scale
	# slipping into the integration.
	var ideal_airtime := 2.0 * (
		(Tuning.JUMP_SPEED - Tuning.APEX_THRESHOLD) / Tuning.GRAVITY
		+ Tuning.APEX_THRESHOLD / (Tuning.GRAVITY * Tuning.APEX_GRAVITY_SCALE)
	)
	_check.is_true(Tuning.jump_airtime() <= ideal_airtime,
		"the simulated airtime (%.4f s) is not longer than the continuous one (%.4f s)"
			% [Tuning.jump_airtime(), ideal_airtime])
	_check.greater(Tuning.jump_airtime(), ideal_airtime * 0.9,
		"the simulated airtime is within 10%% of the continuous one")
	_check.is_true(Tuning.run_jump_reach() <= Tuning.RUN_SPEED * ideal_airtime,
		"the simulated run-jump reach is not larger than the analytic bound")


## A shaft too tall to grab out of, with one ladder. Reachable with the ladder,
## unreachable without it — so the ladder primitive is doing the work and is
## not quietly dead code.
func _check_ladder_is_required() -> void:
	var with_ladder := _shaft(true)
	var without := _shaft(false)
	var goal: Array[Vector2i] = [Vector2i(9, 4)]

	_check.is_true(bool(LevelReachability.reaches(with_ladder, goal)["ok"]),
		"a ladder carries the player out of a shaft too tall to grab")
	_check.is_false(bool(LevelReachability.reaches(without, goal)["ok"]),
		"the same shaft without the ladder is unreachable")


## The shaft: floor at row 11, a block on the right whose top is 6 tiles up —
## past grab_tiles() — and optionally a ladder column at 7.
func _shaft(ladder: bool) -> AsciiLevel:
	var grid := LevelGrammar.Canvas.new(14, 14)
	for x: int in 14:
		grid.fill_column(x, 11, 13, LevelGrammar.SOLID)
	grid.fill_column(0, 0, 13, LevelGrammar.SOLID)
	for x: int in range(8, 14):
		grid.fill_column(x, 5, 13, LevelGrammar.SOLID)
	if ladder:
		grid.fill_column(7, 4, 10, LevelGrammar.LADDER)
	grid.set_cell(3, 10, LevelGrammar.SPAWN)
	return _parse(grid)


## A sealed box: the player starts on a one-way platform and the floor below is
## walled in, so the only way down is dropping through the platform.
func _check_drop_through_is_required() -> void:
	var goal: Array[Vector2i] = [Vector2i(4, 10)]
	_check.is_true(bool(LevelReachability.reaches(_box(true), goal)["ok"]),
		"the player can drop through a one-way platform")
	_check.is_false(bool(LevelReachability.reaches(_box(false), goal)["ok"]),
		"the same box with a solid floor instead of a platform is sealed")


func _box(one_way: bool) -> AsciiLevel:
	var grid := LevelGrammar.Canvas.new(14, 14)
	for x: int in 14:
		grid.fill_column(x, 11, 13, LevelGrammar.SOLID)
	grid.fill_column(1, 0, 11, LevelGrammar.SOLID)
	grid.fill_column(7, 0, 11, LevelGrammar.SOLID)
	for x: int in range(2, 7):
		grid.set_cell(x, 8, LevelGrammar.PLATFORM if one_way else LevelGrammar.SOLID)
	grid.set_cell(4, 7, LevelGrammar.SPAWN)
	return _parse(grid)


## A wall of exactly grab_rise() must be climbable, and one tile taller must
## not be — the boundary the whole grammar is built on.
func _check_grab_wall_is_grabbable() -> void:
	var rise := LevelGrammar.grab_rise()
	_check.is_true(bool(LevelReachability.reaches(_wall(rise), _wall_goal(rise))["ok"]),
		"a wall of grab_rise() (%d) tiles is climbable" % rise)
	_check.is_false(bool(LevelReachability.reaches(
			_wall(rise + 1), _wall_goal(rise + 1))["ok"]),
		"a wall one tile taller than grab_rise() is not")


func _wall(rise: int) -> AsciiLevel:
	var grid := LevelGrammar.Canvas.new(16, 16)
	for x: int in 16:
		grid.fill_column(x, 12, 15, LevelGrammar.SOLID)
	for x: int in range(9, 16):
		grid.fill_column(x, 12 - rise, 15, LevelGrammar.SOLID)
	grid.set_cell(2, 11, LevelGrammar.SPAWN)
	return _parse(grid)


func _wall_goal(rise: int) -> Array[Vector2i]:
	return [Vector2i(12, 11 - rise)]


## Spikes and water have to stop a route, not decorate it: the same corridor is
## crossable when it is empty and not when it is flooded.
func _check_hazards_are_fatal() -> void:
	var goal: Array[Vector2i] = [Vector2i(12, 11)]
	_check.is_true(bool(LevelReachability.reaches(_corridor(""), goal)["ok"]),
		"a plain corridor is walkable end to end")
	for glyph: String in [LevelGrammar.SPIKES, LevelGrammar.WATER]:
		_check.is_false(bool(LevelReachability.reaches(_corridor(glyph), goal)["ok"]),
			"a corridor flooded with '%s' is not crossable" % glyph)


## A corridor with a six-tile hazard trench in the middle — far wider than the
## jump envelope, so only a verifier that ignored hazards would cross it.
func _corridor(glyph: String) -> AsciiLevel:
	var grid := LevelGrammar.Canvas.new(16, 16)
	for x: int in 16:
		grid.fill_column(x, 12, 15, LevelGrammar.SOLID)
	if glyph != "":
		for x: int in range(5, 11):
			grid.fill_column(x, 9, 12, glyph)
	grid.set_cell(2, 11, LevelGrammar.SPAWN)
	return _parse(grid)


func _parse(grid: LevelGrammar.Canvas) -> AsciiLevel:
	var level := AsciiLevel.new()
	level.parse("\n".join(grid.to_lines()))
	return level
