extends GutTest
## The two special moves, against the sentinel: the plunge (down + SWORD in
## the air) and the parry (up + SWORD on the ground).
##
## Each is held to the same three things: it can be done with the stick and
## the two buttons a phone has, it pays off against the guard, and it costs
## something when it is wrong. The numbers half pins the risk and the reward
## against Patrol's timings the way tests/unit/test_patrol.gd pins the plain
## swing, so a retune of either side cannot quietly make a special free or
## useless. The scene half plays them.

const GAME_SCENE := "res://scenes/game.tscn"
const TOUCH_SCENE := preload("res://scenes/touch_controls.tscn")
const FRAME := 1.0 / 60.0

## The prince at column 4 facing right, a guard at column 5 facing him: inside
## each other's reach, so the guard raises at once.
const FACE_TO_FACE := """; Face to Face








    @p            D
###################
###################
"""

## The prince well away from a guard, so nothing starts until he is put there.
const APART := """; Apart








  @            p        D
#########################
#########################
"""


class ScriptedInput extends PlayerInput:
	var bits := 0

	func poll() -> void:
		apply_bits(bits)


var _game: Game
var _input: ScriptedInput


func after_each() -> void:
	for action: String in ["attack", "move_up", "move_down", "move_left", "move_right"]:
		Input.action_release(action)


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
		if _game.player.state == Player.State.IDLE and not Flow.is_hitstopped():
			break


func _player() -> Player:
	return _game.player


func _guard() -> Patrol:
	for node: Node in _game.get_node("Entities").get_children():
		if node is Patrol and not node.is_queued_for_deletion():
			return node as Patrol
	return null


func _state_name() -> String:
	return String(Player.State.find_key(_player().state))


func _tap(bits: int) -> void:
	_input.bits = bits
	await wait_physics_frames(1)
	_input.bits = 0


## Puts the prince `height` px above `x`, falling from rest.
func _drop_from(x: float, height: float) -> void:
	_player().position = Vector2(x, _player().position.y - height)
	_player().velocity = Vector2.ZERO
	await wait_physics_frames(2)


## --- the numbers -------------------------------------------------------------

func test_the_plunge_is_out_of_the_cut_and_a_miss_is_not() -> void:
	# Reward: the cut's band stops below the top of the guard's own head, so a
	# prince coming down on him from above cannot be reached by it.
	assert_lt(Patrol.CUT_HIGH, Patrol.BODY.y, "a body above the guard is above the cut")
	# Risk: a plunge that meets the floor in front of a guard that starts its
	# raise on the landing cannot swing back before the cut comes down.
	var answer := Tuning.PLUNGE_RECOVER + Tuning.ATTACK_TIME * 0.25
	assert_gt(answer, Patrol.WINDUP_TIME, "a missed plunge in front of him eats the cut")


func test_the_parry_is_the_late_answer_and_an_early_one_fails() -> void:
	# The swing is the answer to the raise while it can still land first; the
	# parry has to cover the frames after that, or it is just a worse swing.
	var last_swing := Patrol.WINDUP_TIME - Tuning.ATTACK_TIME * 0.25
	assert_gt(last_swing + Tuning.PARRY_ACTIVE, Patrol.WINDUP_TIME,
		"a parry pressed after the last winning swing still catches the cut")
	# Risk: a parry thrown up the moment the raise starts is down again
	# before the blade arrives.
	assert_lt(Tuning.PARRY_ACTIVE, Patrol.WINDUP_TIME, "a parry on sight is a parry too soon")
	assert_lt(Tuning.PARRY_ACTIVE, Tuning.PARRY_TIME, "and it leaves a recovery to be caught in")
	# Reward: the opening is longer than the one a whiffed cut gives.
	assert_gt(Patrol.PARRIED_TIME, Patrol.RECOVER_TIME, "a parried guard reels longest")


## --- on the phone ------------------------------------------------------------

