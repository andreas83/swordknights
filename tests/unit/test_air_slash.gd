extends GutTest
## The sword swings in the air: rising, falling, and through the same rules as
## a swing on the ground.
##
## Until this, a sword press in the air was held in the buffer and came out on
## landing, so jump-and-attack was a jump followed by an attack. The owner
## asked for both at once. Three things are held here: the slash exists in a
## jump and in a fall, it wounds a guard through `Game._resolve_foe()` with
## the one-swing-one-heart rule intact, and it leaves the jump's arc exactly
## as it was -- which is the decision that keeps it out of the traversal
## grammar (see `Tuning.ATTACK_TIME`'s note and docs/character.md).

const GAME_SCENE := "res://scenes/game.tscn"

## The prince at column 4 facing right, a guard at column 5, as in
## test_one_swing.gd.
const GUARDED := """; Air Slash








    @p            D
###################
###################
"""

## Open floor, nothing to hit.
const OPEN := """; Open Floor








  @                                  D
#######################################
#######################################
"""


class ScriptedInput extends PlayerInput:
	var bits := 0

	func poll() -> void:
		apply_bits(bits)


## Drives one jump frame by frame and records it, from inside the player's
## own step: a GUT wait can span more than one physics frame, and two arcs are
## only comparable if they are sampled on the same frames.
class Timeline extends PlayerInput:
	var player: Player
	## Frame the jump is pressed on, how long it is held, and the frame after
	## takeoff the sword is pressed on (-1 for never).
	var takeoff := 40
	var hold := 20
	var slash_at := -1
	## Hold right the whole time, for a running jump.
	var run := true

	var slashed := false
	var done := false
	var arc: Array[Vector2] = []
	var _frame := 0

	func poll() -> void:
		var bits := PlayerInput.BIT_RIGHT if run else 0
		if _frame >= takeoff and _frame < takeoff + maxi(1, hold):
			bits |= PlayerInput.BIT_JUMP
		if slash_at >= 0 and _frame == takeoff + slash_at:
			bits |= PlayerInput.BIT_ATTACK
		if _frame > takeoff and not done:
			if player.is_grounded():
				done = true
			else:
				arc.append(player.position)
		slashed = slashed or player.state == Player.State.AIR_SLASH
		apply_bits(bits)
		_frame += 1


var _game: Game
var _input: ScriptedInput


func _play(text: String) -> void:
	if _game != null and is_instance_valid(_game):
		_game.queue_free()
		await wait_physics_frames(1)
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


func _state_name() -> String:
	return String(Player.State.find_key(_game.player.state))


func _guard() -> Patrol:
	for node: Node in _game.get_node("Entities").get_children():
		if node is Patrol and not node.is_queued_for_deletion():
			return node as Patrol
	return null


## Jumps with `held` and the button down, and returns once the feet are off.
func _take_off(held: int) -> void:
	_input.bits = held | PlayerInput.BIT_JUMP
	for _frame: int in 10:
		await wait_physics_frames(1)
		if not _game.player.is_grounded():
			return


func _press_sword(held: int) -> void:
	_input.bits = held | PlayerInput.BIT_ATTACK
	await wait_physics_frames(1)
	_input.bits = held


func test_the_sword_swings_on_the_way_up() -> void:
	await _play(OPEN)
	await _take_off(0)
	assert_eq(_state_name(), "JUMP", "rising")
	await _press_sword(PlayerInput.BIT_JUMP)
	assert_eq(_state_name(), "AIR_SLASH", "a sword press in a jump slashes there and then")
	var live := false
	for _frame: int in 12:
		await wait_physics_frames(1)
		live = live or _game.player.attack_rect().size.x > 0.0
	assert_true(live, "and the blade is live in the air")


func test_the_sword_swings_on_the_way_down() -> void:
	await _play(OPEN)
	await _take_off(0)
	_input.bits = PlayerInput.BIT_JUMP
	for _frame: int in 40:
		await wait_physics_frames(1)
		if _game.player.state == Player.State.FALL:
			break
	assert_eq(_state_name(), "FALL", "falling")
	await _press_sword(0)
	assert_eq(_state_name(), "AIR_SLASH", "a sword press in a fall slashes too")


## The decision: the slash does not touch momentum. A slash that stalled the
## fall would stretch every gap past Tuning.gap_tiles(); one that braked would
## drop a mid-gap swing into the pit. So a jump with a slash in it must trace
## the same arc, frame for frame, as the same jump without.
func test_the_slash_leaves_the_arc_alone() -> void:
	var plain := await _arc(false)
	var slashed := await _arc(true)
	assert_true(slashed.slashed, "the slashed jump really slashed")
	assert_gt(plain.arc.size(), 20, "a whole jump was recorded")
	assert_eq(slashed.arc.size(), plain.arc.size(), "airborne for the same number of frames")
	var worst := 0.0
	for i: int in mini(plain.arc.size(), slashed.arc.size()):
		worst = maxf(worst, plain.arc[i].distance_to(slashed.arc[i]))
	assert_eq(worst, 0.0, "and in the same place on every one of them")


## One running jump to the right, recorded every airborne physics frame.
func _arc(slash: bool) -> Timeline:
	await _play(OPEN)
	var timeline := Timeline.new()
	timeline.slash_at = 4 if slash else -1
	await _run(timeline)
	return timeline


func _run(timeline: Timeline) -> void:
	timeline.player = _game.player
	_game.player.input = timeline
	for _wait: int in 200:
		await wait_physics_frames(1)
		if timeline.done:
			break


func test_an_air_slash_takes_one_heart() -> void:
	await _play(GUARDED)
	var guard := _guard()
	assert_not_null(guard, "the level has a guard")
	# A tapped hop with the sword pressed the frame after the feet leave: the
	# thumb hitting JUMP and SWORD together.
	var hop := Timeline.new()
	hop.takeoff = 0
	hop.hold = 1
	hop.slash_at = 1
	hop.run = false
	await _run(hop)
	assert_true(hop.slashed, "the hop slashed")
	# Out the far side of the landing, its hitstop and the stagger.
	await wait_physics_frames(40)
	assert_true(is_instance_valid(guard) and guard.is_alive(),
		"a guard with two hearts survives one slash")
	if is_instance_valid(guard):
		assert_eq(guard.health, Patrol.MAX_HEALTH - 1, "one slash, one heart")
	assert_eq(_game.player.health, Tuning.MAX_HEALTH, "and the slash beat his cut")
