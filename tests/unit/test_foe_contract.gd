extends GutTest
## The foe contract (scripts/entities/foe.gd), held by a foe that exists only
## in this file and is refereed by the real game scene.
##
## The guard only ever answers the contract one way -- every blow a wound,
## every cut parriable -- so the guard's own suites cannot show that Game
## reads the answers rather than assuming them. The sentry here answers
## differently on purpose: a shield that turns a sword from the front, a
## spiked helm no stomp lands on, a slam no parry turns. Each test is one of
## those answers going through Game, plus the post memory that keeps a foe
## down after a respawn, the summons that has no post, and the presentation
## hooks that keep a foe's sounds on GameAudio.cue and its weight on Game's
## one impact budget.

const GAME_SCENE := "res://scenes/game.tscn"
const DeathWatch := preload("res://tests/death_watch.gd")
const SENTRY := "test_sentry"

## The prince at column 4 facing right; the sentry goes at column 5, inside the
## sword's reach.
const FLOOR := """; Contract Floor








    @            D
###################
###################
"""


## A foe that faces west, with a shield in front and spikes on its helm.
class Sentry extends Foe:
	var facing := -1
	var health := 2
	var slamming := false
	var blows: Array[int] = []

	func bounds() -> Rect2:
		return Rect2(global_position - Vector2(5.0, 20.0), Vector2(10.0, 20.0))

	func is_alive() -> bool:
		return health > 0

	func is_dangerous() -> bool:
		return slamming and is_alive()

	## A slam across the floor either side: there is no turning it.
	func dangers() -> Array[FoeDanger]:
		var slam := FoeDanger.make(
			Rect2(global_position.x - 24.0, global_position.y - 22.0, 48.0, 22.0),
			global_position.x)
		var out: Array[FoeDanger] = [slam]
		return out

	func hit(_from_x: float) -> bool:
		health -= 1
		if health <= 0:
			defeated.emit()
			return true
		return false

	func take_blow(blow: Blow, from_x: float) -> Outcome:
		blows.append(blow)
		if blow == Blow.STOMP:
			return Outcome.NONE
		if blow == Blow.SWORD and int(signf(from_x - global_position.x)) == facing:
			return Outcome.BLOCKED
		return super(blow, from_x)


class ScriptedInput extends PlayerInput:
	var bits := 0

	func poll() -> void:
		apply_bits(bits)


## Stands in for the audio director and writes down what it is asked to play.
class CueRecorder extends Node:
	var settings := AudioSettings.new()
	var heard: Array[String] = []

	func play(event: String, opts: Dictionary = {}) -> AudioStreamPlayer:
		heard.append("%s %s" % [event, opts])
		return null

	func toggle_mute() -> void:
		pass


var _game: Game
var _input: ScriptedInput


func before_all() -> void:
	EntityRegistry.add_for_test(SENTRY, Sentry)


func after_all() -> void:
	EntityRegistry.remove_for_test(SENTRY)


func _play() -> void:
	var data := AsciiLevel.new()
	data.parse(FLOOR)
	data.entities.append({"kind": SENTRY, "cell": Vector2i(5, 8)})
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Game
	_game.level_source = data
	add_child_autofree(_game)
	_input = ScriptedInput.new()
	_game.player.input = _input
	for _frame: int in 30:
		await wait_physics_frames(1)
		if _game.player.state == Player.State.IDLE and not Flow.is_hitstopped():
			break


func _sentries() -> Array[Sentry]:
	var out: Array[Sentry] = []
	for node: Node in _game.get_node("Entities").get_children():
		if node is Sentry and not node.is_queued_for_deletion():
			out.append(node as Sentry)
	return out


func _sentry() -> Sentry:
	var all := _sentries()
	return all[0] if not all.is_empty() else null


func _swing() -> void:
	_input.bits = PlayerInput.BIT_ATTACK
	await wait_physics_frames(1)
	_input.bits = 0
	await wait_physics_frames(30)


## Kills the prince and waits until the checkpoint has him back.
func _die_and_return() -> void:
	_game.player.kill()
	for _frame: int in 120:
		await wait_physics_frames(1)
		if _game.phase == Game.Phase.PLAYING and _game.player.is_alive():
			break
	await wait_physics_frames(2)


func test_a_blocked_blow_is_no_wound_and_one_from_behind_is() -> void:
	await _play()
	var sentry := _sentry()
	await _swing()
	assert_eq(sentry.blows, [Foe.Blow.SWORD] as Array[int], "the swing reached it")
	assert_eq(sentry.health, 2, "and its shield turned it: Game read BLOCKED, not a wound")

	_game.player.position.x = sentry.position.x + 14.0
	_game.player.facing = -1
	await _swing()
	assert_eq(sentry.health, 1, "from behind, the same swing wounds")


