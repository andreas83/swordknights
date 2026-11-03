extends GutTest
## The mechanism framework in play (scripts/mechanisms/), with a plate and a
## gate that exist only in this file, wired by a `;!` declaration and played
## through the real game scene.
##
## What builders lean on, each held here:
##
## - the bus: a held channel is on while anything holds it, a latched one for
##   good, and `changed` fires on edges only;
## - the overlay: what a mechanism made of a cell is what every tile query
##   answers, and only its owner can take it back;
## - a shut gate stops the prince's body and his probes alike, and the plate
##   wired to it opens both;
## - the rule for putting mechanisms back: a restart and a checkpoint respawn
##   both bring every mechanism back as the level text placed it.

const GAME_SCENE := "res://scenes/game.tscn"
const DeathWatch := preload("res://tests/death_watch.gd")

## The plate is behind the spawn, so the gate can be met shut first.
const GATEHOUSE := """;! mark 1 test_plate channel=gate
;! mark 2 test_gate channel=gate
; Gatehouse






###############
       2
 1@    2     D
###############
###############
"""

const GATE_CELLS: Array[Vector2i] = [Vector2i(7, 7), Vector2i(7, 8)]


## Clicks down when stood on and stays down: it latches its channel.
class TestPlate extends Mechanism:
	var pressed := false

	func meet(contact: Contact) -> void:
		if not pressed and feet_on(contact):
			pressed = true
			bus.latch(channel)


## Stone while its channel is off, air while it is on.
class TestGate extends Mechanism:
	func _setup() -> void:
		set_kind(Tiles.Kind.EMPTY if bus.is_on(channel) else Tiles.Kind.SOLID)

	func _on_channel(on: bool) -> void:
		set_kind(Tiles.Kind.EMPTY if on else Tiles.Kind.SOLID)


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
	EntityRegistry.add_for_test("test_plate", TestPlate)
	EntityRegistry.add_for_test("test_gate", TestGate)


func after_all() -> void:
	EntityRegistry.remove_for_test("test_plate")
	EntityRegistry.remove_for_test("test_gate")


func _play() -> void:
	var data := AsciiLevel.new()
	data.parse(GATEHOUSE)
	assert_eq(data.problems, PackedStringArray(), "the gatehouse parses clean")
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


## Walks onto the plate, behind the spawn.
func _open_the_gate() -> void:
	await _walk(PlayerInput.BIT_LEFT, 20)


## --- the bus ------------------------------------------------------------------

func test_a_held_channel_is_on_while_anything_holds_it() -> void:
	var bus := ChannelBus.new()
	var ear := Listener.new()
	bus.changed.connect(ear.hear)
	var one := RefCounted.new()
	var two := RefCounted.new()
	bus.hold(&"west", one)
	bus.hold(&"west", two)
	bus.release(&"west", one)
	assert_true(bus.is_on(&"west"), "the second plate still holds it")
	bus.release(&"west", two)
	assert_false(bus.is_on(&"west"), "and lets it go")
	assert_eq(ear.heard, ["west on", "west off"] as Array[String], "two edges, no repeats")


func test_a_latched_channel_stays_on() -> void:
	var bus := ChannelBus.new()
	var ear := Listener.new()
	bus.changed.connect(ear.hear)
	var plate := RefCounted.new()
	bus.hold(&"east", plate)
	bus.latch(&"east")
	bus.release(&"east", plate)
	assert_true(bus.is_on(&"east"), "latched outlasts every hold")
	assert_eq(ear.heard, ["east on"] as Array[String], "and was one edge")
	assert_eq(bus.on_channels(), [&"east"] as Array[StringName])


## --- the overlay ----------------------------------------------------------------

func test_the_overlay_is_what_every_query_answers_and_only_its_owner_clears_it() -> void:
	await _play()
	var level := _game.level
	var cell := Vector2i(4, 8)
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


func test_the_plate_opens_the_gate_it_is_wired_to() -> void:
	await _play()
	await _open_the_gate()
	assert_true(_plate().pressed, "the plate went down")
	assert_true(_game._bus.is_on(&"gate"), "and turned its channel on")
	assert_false(_gate_is_shut(), "which opened the gate")
	for cell: Vector2i in GATE_CELLS:
		assert_false(_game.level.is_solid_cell(cell), "probes see air at %s" % cell)
	await _walk(PlayerInput.BIT_RIGHT, 150)
	assert_eq(_game.phase, Game.Phase.COMPLETE, "and he walked through it to the door")


func test_a_restart_puts_every_mechanism_back_as_authored() -> void:
	await _play()
	await _open_the_gate()
	assert_false(_gate_is_shut(), "opened")
	_game._restart()
	await wait_physics_frames(3)
	assert_true(_gate_is_shut(), "a restart shuts it again")
	assert_false(_plate().pressed, "and the plate is up")


func test_a_checkpoint_respawn_puts_every_mechanism_back_as_authored() -> void:
	await _play()
	await _open_the_gate()
	assert_false(_gate_is_shut(), "opened")
	DeathWatch.expect_deaths(1)
	_game.player.kill()
	for _frame: int in 120:
		await wait_physics_frames(1)
		if _game.phase == Game.Phase.PLAYING and _game.player.is_alive():
			break
	await wait_physics_frames(2)
	assert_true(_gate_is_shut(),
		"shut again: the respawn is the state the checkpoint was proved in")
	assert_false(_plate().pressed, "the plate is up")
	assert_false(_game._bus.is_on(&"gate"), "on a fresh bus")
