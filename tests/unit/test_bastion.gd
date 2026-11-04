extends GutTest
## The Bastion (scripts/entities/bastion.gd), pinned the way test_patrol.gd
## and test_specials.gd pin the sentinel, against docs/campaign.md:
##
## - the shove's tell is WINDUP_TIME, 27 frames, and LONGER WARNINGS
##   stretches it and nothing else;
## - blows from the front clang -- a swing, a shot, a stomp -- and push the
##   prince back; nothing parries a shove;
## - two plunges kill, and the rebound off the first is what makes the second;
## - the turn exposes his back for 30 frames, far longer than a swing's lead;
## - the shove costs no heart and grants no grace, and throws him about two
##   tiles; his front is a wall a running prince cannot pass;
## - his weight holds a plate, and the gate falls when he does.

const FRAME := 1.0 / 60.0
const GAME_SCENE := "res://scenes/game.tscn"

## A yard: the prince comes from the left at a Bastion posted facing him.
const YARD := """; Bastion Yard






  @         w            D
###########################
###########################
"""

## A Bastion on a plate that holds a gate behind him.
const WEIGHED := """;! channel 3 hold 1.0
; Weighed Gate






##################3########
                  !
  @         w     !      D
############o##############
############3##############
"""


class ScriptedInput extends PlayerInput:
	var bits := 0

	func poll() -> void:
		apply_bits(bits)


var _game: Game
var _input: ScriptedInput


func before_each() -> void:
	Assist.reset()


func after_each() -> void:
	Assist.reset()


## --- the clock, without a scene ----------------------------------------------------

## A Bastion facing right with a prince just inside a tile of his shield, so
## he winds up on the first frame. Frames each state lasted, to the end of
## the recovery.
func _shove_frames() -> Dictionary:
	var guard: Bastion = autofree(Bastion.new())
	guard.facing = 1
	guard.position = Vector2(100.0, 200.0)
	guard.post_x = guard.position.x
	var front := guard.position.x + Bastion.BODY.x * 0.5
	guard.target_rect = Rect2(Vector2(front + Bastion.SHOVE_GAP - 2.0, 200.0 - 22.0),
		Vector2(Tuning.BODY_WIDTH, Tuning.BODY_HEIGHT))
	var frames := {}
	for _frame: int in 300:
		guard.tick(FRAME, true)
		var state := String(Bastion.State.keys()[guard.state])
		frames[state] = int(frames.get(state, 0)) + 1
		if frames.has("RECOVER") and guard.state != Bastion.State.RECOVER:
			break
	return frames


func test_the_shove_is_told_for_the_sentinels_27_frames() -> void:
	var frames := _shove_frames()
	assert_almost_eq(int(frames.get("WINDUP", 0)), 27, 1, "the windup is the game's telegraph")
	assert_almost_eq(int(frames.get("SHOVE", 0)), 9, 1, "the shove is a cut's 9 frames")
	assert_almost_eq(int(frames.get("RECOVER", 0)), 33, 1, "and the recovery a cut's 33")


func test_longer_warnings_stretch_the_windup_and_nothing_else() -> void:
	var off := _shove_frames()
	Assist.load_saved(UserData.at("user://test_bastion_assist.cfg"))
	Assist.set_longer_warnings(true)
	var on := _shove_frames()
	assert_almost_eq(int(on.get("WINDUP", 0)), roundi(27 * Assist.LONGER), 1,
		"the windup, frame for frame")
	assert_eq(on.get("SHOVE"), off.get("SHOVE"), "the shove itself is not slowed")
	assert_eq(on.get("RECOVER"), off.get("RECOVER"), "nor the recovery")
	var assist_file := UserData.at("user://test_bastion_assist.cfg")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(assist_file))


func test_the_front_turns_every_blow_but_the_plunge() -> void:
	var guard: Bastion = autofree(Bastion.new())
	guard.facing = -1
	guard.position = Vector2(100.0, 200.0)
	var front := 60.0
	assert_eq(guard.take_blow(Foe.Blow.SWORD, front), Foe.Outcome.BLOCKED, "a swing clangs")
	assert_eq(guard.take_blow(Foe.Blow.SHOT, front), Foe.Outcome.BLOCKED, "a shot stops")
	assert_eq(guard.take_blow(Foe.Blow.STOMP, 100.0), Foe.Outcome.BLOCKED,
		"a stomp rings off the hat")
	assert_eq(guard.health, Bastion.MAX_HEALTH, "and none of them wounds")
	assert_eq(guard.take_blow(Foe.Blow.PLUNGE, 100.0), Foe.Outcome.WOUNDED, "a plunge does")
	assert_eq(guard.velocity.x, 0.0, "and does not knock him back: the rebound comes down again")
	assert_eq(guard.take_blow(Foe.Blow.PLUNGE, 100.0), Foe.Outcome.KILLED, "two plunges kill")


func test_a_blade_at_his_back_wounds_and_the_turn_leaves_it_open() -> void:
	var guard: Bastion = autofree(Bastion.new())
	guard.facing = -1
	guard.position = Vector2(100.0, 200.0)
	guard.post_x = 100.0
	guard.target_rect = Rect2(Vector2(110.0, 178.0), Vector2(9.0, 22.0))
	guard.tick(FRAME, true)
	assert_eq(guard.state, Bastion.State.TURN, "a prince behind him: he turns")
	var turning := 1
	for _frame: int in 120:
		guard.tick(FRAME, true)
		if guard.state != Bastion.State.TURN:
			break
		turning += 1
	assert_almost_eq(turning, 30, 1, "for 30 frames")
	var lead := Tuning.ATTACK_TIME * 0.25 / FRAME
	assert_gt(float(turning), lead * 4.0, "many times a swing's %.1f-frame lead" % lead)
	var back: Bastion = autofree(Bastion.new())
	back.facing = -1
	back.position = Vector2(100.0, 200.0)
	assert_eq(back.take_blow(Foe.Blow.SWORD, 120.0), Foe.Outcome.WOUNDED, "his back is open")


