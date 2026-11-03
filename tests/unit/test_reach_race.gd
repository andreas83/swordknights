extends GutTest
## The race against a held gate, in the reachability proof
## (scripts/levels/reach_race.gd): a plate on a `hold` wire is a move to
## everywhere the prince can run before the hold runs out, with 25% of it to
## spare, and the gate is shut again when he gets there.
##
## Held here:
##
## - a race with room to spare is a route, and the proof measures it in
##   frames from the primitives' own counts -- the arc frames the solver
##   stepped, a tile at a run;
## - the same race with only 10% to spare is refused, and so is one past
##   its hold altogether: a thumb on a phone does not run perfectly;
## - a race sets no bit, so the checkpoint proof's argument -- every bit is
##   a latch -- still holds, and nothing behind a raced gate is claimed after;
## - a jump in a race costs the frames the arc took.
##
## Levels without mechanisms are untouched; tests/unit/test_reach_guard_rail.gd
## holds that.

## A roofed street: plate 2 holds gate 2 for HOLD seconds against an
## eight-tile run from the plate to the far side.
const STREET := """;! channel 2 hold HOLD
; Race Street

####################2#####
                    !
  @          t      !    D
#############o############
#############2############
"""

func _street(hold: String) -> AsciiLevel:
	var level := AsciiLevel.new()
	level.parse(STREET.replace("HOLD", hold))
	assert_eq(level.problems, PackedStringArray(), "the street parses clean")
	return level


func _race(level: AsciiLevel) -> Dictionary:
	var races := ReachRace.measure(level)
	assert_eq(races.size(), 1, "one plate, one race")
	return races[0] if races.size() == 1 else {}


func test_a_race_with_room_to_spare_is_a_route() -> void:
	var level := _street("2.4")
	var race := _race(level)
	var run := float(race["frames"])
	# From the plate (column 13) to standing past the gate (column 21): eight
	# tiles at a run and a standing start.
	assert_almost_eq(run, 8.0 * ReachRace.RUN_TILE + ReachRace.START, 3.0,
		"eight tiles at a run, from a standing start")
	assert_true(bool(race["ok"]), "%.1f frames of a 108-frame budget" % run)
	assert_true(bool(LevelReachability.verify(level)["ok"]), "so the door is reachable")


func test_a_race_with_ten_percent_slack_is_refused() -> void:
	var run := float(_race(_street("2.4"))["frames"])
	var tight := "%.2f" % (run / 0.9 / 60.0)
	var level := _street(tight)
	var race := _race(level)
	assert_almost_eq(float(race["frames"]) / float(race["hold"]), 0.9, 0.01,
		"the run is nine tenths of a %s s hold" % tight)
	assert_false(bool(race["ok"]), "which leaves 10%, not the 25% a thumb needs")
	assert_false(bool(LevelReachability.verify(level)["ok"]), "so it is no route")
	var easy := _street("%.2f" % (run / 0.74 / 60.0))
	assert_true(bool(LevelReachability.verify(easy)["ok"]), "and with 26% to spare it is")


func test_a_race_past_its_hold_is_no_route() -> void:
	var level := _street("1.0")
	assert_false(bool(_race(level)["ok"]), "a second is not enough for eight tiles")
	assert_false(bool(LevelReachability.verify(level)["ok"]), "the gate might as well be a wall")


func test_a_race_sets_no_bit() -> void:
	var level := _street("2.4")
	var model := ReachModel.for_level(level)
	var solver := LevelReachability.Solver.new(level, model)
	var past: Array[Vector2i] = [Vector2i(22, 3)]
	var claims: Dictionary = ReachSearch.standing_masks(solver, level.spawn_point, past)["masks"]
	assert_eq(claims.get(Vector2i(22, 3)), [0] as Array[int],
		"past the gate with every wire off: the gate is down behind him")
	assert_eq(Game.checkpoint_cells(level), [Vector2i(13, 3)] as Array[Vector2i],
		"and the torch on the plate is a checkpoint, proved through its race")


## A street three courses high, room to hop a kerb under its roof; KERB is
## where the kerb goes, or nothing.
const HIGH := """;! channel 2 hold 2.4
; High Street

####################2#####
                    !
                    !
  @          t   K  !    D
#############o############
#############2############
"""


func test_a_jump_in_a_race_costs_the_frames_of_its_arc() -> void:
	var flat := AsciiLevel.new()
	flat.parse(HIGH.replace("K", " "))
	var kerb := AsciiLevel.new()
	kerb.parse(HIGH.replace("K", "#"))
	var plain := float(_race(flat)["frames"])
	var over := float(_race(kerb)["frames"])
	assert_lt(plain, INF, "the flat street is a race")
	assert_gt(over, plain, "a hop over a kerb is slower than running the flat")
	assert_lt(over - plain, Tuning.jump_airtime() * 60.0,
		"by less than a jump's airtime: the arc carries him on as it goes")


## Open sky over the street, a tower over the gate: room for real arcs.
const OPEN := """;! channel 2 hold 2.4
; Open Street

                    #
                    #
                    2
                    !
  @          t      !    D
#############o############
#############2############
"""


## Under open sky a running jump is a long arc, and it must cost every frame
## the solver stepped it for: no move outruns running, so the race is never
## faster than its tiles at a run.
func test_no_move_in_a_race_outruns_a_run() -> void:
	var level := AsciiLevel.new()
	level.parse(OPEN)
	assert_eq(level.problems, PackedStringArray(), "the open street parses clean")
	var run := float(_race(level)["frames"])
	assert_gte(run, 8.0 * ReachRace.RUN_TILE - 1.0,
		"eight tiles in %.1f frames: not faster than running them" % run)
