extends GutTest
## Every foe bleeds when it dies, the blood is capped, a restart takes it off
## the floor and a checkpoint respawn leaves it there (scripts/world/bloodshed.gd).
##
## "Every foe" is read from the entity registry at run time, so a kind a
## chapter adds next week is in this suite the day it is registered, with no
## edit here. A toy foe that exists only in this file is registered as well,
## so the loop over kinds can never be a loop over nothing -- and because it
## answers the contract its own way (a shield in front), it also shows the
## blood hangs on `defeated` and not on any one foe's way of dying.
##
## Seen to fail: with `blood.clear()` taken out of Game._restart(), the
## restart test goes red; with `entities.child_entered_tree` left unconnected
## in Bloodshed.install(), every kind's test does.

const GAME_SCENE := "res://scenes/game.tscn"
const DeathWatch := preload("res://tests/death_watch.gd")
const SHIELDED := "test_shielded"

## The prince at column 4, a foe goes at column 9: a floor, a wall at the far
## end for the burst to hit, and a torch at column 2 that is the checkpoint.
const FLOOR := """; Blood Floor








  t @              #  D
######################
######################
"""


## Turns a sword from the front; one wound from behind kills it.
class Shielded extends Foe:
	var health := 1

	func bounds() -> Rect2:
		return Rect2(global_position - Vector2(5.0, 20.0), Vector2(10.0, 20.0))

	func is_alive() -> bool:
		return health > 0

	func hit(_from_x: float) -> bool:
		health -= 1
		if health <= 0:
			defeated.emit()
			return true
		return false

	func take_blow(blow: Blow, from_x: float) -> Outcome:
		if blow == Blow.SWORD and from_x < global_position.x:
			return Outcome.BLOCKED
		return super(blow, from_x)


class CueRecorder extends Node:
	var settings := AudioSettings.new()
	var heard: Array[String] = []

	func play(event: String, _opts: Dictionary = {}) -> AudioStreamPlayer:
		heard.append(event)
		return null

	func toggle_mute() -> void:
		pass


var _game: Game
var _cues: CueRecorder
var _previous: Node


func before_all() -> void:
	EntityRegistry.add_for_test(SHIELDED, Shielded)


func after_all() -> void:
	EntityRegistry.remove_for_test(SHIELDED)


func before_each() -> void:
	_cues = CueRecorder.new()
	_previous = GameAudio._director
	GameAudio._director = _cues


func after_each() -> void:
	GameAudio._director = _previous
	_cues.free()


func _play(kind: String) -> void:
	var data := AsciiLevel.new()
	data.parse(FLOOR)
	if kind != "":
		data.entities.append({"kind": kind, "cell": Vector2i(9, 8)})
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Game
	_game.level_source = data
	add_child_autofree(_game)
	await wait_physics_frames(3)


func _foe() -> Foe:
	for node: Node in _game.get_node("Entities").get_children():
		if node is Foe and not node.is_queued_for_deletion():
			return node as Foe
	return null


## Every kind the registry places that is a Foe.
func _foe_kinds() -> Array[String]:
	var out: Array[String] = []
	var kinds := EntityRegistry.kinds()
	for kind: String in kinds:
		var made: Node = (kinds[kind] as Script).new()
		if made is Foe:
			out.append(kind)
		made.free()
	return out


## Cuts `foe` down the way the prince would, from where he stands: every kind
## of blow, from the front and then from behind, until one kills it. A foe
## that no blow can kill still dies by the contract's own word, `defeated`,
## which is what the blood hangs on -- so a boss with a phase that turns every
## blow is still tested, and the message says so.
func _cut_down(foe: Foe) -> bool:
	var prince_x := _game.player.global_position.x
	var behind := foe.global_position.x + (foe.global_position.x - prince_x)
	for _round: int in 6:
		for from_x: float in [prince_x, behind]:
			for blow: int in [Foe.Blow.SWORD, Foe.Blow.PLUNGE, Foe.Blow.STOMP, Foe.Blow.SHOT]:
				if not foe.is_alive():
					return true
				foe.take_blow(blow as Foe.Blow, from_x)
	if foe.is_alive():
		foe.defeated.emit()
		return false
	return true


func test_there_is_at_least_one_real_foe_kind_and_the_toy() -> void:
	var kinds := _foe_kinds()
	assert_has(kinds, SHIELDED, "the toy foe is registered")
	assert_gt(kinds.size(), 1, "and at least one foe of the game's own: %s" % [kinds])


func test_every_foe_kind_bleeds_when_it_dies() -> void:
	for kind: String in _foe_kinds():
		await _play(kind)
		var foe := _foe()
		assert_not_null(foe, "%s: placed" % kind)
		if foe == null:
			continue
		var blood := _game.blood
		if not _cut_down(foe):
			gut.p("%s: no blow killed it; died by `defeated` alone" % kind)
		assert_eq(blood.kills, 1, "%s: one kill bled for" % kind)
		assert_eq(blood.drops_in_flight(), Bloodshed.KILL_DROPS, "%s: a burst" % kind)
		assert_has(_cues.heard, "kill", "%s: and the kill was heard" % kind)
		await wait_physics_frames(90)
		assert_gt(blood.stain_count(), 3, "%s: the drops landed as stains" % kind)
		assert_eq(blood.drops_in_flight(), 0, "%s: and none are left in the air" % kind)
		_game.queue_free()
		_cues.heard.clear()
		await wait_physics_frames(1)


