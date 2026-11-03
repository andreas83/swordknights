extends GutTest
## The lift (scripts/mechanisms/lift.gd), played through the real game scene:
## a stone slab that carries whatever stands on it between its two stops.
##
## What is held here, each against the bible's numbers (docs/campaign.md,
## "Counterweights"):
##
## - the glyphs: `[ ]` and `'` are one mechanism, and which end of the run
##   the slab is drawn at decides which way it goes;
## - ridden: it leaves DEPART_FRAMES after a body stands on it, travels at a
##   walk's 40 px/s with the prince on it, and waits at the far stop until
##   it has been empty for RETURN_FRAMES; stepping off early keeps it home,
##   and a rider who stays aboard is not ferried back;
## - it never moves into a body: one in the pit its home stop leaves is waited
##   above, not crushed;
## - wired: it is at its far stop while its channel is on;
## - the overlay: stone at rest, nothing while it moves;
## - the proof: a ladder between its stops, which is the only way up here;
## - a respawn puts it home, where the level text drew it.

const GAME_SCENE := "res://scenes/game.tscn"
const DeathWatch := preload("res://tests/death_watch.gd")

## Five courses up from the floor to a landing too high to jump or grab: the
## lift court of Chapter II in miniature. The slab is drawn at the bottom, so
## it goes up.
const COURT := """; Lift Court

                 D
         ''#########
         ''#########
         ''#########
         ''#########
  @      ''#########
#########[]#########
####################
"""

const HOME_ROW := 7
const FAR_ROW := 2
## Five courses at 40 px/s.
const TRAVEL_FRAMES := 120

## The same court, wired: a toy plate on mark 1 behind the spawn holds it up.
const WIRED := """;! channel 1 latch
;! mark k toy_plate channel=1
; Wired Court

                 D
         ''#########
         ''#########
         ''#########
         ''#########
 k@      ''#########
#########[]1########
####################
"""

## The court with its slab drawn at the top: a lift that goes down.
const DOWNWARD := """; Down Court

         []
         ''
         ''
  @      ''      D
#########''#########
####################
"""


## Down while stood on; a latch on its wire is the level's to say.
class ToyPlate extends Mechanism:
	var pressed := false

	func meet(contact: Contact) -> void:
		var on := feet_on(contact)
		if on and not pressed:
			bus.press(channel, self)
		elif pressed and not on:
			bus.release(channel, self)
		pressed = on


class ScriptedInput extends PlayerInput:
	var bits := 0

	func poll() -> void:
		apply_bits(bits)


var _game: Game
var _input: ScriptedInput


func before_all() -> void:
	EntityRegistry.add_for_test("toy_plate", ToyPlate)


func after_all() -> void:
	EntityRegistry.remove_for_test("toy_plate")


func _parse(text: String) -> AsciiLevel:
	var data := AsciiLevel.new()
	data.parse(text)
	return data


func _play(text: String = COURT) -> void:
	var data := _parse(text)
	assert_eq(data.problems, PackedStringArray(), "the court parses clean")
	assert_eq(EntityRegistry.problems_in(data), PackedStringArray(), "and is wired")
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Game
	_game.level_source = data
	add_child_autofree(_game)
	_input = ScriptedInput.new()
	_game.player.input = _input
	await wait_physics_frames(6)


func _lift() -> Lift:
	for node: Node in _game.get_node("Entities").get_children():
		if node is Lift and not node.is_queued_for_deletion():
			return node as Lift
	return null


func _home_top() -> float:
	return float(HOME_ROW) * Tuning.TILE


func _far_top() -> float:
	return float(FAR_ROW) * Tuning.TILE


## Drives the game one physics tick at a time: on every tick `step` gets the
## tick's index and answers the input bits for it, or -1 to stop. Returns the
## ticks it ran. GUT's wait_physics_frames(1) waits two ticks, so anything
## counted in frames is counted here, from the tree's own signal, which fires
## just before every node's _physics_process.
func _drive(step: Callable, limit: int) -> int:
	var run := {"tick": 0, "done": false}
	var on_tick := func() -> void:
		if bool(run["done"]) or not is_instance_valid(_game):
			return
		var bits := int(step.call(int(run["tick"])))
		if bits < 0 or int(run["tick"]) >= limit:
			run["done"] = true
			_input.bits = 0
			return
		_input.bits = bits
		run["tick"] = int(run["tick"]) + 1
	get_tree().physics_frame.connect(on_tick)
	while not bool(run["done"]):
		await wait_physics_frames(1)
	get_tree().physics_frame.disconnect(on_tick)
	return int(run["tick"])


