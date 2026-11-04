extends GutTest
## The Glassbearer and his sunbolt (docs/campaign.md, "The Glassbearer -- the
## parry"), played through the real game scene: he aims only with his glass
## in the sun, and only at a prince he can see on his floor and on screen;
## the aim is the game's one telegraph, stretched by LONGER WARNINGS; the
## bolt flies over a crouch and lands on a standing prince; the parry's
## window meets it about thirty pixels out and sends it home to kill him; the
## backstep does not; a bolt wounds whoever is in its line; and a mirror in
## the line turns a bolt into a seal, which a bolt fills at once. Of the
## duel's moves: a bolt goes over a roll's tuck, the feet knock him out of
## his aim with no wound, and a thrown sword kills him.

const GAME_SCENE := "res://scenes/game.tscn"
const DeathWatch := preload("res://tests/death_watch.gd")
var _assist_path := UserData.at("user://test_chapter04_glassbearer_assist.cfg")

## A long lit floor: the prince at one end, a Glassbearer facing him. Dressed
## by hand, with nothing: left to the dresser, the floor grows a colonnade
## whose shaft shades his glass a few steps into his walk, and a test of when
## he aims would be measuring where a column fell.
const RANGE := """; Glass Range
;! dress authored





  @                g    D
##########################
##########################
"""

## The same floor with the sun set behind the far city: every row is under
## the horizon, and his glass is dull.
const DUSKED := ";! horizon 0\n" + RANGE

## A sentinel on the floor between them, the prince out of the Glassbearer's
## range: a bolt loosed down the floor meets the sentinel first.
const CROWDED := """; Crowded Range





  @       p        g    D
##########################
##########################
"""

## A mirror in his line of fire with a hatch in a slab above it: the prince
## stands just behind the mirror, the bolt goes up, and the hatch takes it.
const HATCH := """; Hatch Range

           #O#



  @         x    g      D
##########################
##########################
"""


class ScriptedInput extends PlayerInput:
	var bits := 0

	func poll() -> void:
		apply_bits(bits)


var _game: Game
var _input: ScriptedInput


func after_each() -> void:
	Assist.reset()
	if FileAccess.file_exists(_assist_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_assist_path))


func _play(text: String, prince_at: int = -1) -> void:
	var data := AsciiLevel.new()
	data.parse(text)
	assert_eq(data.problems, PackedStringArray(), "the range parses clean")
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Game
	_game.level_source = data
	add_child_autofree(_game)
	_input = ScriptedInput.new()
	_game.player.input = _input
	await wait_physics_frames(2)
	if prince_at >= 0:
		var row := data.spawn_point.y
		_game.player.respawn(_game.level.entity_world_position(Vector2i(prince_at, row)))
	_game.player.facing = 1
	_game.player.invulnerable = 0.0
	await wait_physics_frames(2)


func _bearer() -> Glassbearer:
	for node: Node in _game.get_node("Entities").get_children():
		if node is Glassbearer:
			return node as Glassbearer
	return null


func _bolt() -> Sunbolt:
	for node: Node in _game.get_node("Entities").get_children():
		if node is Sunbolt and not (node as Sunbolt).is_spent():
			return node as Sunbolt
	return null


## Steps until `done` says so or `frames` pass. True when it did.
func _until(done: Callable, frames: int) -> bool:
	for _frame: int in frames:
		if bool(done.call()):
			return true
		await wait_physics_frames(1)
	return bool(done.call())


## The gap between the bolt's leading edge and the prince's body: the bolt
## flies west at him from the Glassbearer's side.
func _gap(bolt: Sunbolt) -> float:
	return bolt.rect().position.x - _game.player.body_rect().end.x


## Whether the bolt `ref` holds is gone: spent and freed.
func _gone(ref: WeakRef) -> bool:
	var bolt := ref.get_ref() as Sunbolt
	return bolt == null or bolt.is_spent()


func test_his_glass_is_dull_under_the_horizon_and_he_never_aims() -> void:
	await _play(DUSKED, 12)
	var bearer := _bearer()
	var aimed := await _until(func() -> bool: return bearer.state == Glassbearer.State.AIM, 180)
	assert_false(bearer.glass, "the glass is dull in the city's shadow")
	assert_false(aimed, "and a dull glass never aims, however close he is")


