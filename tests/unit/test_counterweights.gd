extends GutTest
## Plates and gates (scripts/mechanisms/plate.gd, gate.gd), played through the
## real game scene on a street in miniature: a latched gate, then a race.
##
## What is held here, against the bible's numbers (docs/campaign.md,
## "Counterweights"):
##
## - a plate is a floor stone that sinks 2 px over 4 frames under a foot, and
##   its wire says what the press means: gate 1 latches and stays up;
## - a gate rises over 30 frames and falls in 12, and its foot clears the
##   prince's 22 px about frame 21 on a two-course gate;
## - a held gate is a race: won at a run, lost by dawdling -- and losing costs
##   time, not the chapter;
## - the counterweight is the clock: up while held, sinking for exactly the
##   hold after the last foot leaves, five chain ticks 12 frames apart in its
##   last second, and the gate falls when it lands;
## - a gate never closes on a body: it waits above him until he has gone;
## - a respawn shuts the race's gate and keeps the latched one open.

const GAME_SCENE := "res://scenes/game.tscn"
const DeathWatch := preload("res://tests/death_watch.gd")

## A roofed street two courses high: plate 1 opens gate 1 for good; plate 2
## holds gate 2 for 2.4 seconds, against an eight-tile run.
const STREET := """;! channel 1 latch
;! channel 2 hold 2.4
; Gate Street

########1###########2#####
        !           !
  @  t  !           !    D
#####o#######o############
#####1#######2############
"""

const GATE_1 := 8
const GATE_2 := 20
const PLATE_1 := 5
const PLATE_2 := 13
const STAND_ROW := 3
const HOLD_FRAMES := 144


class ScriptedInput extends PlayerInput:
	var bits := 0

	func poll() -> void:
		apply_bits(bits)


var _game: Game
var _input: ScriptedInput
var _heard: Array[String] = []


func _play(text: String = STREET) -> void:
	var data := AsciiLevel.new()
	data.parse(text)
	assert_eq(data.problems, PackedStringArray(), "the street parses clean")
	assert_eq(EntityRegistry.problems_in(data), PackedStringArray(), "and is wired")
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Game
	_game.level_source = data
	add_child_autofree(_game)
	_input = ScriptedInput.new()
	_game.player.input = _input
	_heard.clear()
	await wait_physics_frames(4)
	for gate: Gate in _gates():
		gate.cue.connect(func(voice: StringName, options: Dictionary) -> void:
			_heard.append("%d %s %s" % [gate.cells[0].x, voice, options.get("pitch", 1.0)]))


func _gates() -> Array[Gate]:
	var out: Array[Gate] = []
	for node: Node in _game.get_node("Entities").get_children():
		if node is Gate and not node.is_queued_for_deletion():
			out.append(node as Gate)
	return out


func _gate(column: int) -> Gate:
	for gate: Gate in _gates():
		if gate.cells[0].x == column:
			return gate
	return null


func _plate(column: int) -> Plate:
	for node: Node in _game.get_node("Entities").get_children():
		if node is Plate and (node as Plate).cells[0].x == column \
				and not node.is_queued_for_deletion():
			return node as Plate
	return null


## Drives the game a physics tick at a time (see tests/unit/test_lift.gd for
## why): `step` answers each tick's input bits, or -1 to stop.
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


func _x() -> float:
	return _game.player.position.x


func _cell_x() -> int:
	return floori(_x() / Tuning.TILE)


## Right until he stands on the plate in `column`, then still.
func _onto(column: int, bits: int = PlayerInput.BIT_RIGHT) -> void:
	await _drive(func(_t: int) -> int: return -1 if _plate(column).pressed else bits, 300)
	await _drive(func(_t: int) -> int:
		return -1 if is_zero_approx(_game.player.velocity.x) else 0, 30)


func _hold_still(frames: int) -> void:
	await _drive(func(_t: int) -> int: return 0, frames)


## --- the plate --------------------------------------------------------------------

