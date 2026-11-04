extends GutTest
## Down + JUMP on a one-way floor drops the prince through it -- and only
## that. The press that asks for the drop is also a jump press: it went into
## the jump buffer, and on the next frame, falling with coyote time still
## running from the floor he had just left, the buffered jump fired and threw
## him back up through the platform. Chapter II's corridor hatch is a drop
## onto a Bastion; it bounced the prince off its own floor instead, and the
## controller that authored the chapter's clear run is what found it.

const GAME_SCENE := "res://scenes/game.tscn"

## A one-way floor over a room, the prince on it.
const LOFT := """; Loft




   @
#######===#######
#               #
#               #
#               D
#################
"""


class ScriptedInput extends PlayerInput:
	var bits := 0

	func poll() -> void:
		apply_bits(bits)


func test_down_and_jump_drops_through_and_does_not_jump() -> void:
	var data := AsciiLevel.new()
	data.parse(LOFT)
	var game := (load(GAME_SCENE) as PackedScene).instantiate() as Game
	game.level_source = data
	add_child_autofree(game)
	var input := ScriptedInput.new()
	game.player.input = input
	await wait_physics_frames(4)
	game.player.position = Vector2(8.5 * Tuning.TILE, 5.0 * Tuning.TILE)
	await wait_physics_frames(4)
	var top := game.player.position.y
	var trace := {"tick": 0, "highest": top}
	var on_tick := func() -> void:
		var t := int(trace["tick"])
		input.bits = PlayerInput.BIT_DOWN | (PlayerInput.BIT_JUMP if t == 8 else 0)
		trace["highest"] = minf(float(trace["highest"]), game.player.position.y)
		trace["tick"] = t + 1
	get_tree().physics_frame.connect(on_tick)
	await wait_physics_frames(40)
	get_tree().physics_frame.disconnect(on_tick)
	input.bits = 0
	assert_gt(game.player.position.y, top + Tuning.TILE, "he dropped through the floor")
	assert_lte(float(trace["highest"]), top + 0.1, "he was standing on it first")
	assert_gt(float(trace["highest"]), top - 2.0, "and never jumped up off it")
