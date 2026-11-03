extends GutTest
## The reachability proof with mechanisms in it: the channel mask in the
## search state (scripts/levels/reach_model.gd, scripts/levels/reach_search.gd)
## proved on the one toy the framework ships with -- a permanent plate that
## opens a gate -- plus a trapdoor, which is the same gate laid in a floor.
##
## The toys exist only here and say nothing but how they change passability:
## the plate latches its channel when stood on, the gate is stone until its
## channel is on. What is held is the generic part every real mechanism will
## lean on: a gate is passable only through its plate; a latch that takes the
## floor takes the prince with it; a checkpoint is proved with every wire off
## and inherits nothing from a state with one on; and the flood finds the
## state that is a trap.

## A ceiling over the corridor, so nothing is jumped over or climbed round.
const GATEHOUSE := """;! mark 1 reach_plate channel=a
;! mark 2 reach_gate channel=a
; Proof Gatehouse






###############
       2
  @ 1  2  t  D
###############
###############
"""

const NO_PLATE := """;! mark 2 reach_gate channel=a
; No Plate






###############
       2
  @    2     D
###############
###############
"""

## The plate is beyond the gate it opens, and the torch before it.
const BEHIND := """;! mark 1 reach_plate channel=a
;! mark 2 reach_gate channel=a
; Behind






###############
       2
  @  t 2  1  D
###############
###############
"""

## A two-wide plate over a two-wide trapdoor over a shaft too deep to climb,
## under a ceiling too low to jump the plate.
const TRAPDOOR := """;! mark 1 reach_plate channel=a
;! mark 2 reach_gate channel=a
; Trapdoor




##############

  @  11     D
#####22#######
#####  #######
#####  #######
#####  #######
#####  #######
#####  #######
#####  #######
##############
"""


## Stood on, its channel is on for good.
class ReachPlate extends Mechanism:
	static func reach(mark: Dictionary, model: ReachModel) -> void:
		model.latch_on_stand(Mechanism.mark_cells(mark), Mechanism.mark_channel(mark))


## Stone until its channel is on, then air.
class ReachGate extends Mechanism:
	static func reach(mark: Dictionary, model: ReachModel) -> void:
		model.switch_cells(Mechanism.mark_cells(mark), Mechanism.mark_channel(mark),
			Tiles.Kind.SOLID, Tiles.Kind.EMPTY)


## A mechanism that says nothing to the proof: it only gives light.
class Lamp extends Mechanism:
	var lit := true


func before_all() -> void:
	EntityRegistry.add_for_test("reach_plate", ReachPlate)
	EntityRegistry.add_for_test("reach_gate", ReachGate)
	EntityRegistry.add_for_test("reach_lamp", Lamp)


func after_all() -> void:
	for kind: String in ["reach_plate", "reach_gate", "reach_lamp"]:
		EntityRegistry.remove_for_test(kind)


func _parse(text: String) -> AsciiLevel:
	var level := AsciiLevel.new()
	level.parse(text)
	return level


func test_the_marks_describe_themselves_to_the_model() -> void:
	var model := ReachModel.for_level(_parse(GATEHOUSE))
	assert_false(model.is_empty(), "the plate and the gate said something")
	assert_eq(model.channel_count(), 1, "one wire")
	assert_eq(model.after_standing(0, Vector2i(4, 8)), 1, "standing on the plate sets it")
	assert_eq(model.after_standing(0, Vector2i(5, 8)), 0, "standing beside it does not")
	assert_eq(model.kinds_for(0)[Vector2i(7, 7)], Tiles.Kind.SOLID, "the gate is shut with it off")
	assert_eq(model.kinds_for(1)[Vector2i(7, 8)], Tiles.Kind.EMPTY, "and open with it on")


func test_a_mechanism_with_nothing_to_say_leaves_the_model_empty() -> void:
	var level := _parse(""";! mark 9 reach_lamp
; Lamplit


 @ 9 D
#######
""")
	assert_true(ReachModel.for_level(level).is_empty(),
		"the inherited hook says nothing, so the level is proved as if it were not there")


func test_the_gate_is_passable_only_through_its_plate() -> void:
	assert_true(bool(LevelReachability.verify(_parse(GATEHOUSE))["ok"]),
		"with the plate before it, the way is open")
	var shut := LevelReachability.verify(_parse(NO_PLATE))
	assert_false(bool(shut["ok"]), "with no plate, the gate is a wall")
	assert_false(bool(LevelReachability.verify(_parse(BEHIND))["ok"]),
		"and with the plate beyond it, it might as well have none")


func test_a_latch_that_takes_the_floor_takes_the_prince() -> void:
	var walkway := _parse(TRAPDOOR.replace("#####22#######", "##############"))
	assert_true(bool(LevelReachability.verify(walkway)["ok"]),
		"without the trapdoor the plate is just floor")
	var level := _parse(TRAPDOOR)
	assert_false(bool(LevelReachability.verify(level)["ok"]),
		"with it, every way across stands on the plate and drops him")

	var solver := LevelReachability.Solver.new(level, ReachModel.for_level(level))
	var landed: Array[int] = []
	var on_plate := solver.cell_key(LevelReachability.MODE_STAND, 5, 6)
	ReachSearch.arrive(solver, on_plate, 0, landed)
	assert_false(landed.is_empty(), "he arrives somewhere")
	for state: int in landed:
		var index := (state & ReachSearch.LOW_MASK) >> 1
		assert_eq(index / solver.cols, 13, "at the bottom of the shaft, not on the plate")
		assert_eq(state >> ReachSearch.MASK_SHIFT, 1, "with the plate's wire on")


func test_the_flood_finds_the_trap_as_a_state() -> void:
	var played := LevelReachability.survey(_parse(TRAPDOOR))
	var stranded: Dictionary = played["stranded"]
	assert_true(stranded.has(Vector2i(5, 13)), "the shaft's floor is a dead end")
	assert_false((played["stranded_states"] as Dictionary).is_empty(),
		"and the flood names the state")


func test_a_checkpoint_is_proved_with_every_wire_off() -> void:
	assert_eq(Game.checkpoint_cells(_parse(GATEHOUSE)), [Vector2i(10, 8)] as Array[Vector2i],
		"a torch past the gate leads to the door")
	assert_eq(Game.checkpoint_cells(_parse(BEHIND)), [] as Array[Vector2i],
		"one before a gate whose plate is out of reach does not")


func test_a_proved_cell_is_only_as_good_as_the_state_it_was_proved_in() -> void:
	var level := _parse(GATEHOUSE)
	var solver := LevelReachability.Solver.new(level, ReachModel.for_level(level))
	var no_exits: Array[Vector2i] = []
	var near: Array[Vector2i] = [Vector2i(3, 8)]
	assert_true(bool(ReachSearch.search(solver, level.spawn_point, no_exits, near)["ok"]),
		"a proved cell reached with every wire off counts as the door")
	var far: Array[Vector2i] = [Vector2i(10, 8)]
	assert_false(bool(ReachSearch.search(solver, level.spawn_point, no_exits, far)["ok"]),
		"one reached only with the plate down does not inherit a proof made with it up")