func test_in_the_sun_he_aims_and_the_aim_is_the_telegraph() -> void:
	await _play(RANGE, 11)
	var bearer := _bearer()
	assert_true(bearer.glass, "his glass is in the sun")
	assert_true(await _until(func() -> bool: return bearer.state == Glassbearer.State.AIM, 120),
		"he aims at a prince on his floor and in sight")
	var start := Engine.get_physics_frames()
	assert_true(await _until(func() -> bool: return _bolt() != null, 90), "and fires")
	assert_almost_eq(Engine.get_physics_frames() - start, roundi(Patrol.WINDUP_TIME * 60.0), 2,
		"after the sentinel's 27 frames: one telegraph length for every foe")


func test_longer_warnings_stretch_the_aim() -> void:
	Assist.load_saved(_assist_path)
	assert_eq(Assist.set_longer_warnings(true), OK)
	await _play(RANGE, 11)
	var bearer := _bearer()
	assert_almost_eq(bearer.aim_time(), Patrol.WINDUP_TIME * Assist.LONGER, 0.0001,
		"the aim is read through warn()")
	assert_true(await _until(func() -> bool: return bearer.state == Glassbearer.State.AIM, 120))
	var start := Engine.get_physics_frames()
	assert_true(await _until(func() -> bool: return _bolt() != null, 120))
	assert_almost_eq(Engine.get_physics_frames() - start,
		roundi(Patrol.WINDUP_TIME * Assist.LONGER * 60.0), 2, "and the shot waits for it")


func test_he_waits_until_he_is_on_screen() -> void:
	await _play(RANGE, 11)
	var bearer := _bearer()
	bearer.frame_half_width = 40.0
	var aimed := await _until(func() -> bool: return bearer.state == Glassbearer.State.AIM, 120)
	assert_false(aimed, "a foe off the frame does not act")


func test_a_bolt_lands_on_a_standing_prince() -> void:
	DeathWatch.expect_deaths(0)
	await _play(RANGE, 12)
	var before := _game.player.health
	assert_true(await _until(func() -> bool: return _game.player.health < before, 200),
		"the bolt at chest height costs a standing prince a heart")
	assert_eq(_game.player.health, before - 1, "one heart")


func test_a_bolt_flies_over_a_crouch() -> void:
	await _play(RANGE, 12)
	_input.bits = PlayerInput.BIT_DOWN
	var before := _game.player.health
	assert_true(await _until(func() -> bool: return _bolt() != null, 200), "he fired")
	var bolt := _bolt()
	assert_lt(bolt.rect().end.y, _game.player.body_rect().position.y,
		"the bolt flies above a crouching prince's head")
	await _until(func() -> bool: return _bolt() == null, 200)
	assert_eq(_game.player.health, before, "and passes him by")
	_input.bits = 0


func test_a_bolt_flies_over_a_roll() -> void:
	DeathWatch.expect_deaths(0)
	await _play(RANGE, 12)
	var before := _game.player.health
	assert_true(await _until(func() -> bool: return _bolt() != null, 200), "he fired")
	var ref: WeakRef = weakref(_bolt())
	await _until(func() -> bool:
		return _gone(ref) or _gap(ref.get_ref() as Sunbolt) <= 30.0, 200)
	assert_false(_gone(ref), "the bolt is still coming")
	_input.bits = PlayerInput.BIT_DOWN | PlayerInput.BIT_JUMP
	await wait_physics_frames(1)
	_input.bits = 0
	assert_true(await _until(func() -> bool: return _game.player.moves.rolling_under(), 4),
		"he is in the tuck")
	await _until(func() -> bool: return _gone(ref) or _gap(ref.get_ref() as Sunbolt) < -20.0, 40)
	assert_eq(_game.player.health, before, "the bolt at chest height goes over the tuck")


func test_the_feet_knock_him_out_of_his_aim_and_cost_him_nothing() -> void:
	for blow: Foe.Blow in [Foe.Blow.KICK, Foe.Blow.SWEEP]:
		await _play(RANGE, 12)
		var bearer := _bearer()
		assert_true(await _until(func() -> bool: return bearer.state == Glassbearer.State.AIM, 60))
		assert_eq(bearer.take_blow(blow, _game.player.global_position.x),
			Foe.Outcome.STAGGERED, "%s rocks him" % Foe.Blow.keys()[blow])
		assert_eq(bearer.state, Glassbearer.State.SPENT, "out of the aim, the glass spent")
		assert_true(bearer.is_alive(), "and no wound")
		var fired := await _until(func() -> bool: return _bolt() != null, 40)
		assert_false(fired, "the aim he was knocked out of fires nothing")
		_game.queue_free()
		await wait_physics_frames(1)


