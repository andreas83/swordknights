extends GutTest
## Crumbling stone (scripts/mechanisms/crumbling_stone.gd) in the real game
## scene, and in the proof (scripts/levels/crumble_audit.gd).
##
## In play: the fuse is the game's telegraph and is lit by feet alone; a
## walker goes through a run and a runner does not; a slab that drops lights
## its neighbours for the chain; the assist stretches both; a cat breaks what
## it pushes off; a sentinel turns at it; a respawn puts every slab back.
##
## In the proof: a run is crossed by a leap and the floor can be the door;
## a crumbling ledge is grabbed, stood on and left; the design rule refuses a
## four-slab run and a run that ends on one stone; and the collapse audit
## finds the walker who fell into a pit he cannot leave.

const GAME_SCENE := "res://scenes/game.tscn"
const FLOOR_Y := 6.0 * 16.0

## Three slabs over a cellar two deep, a runway either side. Rows 0-4 are air.
const CELLAR := """; Crumble Cellar





  @                     D
#########,,,#############
#########   #############
#########   #############
#########################
"""

## A crumbling stone jutting from a wall, three tiles over the floor: grab
## it, and stand.
const LEDGE := """; Crumble Ledge





       ,####
        ####
        ####   D
  @     ####
################
"""

## A sentinel walking east at a run of slabs over the void, with the prince
## across it, out of his reach.
const SENTRY := """; Crumble Sentry





        p           @ D
############,,,#########
############   #########
############   #########
############   #########
"""

## The only way on is down through the floor: a roofed deck, its floor one
## slab over a room with the door in it. Stepping off it leaves it on stone,
## so standing still is the only way through.
const TRAPDOOR := """; Floor Is The Door




##############

  @          #
######,#######
#            #
#  D         #
##############
"""

## R2's shape: a jutting crumbling stone below a tower's top, and a relic
## on the top that nothing else reaches.
const TOWER := """; Crumble Tower



      *
     ####
     ####
    ,####
     ####
     ####
  @  ####      D
###############
"""

## A walker on these slabs drops into a shaft too deep to climb.
const PIT := """; Crumble Pit




  @          D
######,,#######
######  #######
######  #######
######  #######
######  #######
######  #######
###############
"""

const FOUR := """; Crumble Four




  @               D
#####,,,,##########
#####    ##########
"""

const ONE_STONE := """; Crumble Lone Stone




  @               D
#####,,,#,,,#######
#####   #   #######
"""


class ScriptedInput extends PlayerInput:
	var bits := 0

	func poll() -> void:
		apply_bits(bits)


var _game: Game
var _input: ScriptedInput


## Unassisted unless a test says otherwise, whatever ran before it -- and a
## test that turns the assist on saves it here, never over the player's own
## user://assist.cfg, which the next game to boot would read.
const ASSIST_PATH := "user://test_crumbling_assist.cfg"


func before_each() -> void:
	Assist.reset()
	Assist.load_saved(ASSIST_PATH)


func after_each() -> void:
	Assist.reset()
	if FileAccess.file_exists(ASSIST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ASSIST_PATH))


func _play(text: String) -> void:
	var data := AsciiLevel.new()
	data.parse(text)
	assert_eq(data.problems, PackedStringArray(), "the level parses clean")
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Game
	_game.level_source = data
	add_child_autofree(_game)
	_input = ScriptedInput.new()
	_game.player.input = _input
	await wait_physics_frames(6)


func _stone() -> CrumblingStone:
	for node: Node in _game.get_node("Entities").get_children():
		if node is CrumblingStone and not node.is_queued_for_deletion():
			return node as CrumblingStone
	return null


func _parse(text: String) -> AsciiLevel:
	var level := AsciiLevel.new()
	level.parse(text)
	return level


## Puts the prince's feet at the middle of `cell`'s top, at rest.
func _stand_on(cell: Vector2i) -> void:
	_game.player.position = Vector2(cell.x * 16.0 + 8.0, cell.y * 16.0)
	_game.player.velocity = Vector2.ZERO


