extends GutTest
## The backstep: back + SWORD on the ground. A short slide away from the way
## the prince faces with the blade raised across the body, during which a
## guard's cut from the front does not land.
##
## Held to what the parry and the plunge are held to in test_specials.gd --
## it is on the stick and the two buttons, it pays, and it costs -- plus the
## two things only a move that travels along the floor can get wrong: it must
## read the stick before the stick has turned him round, and it must never
## carry him off a ledge or across a gap. This file pins the numbers against
## Patrol's raise, cut and opening, reads the stick and plays the window;
## tests/unit/test_backstep_costs.gd plays the costs and the edges. Two files
## because one held more test functions than the lint allows a class.
##
## The intended role, which the numbers enforce: the parry WINS the exchange
## (the guard reels, the riposte is free), the backstep SURVIVES it (no reel,
## no riposte, and the ground it gave up costs the guard's whole opening).

const GAME_SCENE := "res://scenes/game.tscn"
const TOUCH_SCENE := preload("res://scenes/touch_controls.tscn")
const FRAME := 1.0 / 60.0

## Open floor both ways, nobody about. The prince spawns facing right.
const OPEN := """; Open








          @         D
######################
######################
"""

## The prince with his back to a wall and a guard in front of him, inside
## each other's reach: the backstep has nowhere to go, so only its window can
## save him. The guard raises at once.
const BACK_TO_THE_WALL := """; Back to the Wall







   #
   #@p            D
###################
###################
"""

## The prince at column 4 facing right, a guard at column 5 facing him.
const FACE_TO_FACE := """; Face to Face








    @p            D
###################
###################
"""


class ScriptedInput extends PlayerInput:
	var bits := 0

	func poll() -> void:
		apply_bits(bits)


var _game: Game
var _input: ScriptedInput
var _backsteps := 0
var _swings := 0


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
	_backsteps = 0
	_swings = 0
	_game.player.backstepped.connect(func() -> void: _backsteps += 1)
	_game.player.attacked.connect(func() -> void: _swings += 1)
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


## Holds `bits` for `frames` physics frames (two at the least). GUT's
## wait_physics_frames(n) waits n + 1, so it is asked for one fewer.
func _hold(bits: int, frames: int) -> void:
	_input.bits = bits
	await wait_physics_frames(maxi(1, frames - 1))
	_input.bits = 0


## The stick pointing away from the way the prince faces.
func _back() -> int:
	return PlayerInput.BIT_LEFT if _player().facing > 0 else PlayerInput.BIT_RIGHT


## Waits out a backstep in progress, and any hitstop.
func _until_settled() -> void:
	for _wait: int in 90:
		if _player().state != Player.State.BACKSTEP and not Flow.is_hitstopped():
			return
		await wait_physics_frames(1)


## Holds still until the guard's raise is `left` seconds from the cut.
func _until_the_raise_has(left: float) -> void:
	var guard := _guard()
	for _wait: int in 60:
		if guard.state == Patrol.State.WINDUP and guard.state_time >= Patrol.WINDUP_TIME - left:
			return
		await wait_physics_frames(1)


## --- the numbers -------------------------------------------------------------

## How far the guard's half step into his cut carries his blade.
func _guard_step() -> float:
	return Patrol.SPEED * 0.6 * Patrol.STRIKE_TIME


## Frames of slide before the body has covered `distance`.
func _slide_frames(distance: float) -> int:
	var covered := 0.0
	var frames := 0
	while covered < distance and frames < 600:
		covered += Tuning.backstep_speed(frames * FRAME) * FRAME
		frames += 1
	return frames


## Frames, from a standstill `gap` px in front of a guard, until a swing can
## first be live on him: run in at the real acceleration and press the swing
## on whichever frame lets its slide carry the live blade onto him soonest.
func _frames_to_wound(gap: float) -> int:
	var lead := ceili(Tuning.ATTACK_TIME * 0.25 / FRAME)
	var run := 0.0
	var speed := 0.0
	for frame: int in 600:
		var at := run
		var sliding := speed
		for _k: int in lead:
			sliding = move_toward(sliding, 0.0, Tuning.GROUND_FRICTION * FRAME)
			at += sliding * FRAME
		if at >= gap - Tuning.ATTACK_REACH:
			return frame + lead
		speed = minf(Tuning.RUN_SPEED, speed + Tuning.GROUND_ACCEL * FRAME)
		run += speed * FRAME
	return 600