func test_a_shove_is_not_a_blade() -> void:
	var guard: Bastion = autofree(Bastion.new())
	guard.facing = 1
	guard.position = Vector2(100.0, 200.0)
	guard.state = Bastion.State.SHOVE
	var shove: FoeDanger = guard.dangers()[0]
	assert_eq(shove.damage, 0, "it costs no heart")
	assert_eq(shove.push, Bastion.SHOVE_PUSH, "it throws him at (180, -120) px/s")
	assert_false(shove.can_be_parried(), "there is nothing to parry")
	assert_true(shove.evadable, "and the backstep slides out of it")
	assert_true(guard.has_weight(), "he is heavy")


## --- in the scene ---------------------------------------------------------------

func _play(text: String) -> void:
	var data := AsciiLevel.new()
	data.parse(text)
	assert_eq(data.problems, PackedStringArray(), "the level parses clean")
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Game
	_game.level_source = data
	add_child_autofree(_game)
	_input = ScriptedInput.new()
	_game.player.input = _input
	await wait_physics_frames(4)


func _bastion() -> Bastion:
	for node: Node in _game.get_node("Entities").get_children():
		if node is Bastion and not node.is_queued_for_deletion():
			return node as Bastion
	return null


## One physics tick at a time, as tests/unit/test_lift.gd explains.
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


func test_his_front_is_a_wall_and_his_shove_costs_no_heart() -> void:
	await _play(YARD)
	var guard := _bastion()
	var face := guard.global_position.x - Bastion.BODY.x * 0.5
	var nearest := [INF, false, 0.0]
	await _drive(func(t: int) -> int:
		var gap := face - (_game.player.position.x + Tuning.BODY_WIDTH * 0.5)
		nearest[0] = minf(float(nearest[0]), gap)
		nearest[2] = maxf(float(nearest[2]), absf(guard.global_position.x - guard.post_x))
		if guard.state == Bastion.State.SHOVE:
			nearest[1] = true
		return -1 if t > 240 else PlayerInput.BIT_RIGHT, 300)
	assert_gt(float(nearest[0]), -4.0, "running at him, he never got through the shield")
	assert_true(bool(nearest[1]), "and the Bastion shoved")
	assert_eq(_game.player.health, Tuning.MAX_HEALTH, "the shove cost no heart")
	assert_eq(_game.player.invulnerable, 0.0, "and gave no grace to walk through him in")
	assert_eq(_game.deaths, 0, "alive")
	assert_lte(float(nearest[2]), Bastion.LUNGE + 0.5, "he never strayed past one lunge")
	await _drive(func(_t: int) -> int: return 0, 60)
	assert_almost_eq(guard.global_position.x, guard.post_x, 0.5,
		"and holds his spot: shove after shove, he steps back to his post")


func test_a_shove_throws_him_about_two_tiles() -> void:
	await _play(YARD)
	var guard := _bastion()
	await _drive(func(_t: int) -> int:
		return -1 if guard.state == Bastion.State.WINDUP else PlayerInput.BIT_RIGHT, 200)
	var before := _game.player.position.x
	await _drive(func(_t: int) -> int:
		return -1 if guard.state == Bastion.State.RECOVER else 0, 60)
	await _drive(func(_t: int) -> int:
		return -1 if _game.player.is_grounded() and _game.player.velocity.x == 0.0 else 0, 90)
	var thrown := before - _game.player.position.x
	assert_almost_eq(thrown, 2.0 * Tuning.TILE, 10.0,
		"thrown back about two tiles (%.1f px)" % thrown)


func test_two_plunges_kill_him() -> void:
	await _play(YARD)
	var guard := _bastion()
	var above := Vector2(guard.global_position.x, guard.global_position.y - 64.0)
	_game.player.position = above
	_game.player.velocity = Vector2.ZERO
	var plunges := [0]
	await _drive(func(t: int) -> int:
		if not guard.is_alive():
			return -1
		if _game.player.state == Player.State.PLUNGE:
			return PlayerInput.BIT_DOWN
		if not _game.player.is_grounded() and t % 2 == 0:
			if _game.player.velocity.y > -40.0:
				plunges[0] = int(plunges[0]) + 1
				return PlayerInput.BIT_DOWN | PlayerInput.BIT_ATTACK
		return PlayerInput.BIT_DOWN, 240)
	assert_false(guard.is_alive(), "two plunges, and down he goes")
	assert_eq(_game.player.health, Tuning.MAX_HEALTH, "without a scratch")


func test_his_weight_holds_the_gate_until_he_falls() -> void:
	await _play(WEIGHED)
	await wait_physics_frames(40)
	var gate: Gate = null
	for node: Node in _game.get_node("Entities").get_children():
		if node is Gate:
			gate = node as Gate
	assert_false(gate.is_shut(), "his weight on the plate holds the gate up")
	assert_true(_game._bus.is_on(&"3"), "wire 3 is on")
	_bastion().hit(0.0)
	_bastion().hit(0.0)
	await wait_physics_frames(4)
	assert_true(_game._bus.is_on(&"3"), "he falls, and the hold starts")
	await _drive(func(_t: int) -> int: return -1 if gate.is_shut() else 0, 120)
	assert_true(gate.is_shut(), "then the gate falls")
