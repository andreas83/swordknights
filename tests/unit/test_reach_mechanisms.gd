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
## floor takes the prince with it; the flood finds the state that is a trap;
## and a checkpoint, because a respawn keeps what was latched, is proved from
## every mask the prince can be standing on it under -- which can cost a torch
## its checkpoint, or be the only reason it has one.
##
## Then the same gate drafted the way the campaign is: a stone plate and a
## portcullis carrying one mason's mark, and the plate's hook asking the wire
## what a press means. Only a latch is something the proof can lean on.

## A ceiling over the corridor, so nothing is jumped over or climbed round.
const GATEHOUSE := """;! mark k reach_plate channel=a
;! mark m reach_gate channel=a
; Proof Gatehouse






###############
       m
  @ k  m  t  D
###############
###############
"""

const NO_PLATE := """;! mark m reach_gate channel=a
; No Plate






###############
       m
  @    m     D
###############
###############
"""

## The plate is beyond the gate it opens, and the torch before it.
const BEHIND := """;! mark k reach_plate channel=a
;! mark m reach_gate channel=a
; Behind






###############
       m
  @  t m  k  D
###############
###############
"""

## The torch is in a side room past the gate, and the door is back before it:
## a checkpoint only because the gate stays open behind him.
const SIDE_ROOM := """;! mark k reach_plate channel=a
;! mark m reach_gate channel=a
; Side Room






###############
         m
  @ k  D m  t
###############
###############
"""

## A plate behind the spawn that drops the bridge past the torch -- three
## cells, too wide to jump under that ceiling -- so he can take the torch
## with the bridge already gone.
const BRIDGE := """;! mark k reach_plate channel=a
;! mark m reach_gate channel=a
; Bridge




##############

 k @ t     D
######mmm#####
######   #####
######   #####
######   #####
######   #####
######   #####
######   #####
##############
"""

## A two-wide plate over a two-wide trapdoor over a shaft too deep to climb,
## under a ceiling too low to jump the plate.
const TRAPDOOR := """;! mark k reach_plate channel=a
;! mark m reach_gate channel=a
; Trapdoor




##############

  @  kk     D
#####mm#######
#####  #######
#####  #######
#####  #######
#####  #######
#####  #######
#####  #######
##############
"""


## The campaign's drafting, in miniature: the plate is a floor stone with its
## mark under it, the gate hangs from a lintel carrying the same mark, and a
## `;! channel` line says the wire latches.
const MASONS := """;! channel 1 latch
; Masons' Gatehouse






#######1#######
       !
  @    !  t  D
###o###########
###1###########
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


## A floor stone wired by its mason's mark: stood on from the cell above it,
## and what that does is its wire's. A momentary or held wire is down only
## while he stands there, or for a race the proof has no clock for, so only
## a latch is said.
class StonePlate extends Mechanism:
	static func reach(mark: Dictionary, model: ReachModel) -> void:
		var channel := Mechanism.mark_channel(mark)
		if model.channel_mode(channel) == "latch":
			model.latch_on_stand(Mechanism.cells_above(Mechanism.mark_cells(mark)), channel)


## A mechanism that says nothing to the proof: it only gives light.
class Lamp extends Mechanism:
	var lit := true


func before_all() -> void:
	Tiles.add_mechanism_for_test("o", "reach_stone_plate", Tiles.Kind.SOLID)
	Tiles.add_mechanism_for_test("!", "reach_gate")
	EntityRegistry.add_for_test("reach_plate", ReachPlate)
	EntityRegistry.add_for_test("reach_gate", ReachGate)
	EntityRegistry.add_for_test("reach_lamp", Lamp)
	EntityRegistry.add_for_test("reach_stone_plate", StonePlate)


func after_all() -> void:
	Tiles.remove_mechanism_for_test("o")
	Tiles.remove_mechanism_for_test("!")
	for kind: String in ["reach_plate", "reach_gate", "reach_lamp", "reach_stone_plate"]:
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
	var level := _parse(""";! mark u reach_lamp
; Lamplit


 @ u D
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
	var walkway := _parse(TRAPDOOR.replace("#####mm#######", "##############"))
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


