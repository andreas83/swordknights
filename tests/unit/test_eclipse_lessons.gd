extends GutTest
## Each of the Eclipse's phases is a lesson from an earlier chapter, and here
## each is played in the real Vault through the real referee
## (scripts/core/game.gd): the wrong answer costs a heart or wins nothing, and
## the right one wounds him.
##
## | Phase | Wrong | Right |
## | --- | --- | --- |
## | the Shield | a sword at his front: a clang | a plunge as he pauses, and its rebound |
## | the Burning | a crouch: nothing won; a backstep: struck | a parry: his own bolt in his chest |
## | the Eclipse | a parry: the pounce comes through it | a backstep, and a cut while he skids |
## | the finale | a crouch: struck, and he gathers again | a parry: the beam into the disc |
##
## The right answers are played by the pilot (tests/eclipse_support.gd), the
## same player the clear run was recorded from; the wrong ones by hand. Each
## test wakes the King in its phase with Eclipse.resume() and puts the prince
## down on the floor, so it waits only for the phase it is about.

const EclipseSupport := preload("res://tests/eclipse_support.gd")
const GAME_SCENE := "res://scenes/game.tscn"
const R := PlayerInput.BIT_RIGHT
const L := PlayerInput.BIT_LEFT
const U := PlayerInput.BIT_UP
const D := PlayerInput.BIT_DOWN
const A := PlayerInput.BIT_ATTACK


class Held extends PlayerInput:
	var bits := 0

	func poll() -> void:
		apply_bits(bits)


var _game: Game
var _king: Eclipse
var _held: Held


func after_each() -> void:
	Assist.reset()


## The Vault, the King woken in `phase`, and the prince on the floor at `x`
## facing him. Returns once the phase has begun.
func _arena(phase: int, x: float) -> void:
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Game
	_game.level_path = EclipseSupport.LEVEL
	add_child_autofree(_game)
	_held = Held.new()
	_game.player.input = _held
	await wait_physics_frames(2)
	for node: Node in _game.get_node("Entities").get_children():
		if node is Eclipse:
			_king = node as Eclipse
	_king.resume(phase)
	var prince := _game.player
	prince.position = Vector2(x, _king.floor_y)
	prince.velocity = Vector2.ZERO
	prince.facing = 1 if _king.position.x > x else -1
	await wait_until(func() -> bool:
		return _king.state != Eclipse.State.AWAIT and _king.state != Eclipse.State.RISE, 5.0)


func _pilot() -> EclipseSupport.Pilot:
	var pilot := EclipseSupport.Pilot.new(_game)
	_game.player.input = pilot
	return pilot


## The prince's front edge to the nearest point of `shot`'s danger, along x.
func _gap_to(shot: FoeProjectile) -> float:
	var rect := shot.rect()
	var prince := _game.player.position.x
	if rect.position.x > prince:
		return rect.position.x - (prince + Tuning.BODY_WIDTH * 0.5)
	return (prince - Tuning.BODY_WIDTH * 0.5) - rect.end.x


func _incoming() -> FoeProjectile:
	for node: Node in _game.get_node("Entities").get_children():
		var shot := node as FoeProjectile
		if shot != null and not shot.reflected and not shot.is_spent():
			return shot
	return null


func test_the_shield_rings_off_a_sword_from_the_front() -> void:
	await _arena(Eclipse.Phase.SHIELD, 240.0)
	# He walks at the prince and draws his shove a tile off; the prince steps
	# into the draw and cuts at the disc, the Bastion's front.
	await wait_until(func() -> bool: return _king.state == Eclipse.State.DRAW, 6.0)
	_held.bits = R | PlayerInput.BIT_WALK
	await wait_physics_frames(6)
	_held.bits = A
	var reached := false
	for _frame: int in 14:
		await wait_physics_frames(1)
		_held.bits = 0
		if _game.player.attack_rect().intersects(_king.hurt_rect()):
			reached = true
	assert_true(reached, "the blade reached him")
	assert_eq(_king.wounds, 0, "and rang off: a sword from the front is not the lesson")
	# Out of the shove that follows, so the test is about the sword alone.
	_held.bits = L
	await wait_physics_frames(30)
	_held.bits = 0


func test_the_shield_falls_to_a_plunge_and_its_rebound() -> void:
	await _arena(Eclipse.Phase.SHIELD, 240.0)
	# The pilot climbs the west gallery and waits there for his pause.
	var pilot := _pilot()
	pilot.chain_plunges = true
	await wait_until(func() -> bool: return _king.wounds >= 2, 30.0)
	assert_eq(_king.wounds, 2, "the plunge and the rebound's plunge, in one pass")
	assert_true(_king.crown_guard, "and then the disc goes over his crown")
	assert_eq(_game.player.health, Tuning.MAX_HEALTH, "with no heart lost")