## --- the numbers ---------------------------------------------------------------

func test_the_fuse_is_the_games_telegraph_and_the_chain_four_tiles_a_second() -> void:
	var stone := CrumblingStone.new()
	assert_eq(stone.fuse_frames(), roundi(Patrol.WINDUP_TIME * 60.0), "27 frames: 'now'")
	assert_eq(stone.fuse_frames(), 27)
	assert_eq(stone.chain_frames(), 15, "15 frames a slab")
	assert_almost_eq(60.0 / float(stone.chain_frames()), 4.0, 0.01, "four tiles a second")
	assert_lt(60.0 / float(stone.chain_frames()), Tuning.RUN_SPEED / 16.0, "slower than a run")
	assert_gt(60.0 / float(stone.chain_frames()), Tuning.WALK_SPEED / 16.0, "faster than a walk")
	assert_eq(Assist.set_longer_warnings(true), OK, "saved to the test's own file")
	assert_eq(stone.fuse_frames(), roundi(27.0 * Assist.LONGER), "the assist stretches the fuse")
	assert_eq(stone.chain_frames(), roundi(15.0 * Assist.LONGER), "and the chain")
	stone.free()


## --- in play -----------------------------------------------------------------------

func test_a_walker_falls_through_and_a_runner_does_not() -> void:
	await _play(CELLAR)
	_input.bits = PlayerInput.BIT_RIGHT | PlayerInput.BIT_WALK
	var fell := false
	for _frame: int in 360:
		await wait_physics_frames(1)
		if _game.player.position.y > FLOOR_Y + 8.0:
			fell = true
			break
	assert_true(fell, "walking, he is over a slab longer than its fuse: into the cellar")

	await _play(CELLAR)
	_input.bits = PlayerInput.BIT_RIGHT
	var lowest := 0.0
	for _frame: int in 150:
		await wait_physics_frames(1)
		lowest = maxf(lowest, _game.player.position.y)
	assert_almost_eq(lowest, FLOOR_Y, 0.5, "running, every slab is behind him before it goes")
	assert_gt(_game.player.position.x, 13.0 * 16.0, "and he is across")
	var stone := _stone()
	for index: int in 3:
		assert_false(stone.holds(index), "slab %d fell behind him" % index)


func test_a_slab_holds_for_exactly_the_fuse_then_drops_him() -> void:
	await _play(CELLAR)
	_stand_on(Vector2i(9, 5))
	var stone := _stone()
	var lit_on := -1
	var gone_on := -1
	for _step: int in 80:
		await get_tree().physics_frame
		var frame := Engine.get_physics_frames()
		if lit_on < 0 and stone.is_lit(0):
			lit_on = frame
		if gone_on < 0 and not stone.holds(0):
			gone_on = frame
	assert_gt(lit_on, -1, "his feet lit it")
	assert_eq(gone_on - lit_on, 27, "it held him for the fuse, to the frame")
	await wait_physics_frames(30)
	assert_gt(_game.player.position.y, FLOOR_Y + 8.0, "and let him down")


func test_with_longer_warnings_a_slab_holds_for_the_stretched_fuse() -> void:
	Assist.set_longer_warnings(true)
	await _play(CELLAR)
	_stand_on(Vector2i(9, 5))
	var stone := _stone()
	var lit_on := -1
	var gone_on := -1
	for _step: int in 100:
		await get_tree().physics_frame
		var frame := Engine.get_physics_frames()
		if lit_on < 0 and stone.is_lit(0):
			lit_on = frame
		if gone_on < 0 and not stone.holds(0):
			gone_on = frame
	assert_eq(gone_on - lit_on, roundi(27.0 * Assist.LONGER), "41 frames")