## Standing on the slab as its rider: grounded, feet on its top, their middle
## over it.
func _aboard() -> bool:
	var lift := _lift()
	var player := _game.player
	return player.is_grounded() and absf(player.position.y - lift.top) <= Weight.TOLERANCE \
		and player.position.x >= lift.left() and player.position.x < lift.left() + lift.width()


## Right until he stands on the slab, then still until he has stopped.
func _board() -> void:
	await _drive(func(_t: int) -> int: return -1 if _aboard() else PlayerInput.BIT_RIGHT, 240)
	await _drive(func(_t: int) -> int: return -1 if is_zero_approx(_game.player.velocity.x) else 0,
		30)


## Ticks until `done` says so, holding still, or `limit`.
func _ticks_until(done: Callable, limit: int) -> int:
	return await _drive(func(_t: int) -> int: return -1 if bool(done.call()) else 0, limit)


func _ride_up() -> void:
	await _board()
	await _ticks_until(func() -> bool: return _lift().moving, 60)
	await _ticks_until(func() -> bool: return not _lift().moving, TRAVEL_FRAMES + 30)


## --- what it is ------------------------------------------------------------------

func test_its_numbers_are_the_bibles() -> void:
	assert_eq(Lift.SPEED, 40.0, "a walk's pace: 40 px/s")
	assert_eq(Lift.DEPART_FRAMES, 30, "it leaves 30 frames after a body stands on it")
	assert_eq(Lift.RETURN_FRAMES, 180, "and goes home 180 frames after it is empty")



func test_the_glyphs_are_one_lift_that_knows_its_stops() -> void:
	var data := _parse(COURT)
	var lifts := data.entities.filter(func(m: Dictionary) -> bool: return m["kind"] == "lift")
	assert_eq(lifts.size(), 1, "slab and shaft are one mechanism")
	var shape := Lift.geometry(Mechanism.mark_cells(lifts[0]), lifts[0]["glyphs"])
	assert_eq(int(shape["home"]), HOME_ROW, "home is where the slab is drawn")
	assert_eq(int(shape["far"]), FAR_ROW, "and the far stop is the shaft's other end")
	assert_eq([int(shape["first"]), int(shape["last"])], [9, 10], "two columns wide")

	var down := _parse(DOWNWARD).entities.filter(
		func(m: Dictionary) -> bool: return m["kind"] == "lift")
	var under := Lift.geometry(Mechanism.mark_cells(down[0]), down[0]["glyphs"])
	assert_eq([int(under["home"]), int(under["far"])], [1, 5],
		"drawn at the top, it goes down: Chapter V's throat")


## --- ridden ------------------------------------------------------------------------

func test_a_rider_is_carried_up_after_thirty_frames() -> void:
	await _play()
	var lift := _lift()
	var marks := {"on": -1, "go": -1, "stop": -1}
	var run := func(t: int) -> int:
		if int(marks["on"]) < 0 and _aboard():
			marks["on"] = t
		if int(marks["go"]) < 0 and lift.moving:
			marks["go"] = t
		if int(marks["go"]) >= 0 and not lift.moving:
			marks["stop"] = t
			return -1
		return PlayerInput.BIT_RIGHT if int(marks["on"]) < 0 else 0
	await _drive(run, 600)
	assert_almost_eq(int(marks["go"]) - int(marks["on"]), Lift.DEPART_FRAMES, 1,
		"it leaves thirty frames after he steps on")
	assert_almost_eq(int(marks["stop"]) - int(marks["go"]), TRAVEL_FRAMES, 1,
		"and takes five courses at a walk's 40 px/s")
	assert_eq(lift.top, _far_top(), "flush with the landing")
	await wait_physics_frames(2)
	assert_almost_eq(_game.player.position.y, _far_top(), 1.0, "with him on it")
	assert_true(_game.player.is_grounded(), "on his feet")
	await _drive(func(_t: int) -> int:
		return -1 if _game.phase == Game.Phase.COMPLETE else PlayerInput.BIT_RIGHT, 120)
	assert_eq(_game.phase, Game.Phase.COMPLETE, "and the landing leads to the door")