func test_the_burning_is_not_won_crouching_or_stepped_from() -> void:
	await _arena(Eclipse.Phase.BURNING, 180.0)
	# Crouched under a whole volley: nothing reaches him, nothing reaches the King.
	_held.bits = D
	await wait_until(func() -> bool: return _king.volley >= 2, 8.0)
	assert_eq(_game.player.health, Tuning.MAX_HEALTH, "the bolts fly over a crouch")
	assert_eq(_king.wounds, 0, "and win nothing")
	# Stepped back from: a bolt at chest height is still at chest height.
	_held.bits = 0
	var shot: FoeProjectile = null
	await wait_until(func() -> bool:
		shot = _incoming()
		return shot != null and _gap_to(shot) < 6.0, 6.0)
	_held.bits = L | A
	await wait_physics_frames(1)
	_held.bits = 0
	await wait_physics_frames(20)
	assert_eq(_game.player.health, Tuning.MAX_HEALTH - 1, "the backstep does not let it by")
	assert_eq(_king.wounds, 0)


func test_the_burning_falls_to_his_own_light_parried_back() -> void:
	await _arena(Eclipse.Phase.BURNING, 180.0)
	_pilot()
	await wait_until(func() -> bool: return _king.wounds >= 1, 8.0)
	assert_eq(_king.wounds, 1, "a parried bolt flew back into his chest")
	assert_eq(_game.player.health, Tuning.MAX_HEALTH, "and the parry cost nothing")


func test_the_eclipse_comes_through_a_parry() -> void:
	await _arena(Eclipse.Phase.ECLIPSE, 200.0)
	await wait_until(func() -> bool:
		return _king.state == Eclipse.State.LEAP and _king.state_time >= 0.3, 8.0)
	_held.bits = U | A
	await wait_physics_frames(1)
	_held.bits = 0
	await wait_physics_frames(30)
	assert_eq(_game.player.health, Tuning.MAX_HEALTH - 1,
		"a parry turns blades, not bodies: the pounce lands")
	assert_eq(_king.wounds, 0)
	assert_ne(_king.state, Eclipse.State.SKID, "and a pounce that lands leaves no opening")


func test_the_eclipse_falls_to_a_backstep_and_a_cut() -> void:
	await _arena(Eclipse.Phase.ECLIPSE, 200.0)
	_pilot()
	var skidded := [false]
	await wait_until(func() -> bool:
		skidded[0] = skidded[0] or _king.state == Eclipse.State.SKID
		return _king.wounds >= 1, 10.0)
	assert_true(skidded[0], "the backstep let him by and he skidded")
	assert_eq(_king.wounds, 1, "and the cut in the skid wounded him")
	assert_eq(_game.player.health, Tuning.MAX_HEALTH, "with no heart lost")


func test_the_finale_strikes_a_crouch_and_gathers_again() -> void:
	await _arena(Eclipse.Phase.FINALE, 200.0)
	_held.bits = D
	await wait_until(func() -> bool: return _game.player.health < Tuning.MAX_HEALTH, 6.0)
	assert_eq(_game.player.health, Tuning.MAX_HEALTH - 1,
		"the whole kept sun reaches a crouching prince's shoulders")
	_held.bits = 0
	await wait_until(func() -> bool: return _king.state == Eclipse.State.SPENT, 3.0)
	var spent_at := Engine.get_physics_frames()
	await wait_until(func() -> bool: return _king.state == Eclipse.State.GATHER, 5.0)
	var waited := float(Engine.get_physics_frames() - spent_at) / 60.0
	assert_almost_eq(waited, Eclipse.SPENT_TIME, 0.1, "he gathers again after three seconds")
	assert_true(_king.is_alive(), "and stands")


func test_the_finale_falls_to_the_parry_and_dawns_door_opens() -> void:
	await _arena(Eclipse.Phase.FINALE, 200.0)
	_held.bits = 0
	var door: ExitDoor = null
	for node: Node in _game.get_node("Entities").get_children():
		if node is ExitDoor:
			door = node as ExitDoor
	assert_not_null(door, "dawn's door is in the east wall")
	assert_true(door.is_held(), "and shut while he stands")
	_pilot()
	await wait_until(func() -> bool: return not _king.is_alive(), 6.0)
	assert_eq(_king.state, Eclipse.State.FALL, "the beam went back into the disc")
	assert_true(door.is_held(), "the door waits for the kept sun to rise")
	await wait_until(func() -> bool: return not door.is_held(), Eclipse.FALL_TIME + 1.0)
	assert_false(door.is_held(), "then opens")
	await wait_until(func() -> bool: return _game.phase == Game.Phase.COMPLETE, 6.0)
	assert_eq(_game.phase, Game.Phase.COMPLETE, "and the prince walks out through it")


func test_dawns_door_will_not_let_him_by_while_he_stands() -> void:
	await _arena(Eclipse.Phase.SHIELD, 240.0)
	var door: ExitDoor = null
	for node: Node in _game.get_node("Entities").get_children():
		if node is ExitDoor:
			door = node as ExitDoor
	# Straight into the door: inside it, and the level goes on.
	_game.player.position = door.global_position + Vector2(-2.0, 0.0)
	_game.player.velocity = Vector2.ZERO
	await wait_physics_frames(20)
	assert_true(_game.player.body_rect().intersects(door.bounds()), "the prince is at the door")
	assert_eq(_game.phase, Game.Phase.PLAYING, "and it is shut to him while the King stands")
