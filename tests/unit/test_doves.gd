extends GutTest
## The doves (scripts/entities/dove_flock.gd): the city's life, and the
## Caracal's first lesson shown on something else.
##
## Held here: a cat with no prince on its floor hunts a flock -- crouches,
## pounces, and lands on the spot they have just left, because a pounce
## startles them as it leaves the ground; a running prince puts them up and a
## walking one does not; they settle at the far end of their stretch; they go
## to roost at dusk; and they are nothing to the proof or to the prince's body.

const GAME_SCENE := "res://scenes/game.tscn"

## A walled yard under a walk: the prince above, the cat and the doves below.
const YARD := """; Dove Yard



          @             D
##########################
#                        #
#                        #
#   v          j         #
##########################
"""

## A flock on the prince's own floor.
const TERRACE := """; Dove Terrace





  @          v            D
############################
"""

const DUSK := """;! time dusk
; Dove Roost





  @          v            D
############################
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
	assert_eq(data.problems, PackedStringArray(), "the level parses clean")
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Game
	_game.level_source = data
	add_child_autofree(_game)
	_input = ScriptedInput.new()
	_game.player.input = _input
	await wait_physics_frames(2)


func _find(kind: Script) -> Node:
	for node: Node in _game.get_node("Entities").get_children():
		if is_instance_of(node, kind) and not node.is_queued_for_deletion():
			return node
	return null


func test_the_cat_pounces_at_the_doves_and_always_misses() -> void:
	await _play(YARD)
	var cat := _find(Caracal) as Caracal
	var flock := _find(DoveFlock) as DoveFlock
	var home := flock.spot()
	var startled_in_flight := false
	var landed_at := Vector2.INF
	for _frame: int in 600:
		await get_tree().physics_frame
		if cat.state == Caracal.State.POUNCE and not flock.is_settled():
			startled_in_flight = true
		if cat.state == Caracal.State.SKID and landed_at == Vector2.INF:
			landed_at = cat.position
			break
	assert_true(startled_in_flight, "the flock was up before the cat came down")
	assert_ne(landed_at, Vector2.INF, "it pounced and landed")
	assert_lt(absf(landed_at.x - home.x), 3.0 * 16.0, "on the spot they had left")
	for _frame: int in 60:
		if flock.is_settled():
			break
		await get_tree().physics_frame
	assert_true(flock.is_settled(), "and they settled again, before it could come again")
	assert_gt(absf(flock.spot().x - home.x), 3.0 * 16.0, "somewhere else")
	assert_eq(_game.player.health, Tuning.MAX_HEALTH, "all of it out of the prince's reach")


func test_running_puts_them_up_and_walking_does_not() -> void:
	await _play(TERRACE)
	var flock := _find(DoveFlock) as DoveFlock
	_input.bits = PlayerInput.BIT_RIGHT | PlayerInput.BIT_WALK
	for _frame: int in 400:
		await get_tree().physics_frame
		if _game.player.position.x > flock.spot().x - 8.0:
			break
	assert_true(flock.is_settled(), "a walker can walk right up to them")
	_input.bits = 0
	_game.player.position.x = flock.spot().x - 6.0 * 16.0
	await wait_physics_frames(4)
	_input.bits = PlayerInput.BIT_RIGHT
	var flushed := false
	for _frame: int in 120:
		await get_tree().physics_frame
		if not flock.is_settled():
			flushed = true
			assert_lt(absf(_game.player.position.x - flock.spot().x), 3.0 * 16.0 + 4.0,
				"within three tiles")
			break
	assert_true(flushed, "a runner puts them up")


func test_doves_go_to_roost_at_dusk() -> void:
	await _play(DUSK)
	var flock := _find(DoveFlock) as DoveFlock
	assert_false(flock.visible, "at dusk there are no doves on the terrace")
	assert_false(flock.is_in_group(DoveFlock.GROUP), "and nothing to hunt")


func test_doves_are_nothing_to_the_proof_or_the_body() -> void:
	var level := AsciiLevel.new()
	level.parse(TERRACE)
	assert_true(ReachModel.for_level(level).is_empty(), "the proof never hears of them")
	assert_eq(level.kind_at(13, 5), Tiles.Kind.EMPTY, "their cell is air")
	await _play(TERRACE)
	var flock := _find(DoveFlock) as DoveFlock
	assert_eq(flock.get_children().filter(func(n: Node) -> bool:
		return n is CollisionObject2D).size(), 0, "no body")
