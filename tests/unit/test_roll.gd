extends GutTest
## The roll: its numbers, the ground it may and may not cover, and its window.
##
## A roll is the one new move that travels along the floor, so it is held to
## what the backstep is held to (tests/unit/test_backstep_costs.gd) and one
## thing more. It must add no traversal the reachability proof does not know:
## it stops at every lip, it enters no space a standing body cannot, and it
## covers less floor a second than a run, so it can shorten no race. And its
## window must be exactly what docs/character.md says: while tucked, a blade
## or a shield from either side goes over him, and nothing in flight does,
## and the moment the tuck ends the same blade lands.
##
## The roll against each foe, live, is tests/unit/test_roll_foes.gd.

const GAME_SCENE := "res://scenes/game.tscn"
const D := PlayerInput.BIT_DOWN
const J := PlayerInput.BIT_JUMP

## Stone that ends two tiles to the prince's right, over a long drop.
const LIP := """; Lip



     @
########



                         D
##########################
##########################
"""

## A one-tile-high slot in a wall two tiles ahead of him: room for a tucked
## body, none for a standing one.
const SLOT := """; Slot





         ######
         ######
     @           D
##################
##################
"""

## Open floor.
const OPEN := """; Open








      @                  D
##########################
##########################
"""


class ScriptedInput extends PlayerInput:
	var bits := 0

	func poll() -> void:
		apply_bits(bits)


var _game: Game
var _input: ScriptedInput


func _play(text: String) -> void:
	var data := AsciiLevel.new()
	data.parse(text)
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Game
	_game.level_source = data
	add_child_autofree(_game)
	_input = ScriptedInput.new()
	_game.player.input = _input
	for _frame: int in 30:
		await wait_physics_frames(1)
		if _game.player.state == Player.State.IDLE and _game.player.is_grounded():
			break


func _roll_out() -> void:
	_input.bits = D | J
	await wait_physics_frames(1)
	_input.bits = 0
	for _frame: int in 60:
		if _game.player.state != Player.State.ROLL:
			return
		await wait_physics_frames(1)


## --- the numbers ------------------------------------------------------------------

func test_a_roll_covers_less_floor_a_second_than_a_run() -> void:
	var average := Tuning.roll_distance() / Tuning.ROLL_TIME
	assert_lt(average, Tuning.RUN_SPEED,
		"rolling the whole way is slower than running it: no race is shortened")
	var through := Tuning.BODY_WIDTH + Patrol.ENGAGE_GAP + Patrol.BODY.x
	assert_gt(Tuning.roll_distance(), through,
		"long enough to go from where a guard raises clean through him")
	assert_lt(Tuning.roll_distance(), through + Tuning.ATTACK_REACH,
		"and short enough to come up with his back inside a swing")


func test_the_tuck_is_lower_than_a_crouch_and_higher_than_a_cut() -> void:
	assert_lt(Tuning.ROLL_HEIGHT, Tuning.CROUCH_HEIGHT,
		"what a crouch ducks, a roll ducks: a bolt at chest height goes over it")
	assert_gt(Tuning.ROLL_HEIGHT, Patrol.CUT_LOW,
		"and a sentinel's cut reaches it, so only the window lets the blade by")


func test_the_roll_is_dearer_than_its_window() -> void:
	assert_gt(Tuning.ROLL_RECOVER, 0.0, "a rise in which nothing comes out")
	assert_gt(Tuning.ROLL_TIME, Tuning.BACKSTEP_TIME,
		"and the whole roll commits longer than a backstep")


## --- the ground ------------------------------------------------------------------

func test_a_roll_stops_at_the_lip() -> void:
	await _play(LIP)
	var floor_y := _game.player.position.y
	await _roll_out()
	await wait_physics_frames(20)
	assert_true(_game.player.is_grounded(), "still on the stone")
	assert_almost_eq(_game.player.position.y, floor_y, 0.5, "on the floor it rolled on")
	var lip := 8.0 * Tuning.TILE - Tuning.BODY_WIDTH * 0.5
	assert_almost_eq(_game.player.position.x, lip, 1.0, "stopped at the lip, not over it")


func test_a_roll_does_not_go_where_a_standing_body_cannot() -> void:
	await _play(SLOT)
	await _roll_out()
	var wall := 9.0 * Tuning.TILE
	assert_lt(_game.player.body_rect().end.x, wall + 0.5,
		"the roll keeps the standing body's shape: a one-tile slot stops it at the mouth")


## --- the window --------------------------------------------------------------------

func test_a_blade_from_in_front_or_behind_goes_over_the_tuck() -> void:
	await _play(OPEN)
	var p := _game.player
	p.set_physics_process(false)
	p.state = Player.State.ROLL
	for side: float in [1.0, -1.0]:
		p.state_time = Tuning.ROLL_TUCK * 0.5
		var cut := FoeDanger.make(p.moves.hurt_rect(), p.position.x + side * 12.0)
		_game._resolve_danger(cut, p.moves.hurt_rect())
		assert_eq(p.health, Tuning.MAX_HEALTH,
			"tucked, a cut from %s goes over him" % ("in front" if side > 0.0 else "behind"))


func test_the_same_blade_lands_once_the_tuck_is_over() -> void:
	await _play(OPEN)
	var p := _game.player
	p.set_physics_process(false)
	p.state = Player.State.ROLL
	p.state_time = Tuning.ROLL_TUCK + 0.01
	var cut := FoeDanger.make(p.moves.hurt_rect(), p.position.x + 12.0)
	_game._resolve_danger(cut, p.moves.hurt_rect())
	assert_eq(p.health, Tuning.MAX_HEALTH - 1, "rising, he is a body again, and is cut")


func test_a_shot_is_not_rolled_under_by_the_window() -> void:
	await _play(OPEN)
	var p := _game.player
	p.set_physics_process(false)
	p.state = Player.State.ROLL
	p.state_time = 0.05
	var shot := FoeProjectile.new()
	add_child_autofree(shot)
	shot.position = p.position + Vector2(0.0, -4.0)
	shot.velocity = Vector2(-150.0, 0.0)
	_game._resolve_danger(shot.danger(), p.moves.hurt_rect())
	assert_eq(p.health, Tuning.MAX_HEALTH - 1, "a shot at the shins finds a tucked body")


func test_a_shot_at_chest_height_goes_over_the_tuck_by_height() -> void:
	await _play(OPEN)
	var p := _game.player
	p.set_physics_process(false)
	p.state = Player.State.ROLL
	p.state_time = 0.05
	var chest := Rect2(p.position.x - 4.0, p.position.y - 16.0, 8.0, 2.0)
	assert_false(p.moves.hurt_rect().intersects(chest),
		"a sunbolt's band, 14 to 16 px up, is over the tuck")
	assert_true(p.body_rect().intersects(chest), "and would hit the standing body")
	assert_eq(p.moves.hurt_rect().size.y, Tuning.ROLL_HEIGHT, "the tuck is the foe's target")
	assert_eq(p.body_rect().size.y, Tuning.BODY_HEIGHT,
		"while the world -- floors, spikes, water -- still sees the standing body")