func test_the_window_outlasts_a_cut_and_not_a_raise() -> void:
	# A backstep with nowhere to go can still outlast the whole cut...
	assert_gt(Tuning.BACKSTEP_ACTIVE, Patrol.STRIKE_TIME, "the window is longer than the cut")
	# ...but thrown on sight with nowhere to go, it is over before the blade.
	assert_lt(Tuning.BACKSTEP_ACTIVE, Patrol.WINDUP_TIME, "a backstep on sight is too soon")
	assert_lt(Tuning.BACKSTEP_ACTIVE, Tuning.BACKSTEP_TIME, "and it leaves a recovery")
	assert_lt(Tuning.BACKSTEP_SLIDE, Tuning.BACKSTEP_TIME, "the feet stop before it ends")


func test_it_gives_up_a_tile_or_more_and_steps_out_of_the_cut() -> void:
	var distance := Tuning.backstep_distance()
	assert_gte(distance, Tuning.TILE, "at least a tile of ground is lost")
	assert_lte(distance, Tuning.TILE * 1.5, "and no more than a tile and a half")
	var out := Patrol.REACH + _guard_step() - Patrol.ENGAGE_GAP
	assert_gt(distance, out, "from where a guard raises, it carries the body out of his reach")


## The latest backstep that needed its window is the one thrown just too late
## to slide clear before the blade came down. From there, the recovery, the run
## back over the lost ground and the swing's lead outlast the guard's opening:
## the cut was survived, and the guard lost nothing by it. A parry thrown in
## the same frames turns the cut and gets its riposte in at once.
func test_it_survives_the_exchange_and_the_parry_wins_it() -> void:
	var out := Patrol.REACH + _guard_step() - Patrol.ENGAGE_GAP
	var latest := _slide_frames(out) * FRAME
	var gap := Patrol.ENGAGE_GAP + Tuning.backstep_distance() - _guard_step()
	var wound := -latest + Tuning.BACKSTEP_TIME + _frames_to_wound(gap) * FRAME
	var opening := Patrol.STRIKE_TIME + Patrol.RECOVER_TIME
	assert_gt(wound, opening, "his opening closes before the backstep can answer it")
	# With its back to a wall it loses no ground, and still answers later than
	# the parry: its earliest start that covers the whole cut, plus its length,
	# is after the riposte's held frames.
	var blocked := Patrol.STRIKE_TIME - Tuning.BACKSTEP_ACTIVE + Tuning.BACKSTEP_TIME
	assert_gt(blocked, Flow.PARRY_FRAMES * FRAME, "even blocked, the parry's riposte is first")


func test_it_cannot_be_held_up_as_a_shield() -> void:
	# Between the windows of two backsteps as close as they can come there is
	# always a hole a whole cut long.
	var hole := Tuning.BACKSTEP_TIME - Tuning.BACKSTEP_ACTIVE + Tuning.BACKSTEP_REARM
	assert_gt(hole, Patrol.STRIKE_TIME, "a chain of backsteps leaves a cut-sized hole")
	# And backstepping away is slower than walking away: it is not travel.
	var pace := Tuning.backstep_distance() / (Tuning.BACKSTEP_TIME + Tuning.BACKSTEP_REARM)
	assert_lt(pace, Tuning.WALK_SPEED, "a chain retreats slower than a walk")


func test_the_grammar_is_untouched() -> void:
	assert_eq(Tuning.hop_tiles(), 2, "a 2-tile rise is a hop")
	assert_eq(Tuning.platform_step_tiles(), 3, "a 3-tile rise is a step")
	assert_eq(Tuning.grab_tiles(), 4, "a 4-tile rise is a grab")
	assert_eq(Tuning.gap_tiles(), 3, "a 3-tile gap is the widest jump")


## --- reading the stick -------------------------------------------------------

func test_back_and_sword_together_step_back_facing_the_same_way() -> void:
	await _play(OPEN)
	var start := _player().position.x
	assert_eq(_player().facing, 1, "facing right")
	await _tap(PlayerInput.BIT_LEFT | PlayerInput.BIT_ATTACK)
	assert_eq(_state_name(), "BACKSTEP", "back and SWORD on the ground is a backstep")
	assert_eq(_player().facing, 1, "and it did not turn him")
	assert_eq(_swings, 0, "it is not a swing")
	await _until_settled()
	assert_eq(_player().facing, 1, "still facing the way he was")
	assert_lt(_player().position.x, start - Tuning.TILE, "a tile or more further back")


