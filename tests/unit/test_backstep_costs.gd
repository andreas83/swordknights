extends GutTest
## The backstep's price and its edges, played in the real game scene: no
## riposte and no reel, no jump or turn out of it, no chain, the ground it
## gives up; that it stops at a lip, a gap and a spike pit rather than going
## over; that one swing still takes one heart and the raised blade opens no
## wall; and that the idle, the dust, the cloth and the camera answer to it.
##
## The reading of the stick and the window are tests/unit/test_backstep.gd,
## which also pins the numbers these play. Two files because one held more
## test functions than the lint allows a class, and the line between them is
## the line between what the move IS and what it COSTS.

const GAME_SCENE := "res://scenes/game.tscn"
const FRAME := 1.0 / 60.0

## Open floor both ways, nobody about. The prince spawns facing right.
const OPEN := """; Open








          @         D
######################
######################
"""

## The prince with his back to a wall and a guard in front of him, inside
## each other's reach. The guard raises at once.
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

## The floor ends just behind the prince: a drop of nine tiles.
const LIP := """; Lip








     @              D
     ################
     ################
"""

## A one-tile gap behind the prince: narrower than the slide is long.
const GAP := """; Gap








        @           D
####### #############
#####################
"""

## Spikes set into the floor behind the prince.
const SPIKES := """; Spikes








         @          D
######^^^############
#####################
"""

