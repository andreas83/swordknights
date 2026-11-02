extends SceneTree
## PlayerInput's wire encoding and its press edges.
##
##     godot --headless --script tests/duel_input_bits.gd
##
## This is the seam the whole netplay design rests on: one frame of a player's
## intent is one byte, and the character reads only that. If a byte does not
## round-trip, or if the press edges are not derived purely from the previous
## byte, then a remote peer and a replayed frame stop being equivalent to a
## local one and nothing downstream can be trusted.

const Support := preload("res://tests/duel_support.gd")

var _s := Support.new()


func _initialize() -> void:
	_the_frame_fits_in_a_byte()
	_every_byte_round_trips()
	_booleans_match_their_bits()
	_presses_are_edges_not_states()
	_edges_ignore_unrelated_bits()
	_clear_forgets_the_previous_frame()
	_the_edge_memory_can_be_saved_and_restored()
	_axes_come_out_of_the_direction_bits()
	_the_input_map_fills_a_byte()

	quit(_s.report("duel_input_bits"))


## --- cases ------------------------------------------------------------------

func _the_frame_fits_in_a_byte() -> void:
	var bits := [
		PlayerInput.BIT_LEFT, PlayerInput.BIT_RIGHT, PlayerInput.BIT_UP,
		PlayerInput.BIT_DOWN, PlayerInput.BIT_JUMP, PlayerInput.BIT_ATTACK,
		PlayerInput.BIT_WALK, PlayerInput.BIT_GUARD,
	]
	var union := 0
	for bit: int in bits:
		_s.check(bit > 0 and bit < 256, "bit %d is inside one byte" % bit)
		_s.check(union & bit == 0, "bit %d does not collide with another" % bit)
		union |= bit
	_s.equal(union, 0xff, "the eight bits fill the byte exactly")


func _every_byte_round_trips() -> void:
	var input := PlayerInput.new()
	var bad := -1
	for value: int in 256:
		input.apply_bits(value)
		if input.to_bits() != value:
			bad = value
			break
	_s.equal(bad, -1, "all 256 bytes survive apply_bits -> to_bits")


func _booleans_match_their_bits() -> void:
	var input := PlayerInput.new()
	input.apply_bits(PlayerInput.BIT_LEFT | PlayerInput.BIT_GUARD | PlayerInput.BIT_WALK)
	_s.check(input.left, "the left bit sets left")
	_s.check(input.guard, "the guard bit sets guard")
	_s.check(input.walk, "the walk bit sets walk")
	_s.check(not input.right, "an unset bit stays false")
	_s.check(not input.attack, "an unset bit stays false")
	_s.check(not input.jump, "an unset bit stays false")


func _presses_are_edges_not_states() -> void:
	for spec: Array in [
		[PlayerInput.BIT_JUMP, "jump"],
		[PlayerInput.BIT_ATTACK, "attack"],
		[PlayerInput.BIT_GUARD, "guard"],
	]:
		var bit: int = spec[0]
		var name: String = spec[1]
		var input := PlayerInput.new()

		input.apply_bits(0)
		_s.check(not _edge(input, name), "%s: no press on an empty first frame" % name)

		input.apply_bits(bit)
		_s.check(_edge(input, name), "%s: a press fires on the frame it goes down" % name)

		input.apply_bits(bit)
		_s.check(not _edge(input, name), "%s: holding is not a press" % name)

		input.apply_bits(bit)
		_s.check(not _edge(input, name), "%s: still held, still not a press" % name)

		input.apply_bits(0)
		_s.check(not _edge(input, name), "%s: releasing is not a press" % name)

		input.apply_bits(bit)
		_s.check(_edge(input, name), "%s: pressing again fires again" % name)


func _edges_ignore_unrelated_bits() -> void:
	var input := PlayerInput.new()
	input.apply_bits(PlayerInput.BIT_JUMP)
	_s.check(input.just_pressed_jump, "jump pressed")
	# Everything else changes around a held jump: the edge must stay quiet.
	input.apply_bits(PlayerInput.BIT_JUMP | PlayerInput.BIT_LEFT)
	_s.check(not input.just_pressed_jump, "another bit arriving does not re-press jump")
	input.apply_bits(PlayerInput.BIT_JUMP | PlayerInput.BIT_LEFT | PlayerInput.BIT_WALK)
	_s.check(not input.just_pressed_jump, "nor does a third")
	input.apply_bits(PlayerInput.BIT_JUMP | PlayerInput.BIT_ATTACK)
	_s.check(not input.just_pressed_jump, "jump is still held, so still no press")
	_s.check(input.just_pressed_attack, "and attack presses on its own edge")