func test_both_are_on_the_stick_and_the_sword_button() -> void:
	var controls := TOUCH_SCENE.instantiate() as TouchControls
	add_child_autofree(controls)
	await wait_physics_frames(2)
	controls._layout()
	var sword: Dictionary = {}
	for button: Dictionary in controls._buttons:
		if String(button["action"]) == "attack":
			sword = button
	assert_false(sword.is_empty(), "there is a SWORD button")
	var view := controls.get_viewport().get_visible_rect().size
	var origin := Vector2(view.x * 0.2, view.y * 0.6)

	for push: Vector2 in [Vector2(0.0, 1.0), Vector2(0.0, -1.0)]:
		controls._input(_touch(origin, true, 1))
		controls._input(_drag(origin + push * TouchControls.STICK_RADIUS, 1))
		controls._input(_touch(sword["at"], true, 2))
		var bits := PlayerInput.bits_from_actions()
		var wanted := PlayerInput.BIT_DOWN if push.y > 0.0 else PlayerInput.BIT_UP
		assert_eq(bits & (wanted | PlayerInput.BIT_ATTACK), wanted | PlayerInput.BIT_ATTACK,
			"the stick %s and SWORD together reach the simulation" % (
				"down" if push.y > 0.0 else "up"))
		controls._input(_touch(sword["at"], false, 2))
		controls._input(_touch(origin, false, 1))


func _touch(at: Vector2, down: bool, index: int) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.position = at
	event.pressed = down
	event.index = index
	return event


func _drag(at: Vector2, index: int) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.position = at
	event.index = index
	return event


## --- the plunge ---------------------------------------------------------------

func test_the_plunge_drops_straight_and_bites_the_floor() -> void:
	await _play(APART)
	_input.bits = PlayerInput.BIT_RIGHT
	await wait_physics_frames(20)
	_input.bits = PlayerInput.BIT_RIGHT | PlayerInput.BIT_JUMP
	for _wait: int in 30:
		await wait_physics_frames(1)
		if _player().velocity.y > 0.0:
			break
	await _tap(PlayerInput.BIT_RIGHT | PlayerInput.BIT_DOWN | PlayerInput.BIT_ATTACK)
	assert_eq(_state_name(), "PLUNGE", "down and SWORD in the air plunge")
	assert_eq(_player().velocity.x, 0.0, "the run is given up: it goes straight down")
	assert_eq(_player().velocity.y, Tuning.MAX_FALL_SPEED, "at full fall speed at once")
	assert_gt(_player().attack_rect().end.y, _player().position.y, "the point is under the feet")

	for _wait: int in 30:
		await wait_physics_frames(1)
		if _player().is_grounded():
			break
	assert_eq(_state_name(), "PLUNGE_LAND", "the blade bites the floor")
	var landed := Engine.get_physics_frames()
	_input.bits = PlayerInput.BIT_JUMP
	for _wait: int in 60:
		await wait_physics_frames(1)
		if _player().state != Player.State.PLUNGE_LAND:
			break
	var held := Engine.get_physics_frames() - landed
	assert_gte(held, roundi(Tuning.PLUNGE_RECOVER / FRAME) - 2,
		"and holds him for the recovery, jump or no jump")


func test_a_plunge_on_a_guard_wounds_once_and_springs_back() -> void:
	await _play(APART)
	var guard := _guard()
	await _drop_from(guard.global_position.x, 44.0)
	await _tap(PlayerInput.BIT_DOWN | PlayerInput.BIT_ATTACK)
	var sprang := false
	for _wait: int in 30:
		await wait_physics_frames(1)
		if _player().velocity.y < 0.0:
			sprang = true
			break
	assert_true(sprang, "the plunge springs back off him, the way a stomp does")
	assert_eq(_state_name(), "JUMP", "into a jump, steerable again")
	# Long enough for any second wound to land, short of the guard getting
	# up out of his stagger and raising on the prince all over again.
	await wait_physics_frames(10)
	assert_true(is_instance_valid(guard) and guard.is_alive(), "two hearts, one plunge")
	if is_instance_valid(guard):
		assert_eq(guard.health, Patrol.MAX_HEALTH - 1, "one plunge, one heart")
	assert_eq(_player().health, Tuning.MAX_HEALTH, "and from above, the cut never reached")