func test_the_burst_goes_the_way_the_blow_went() -> void:
	await _play("patrol")
	var foe := _foe()
	assert_true(foe.global_position.x > _game.player.global_position.x, "the prince is west")
	_cut_down(foe)
	var east := 0
	for v: Vector2 in _game.blood.velocities():
		east += 1 if v.x > 0.0 else 0
		assert_lt(v.y, 0.0, "every drop is thrown upward")
	assert_gt(east, Bloodshed.KILL_DROPS / 2, "most of it goes east, away from the prince")


func test_a_real_swing_that_kills_bleeds() -> void:
	await _play("patrol")
	var foe := _foe()
	var input := ScriptedSwing.new()
	_game.player.input = input
	_game.player.position.x = foe.global_position.x - 14.0
	_game.player.facing = 1
	for _swing: int in 6:
		if not foe.is_alive():
			break
		input.bits = PlayerInput.BIT_ATTACK
		await wait_physics_frames(1)
		input.bits = 0
		await wait_physics_frames(40)
		_game.player.position.x = foe.global_position.x - 14.0
	assert_false(foe.is_alive(), "the prince's sword cut the guard down through Game")
	assert_eq(_game.blood.kills, 1, "and the kill bled")


func test_drops_and_stains_are_capped() -> void:
	await _play("")
	var blood := _game.blood
	for _i: int in 20:
		blood.burst(Vector2(100.0, 100.0), 1.0, Bloodshed.KILL_DROPS)
	assert_eq(blood.drops_in_flight(), Bloodshed.MAX_DROPS, "no more than MAX_DROPS in the air")
	for i: int in Bloodshed.MAX_STAINS + 40:
		blood.stain(Rect2(float(i), 0.0, 1.0, 1.0), Palette.BLOOD)
	assert_eq(blood.stain_count(), Bloodshed.MAX_STAINS, "no more than MAX_STAINS on the floor")
	for _i: int in Bloodshed.MAX_POOLS + 10:
		blood.pool(Vector2(100.0, 100.0), Bloodshed.POOL_MAX)
	assert_eq(blood.pool_count(), Bloodshed.MAX_POOLS, "no more than MAX_POOLS on the floor")


func test_a_kill_leaves_a_pool_and_so_does_the_princes_death() -> void:
	await _play("patrol")
	_cut_down(_foe())
	assert_eq(_game.blood.pool_count(), 1, "the guard's pool")
	DeathWatch.expect_deaths(1)
	_game.player.kill()
	assert_eq(_game.blood.pool_count(), 2, "and the prince's own where he fell")
	assert_eq(_game.blood.drops_in_flight(), Bloodshed.KILL_DROPS + Bloodshed.DEATH_DROPS,
		"his death throws more than a wound and fewer than a kill")


## The tiles take no hour (their shader is unshaded), so the blood on them must
## not either: the hour's multiply, times the blood's own modulate, is white.
## Seen to fail: with _grade_like_the_stone() not called, this is the night.
func test_the_blood_takes_the_stones_light_at_night() -> void:
	var data := AsciiLevel.new()
	data.parse(FLOOR + "\n;! time night\n")
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Game
	_game.level_source = data
	add_child_autofree(_game)
	await wait_process_frames(3)
	var grade := get_tree().get_first_node_in_group(WorldGrade.GROUP) as WorldGrade
	assert_not_null(grade, "a night level is graded")
	if grade == null:
		return
	var seen := _game.blood.modulate * grade.color
	assert_almost_eq(seen.r, 1.0, 0.001, "red as the stone")
	assert_almost_eq(seen.g, 1.0, 0.001, "green as the stone")
	assert_almost_eq(seen.b, 1.0, 0.001, "blue as the stone")


func test_a_checkpoint_respawn_keeps_the_blood_and_a_restart_clears_it() -> void:
	await _play("patrol")
	_cut_down(_foe())
	await wait_physics_frames(90)
	var stains := _game.blood.stain_count()
	assert_gt(stains, 0, "the kill left blood")

	DeathWatch.expect_deaths(1)
	_game.player.kill()
	for _frame: int in 150:
		await wait_physics_frames(1)
		if _game.phase == Game.Phase.PLAYING and _game.player.is_alive():
			break
	assert_true(_game.player.is_alive(), "back at the checkpoint")
	assert_gte(_game.blood.stain_count(), stains, "a respawn leaves the guard's blood where it fell")

	_game._restart()
	assert_eq(_game.blood.stain_count(), 0, "a restart takes it off the floor")
	assert_eq(_game.blood.drops_in_flight(), 0, "and out of the air")
	assert_eq(_game.blood.kills, 0, "and forgets the kills")


class ScriptedSwing extends PlayerInput:
	var bits := 0

	func poll() -> void:
		apply_bits(bits)
