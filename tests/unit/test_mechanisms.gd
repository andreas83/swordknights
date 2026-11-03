extends GutTest
## The mechanism framework in play (scripts/mechanisms/), with a plate and a
## gate that exist only in this file, wired the way the campaign is drafted --
## a stone plate and a portcullis carrying the same mason's mark, and a
## `;! channel` line saying the wire latches -- and played through the real
## game scene.
##
## What builders lean on, each held here:
##
## - the bus: what a press means is the channel's -- momentary, latched, held
##   for a time -- and a beat channel turns on the physics step alone;
## - the overlay: what a mechanism made of a cell is what every tile query
##   answers, and only its owner can take it back;
## - a shut gate stops the prince's body and his probes alike, and the plate
##   on its wire opens both;
## - the rule for putting mechanisms back: a restart brings every mechanism
##   back as the level text placed it, and a checkpoint respawn does too but
##   keeps what was latched -- a trap resets, a deed does not;
## - a mechanism that is nothing without a wire, placed without one, is a
##   problem in the level.

const GAME_SCENE := "res://scenes/game.tscn"
const DeathWatch := preload("res://tests/death_watch.gd")

## The plate is behind the spawn, so the gate can be met shut first, and
## against the wall, so walking left ends on it. The plate is a floor stone
## with its mark under it; the gate hangs from a lintel carrying the same
## mark.
const GATEHOUSE := """;! channel 1 latch
; Gatehouse





#######1#######
#      !
# @    !     D
#o#############
#1#############
"""

const GATE_CELLS: Array[Vector2i] = [Vector2i(7, 6), Vector2i(7, 7)]

## The gatehouse with no plate, and its gate on a beat: open for ten steps,
## shut for ten.
const BEAT_GATEHOUSE := ";! channel 1 beat 0 period=20\n" + """; Beat Gatehouse





#######1#######
       !
  @    !     D
###############
###############
"""


## Down while stood on; what that does is the wire's.
class TestPlate extends Mechanism:
	var pressed := false

	func meet(contact: Contact) -> void:
		var on := feet_on(contact)
		if on and not pressed:
			bus.press(channel, self)
		elif pressed and not on:
			bus.release(channel, self)
		pressed = on


## Stone while its channel is off, air while it is on. Nothing without one.
class TestGate extends Mechanism:
	func _setup() -> void:
		set_kind(Tiles.Kind.EMPTY if bus.is_on(channel) else Tiles.Kind.SOLID)

	func _on_channel(on: bool) -> void:
		set_kind(Tiles.Kind.EMPTY if on else Tiles.Kind.SOLID)

	static func wired() -> bool:
		return true


class ScriptedInput extends PlayerInput:
	var bits := 0

	func poll() -> void:
		apply_bits(bits)


class Listener extends RefCounted:
	var heard: Array[String] = []

	func hear(channel: StringName, on: bool) -> void:
		heard.append("%s %s" % [channel, "on" if on else "off"])


var _game: Game
var _input: ScriptedInput


func before_all() -> void:
	Tiles.add_mechanism_for_test("o", "test_plate", Tiles.Kind.SOLID)
	Tiles.add_mechanism_for_test("!", "test_gate")
	EntityRegistry.add_for_test("test_plate", TestPlate)
	EntityRegistry.add_for_test("test_gate", TestGate)


func after_all() -> void:
	Tiles.remove_mechanism_for_test("o")
	Tiles.remove_mechanism_for_test("!")
	EntityRegistry.remove_for_test("test_plate")
	EntityRegistry.remove_for_test("test_gate")


func _play(text: String = GATEHOUSE) -> void:
	var data := AsciiLevel.new()
	data.parse(text)
	assert_eq(data.problems, PackedStringArray(), "the gatehouse parses clean")
	assert_eq(EntityRegistry.problems_in(data), PackedStringArray(), "and is wired")
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Game
	_game.level_source = data
	add_child_autofree(_game)
	_input = ScriptedInput.new()
	_game.player.input = _input
	await wait_physics_frames(6)


func _gate() -> TestGate:
	for node: Node in _game.get_node("Entities").get_children():
		if node is TestGate and not node.is_queued_for_deletion():
			return node as TestGate
	return null


func _plate() -> TestPlate:
	for node: Node in _game.get_node("Entities").get_children():
		if node is TestPlate and not node.is_queued_for_deletion():
			return node as TestPlate
	return null


func _walk(bits: int, frames: int) -> void:
	_input.bits = bits
	await wait_physics_frames(frames)
	_input.bits = 0
	await wait_physics_frames(4)


func _gate_is_shut() -> bool:
	for cell: Vector2i in GATE_CELLS:
		if not _game.level.is_solid_cell(cell):
			return false
	return _gate() != null and _gate().current_kind() == Tiles.Kind.SOLID