func test_the_stick_may_lead_the_button_without_turning_him() -> void:
	await _play(OPEN)
	# Three frames of stick before the button: standing, that turned him on the
	# spot. The backstep reads the stick against the facing before that turn.
	await _hold(PlayerInput.BIT_LEFT, 3)
	assert_eq(_player().facing, -1, "the stick alone turns a standing prince")
	await _tap(PlayerInput.BIT_LEFT | PlayerInput.BIT_ATTACK)
	assert_eq(_state_name(), "BACKSTEP", "the press a few frames behind the stick backsteps")
	assert_eq(_player().facing, 1, "and the turn is taken back")
	await _until_settled()
	assert_eq(_player().facing, 1, "he never ends it facing away")
	assert_eq(_swings, 0, "and nothing swung")


func test_a_turn_that_has_settled_is_a_turn_and_a_swing() -> void:
	await _play(OPEN)
	var frames := ceili(Tuning.BACKSTEP_READ / FRAME) + 4
	await _hold(PlayerInput.BIT_LEFT, frames)
	await _tap(PlayerInput.BIT_LEFT | PlayerInput.BIT_ATTACK)
	assert_eq(_state_name(), "ATTACK", "past BACKSTEP_READ the stick is just where he faces")
	assert_eq(_player().facing, -1, "and he swings the way he turned")
	assert_eq(_backsteps, 0, "no backstep")


func test_a_wiggle_does_not_step_toward_the_blade() -> void:
	await _play(OPEN)
	# Back and forward again inside the read: the second turn cancels the
	# first, so SWORD with the stick forward is the plain swing, forward.
	await _hold(PlayerInput.BIT_LEFT | PlayerInput.BIT_WALK, 2)
	await _hold(PlayerInput.BIT_RIGHT | PlayerInput.BIT_WALK, 2)
	await _tap(PlayerInput.BIT_RIGHT | PlayerInput.BIT_ATTACK)
	assert_eq(_state_name(), "ATTACK", "stick forward and SWORD swings")
	assert_eq(_player().facing, 1, "forward")


func test_at_a_run_the_stick_behind_is_still_a_turn() -> void:
	await _play(OPEN)
	await _hold(PlayerInput.BIT_RIGHT, 30)
	assert_gt(absf(_player().velocity.x), Tuning.WALK_SPEED, "running")
	_input.bits = PlayerInput.BIT_LEFT
	await wait_physics_frames(1)
	assert_eq(_state_name(), "TURN", "the stick behind a run plants a turn")
	await _tap(PlayerInput.BIT_LEFT | PlayerInput.BIT_ATTACK)
	_input.bits = PlayerInput.BIT_LEFT
	for _wait: int in 20:
		await wait_physics_frames(1)
		if _player().state == Player.State.ATTACK or _backsteps > 0:
			break
	_input.bits = 0
	assert_eq(_state_name(), "ATTACK", "and SWORD in it swings when the turn is done")
	assert_eq(_player().facing, -1, "the new way")
	assert_eq(_backsteps, 0, "a backstep is a move from a stance")


func test_up_wins_over_back_and_sword_alone_swings() -> void:
	await _play(OPEN)
	await _tap(PlayerInput.BIT_UP | PlayerInput.BIT_LEFT | PlayerInput.BIT_ATTACK)
	assert_eq(_state_name(), "PARRY", "up and back with SWORD is the parry")
	await wait_physics_frames(ceili(Tuning.PARRY_TIME / FRAME) + 2)
	await _tap(PlayerInput.BIT_ATTACK)
	assert_eq(_state_name(), "ATTACK", "SWORD alone is the swing")
	assert_eq(_backsteps, 0, "neither is a backstep")


func test_in_the_air_it_is_the_slash() -> void:
	await _play(OPEN)
	_input.bits = PlayerInput.BIT_JUMP
	for _wait: int in 20:
		await wait_physics_frames(1)
		if not _player().is_grounded() and _player().velocity.y < 0.0:
			break
	await _tap(PlayerInput.BIT_JUMP | PlayerInput.BIT_LEFT | PlayerInput.BIT_ATTACK)
	assert_eq(_state_name(), "AIR_SLASH", "back and SWORD in the air is the slash")
	assert_eq(_backsteps, 0, "the backstep is ground-only")


