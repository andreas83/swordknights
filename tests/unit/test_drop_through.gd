extends GutTest
## Down + JUMP on a one-way floor drops the prince through it -- and only
## that. The press that asks for the drop is also a jump press: it went into
## the jump buffer, and on the next frame, falling with coyote time still
## running from the floor he had just left, the buffered jump fired and threw
## him back up through the platform. Chapter II's corridor hatch is a drop
## onto a Bastion; it bounced the prince off its own floor instead, and the
## controller that authored the chapter's clear run is what found it.
##
## Down + SWORD on a one-way floor is the plunge through it (Player.
## _plunge_through()): the move that beats what is under a hatch, in one
## press, where it used to take a drop and then a plunge inside a two-tile
## fall. On stone, or half on stone, down + SWORD is still the swing.

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


## The same loft with a Bastion under the hatch, and the hatch drawn as one.
const UNDER := """; Under the Hatch




   @
#######hhh#######
#               #
#        w      #
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
	# Guarded: GUT resumes the test inside the physics_frame emission, and a
	# slot disconnected during an emission is still called by it, once more.
	var on_tick := func() -> void:
		if not is_instance_valid(game):
			return
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


func _loft(text: String, at: Vector2) -> Array:
	var data := AsciiLevel.new()
	data.parse(text)
	assert_eq(data.problems, PackedStringArray(), "the loft parses clean")
	var game := (load(GAME_SCENE) as PackedScene).instantiate() as Game
	game.level_source = data
	add_child_autofree(game)
	var input := ScriptedInput.new()
	game.player.input = input
	await wait_physics_frames(4)
	game.player.position = at
	await wait_physics_frames(6)
	return [game, input]


## Holds down, presses SWORD once, and returns the states the prince went
## through and the highest his feet rose.
func _down_and_sword(game: Game, input: ScriptedInput, ticks: int) -> Dictionary:
	var trace := {"tick": 0, "states": [], "highest": game.player.position.y}
	var on_tick := func() -> void:
		if not is_instance_valid(game):
			return
		var t := int(trace["tick"])
		input.bits = PlayerInput.BIT_DOWN | (PlayerInput.BIT_ATTACK if t == 8 else 0)
		(trace["states"] as Array).append(game.player.state)
		trace["highest"] = minf(float(trace["highest"]), game.player.position.y)
		trace["tick"] = t + 1
	get_tree().physics_frame.connect(on_tick)
	await wait_physics_frames(ticks)
	get_tree().physics_frame.disconnect(on_tick)
	input.bits = 0
	return trace


func test_down_and_sword_on_a_one_way_floor_plunges_through_it() -> void:
	var made := await _loft(LOFT, Vector2(8.5 * Tuning.TILE, 5.0 * Tuning.TILE))
	var game: Game = made[0]
	var top := game.player.position.y
	var trace := await _down_and_sword(game, made[1], 40)
	assert_true((trace["states"] as Array).has(Player.State.PLUNGE), "point first")
	assert_false((trace["states"] as Array).has(Player.State.ATTACK), "not a swing")
	assert_gt(game.player.position.y, top + Tuning.TILE, "through the floor")
	assert_gt(float(trace["highest"]), top - 1.0, "and never up off it")


func test_down_and_sword_on_stone_is_still_the_swing() -> void:
	var made := await _loft(LOFT, Vector2(3.5 * Tuning.TILE, 5.0 * Tuning.TILE))
	var game: Game = made[0]
	var top := game.player.position.y
	var trace := await _down_and_sword(game, made[1], 30)
	assert_true((trace["states"] as Array).has(Player.State.ATTACK), "a swing")
	assert_false((trace["states"] as Array).has(Player.State.PLUNGE), "not a plunge")
	assert_almost_eq(game.player.position.y, top, 0.5, "on the floor where he stood")


func test_half_on_stone_it_is_still_the_swing() -> void:
	var made := await _loft(LOFT, Vector2(7.0 * Tuning.TILE, 5.0 * Tuning.TILE))
	var game: Game = made[0]
	var trace := await _down_and_sword(game, made[1], 30)
	assert_false((trace["states"] as Array).has(Player.State.PLUNGE),
		"a foot on stone: nothing to plunge through")


func test_a_plunge_through_a_hatch_wounds_the_bastion_under_it() -> void:
	var made := await _loft(UNDER, Vector2(9.5 * Tuning.TILE, 5.0 * Tuning.TILE))
	var game: Game = made[0]
	var guard: Bastion = null
	for node: Node in game.get_node("Entities").get_children():
		if node is Bastion:
			guard = node as Bastion
	var hatches := game.get_node("Entities").get_children().filter(
		func(n: Node) -> bool: return n is Hatch)
	assert_eq(hatches.size(), 1, "the grate is a hatch")
	await _down_and_sword(game, made[1], 40)
	assert_lt(guard.health, Bastion.MAX_HEALTH, "the plunge through the hatch found his helm")
	assert_eq(game.player.health, Tuning.MAX_HEALTH, "and cost the prince nothing")