func test_a_rider_rises_without_falling_off_the_slab() -> void:
	await _play()
	await _board()
	var lift := _lift()
	await _ticks_until(func() -> bool: return lift.moving, 60)
	var worst := [0.0, true]
	var probe := func() -> bool:
		worst[0] = maxf(float(worst[0]), absf(_game.player.position.y - lift.top))
		worst[1] = bool(worst[1]) and _game.player.state != Player.State.FALL
		return not lift.moving
	await _ticks_until(probe, 200)
	assert_lt(float(worst[0]), Weight.TOLERANCE + 0.1, "his feet stay on the slab all the way")
	assert_true(bool(worst[1]), "he never starts falling")


func test_stepping_off_before_it_leaves_keeps_it_home() -> void:
	await _play()
	await _board()
	await _drive(func(_t: int) -> int: return -1 if not _aboard() else PlayerInput.BIT_LEFT, 20)
	await _ticks_until(func() -> bool: return _lift().moving, 90)
	assert_false(_lift().moving, "he stepped off in time")
	assert_eq(_lift().top, _home_top(), "and it never left home")


func test_a_rider_who_stays_on_is_not_ferried_back() -> void:
	await _play()
	await _ride_up()
	await _ticks_until(func() -> bool: return _lift().moving, Lift.DEPART_FRAMES * 3)
	assert_eq(_lift().top, _far_top(), "it waits for him to get off")


func test_an_empty_lift_goes_home_after_its_wait() -> void:
	await _play()
	await _ride_up()
	await _drive(func(_t: int) -> int: return -1 if not _aboard() else PlayerInput.BIT_RIGHT, 30)
	var lift := _lift()
	var waited := await _ticks_until(func() -> bool: return lift.moving, 400)
	assert_almost_eq(waited, Lift.RETURN_FRAMES, 2, "three seconds empty, then home")
	await _ticks_until(func() -> bool: return not lift.moving, 200)
	assert_eq(lift.top, _home_top(), "home, where the level drew it")


## --- it never moves into a body -------------------------------------------------

func test_it_waits_above_a_body_in_its_way() -> void:
	await _play()
	await _ride_up()
	# Off the top, then down into the pit its home stop has left: the cell the
	# slab will come back to.
	await _drive(func(_t: int) -> int: return -1 if not _aboard() else PlayerInput.BIT_RIGHT, 30)
	_game.player.position = Vector2(9.5 * Tuning.TILE, float(HOME_ROW + 1) * Tuning.TILE)
	_game.player.velocity = Vector2.ZERO
	var lift := _lift()
	await _ticks_until(func() -> bool: return lift.moving, Lift.RETURN_FRAMES + 20)
	await _ticks_until(func() -> bool: return false, TRAVEL_FRAMES + 20)
	var head := _game.player.position.y - Tuning.BODY_HEIGHT
	assert_true(_game.player.is_alive(), "nothing crushed him")
	assert_true(lift.moving, "it is still on its way home")
	assert_almost_eq(lift.top + Tuning.TILE, head - Lift.CLEARANCE, 1.0,
		"waiting two tiles over his head")
	var hop := func(t: int) -> int:
		if t > 8 and _game.player.is_grounded():
			return -1
		return PlayerInput.BIT_LEFT | (PlayerInput.BIT_JUMP if t < 12 else 0)
	await _drive(hop, 90)
	assert_lt(_game.player.position.y, float(HOME_ROW) * Tuning.TILE + 0.5,
		"which is room enough to hop out of the pit")
	await _ticks_until(func() -> bool: return not lift.moving, 120)
	assert_eq(lift.top, _home_top(), "and then it comes the rest of the way")


## --- wired ---------------------------------------------------------------------------