## --- the parry ----------------------------------------------------------------

## Holds still until the guard's raise is `left` seconds from the cut.
func _until_the_raise_has(left: float) -> void:
	var guard := _guard()
	for _wait: int in 60:
		if guard.state == Patrol.State.WINDUP and guard.state_time >= Patrol.WINDUP_TIME - left:
			return
		await wait_physics_frames(1)


func test_a_late_parry_turns_the_cut_and_opens_him() -> void:
	await _play(FACE_TO_FACE)
	var guard := _guard()
	await _until_the_raise_has(0.12)
	assert_eq(guard.state, Patrol.State.WINDUP, "the guard is raising")
	await _tap(PlayerInput.BIT_UP | PlayerInput.BIT_ATTACK)
	assert_eq(_state_name(), "PARRY", "up and SWORD on the ground raise the parry")
	for _wait: int in 30:
		await wait_physics_frames(1)
		if guard.state != Patrol.State.WINDUP and guard.state != Patrol.State.STRIKE:
			break
	assert_eq(_player().health, Tuning.MAX_HEALTH, "the cut was turned")
	assert_eq(guard.state, Patrol.State.STAGGER, "and the guard reels")
	assert_eq(guard.health, Patrol.MAX_HEALTH, "a parry is a defence, not a wound")

	# The riposte comes out at once, without waiting out the parry. Pressed
	# after the clang's held frames: input is read in the player's own step,
	# which a hitstop holds.
	for _wait: int in 20:
		if not Flow.is_hitstopped():
			break
		await wait_physics_frames(1)
	assert_eq(_state_name(), "PARRY", "still in the parry's recovery")
	await _tap(PlayerInput.BIT_ATTACK)
	assert_eq(_state_name(), "ATTACK", "the riposte is immediate")
	await wait_physics_frames(30)
	assert_true(is_instance_valid(guard))
	if is_instance_valid(guard):
		assert_eq(guard.health, Patrol.MAX_HEALTH - 1, "and it lands")


func test_a_parry_on_sight_is_too_soon() -> void:
	await _play(FACE_TO_FACE)
	var guard := _guard()
	await _until_the_raise_has(Patrol.WINDUP_TIME)
	assert_eq(guard.state, Patrol.State.WINDUP, "the guard has just begun to raise")
	await _tap(PlayerInput.BIT_UP | PlayerInput.BIT_ATTACK)
	assert_eq(_state_name(), "PARRY", "the parry went up")
	for _wait: int in 60:
		await wait_physics_frames(1)
		if guard.state == Patrol.State.RECOVER or _player().health < Tuning.MAX_HEALTH:
			break
	assert_eq(_player().health, Tuning.MAX_HEALTH - 1, "and was down again when the cut came")


## The guard's half of the parry, without a scene: only a live cut can be
## turned, and a turned cut costs him no heart but a long reel.
func test_only_a_cut_is_parried_and_it_opens_him_longest() -> void:
	var guard: Patrol = autofree(Patrol.new())
	guard.facing = 1
	guard.position = Vector2(100.0, 200.0)
	assert_false(guard.parried(), "a walking guard has nothing to parry")
	var front := guard.position.x + Patrol.BODY.x * 0.5
	guard.target_rect = Rect2(Vector2(front + 4.0, 200.0 - Tuning.BODY_HEIGHT),
		Vector2(Tuning.BODY_WIDTH, Tuning.BODY_HEIGHT))
	while guard.state != Patrol.State.STRIKE:
		guard.tick(FRAME, true)
	assert_true(guard.parried(), "a live cut is turned")
	assert_eq(guard.health, Patrol.MAX_HEALTH, "without a wound")
	assert_false(guard.is_dangerous(), "and the cut is gone at once")
	var frames := 0
	while guard.state == Patrol.State.STAGGER:
		guard.tick(FRAME, true)
		frames += 1
	assert_gte(frames, roundi(Patrol.PARRIED_TIME / FRAME) - 1, "he reels for PARRIED_TIME")