func test_a_fallen_slab_lights_its_neighbours_for_the_chain() -> void:
	await _play(CELLAR)
	_stand_on(Vector2i(9, 5))
	var stone := _stone()
	var gone := [-1, -1, -1]
	for _step: int in 120:
		await get_tree().physics_frame
		var frame := Engine.get_physics_frames()
		for index: int in 3:
			if int(gone[index]) < 0 and not stone.holds(index):
				gone[index] = frame
	assert_eq(int(gone[1]) - int(gone[0]), 15, "the next one 15 frames after")
	assert_eq(int(gone[2]) - int(gone[1]), 15, "and the next")


func test_hands_do_not_light_it_and_feet_do() -> void:
	await _play(LEDGE)
	var stone := _stone()
	# Clear of the stone, so his head misses it and his hand finds it.
	_game.player.position = Vector2(100.0, 144.0)
	_game.player.velocity = Vector2.ZERO
	await wait_physics_frames(2)
	_input.bits = PlayerInput.BIT_RIGHT | PlayerInput.BIT_JUMP
	var hung := false
	for _frame: int in 60:
		await wait_physics_frames(1)
		if _game.player.state == Player.State.HANG:
			hung = true
			break
	assert_true(hung, "he caught the crumbling stone's edge")
	_input.bits = 0
	await wait_physics_frames(40)
	assert_eq(_game.player.state, Player.State.HANG, "still hanging")
	assert_false(stone.is_lit(0), "hands on it light nothing")
	_input.bits = PlayerInput.BIT_UP
	for _frame: int in 40:
		await wait_physics_frames(1)
		if stone.is_lit(0):
			break
	assert_true(stone.is_lit(0), "feet on it do")


func test_a_cat_breaks_what_it_pushes_off_and_the_run_follows() -> void:
	await _play(CELLAR)
	var stone := _stone()
	var at := Vector2(10.0 * 16.0 + 8.0, FLOOR_Y)
	assert_true(CrumblingStone.break_under(_game.level, at), "the middle slab breaks at once")
	assert_false(stone.holds(1), "no fuse")
	assert_false(_game.level.is_solid_cell(Vector2i(10, 6)), "out of the overlay at once")
	await wait_physics_frames(16)
	assert_false(stone.holds(0), "the chain took the slab to its west")
	assert_false(stone.holds(2), "and to its east")
	assert_false(CrumblingStone.break_under(_game.level, at), "nothing left to break")


func test_a_sentinel_treats_crumbling_stone_as_the_end_of_his_beat() -> void:
	await _play(SENTRY)
	var guard: Patrol = null
	for node: Node in _game.get_node("Entities").get_children():
		if node is Patrol:
			guard = node as Patrol
	assert_not_null(guard, "the sentinel is posted")
	guard.facing = 1
	var furthest := 0.0
	for _frame: int in 600:
		await wait_physics_frames(1)
		furthest = maxf(furthest, guard.position.x + Patrol.BODY.x * 0.5)
	assert_lt(furthest, 12.0 * 16.0 + 0.5, "he never set foot on it")
	assert_true(_stone().holds(0), "and it stands")


func test_a_respawn_puts_every_slab_back() -> void:
	await _play(CELLAR)
	for column: int in [9, 10, 11]:
		CrumblingStone.break_under(_game.level, Vector2(column * 16.0 + 8.0, FLOOR_Y))
	await wait_physics_frames(2)
	assert_false(_game.level.is_solid_cell(Vector2i(10, 6)), "the run is down")
	_game.call(&"_respawn")
	await wait_physics_frames(2)
	var stone := _stone()
	for index: int in 3:
		assert_true(stone.holds(index), "slab %d is whole again: a trap resets" % index)
	assert_true(_game.level.is_solid_cell(Vector2i(10, 6)), "and solid to his probes")


## --- the proof ---------------------------------------------------------------------