func test_a_wired_lift_is_at_its_far_stop_while_its_channel_is_on() -> void:
	await _play(WIRED)
	var lift := _lift()
	assert_eq(lift.channel, &"1", "the mark beside its slab wires it")
	await _board()
	await _ticks_until(func() -> bool: return lift.moving, Lift.DEPART_FRAMES * 2)
	assert_eq(lift.top, _home_top(), "standing on a wired lift does nothing")
	await _drive(func(_t: int) -> int:
		return -1 if _game._bus.is_on(&"1") else PlayerInput.BIT_LEFT, 240)
	assert_true(_game._bus.is_on(&"1"), "the plate behind the spawn latched wire 1")
	await _ticks_until(func() -> bool: return lift.moving, 4)
	await _ticks_until(func() -> bool: return not lift.moving, TRAVEL_FRAMES + 30)
	assert_eq(lift.top, _far_top(), "and the lift went to its far stop")


## --- the overlay ------------------------------------------------------------------

func test_it_is_stone_in_the_overlay_only_at_rest() -> void:
	await _play()
	var level := _game.level
	assert_true(level.is_solid_cell(Vector2i(9, HOME_ROW)), "home: the floor it looks like")
	await _board()
	var lift := _lift()
	await _ticks_until(func() -> bool: return lift.moving, 60)
	await _ticks_until(func() -> bool: return false, 20)
	for row: int in range(FAR_ROW, HOME_ROW + 1):
		assert_false(level.is_solid_cell(Vector2i(9, row)), "moving, it is in no cell: row %d" % row)
	await _ticks_until(func() -> bool: return not lift.moving, 200)
	assert_true(level.is_solid_cell(Vector2i(10, FAR_ROW)), "at the far stop, stone there")
	assert_false(level.is_solid_cell(Vector2i(10, HOME_ROW)), "and its home is a pit")


## --- the proof ------------------------------------------------------------------------

func test_the_proof_climbs_the_lift_as_a_ladder() -> void:
	var data := _parse(COURT)
	var model := ReachModel.for_level(data)
	var kinds := model.kinds_for(0)
	assert_eq(kinds.get(Vector2i(9, FAR_ROW - 1)), Tiles.Kind.LADDER, "from above the far stop")
	assert_eq(kinds.get(Vector2i(10, HOME_ROW - 1)), Tiles.Kind.LADDER, "down to the slab")
	assert_eq(kinds.get(Vector2i(10, HOME_ROW)), Tiles.Kind.SOLID, "which is floor")
	assert_true(bool(LevelReachability.verify(data)["ok"]), "so the landing is reachable")
	var bare := _parse(COURT.replace("''", "  ").replace("[]", "##"))
	assert_false(bool(LevelReachability.verify(bare)["ok"]),
		"and without the lift five courses are out of reach")


func test_the_proof_claims_no_ride_on_a_wired_lift() -> void:
	var model := ReachModel.for_level(_parse(WIRED))
	assert_eq(model.kinds_for(0).get(Vector2i(9, HOME_ROW)), Tiles.Kind.SOLID, "home, wire off")
	assert_eq(model.kinds_for(0).get(Vector2i(9, FAR_ROW)), Tiles.Kind.EMPTY, "the far stop open")
	assert_eq(model.kinds_for(1).get(Vector2i(9, FAR_ROW)), Tiles.Kind.SOLID, "floor, wire on")
	assert_false(model.kinds_for(1).values().has(Tiles.Kind.LADDER), "and never a ladder")


## --- respawn ------------------------------------------------------------------------

func test_a_respawn_puts_it_home() -> void:
	await _play()
	await _ride_up()
	assert_eq(_lift().top, _far_top(), "up")
	DeathWatch.expect_deaths(1)
	_game.player.kill()
	for _frame: int in 120:
		await wait_physics_frames(1)
		if _game.phase == Game.Phase.PLAYING and _game.player.is_alive():
			break
	await wait_physics_frames(2)
	assert_eq(_lift().top, _home_top(), "a trap resets: home, where the level drew it")
	assert_true(_game.level.is_solid_cell(Vector2i(9, HOME_ROW)), "and stone there again")