func test_its_numbers_are_the_bibles() -> void:
	assert_eq(Plate.SINK, 2.0, "a plate sinks 2 px")
	assert_eq(Plate.SINK_FRAMES, 4, "over 4 frames")
	assert_eq(Gate.RISE_FRAMES, 30, "a gate rises over 30 frames")
	assert_eq(Gate.FALL_FRAMES, 12, "and falls in 12")
	assert_eq([Gate.TICKS, Gate.TICK_FRAMES], [5, 12], "five ticks, one every 12 frames")


func test_a_plate_sinks_under_a_foot_and_rises_after_it() -> void:
	await _play()
	var plate := _plate(PLATE_1)
	assert_false(plate.pressed, "up to start")
	var sinking := []
	await _drive(func(_t: int) -> int:
		if plate.pressed:
			sinking.append(plate.sink)
		return -1 if sinking.size() >= 6 else PlayerInput.BIT_RIGHT, 200)
	assert_eq(sinking.slice(0, 5), [0.5, 1.0, 1.5, 2.0, 2.0], "two pixels over four frames")


## --- the latched gate ---------------------------------------------------------------

func test_a_latched_gate_rises_over_thirty_frames_and_stays() -> void:
	await _play()
	var gate := _gate(GATE_1)
	assert_true(gate.is_shut(), "shut to start")
	# Sampled from its first frame of rising: gate 1 is above its plate in the
	# level's reading order, so it hears the press on the tick after it.
	var rise := []
	await _drive(func(_t: int) -> int:
		if gate.raised > 0.0:
			rise.append(gate.raised)
		return -1 if rise.size() >= 32 else PlayerInput.BIT_RIGHT, 300)
	var full := 2.0 * Tuning.TILE
	assert_almost_eq(float(rise[29]), full, 0.01, "fully up on the thirtieth frame")
	assert_lt(float(rise[28]), full, "and not before")
	var clear := rise.find(rise.filter(func(r: float) -> bool:
		return r >= Tuning.BODY_HEIGHT)[0]) + 1
	assert_almost_eq(clear, 21, 1, "its foot clears the prince's 22 px about frame 21")
	await _drive(func(_t: int) -> int: return -1 if _x() > float(GATE_1 + 2) * 16.0 \
		else PlayerInput.BIT_RIGHT, 200)
	await _hold_still(200)
	assert_false(_gate(GATE_1).is_shut(), "a latch keeps it up behind him")
	assert_eq(_gate(GATE_1).weight, 1.0, "its counterweight up for good: the clock never runs")


## --- the race --------------------------------------------------------------------------

func test_a_race_run_at_once_is_won() -> void:
	await _play()
	await _onto(PLATE_2)
	await _hold_still(30)
	assert_false(_gate(GATE_2).is_shut(), "the plate holds gate 2 up")
	var ran := await _drive(func(_t: int) -> int:
		return -1 if _x() > float(GATE_2 + 1) * Tuning.TILE else PlayerInput.BIT_RIGHT, 300)
	assert_lt(ran, HOLD_FRAMES, "through inside the hold")
	await _drive(func(_t: int) -> int:
		return -1 if _game.phase == Game.Phase.COMPLETE else PlayerInput.BIT_RIGHT, 300)
	assert_eq(_game.phase, Game.Phase.COMPLETE, "and on to the door")


func test_a_race_lost_costs_time_and_nothing_else() -> void:
	await _play()
	await _onto(PLATE_2)
	await _hold_still(30)
	# Off the plate toward the gate, and then dawdle: running at it again from
	# behind the plate would only press it again.
	await _drive(func(_t: int) -> int: return -1 if not _plate(PLATE_2).pressed \
		else PlayerInput.BIT_RIGHT, 30)
	await _hold_still(HOLD_FRAMES + Gate.FALL_FRAMES + 10)
	assert_true(_gate(GATE_2).is_shut(), "dawdled: the gate is down")
	await _drive(func(_t: int) -> int: return PlayerInput.BIT_RIGHT, 150)
	assert_lt(_x(), float(GATE_2) * Tuning.TILE, "and he is on this side of it")
	assert_true(_game.player.is_alive(), "alive")
	assert_eq(_game.player.health, Tuning.MAX_HEALTH, "and whole: a race costs time, not hearts")
	await _drive(func(_t: int) -> int: return -1 if _plate(PLATE_2).pressed \
		else PlayerInput.BIT_LEFT, 120)
	assert_true(_plate(PLATE_2).pressed, "the plate is right there to try again")