func test_a_checkpoint_is_proved_under_the_latches_it_can_be_claimed_with() -> void:
	assert_eq(Game.checkpoint_cells(_parse(GATEHOUSE)), [Vector2i(10, 8)] as Array[Vector2i],
		"a torch past the gate leads to the door")
	assert_eq(Game.checkpoint_cells(_parse(BEHIND)), [] as Array[Vector2i],
		"one before a gate whose plate is out of reach does not")
	var level := _parse(GATEHOUSE)
	var solver := LevelReachability.Solver.new(level, ReachModel.for_level(level))
	var torch: Array[Vector2i] = [Vector2i(10, 8)]
	var claims: Dictionary = ReachSearch.standing_masks(solver, level.spawn_point, torch)["masks"]
	assert_eq(claims.get(Vector2i(10, 8)), [1] as Array[int],
		"the torch past the gate is only ever taken with the wire on")


func test_a_respawn_that_keeps_a_latch_can_be_the_only_way_back() -> void:
	var level := _parse(SIDE_ROOM)
	assert_true(bool(LevelReachability.verify(level)["ok"]), "the door needs no gate")
	assert_false(bool(LevelReachability.verify_from(level, Vector2i(12, 8))["ok"]),
		"with every wire off, the side room is a cell")
	assert_eq(Game.checkpoint_cells(level), [Vector2i(12, 8)] as Array[Vector2i],
		"but he can only be in it with the gate open, and the respawn keeps it open")


func test_a_torch_he_can_take_with_the_bridge_gone_is_no_checkpoint() -> void:
	assert_eq(Game.checkpoint_cells(_parse(BRIDGE)), [] as Array[Vector2i],
		"a respawn would keep the fallen bridge between the torch and the door")
	var no_plate := _parse(BRIDGE.replace(" k @", "   @"))
	assert_eq(Game.checkpoint_cells(no_plate), [Vector2i(5, 6)] as Array[Vector2i],
		"with no plate to drop it, the same torch is a checkpoint")


func test_a_proved_cell_is_only_as_good_as_the_state_it_was_proved_in() -> void:
	var level := _parse(GATEHOUSE)
	var solver := LevelReachability.Solver.new(level, ReachModel.for_level(level))
	var no_exits: Array[Vector2i] = []
	var off: Array[int] = [0]
	var on: Array[int] = [1]
	var near := ReachSearch.states_of(solver, [Vector2i(3, 8)] as Array[Vector2i], off)
	assert_true(bool(ReachSearch.search(solver, level.spawn_point, no_exits, near)["ok"]),
		"a place proved with every wire off counts as the door when he gets there so")
	var far := ReachSearch.states_of(solver, [Vector2i(10, 8)] as Array[Vector2i], off)
	assert_false(bool(ReachSearch.search(solver, level.spawn_point, no_exits, far)["ok"]),
		"one he only gets to with the wire on does not inherit a proof made with it off")
	far = ReachSearch.states_of(solver, [Vector2i(10, 8)] as Array[Vector2i], on)
	assert_true(bool(ReachSearch.search(solver, level.spawn_point, no_exits, far)["ok"]),
		"and does inherit one made with it on")


func test_a_stone_plate_on_a_latched_wire_opens_the_gate_on_its_mark() -> void:
	var level := _parse(MASONS)
	assert_eq(level.problems, PackedStringArray(), "the drafted gatehouse parses clean")
	var model := ReachModel.for_level(level)
	assert_eq(model.after_standing(0, Vector2i(3, 8)), 1,
		"standing on the stone -- in the cell above it -- sets wire 1")
	assert_eq(model.after_standing(0, Vector2i(3, 9)), 0, "the stone itself is not stood in")
	assert_eq(model.kinds_for(0)[Vector2i(7, 8)], Tiles.Kind.SOLID, "the gate on mark 1 is shut")
	assert_true(bool(LevelReachability.verify(level)["ok"]), "and the latch opens the way")
	assert_eq(Game.checkpoint_cells(level), [Vector2i(10, 8)] as Array[Vector2i],
		"the torch past the gate is proved with every wire off")


func test_a_stone_plate_on_any_other_wire_is_only_floor() -> void:
	var momentary := _parse(MASONS.replace(";! channel 1 latch\n", ""))
	assert_eq(momentary.channels, {}, "no channel line: wire 1 is momentary")
	assert_false(bool(LevelReachability.verify(momentary)["ok"]),
		"he cannot stand on the plate and walk through the gate it holds")
	var held := _parse(MASONS.replace("latch", "hold 3.0"))
	assert_false(bool(LevelReachability.verify(held)["ok"]),
		"and a held gate is a race the proof does not claim")