func test_the_proof_leaps_a_run_and_never_waits_on_one() -> void:
	var cellar := _parse(CELLAR)
	assert_true(bool(LevelReachability.verify(cellar)["ok"]), "a run is a gap with a floor in it")
	var survey := LevelReachability.survey(cellar)
	assert_true(bool(survey["ok"]), "the door is reached")
	assert_true((survey["reached"] as Dictionary).has(Vector2i(10, 8)),
		"and the flood stood on a slab, waited, and went through into the cellar")


func test_the_floor_is_the_door() -> void:
	assert_true(bool(LevelReachability.verify(_parse(TRAPDOOR))["ok"]),
		"stand on the slab, let it go, and fall to the door")


func test_a_crumbling_ledge_can_be_grabbed_stood_on_and_left_at_once() -> void:
	var tower := _parse(TOWER)
	var relic := Vector2i(6, 3)
	var goals: Array[Vector2i] = [relic]
	assert_true(bool(LevelReachability.reaches(tower, goals)["ok"]),
		"the relic on the top: grab the stone, stand, jump and grab the top")
	var solid := tower.copy()
	solid.set_kind(4, 6, Tiles.Kind.EMPTY)
	for mark: Dictionary in solid.entities:
		if String(mark["kind"]) == "crumbling":
			mark["kind"] = "nothing_here"
	assert_false(bool(LevelReachability.reaches(solid, goals)["ok"]),
		"and without the stone there is no way up: the slab is the route")


func test_the_design_rule_refuses_a_four_slab_run_and_a_lone_stone() -> void:
	assert_eq(CrumbleAudit.check_runs(_parse(CELLAR)), PackedStringArray(), "three is allowed")
	var four := CrumbleAudit.check_runs(_parse(FOUR))
	assert_eq(four.size(), 1, "four is not")
	assert_string_contains(four[0] if not four.is_empty() else "", "4 long")
	var lone := CrumbleAudit.check_runs(_parse(ONE_STONE))
	assert_gt(lone.size(), 0, "a run ending on one stone is not")
	assert_false(bool(CrumbleAudit.audit(_parse(FOUR))["ok"]), "and the audit says so")


func test_the_collapse_audit_finds_the_walker_in_the_pit() -> void:
	var report := CrumbleAudit.audit(_parse(PIT))
	assert_false(bool(report["ok"]), "a walker on these slabs is never getting out")
	assert_string_contains(String(report["reason"]), "with every slab whole",
		"and it is the walker who finds it, with nothing broken by anybody else")
	var cellar := CrumbleAudit.audit(_parse(CELLAR))
	assert_true(bool(cellar["ok"]), "while the cellar is climbed out of: %s" % cellar["reason"])
	assert_gt(int(cellar["subsets"]), 0, "having broken the run on purpose")


func test_every_slab_is_a_trap_so_a_torch_is_proved_on_the_whole_level() -> void:
	var model := ReachModel.for_level(_parse(CELLAR))
	assert_true(model.only_traps(), "a crumbling run is a trap")
	var bit := 1 << model.bit(CrumblingStone.wire_of(CrumbleAudit.runs_of(_parse(CELLAR))[0]))
	assert_eq(model.respawn_mask(bit), 0, "a respawn puts it back")



func test_whatever_leaves_a_slab_leaves_it_falling() -> void:
	var level := _parse(TRAPDOOR)
	var solver := LevelReachability.Solver.new(level, ReachModel.for_level(level))
	var on_slab := solver.cell_key(LevelReachability.MODE_STAND, 6, 6)
	var on_stone := solver.cell_key(LevelReachability.MODE_STAND, 4, 6)
	assert_ne(ReachSearch._leaving(solver, on_slab), 0, "every move off a slab burns its fuse")
	assert_eq(ReachSearch._leaving(solver, on_stone), 0, "and off stone nothing burns")
	var landed: Array[int] = []
	ReachSearch.arrive(solver, on_slab, ReachSearch._leaving(solver, on_slab), landed, 0, 0)
	assert_eq(landed.size(), 1, "coming down where the slab was, with it gone,")
	assert_ne(landed[0] & ReachSearch.LOW_MASK, on_slab, "is falling through it")