## The clock, frame by frame: up while he stands on the plate, sinking from
## the frame he steps off for exactly the hold, five ticks in its last second.
func test_the_counterweight_sinks_for_exactly_the_hold() -> void:
	await _play()
	await _onto(PLATE_2)
	await _hold_still(30)
	var gate := _gate(GATE_2)
	assert_eq(gate.weight, 1.0, "up while the plate is held")
	var trace := []
	await _drive(func(t: int) -> int:
		trace.append([gate.weight, gate.is_shut(), gate.jolt])
		if t > HOLD_FRAMES + 40:
			return -1
		return PlayerInput.BIT_LEFT if _plate(PLATE_2).pressed else 0, 400)
	var off := 0
	while off < trace.size() and float(trace[off][0]) >= 1.0:
		off += 1
	var landed := off
	while landed < trace.size() and float(trace[landed][0]) > 0.0:
		landed += 1
	assert_almost_eq(landed - off, HOLD_FRAMES, 2, "it sinks for the whole hold")
	var shut := landed
	while shut < trace.size() and not bool(trace[shut][1]):
		shut += 1
	assert_almost_eq(shut - landed, Gate.FALL_FRAMES, 2, "and the gate falls when it lands")
	var ticks := _heard.filter(func(line: String) -> bool:
		return line.begins_with("%d chain" % GATE_2) and not line.ends_with("0.7"))
	assert_eq(ticks.size(), Gate.TICKS, "five ticks in the last second")
	assert_true(_heard.has("%d land_hard 0.8" % GATE_2), "and a slam")


## --- never on a body -------------------------------------------------------------

func test_a_gate_never_closes_on_a_body() -> void:
	await _play()
	await _onto(PLATE_2)
	await _hold_still(30)
	# Into the gateway itself, and wait there for the hold to run out.
	await _drive(func(_t: int) -> int:
		return -1 if absf(_x() - (float(GATE_2) + 0.5) * Tuning.TILE) < 2.0 \
			else PlayerInput.BIT_RIGHT | PlayerInput.BIT_WALK, 400)
	await _hold_still(HOLD_FRAMES + 60)
	var gate := _gate(GATE_2)
	assert_false(gate.is_shut(), "the hold has run out, and the gate is still up")
	assert_lte(gate.foot(), _game.player.position.y - Tuning.BODY_HEIGHT + 0.01,
		"waiting above his head")
	assert_true(_game.player.is_alive(), "nothing crushed him")
	await _drive(func(_t: int) -> int: return PlayerInput.BIT_LEFT, 40)
	await _hold_still(Gate.FALL_FRAMES + 4)
	assert_true(gate.is_shut(), "once he has gone, it falls")


## --- respawn ---------------------------------------------------------------------

func test_a_respawn_keeps_the_latch_and_resets_the_race() -> void:
	await _play()
	await _onto(PLATE_2)
	await _hold_still(30)
	assert_false(_gate(GATE_2).is_shut(), "the race is on")
	DeathWatch.expect_deaths(1)
	_game.player.kill()
	for _frame: int in 120:
		await wait_physics_frames(1)
		if _game.phase == Game.Phase.PLAYING and _game.player.is_alive():
			break
	await wait_physics_frames(2)
	assert_false(_gate(GATE_1).is_shut(), "the latched gate is a deed: still up")
	assert_true(_gate(GATE_2).is_shut(), "the race is a trap: its gate is down again")
	assert_eq(_gate(GATE_2).weight, 0.0, "and its clock has landed")
	for row: int in [2, 3]:
		assert_true(_game.level.is_solid_cell(Vector2i(GATE_2, row)),
			"stone to every probe at row %d, not just to his body" % row)
		assert_false(_game.level.is_solid_cell(Vector2i(GATE_1, row)),
			"and the open gate is air at row %d" % row)