## A cracked wall right in front of him, the room behind it.
const CRACKED := """; Cracked


       #####
       #####
       &:::#
 D @   &::*#
############
############
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
		if _game.player.state == Player.State.IDLE and _game.player.is_grounded() \
				and not Flow.is_hitstopped():
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


## --- the costs ---------------------------------------------------------------

func test_no_riposte_and_no_reel() -> void:
	await _play(BACK_TO_THE_WALL)
	var guard := _guard()
	await _until_the_raise_has(0.06)
	await _tap(_back() | PlayerInput.BIT_ATTACK)
	var started := Engine.get_physics_frames()
	for _wait: int in 40:
		await wait_physics_frames(1)
		if guard.state != Patrol.State.WINDUP and guard.state != Patrol.State.STRIKE:
			break
	assert_eq(guard.state, Patrol.State.RECOVER, "the guard is in his plain opening, not reeling")
	assert_eq(_player().health, Tuning.MAX_HEALTH, "the cut missed")
	assert_eq(_state_name(), "BACKSTEP", "still in the backstep")
	await _tap(PlayerInput.BIT_ATTACK)
	assert_eq(_state_name(), "BACKSTEP", "SWORD does not cut the recovery short")
	_input.bits = 0
	for _wait: int in 40:
		if _player().state != Player.State.BACKSTEP:
			break
		await wait_physics_frames(1)
	var held := Engine.get_physics_frames() - started
	assert_gte(held, roundi(Tuning.BACKSTEP_TIME / FRAME) - 2, "it is held to the end")


func test_no_jump_and_no_turn_out_of_it() -> void:
	await _play(OPEN)
	var floor_y := _player().position.y
	await _tap(PlayerInput.BIT_LEFT | PlayerInput.BIT_ATTACK)
	_input.bits = PlayerInput.BIT_LEFT | PlayerInput.BIT_JUMP
	var start := Engine.get_physics_frames()
	while Engine.get_physics_frames() - start < roundi(Tuning.BACKSTEP_TIME / FRAME) - 5:
		await wait_physics_frames(1)
		assert_eq(_player().facing, 1, "no turn inside it")
		assert_almost_eq(_player().position.y, floor_y, 0.5, "and no jump: on the floor")
	_input.bits = 0
	assert_eq(_state_name(), "BACKSTEP", "held to the end")


func test_it_does_not_chain() -> void:
	await _play(OPEN)
	await _tap(PlayerInput.BIT_LEFT | PlayerInput.BIT_ATTACK)
	assert_eq(_backsteps, 1, "one backstep")
	# Stick held back and SWORD mashed through the backstep and its rearm.
	var frames := roundi((Tuning.BACKSTEP_TIME + Tuning.BACKSTEP_REARM) / FRAME) - 3
	var start := Engine.get_physics_frames()
	var beat := 0
	while Engine.get_physics_frames() - start < frames:
		var press := PlayerInput.BIT_ATTACK if beat % 2 == 0 else 0
		_input.bits = PlayerInput.BIT_LEFT | press
		beat += 1
		await wait_physics_frames(1)
	_input.bits = 0
	assert_gt(beat, 6, "SWORD went down again and again")
	assert_eq(_backsteps, 1, "a held stick and a mashed button make one backstep, not a chain")
	await wait_physics_frames(20)
	await _until_settled()
	await _tap(_back() | PlayerInput.BIT_ATTACK)
	assert_eq(_backsteps, 2, "once the rearm is spent, the next one comes")


func test_ground_is_lost() -> void:
	await _play(OPEN)
	var start := _player().position.x
	await _tap(PlayerInput.BIT_LEFT | PlayerInput.BIT_ATTACK)
	await _until_settled()
	assert_almost_eq(start - _player().position.x, Tuning.backstep_distance(), 0.5,
		"the slide covers backstep_distance(), as the tuning says")


## --- edges -------------------------------------------------------------------

func _step_back_and_watch() -> Dictionary:
	var floor_y := _player().position.y
	var airborne := false
	await _tap(_back() | PlayerInput.BIT_ATTACK)
	for _frame: int in roundi(Tuning.BACKSTEP_TIME / FRAME) + 10:
		await wait_physics_frames(1)
		airborne = airborne or not _player().is_grounded()
	return {"airborne": airborne, "dropped": _player().position.y - floor_y}


func test_it_stops_at_the_lip() -> void:
	await _play(LIP)
	var lip := 5.0 * Tuning.TILE
	var watched: Dictionary = await _step_back_and_watch()
	assert_eq(_backsteps, 1, "the backstep went")
	assert_eq(_game.deaths, 0, "he did not die")
	assert_false(bool(watched["airborne"]), "and never left the floor")
	assert_almost_eq(float(watched["dropped"]), 0.0, 0.5, "he is on the ledge, not under it")
	assert_almost_eq(_player().position.x - Tuning.BODY_WIDTH * 0.5, lip, 0.05,
		"stopped with his heel on the lip")


func test_it_crosses_no_gap() -> void:
	await _play(GAP)
	var far_edge := 8.0 * Tuning.TILE
	assert_gt(Tuning.backstep_distance(), Tuning.TILE, "the gap is narrower than the slide")
	var watched: Dictionary = await _step_back_and_watch()
	assert_false(bool(watched["airborne"]), "never airborne")
	assert_gte(_player().position.x - Tuning.BODY_WIDTH * 0.5, far_edge - 0.05,
		"he stops on this side of the gap rather than skipping it")


func test_it_does_not_step_into_spikes() -> void:
	await _play(SPIKES)
	var last_stone := 9.0 * Tuning.TILE
	var watched: Dictionary = await _step_back_and_watch()
	# Spikes do not collide, so a body over them drops in and dies -- and the
	# respawn puts it back on this very spot, alive and whole, before the
	# watch is over. Deaths and the floor are what tell.
	assert_eq(_game.deaths, 0, "he did not die")
	assert_false(bool(watched["airborne"]), "and never left the floor")
	assert_eq(_player().health, Tuning.MAX_HEALTH, "and unhurt")
	assert_gte(_player().position.x - Tuning.BODY_WIDTH * 0.5, last_stone - 0.05,
		"stopped on the last stone before the spikes")


## --- one swing, one heart ------------------------------------------------------

func test_one_swing_still_takes_one_heart() -> void:
	await _play(FACE_TO_FACE)
	var guard := _guard()
	await _tap(PlayerInput.BIT_ATTACK)
	await wait_physics_frames(2)
	await _until_settled()
	for _wait: int in 30:
		if _player().state == Player.State.IDLE and _player().is_grounded() \
				and not Flow.is_hitstopped():
			break
		await wait_physics_frames(1)
	assert_eq(guard.health, Patrol.MAX_HEALTH - 1, "the swing took a heart")
	# Straight out of it with a backstep: the raised blade is no second blow.
	await _tap(_back() | PlayerInput.BIT_ATTACK)
	assert_eq(_state_name(), "BACKSTEP", "the backstep is on")
	for _frame: int in roundi(Tuning.BACKSTEP_TIME / FRAME):
		assert_false(_player().attack_rect().has_area(), "the raised blade is never live")
		await wait_physics_frames(1)
	assert_eq(_swings, 1, "a backstep is not a swing")
	assert_true(is_instance_valid(guard) and guard.is_alive(), "two hearts, one swing")
	if is_instance_valid(guard):
		assert_eq(guard.health, Patrol.MAX_HEALTH - 1, "one swing, one heart")


func test_the_raised_blade_breaks_no_wall() -> void:
	await _play(CRACKED)
	await _hold(PlayerInput.BIT_RIGHT, 60)
	assert_eq(_game.secrets.count, 0, "pressed against the cracked wall")
	await _tap(PlayerInput.BIT_LEFT | PlayerInput.BIT_ATTACK)
	await _until_settled()
	await wait_physics_frames(5)
	assert_eq(_backsteps, 1, "the backstep went")
	assert_eq(_game.secrets.count, 0, "the blade raised across the body is not a blow")
	assert_true(_game.level.data.is_solid(7, 5), "the wall stands")


## --- presentation --------------------------------------------------------------

func test_no_idle_and_the_feel_beat_through_the_front_door() -> void:
	await _play(OPEN)
	await _tap(PlayerInput.BIT_LEFT | PlayerInput.BIT_ATTACK)
	assert_false(IdleArt.is_calm(_player()), "a backstep is not standing idle")
	var fx := _player().get_node_or_null("PlayerFx") as PlayerFx
	assert_not_null(fx, "the effects node is there")
	if fx != null:
		var live := 0
		for i: int in PlayerFx.MAX_PARTICLES:
			if fx._p[i * PlayerFx.STRIDE + PlayerFx.P_LIFE] > 0.0:
				live += 1
		assert_gte(live, PlayerFx.BACKSTEP_DUST, "dust at the feet")
	for event: String in ["cloth", "sword"]:
		assert_true(PlayerAudio.event_names().has(event), "%s is a voice the game has" % event)
	assert_true(PlayerAudio.CLOTH_ON_ENTER.has(Player.State.BACKSTEP), "the cloth moves")
	var lead_before: float = _game.camera._look_ahead_current
	for _frame: int in roundi(Tuning.BACKSTEP_SLIDE / FRAME):
		await wait_physics_frames(1)
	assert_almost_eq(_game.camera._look_ahead_current, lead_before, 0.01,
		"the frame does not lead a step taken against the facing")