func test_a_stomp_the_foe_refuses_is_not_a_stomp() -> void:
	await _play()
	var sentry := _sentry()
	_game.player.position = sentry.position + Vector2(0.0, -40.0)
	_game.player.velocity = Vector2.ZERO
	var bounced := false
	for _frame: int in 40:
		await wait_physics_frames(1)
		bounced = bounced or _game.player.velocity.y < 0.0
	assert_has(sentry.blows, Foe.Blow.STOMP, "the prince came down on its helm")
	assert_false(bounced, "and was not sprung back: NONE means it was never a stomp")
	assert_eq(sentry.health, 2, "nor was it wounded")


func test_a_danger_with_no_parry_lands_through_a_raised_sword() -> void:
	await _play()
	var sentry := _sentry()
	_input.bits = PlayerInput.BIT_UP | PlayerInput.BIT_ATTACK
	await wait_physics_frames(1)
	_input.bits = 0
	assert_eq(_game.player.state, Player.State.PARRY, "the parry is up, facing the sentry")
	sentry.slamming = true
	await wait_physics_frames(2)
	sentry.slamming = false
	assert_eq(_game.player.health, Tuning.MAX_HEALTH - 1, "a slam is not a cut: it lands")


func test_a_foe_cut_down_stays_down_and_one_standing_comes_back_whole() -> void:
	var data := AsciiLevel.new()
	data.parse(FLOOR)
	data.entities.append({"kind": SENTRY, "cell": Vector2i(5, 8)})
	data.entities.append({"kind": SENTRY, "cell": Vector2i(12, 8)})
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Game
	_game.level_source = data
	add_child_autofree(_game)
	_input = ScriptedInput.new()
	_game.player.input = _input
	await wait_physics_frames(10)

	var near := _sentries()[0]
	var far := _sentries()[1]
	var far_post := far.position
	near.hit(0.0)
	near.hit(0.0)
	far.hit(0.0)
	assert_false(near.is_alive(), "one is cut down")
	assert_eq(far.health, 1, "the other is wounded")

	DeathWatch.expect_deaths(1)
	await _die_and_return()
	var back := _sentries()
	assert_eq(back.size(), 1, "the one cut down stays down")
	if back.size() == 1:
		assert_eq(back[0].position, far_post, "the other is back at its post")
		assert_eq(back[0].health, 2, "whole")
		assert_eq(back[0].post, "%s@12,8" % SENTRY, "under the same post")


func test_a_summons_is_refereed_and_a_respawn_clears_it() -> void:
	await _play()
	var minion := Sentry.new()
	minion.position = _sentry().position + Vector2(40.0, 0.0)
	_sentry().summon(minion)
	await wait_physics_frames(2)
	assert_eq(_sentries().size(), 2, "the summons is in the level")
	assert_eq(minion.post, "", "with no post")
	minion.slamming = true
	_game.player.position.x = minion.position.x - 10.0
	await wait_physics_frames(2)
	minion.slamming = false
	assert_eq(_game.player.health, Tuning.MAX_HEALTH - 1, "and refereed like any foe")

	DeathWatch.expect_deaths(1)
	await _die_and_return()
	assert_eq(_sentries().size(), 1, "a respawn clears it and nothing puts it back")


func test_a_foes_sounds_and_weight_go_through_game() -> void:
	await _play()
	var heard := CueRecorder.new()
	var previous: Node = GameAudio._director
	GameAudio._director = heard
	_sentry().cue.emit(&"cloth", {"pitch": 0.5})
	GameAudio._director = previous
	assert_eq(heard.heard, ["cloth { \"pitch\": 0.5 }"] as Array[String],
		"a foe's cue is played through GameAudio.cue")
	heard.free()

	assert_false(Flow.is_hitstopped(), "nothing is held yet")
	_sentry().impact.emit(_sentry().position, Flow.HIT_FRAMES, 1.0, 0.5)
	assert_true(Flow.is_hitstopped(), "a foe's impact is spent from Game's budget")


func test_the_guard_is_a_foe_and_answers_the_contract() -> void:
	var guard: Patrol = autofree(Patrol.new())
	guard.facing = 1
	guard.position = Vector2(100.0, 200.0)
	assert_true(guard is Foe, "Patrol extends the contract")
	assert_eq(guard.hurt_rect(), guard.bounds(), "a blade wounds his body")
	for state: Patrol.State in Patrol.State.values():
		guard.state = state
		var engaged := state in [Patrol.State.WINDUP, Patrol.State.STRIKE, Patrol.State.RECOVER]
		assert_eq(guard.is_engaged(), engaged, "engaged in %s" % Patrol.State.keys()[state])
	guard.state = Patrol.State.STRIKE
	var dangers := guard.dangers()
	assert_eq(dangers.size(), 1, "one cut")
	assert_eq(dangers[0].rect, guard.strike_rect(), "where the blade is")
	assert_eq(dangers[0].from_x, guard.position.x, "from the guard")
	assert_true(dangers[0].evadable, "a backstep lets it by")
	assert_true(dangers[0].parried(), "and a parry turns it, through Patrol.parried()")
	assert_eq(guard.state, Patrol.State.STAGGER, "which reels him")
