extends GutTest
## Escaping an Endless ruin leads down into the next one, a little harder.
##
## Endless used to stop at the first door: "JUMP TO REPLAY" rebuilt the same
## ruin from the same seed at the same 0.55 difficulty, so the mode had no
## second level, no curve and nothing to carry on toward. These tests escape a
## ruin through the real complete screen — the jump action, as a player would
## press it — and check where it leads.

const SCENE := "res://scenes/generated_game.tscn"
const SEED := 2024

var _endless: GeneratedGame


## The press below goes through the real input pipeline, so every scene in the
## tree hears it. test_boot_scene.gd leaves the boot's hand-off — the menu — as
## the tree's current scene, and a jump press there starts the Adventure, whose
## wipe then owns the screen and swallows this test's. A stray scene at the
## root is not part of this test, so it goes.
func before_all() -> void:
	for child: Node in get_tree().root.get_children():
		if child.scene_file_path in ["res://scenes/menu.tscn", "res://scenes/game.tscn"]:
			child.queue_free()
	await wait_physics_frames(2)


func before_each() -> void:
	var packed := load(SCENE) as PackedScene
	_endless = packed.instantiate() as GeneratedGame
	_endless.seed_override = SEED
	add_child_autofree(_endless)
	await wait_physics_frames(3)


func _game() -> Game:
	for child: Node in _endless.get_children():
		if child is Game and not child.is_queued_for_deletion():
			return child as Game
	return null


## Completes the current ruin and presses jump on the complete screen.
func _escape() -> void:
	var game := _game()
	var old := game.get_instance_id()
	await wait_until(func() -> bool: return not Flow.busy(), 2.0)
	game._complete()
	await wait_physics_frames(2)
	# Through the input pipeline rather than Input.action_press(), so the press
	# lands on a frame of its own and is_action_just_pressed() sees it.
	_send_jump(true)
	await wait_physics_frames(2)
	_send_jump(false)
	# By id: the old game is freed at full cover, and a freed capture is null.
	await wait_until(func() -> bool:
		var now := _game()
		return now != null and now.get_instance_id() != old and not Flow.busy(), 3.0)
	await wait_physics_frames(2)


func _send_jump(pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = &"jump"
	event.pressed = pressed
	Input.parse_input_event(event)


func test_escaping_a_ruin_leads_to_a_new_one() -> void:
	var first := _endless.seed_value
	var game := _game()
	assert_not_null(game, "the first ruin is being played")
	await _escape()
	assert_ne(_endless.seed_value, first, "the next ruin is a different ruin")
	assert_not_null(_game(), "and it is being played")
	assert_eq(_game().phase, Game.Phase.PLAYING, "from the start")


func test_each_ruin_is_harder_than_the_last_up_to_a_ceiling() -> void:
	var first := _endless.current_difficulty()
	assert_eq(_endless.depth, 1, "the descent starts at the first ruin")
	assert_lt(first, 0.55, "and starts gentler than the old fixed 0.55")
	await _escape()
	assert_eq(_endless.depth, 2, "one door down")
	assert_gt(_endless.current_difficulty(), first, "and harder")
	for depth: int in range(1, 40):
		assert_lte(GeneratedGame.difficulty_at(depth, first), GeneratedGame.MAX_DIFFICULTY,
			"no ruin is asked to be harder than the generator's top end")


func test_a_pinned_descent_is_reproducible() -> void:
	assert_eq(GeneratedGame.next_seed(SEED, 2), GeneratedGame.next_seed(SEED, 2),
		"the seed of ruin n follows from the first seed alone")
	assert_ne(GeneratedGame.next_seed(SEED, 2), GeneratedGame.next_seed(SEED, 3),
		"and every ruin gets its own")


func test_the_adventure_still_replays_its_one_level() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Game
	add_child_autofree(game)
	await wait_physics_frames(2)
	assert_false(game.advance.is_valid(), "a hand-authored level has nowhere further to go")