func test_a_thrown_sword_kills_him() -> void:
	await _play(RANGE, 12)
	var bearer := _bearer()
	assert_eq(bearer.take_blow(Foe.Blow.THROWN, _game.player.global_position.x),
		Foe.Outcome.KILLED, "a blade in flight is a blade, and he has one heart")
	assert_false(bearer.is_alive())


## Raises the parry when the bolt is `gap` pixels out; true if it was turned.
func _parry_at(gap: float) -> bool:
	await _play(RANGE, 12)
	assert_true(await _until(func() -> bool: return _bolt() != null, 200), "he fired")
	var ref: WeakRef = weakref(_bolt())
	await _until(func() -> bool:
		return _gone(ref) or _gap(ref.get_ref() as Sunbolt) <= gap, 200)
	_input.bits = PlayerInput.BIT_UP | PlayerInput.BIT_ATTACK
	await wait_physics_frames(1)
	_input.bits = 0
	await _until(func() -> bool:
		return _gone(ref) or (ref.get_ref() as Sunbolt).reflected, 60)
	var bolt := ref.get_ref() as Sunbolt
	return bolt != null and bolt.reflected


func test_a_parry_sends_the_bolt_home_and_it_kills_him() -> void:
	var turned := await _parry_at(16.0)
	assert_true(turned, "the parry turned it")
	var bearer := _bearer()
	assert_true(await _until(func() -> bool: return bearer == null or not bearer.is_alive(), 240),
		"and it flew back and killed the hand that threw it")
	assert_eq(_game.player.health, Tuning.MAX_HEALTH, "without costing a heart")


func test_the_parry_meets_it_about_thirty_pixels_out() -> void:
	assert_true(await _parry_at(26.0), "raised 26 px out, the window is still open when it arrives")


func test_a_parry_raised_too_early_is_spent_when_it_arrives() -> void:
	var before := Tuning.MAX_HEALTH
	assert_false(await _parry_at(48.0), "raised 48 px out, the window has closed")
	assert_eq(_game.player.health, before - 1, "and it lands")


func test_the_backstep_does_not_evade_a_bolt() -> void:
	await _play(RANGE, 12)
	assert_true(await _until(func() -> bool: return _bolt() != null, 200), "he fired")
	var ref: WeakRef = weakref(_bolt())
	await _until(func() -> bool:
		return _gone(ref) or _gap(ref.get_ref() as Sunbolt) <= 10.0, 200)
	# Back is away from the bolt: the stick to the west, facing east.
	_input.bits = PlayerInput.BIT_LEFT | PlayerInput.BIT_ATTACK
	await wait_physics_frames(1)
	_input.bits = 0
	await _until(func() -> bool: return _gone(ref), 60)
	assert_true(_game.player.is_backstepping() or _game.player.health < Tuning.MAX_HEALTH,
		"he stepped back")
	assert_eq(_game.player.health, Tuning.MAX_HEALTH - 1,
		"the backstep survives blades, not bolts")


func test_a_bolt_wounds_whoever_is_in_its_line() -> void:
	await _play(CROWDED, 2)
	var sentinel: Patrol = null
	for node: Node in _game.get_node("Entities").get_children():
		if node is Patrol:
			sentinel = node as Patrol
	var bearer := _bearer()
	var at := bearer.global_position + Vector2(-8.0, -Glassbearer.BOLT_HEIGHT)
	bearer.launch(Sunbolt.make(at, Vector2.LEFT))
	assert_true(await _until(func() -> bool: return sentinel.health < Patrol.MAX_HEALTH, 120),
		"the sentinel in the line took it, one heart")
	assert_true(bearer.is_alive(), "not the hand that threw it")
	assert_eq(_game.player.health, Tuning.MAX_HEALTH, "and it was spent on him")


func test_a_mirror_turns_his_bolt_into_a_seal_which_it_fills_at_once() -> void:
	await _play(HATCH, 10)
	assert_true(_bearer().glass, "his glass is in the sun")
	var seal: SunSeal = null
	for node: Node in _game.get_node("Entities").get_children():
		if node is SunSeal:
			seal = node as SunSeal
	assert_eq(seal.phase, SunSeal.Phase.SHUT, "the hatch is shut")
	assert_true(await _until(func() -> bool: return seal.phase != SunSeal.Phase.SHUT, 300),
		"his bolt, turned up by the mirror, opened it")
	assert_eq(_game.player.health, Tuning.MAX_HEALTH, "and the mirror was the prince's cover")