func test_it_is_on_the_stick_and_the_sword_button() -> void:
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
	for push: Vector2 in [Vector2(-1.0, 0.0), Vector2(1.0, 0.0)]:
		controls._input(_touch(origin, true, 1))
		controls._input(_drag(origin + push * TouchControls.STICK_RADIUS, 1))
		controls._input(_touch(sword["at"], true, 2))
		var bits := PlayerInput.bits_from_actions()
		var wanted := PlayerInput.BIT_LEFT if push.x < 0.0 else PlayerInput.BIT_RIGHT
		assert_eq(bits & (wanted | PlayerInput.BIT_ATTACK), wanted | PlayerInput.BIT_ATTACK,
			"the stick sideways and SWORD together reach the simulation")
		assert_eq(bits & (PlayerInput.BIT_UP | PlayerInput.BIT_DOWN), 0,
			"without reading as up or down")
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


## --- the window --------------------------------------------------------------

## The window, without a scene: only in a backstep, only from the front, and
## only for BACKSTEP_ACTIVE.
func test_only_the_front_and_only_the_window() -> void:
	var player: Player = autofree(Player.new())
	player.position = Vector2(100.0, 100.0)
	player.facing = 1
	assert_false(player.evades(120.0), "standing, nothing is evaded")
	player.state = Player.State.BACKSTEP
	player.state_time = 0.0
	assert_true(player.evades(120.0), "a cut from in front misses")
	assert_false(player.evades(80.0), "a cut from behind does not")
	player.state_time = Tuning.BACKSTEP_ACTIVE
	assert_false(player.evades(120.0), "and after the window nothing misses")
	player.facing = -1
	player.state_time = 0.0
	assert_true(player.evades(80.0), "facing left, the front is the left")


func test_a_timed_backstep_outlasts_the_cut_with_nowhere_to_go() -> void:
	await _play(BACK_TO_THE_WALL)
	var guard := _guard()
	await _until_the_raise_has(0.06)
	assert_eq(guard.state, Patrol.State.WINDUP, "the guard is raising")
	await _tap(_back() | PlayerInput.BIT_ATTACK)
	assert_eq(_state_name(), "BACKSTEP", "the backstep is on")
	for _wait: int in 40:
		await wait_physics_frames(1)
		if guard.state == Patrol.State.RECOVER:
			break
	assert_eq(guard.state, Patrol.State.RECOVER, "the cut came and went")
	assert_lt(guard.position.x - _player().position.x, Patrol.REACH + Tuning.BODY_WIDTH,
		"with the prince still inside its reach")
	assert_eq(_player().health, Tuning.MAX_HEALTH, "and it missed him")
	assert_eq(guard.health, Patrol.MAX_HEALTH, "a backstep is no wound")


func test_after_the_window_he_is_hit() -> void:
	await _play(BACK_TO_THE_WALL)
	var guard := _guard()
	await _until_the_raise_has(Patrol.WINDUP_TIME)
	assert_eq(guard.state, Patrol.State.WINDUP, "the guard has just begun to raise")
	await _tap(_back() | PlayerInput.BIT_ATTACK)
	assert_eq(_state_name(), "BACKSTEP", "the backstep went at once")
	for _wait: int in 60:
		await wait_physics_frames(1)
		if guard.state == Patrol.State.RECOVER or _player().health < Tuning.MAX_HEALTH:
			break
	assert_eq(_player().health, Tuning.MAX_HEALTH - 1, "and was over when the cut came")


func test_a_cut_from_behind_lands() -> void:
	await _play(FACE_TO_FACE)
	var guard := _guard()
	# Looking away from the guard: the backstep goes back into him.
	_player().facing = -1
	await _until_the_raise_has(0.03)
	assert_eq(guard.state, Patrol.State.WINDUP, "the guard is raising at his back")
	await _tap(_back() | PlayerInput.BIT_ATTACK)
	assert_eq(_state_name(), "BACKSTEP", "the backstep is on")
	# This cut, and only this one: a guard that raises again later would land
	# a second cut on anybody, and that would prove nothing about this one.
	for _wait: int in 30:
		await wait_physics_frames(1)
		if guard.state != Patrol.State.WINDUP and guard.state != Patrol.State.STRIKE:
			break
	assert_eq(guard.state, Patrol.State.RECOVER, "the cut went through uninterrupted")
	assert_eq(_player().health, Tuning.MAX_HEALTH - 1, "and landed: from behind, it is not dodged")