## Walks onto the plate, behind the spawn, and stops on it: left until it
## goes down, so the test does not depend on the run speed.
func _open_the_gate() -> void:
	_input.bits = PlayerInput.BIT_LEFT
	for _frame: int in 40:
		await wait_physics_frames(1)
		if _plate().pressed:
			break
	_input.bits = 0
	await wait_physics_frames(4)


## --- the bus ------------------------------------------------------------------

func test_a_momentary_channel_is_on_while_anything_presses_it() -> void:
	var bus := ChannelBus.new()
	var ear := Listener.new()
	bus.changed.connect(ear.hear)
	var one := RefCounted.new()
	var two := RefCounted.new()
	bus.press(&"west", one)
	bus.press(&"west", two)
	bus.release(&"west", one)
	assert_true(bus.is_on(&"west"), "the second plate still holds it")
	bus.release(&"west", two)
	assert_false(bus.is_on(&"west"), "and lets it go")
	assert_eq(ear.heard, ["west on", "west off"] as Array[String], "two edges, no repeats")


func test_a_latched_channel_stays_on() -> void:
	var bus := ChannelBus.new()
	bus.configure(&"1", {"mode": "latch"})
	var plate := RefCounted.new()
	bus.press(&"1", plate)
	bus.release(&"1", plate)
	assert_true(bus.is_on(&"1"), "a latch outlasts the foot that pressed it")
	assert_eq(bus.on_channels(), [&"1"] as Array[StringName])


func test_a_held_channel_runs_on_for_its_seconds_after_the_last_release() -> void:
	var bus := ChannelBus.new()
	bus.configure(&"2", {"mode": "hold", "seconds": 0.5})
	var ear := Listener.new()
	bus.changed.connect(ear.hear)
	var plate := RefCounted.new()
	bus.press(&"2", plate)
	for _frame: int in 10:
		bus.step()
	bus.release(&"2", plate)
	assert_eq(bus.hold_left(&"2"), 30, "half a second is thirty steps")
	for _frame: int in 29:
		bus.step()
	assert_true(bus.is_on(&"2"), "on through the hold")
	bus.step()
	assert_false(bus.is_on(&"2"), "and off on its last step")
	assert_eq(ear.heard, ["2 on", "2 off"] as Array[String])


func test_a_beat_channel_turns_on_the_physics_step_alone() -> void:
	var bus := ChannelBus.new()
	bus.configure(&"4", {"mode": "beat", "phase": 0, "period": 100})
	bus.configure(&"5", {"mode": "beat", "phase": 50, "period": 100})
	var ear := Listener.new()
	bus.changed.connect(ear.hear)
	assert_true(bus.is_on(&"4"), "the on-beat starts on")
	assert_false(bus.is_on(&"5"), "the off-beat starts off")
	for _frame: int in 50:
		bus.step()
	assert_eq(bus.beat(&"4"), 50, "fifty frames into the period")
	assert_eq(bus.beat(&"5"), 0, "and the off-beat's period is starting")
	assert_eq(ear.heard, ["4 off", "5 on"] as Array[String], "they cross on frame 50 exactly")


## --- the overlay ----------------------------------------------------------------

func test_the_overlay_is_what_every_query_answers_and_only_its_owner_clears_it() -> void:
	await _play()
	var level := _game.level
	var cell := Vector2i(4, 7)
	var owner := Node.new()
	var stranger := Node.new()
	assert_false(level.rect_is_deadly(Mechanism.cell_rect(cell)), "open floor to start")
	level.set_overlay(cell, Tiles.Kind.SPIKES, owner)
	assert_true(level.rect_is_deadly(Mechanism.cell_rect(cell)),
		"spikes, as far as the hazard check knows")
	assert_eq(level.kind_at_cell(cell), Tiles.Kind.SPIKES, "and the kind query")
	level.clear_overlay(stranger)
	assert_eq(level.overlay_at(cell), Tiles.Kind.SPIKES, "a stranger cannot take it away")
	level.clear_overlay(owner)
	assert_eq(level.overlay_at(cell), -1, "its owner can")
	assert_eq(level.kind_at_cell(cell), Tiles.Kind.EMPTY, "and the cell is what it was")
	owner.free()
	stranger.free()


## --- a plate and a gate, in play ----------------------------------------------

func test_a_shut_gate_stops_the_body_and_the_probes() -> void:
	await _play()
	assert_true(_gate_is_shut(), "the gate starts shut, on both halves")
	await _walk(PlayerInput.BIT_RIGHT, 70)
	var face := float(GATE_CELLS[0].x) * Tuning.TILE - Tuning.BODY_WIDTH * 0.5
	assert_almost_eq(_game.player.position.x, face, 0.6, "his body stopped at its face")
	assert_eq(_game.phase, Game.Phase.PLAYING, "nowhere near the door")