func _clear_forgets_the_previous_frame() -> void:
	var input := PlayerInput.new()
	input.apply_bits(PlayerInput.BIT_ATTACK)
	input.apply_bits(PlayerInput.BIT_ATTACK)
	_s.check(not input.just_pressed_attack, "attack is being held")

	input.clear()
	_s.equal(input.to_bits(), 0, "clear releases everything")
	_s.check(not input.just_pressed_attack, "clear leaves no pending press")

	# A fresh round must not inherit a held button as a press, and must see the
	# next genuine press. This is what Player.duel_reset relies on.
	input.apply_bits(PlayerInput.BIT_ATTACK)
	_s.check(input.just_pressed_attack, "after clear, a held button presses afresh")


func _the_edge_memory_can_be_saved_and_restored() -> void:
	var input := PlayerInput.new()
	input.apply_bits(PlayerInput.BIT_JUMP | PlayerInput.BIT_GUARD)
	var remembered := input.previous_bits()
	_s.equal(remembered, PlayerInput.BIT_JUMP | PlayerInput.BIT_GUARD,
		"previous_bits reports the frame just applied")

	# Wander off, the way a mispredicted frame does.
	input.apply_bits(0)
	input.apply_bits(PlayerInput.BIT_LEFT)

	# Rewind, then replay the frame that followed `remembered`. A held button
	# must not re-fire: that is the bug this accessor exists to prevent.
	input.restore_previous_bits(remembered)
	input.apply_bits(PlayerInput.BIT_JUMP | PlayerInput.BIT_GUARD)
	_s.check(not input.just_pressed_jump,
		"a replayed frame does not re-fire a jump that was already held")
	_s.check(not input.just_pressed_guard,
		"a replayed frame does not re-fire a guard that was already held")

	input.restore_previous_bits(0)
	input.apply_bits(PlayerInput.BIT_JUMP)
	_s.check(input.just_pressed_jump,
		"and a replayed frame does fire a jump that genuinely went down")


func _axes_come_out_of_the_direction_bits() -> void:
	var input := PlayerInput.new()
	input.apply_bits(PlayerInput.BIT_RIGHT)
	_s.equal(input.axis_x, 1, "right is +1")
	input.apply_bits(PlayerInput.BIT_LEFT)
	_s.equal(input.axis_x, -1, "left is -1")
	input.apply_bits(PlayerInput.BIT_LEFT | PlayerInput.BIT_RIGHT)
	_s.equal(input.axis_x, 0, "both directions cancel")
	input.apply_bits(PlayerInput.BIT_DOWN)
	_s.equal(input.axis_y, 1, "down is +1")
	input.apply_bits(PlayerInput.BIT_UP)
	_s.equal(input.axis_y, -1, "up is -1")


## bits_from_actions is the duel's reader. Check that the bindings written by
## tools/configure_project.gd exist and land on the right bits — a typo in a
## suffix would otherwise show up as a duellist who simply cannot move.
func _the_input_map_fills_a_byte() -> void:
	for suffix: String in ["", "_p1", "_p2"]:
		_s.equal(PlayerInput.bits_from_actions(suffix), 0,
			"nothing is pressed, so '%s' reads an empty frame" % suffix)

		var expected := 0
		for pair: Array in [
			["move_left", PlayerInput.BIT_LEFT],
			["move_right", PlayerInput.BIT_RIGHT],
			["move_up", PlayerInput.BIT_UP],
			["move_down", PlayerInput.BIT_DOWN],
			["jump", PlayerInput.BIT_JUMP],
			["attack", PlayerInput.BIT_ATTACK],
			["walk", PlayerInput.BIT_WALK],
			["guard", PlayerInput.BIT_GUARD],
		]:
			var action: String = String(pair[0]) + suffix
			if not _s.check(InputMap.has_action(action), "action '%s' is bound" % action):
				continue
			Input.action_press(action)
			expected |= int(pair[1])
			_s.equal(PlayerInput.bits_from_actions(suffix), expected,
				"'%s' adds its bit and nothing else" % action)

		_s.equal(expected, 0xff, "the '%s' set covers all eight bits" % suffix)
		for pair2: Array in [
			["move_left", 0], ["move_right", 0], ["move_up", 0], ["move_down", 0],
			["jump", 0], ["attack", 0], ["walk", 0], ["guard", 0],
		]:
			var action2: String = String(pair2[0]) + suffix
			if InputMap.has_action(action2):
				Input.action_release(action2)
		_s.equal(PlayerInput.bits_from_actions(suffix), 0,
			"'%s' reads empty again once everything is released" % suffix)


func _edge(input: PlayerInput, which: String) -> bool:
	match which:
		"jump":
			return input.just_pressed_jump
		"attack":
			return input.just_pressed_attack
		_:
			return input.just_pressed_guard