func test_the_plate_opens_the_gate_that_carries_its_mark() -> void:
	await _play()
	await _open_the_gate()
	assert_true(_plate().pressed, "the stone plate is down under his feet")
	assert_true(_game._bus.is_on(&"1"), "and wire 1 is on")
	assert_false(_gate_is_shut(), "which opened the gate on the same mark")
	for cell: Vector2i in GATE_CELLS:
		assert_false(_game.level.is_solid_cell(cell), "probes see air at %s" % cell)
	await _walk(PlayerInput.BIT_RIGHT, 150)
	assert_false(_plate().pressed, "he left the plate behind")
	assert_eq(_game.phase, Game.Phase.COMPLETE, "and the latch kept the way open to the door")


func test_a_restart_puts_every_mechanism_back_as_authored() -> void:
	await _play()
	await _open_the_gate()
	assert_false(_gate_is_shut(), "opened")
	_game._restart()
	await wait_physics_frames(3)
	assert_true(_gate_is_shut(), "a restart shuts it again")
	assert_false(_plate().pressed, "and the plate is up")


## The old mechanisms leave the tree at once. Left in it for the frame, the
## old plate was met again and let go of the old bus, and the old gate shut,
## took back the cells its replacement had claimed and cleared them as it
## was freed: a new gate that collided where every probe saw air.
func test_a_restart_off_a_held_plate_leaves_the_new_gate_whole() -> void:
	await _play(GATEHOUSE.replace(";! channel 1 latch\n", ""))
	await _open_the_gate()
	assert_false(_gate_is_shut(), "held open while he stands on the plate")
	_game._restart()
	await wait_physics_frames(3)
	assert_true(_gate_is_shut(), "shut in the body and in every query")


func _die_and_come_back() -> void:
	DeathWatch.expect_deaths(1)
	_game.player.kill()
	for _frame: int in 120:
		await wait_physics_frames(1)
		if _game.phase == Game.Phase.PLAYING and _game.player.is_alive():
			break
	await wait_physics_frames(2)


func test_a_checkpoint_respawn_keeps_what_was_latched() -> void:
	await _play()
	await _open_the_gate()
	var before := _gate()
	assert_false(_gate_is_shut(), "opened")
	await _die_and_come_back()
	assert_ne(_gate(), before, "the gate was rebuilt, as every mechanism is")
	assert_false(_gate_is_shut(), "and comes back open: a deed does not reset")
	assert_true(_game._bus.is_on(&"1"), "the new bus kept the latch")
	assert_false(_plate().pressed, "though the plate itself is up again")


func test_a_checkpoint_respawn_resets_what_was_only_held() -> void:
	await _play(GATEHOUSE.replace(";! channel 1 latch\n", ""))
	await _open_the_gate()
	assert_false(_gate_is_shut(), "held open while he stands on the plate")
	await _die_and_come_back()
	assert_true(_gate_is_shut(), "shut again: a trap resets")
	assert_false(_game._bus.is_on(&"1"), "and nothing carried the press")


## Sampled on the tree's physics_frame signal, every tick: GUT's
## wait_physics_frames(1) waits two. The sampler stops itself at forty,
## because a slot disconnected during an emission is still called by it.
func test_a_beat_gate_keeps_time_with_the_game() -> void:
	await _play(BEAT_GATEHOUSE)
	var ticks: Array[Dictionary] = []
	var sample := func() -> void:
		if ticks.size() >= 40 or not is_instance_valid(_game):
			return
		ticks.append({"open": not _gate_is_shut(), "on": _game._bus.is_on(&"1"),
			"frame": _game._bus.frame})
	get_tree().physics_frame.connect(sample)
	await wait_physics_frames(42)
	get_tree().physics_frame.disconnect(sample)
	assert_eq(ticks.size(), 40, "sampled every tick")
	if ticks.size() != 40:
		return
	var open_ticks := 0
	var steps_ok := true
	var follows := true
	for index: int in 40:
		var tick := ticks[index]
		follows = follows and bool(tick["open"]) == bool(tick["on"])
		if index > 0:
			steps_ok = steps_ok and int(tick["frame"]) - int(ticks[index - 1]["frame"]) == 1
		if bool(tick["open"]):
			open_ticks += 1
	assert_true(steps_ok, "the game steps the bus once a physics tick")
	assert_true(follows, "the gate is its wire, every tick")
	assert_eq(open_ticks, 20, "two periods: open for half of them, shut for half")


func test_a_mechanism_that_needs_a_wire_and_has_none_is_a_problem() -> void:
	var data := AsciiLevel.new()
	data.parse(GATEHOUSE.replace("#######1#######", "###############"))
	var problems := EntityRegistry.problems_in(data)
	assert_eq(problems.size(), 1, "the gate has lost its mark")
	if problems.size() == 1:
		assert_string_contains(problems[0], "test_gate at column 7, row 7 has no mason's mark")
