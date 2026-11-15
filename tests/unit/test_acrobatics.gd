extends GutTest
## The stick avatar's flips (scripts/player/acrobatics.gd): who flips, that
## every flip starts and lands upright, that a running jump's flip is done
## before any landing a jump can make, that a turn moves the body whole --
## limbs keep their lengths, the blade stays in the hand -- and that a running
## jump flips and a standing one does not.

const PLAYER_SCENE := preload("res://scenes/player.tscn")


func _art(figure: String) -> PlayerArt:
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	player.set_physics_process(false)
	player.position = Vector2(160.0, 120.0)
	var art := player.get_node(^"PlayerArt") as PlayerArt
	CharacterLook.from_ids({"figure": figure}).dress(art)
	return art


func _pose_at(art: PlayerArt, state: Player.State, t: float) -> Dictionary:
	var player := art.get_parent() as Player
	player.state = state
	player.state_time = t
	return art._posture()


func test_only_the_stick_avatar_flips() -> void:
	assert_true(_art("stick").costume.acrobatic(), "the stick avatar flips")
	for figure: String in ["prince", "heroine"]:
		var art := _art(figure)
		assert_false(art.costume.acrobatic(), "%s does not" % figure)
		var pose := _pose_at(art, Player.State.BACKSTEP, Acrobatics.BACKFLIP_TIME * 0.5)
		assert_eq(float(pose["spin"]), 0.0, "%s's backstep stays upright" % figure)
	var stick := _pose_at(_art("stick"), Player.State.BACKSTEP, Acrobatics.BACKFLIP_TIME * 0.5)
	assert_lt(float(stick["spin"]), -1.0, "the stick avatar's backstep is a backflip")


func test_every_flip_starts_and_lands_upright() -> void:
	var ends := {
		Player.State.BACKSTEP: Acrobatics.BACKFLIP_TIME,
		Player.State.DIVE_KICK: Acrobatics.KICK_FLIP_TIME,
		Player.State.AIR_SLASH: Tuning.ATTACK_TIME,
	}
	for state: int in ends:
		var start := Acrobatics.spin_for(state, 0.0, 0.0, false)
		var done := Acrobatics.spin_for(state, float(ends[state]), 0.0, false)
		var name: String = Player.State.keys()[state]
		assert_almost_eq(start, 0.0, 0.001, "%s starts upright" % name)
		assert_almost_eq(fposmod(done, TAU), 0.0, 0.001, "%s lands a whole turn" % name)
		assert_almost_eq(absf(done), TAU, 0.001, "%s turns once" % name)


func test_a_running_jump_is_upright_before_it_can_land() -> void:
	# Take-off is upright; by the time the body falls at the speed it rose
	# with -- the soonest it can be back at its take-off height -- the flip is
	# done, and well before that it already is: FLIP_DONE of the way.
	var take_off := Acrobatics.spin_for(Player.State.JUMP, 0.0, -Tuning.JUMP_SPEED, true)
	assert_almost_eq(take_off, 0.0, 0.001, "upright as it leaves the floor")
	var apex := Acrobatics.spin_for(Player.State.FALL, 0.0, 0.0, true)
	assert_gt(apex, PI * 0.9, "most of the way round at the apex: %.2f" % apex)
	var done_speed := -Tuning.JUMP_SPEED + 2.0 * Tuning.JUMP_SPEED * Acrobatics.FLIP_DONE
	var done := Acrobatics.spin_for(Player.State.FALL, 0.0, done_speed, true)
	assert_almost_eq(done, TAU, 0.001, "a whole turn by %.0f px/s down" % done_speed)
	assert_lt(done_speed, Tuning.JUMP_SPEED, "which is sooner than landing level")
	assert_eq(Acrobatics.spin_for(Player.State.JUMP, 0.0, -100.0, false), 0.0,
		"and no flip at all on a jump that did not start as a run")


func test_a_turn_moves_the_body_whole() -> void:
	var art := _art("stick")
	var player := art.get_parent() as Player
	player.facing = -1
	var upright := _pose_at(art, Player.State.AIR_SLASH, 0.0)
	art._rig(upright)
	var thigh := art._hip.distance_to(art._knee_front)
	var arm := art._shoulder.distance_to(art._hand_front)
	var spun := upright.duplicate()
	spun["spin"] = 2.0
	art._rig(spun)
	assert_almost_eq(art._hip.distance_to(art._knee_front), thigh, 0.001, "the thigh keeps its length")
	assert_almost_eq(art._shoulder.distance_to(art._hand_front), arm, 0.001,
		"the arm keeps its length")
	# The blade, from a real frame mid-slash: it leaves the hand at the pose's
	# angle plus the turn, so it stays in the hand all the way round.
	player.state = Player.State.AIR_SLASH
	player.state_time = Tuning.ATTACK_TIME * 0.5
	art.queue_redraw()
	await wait_process_frames(2)
	var pose := art._posture()
	assert_ne(float(pose["spin"]), 0.0, "the slash is turning")
	var dir := (art.blade_tip - art._hand_front).normalized()
	var angle := float(pose["blade"]) + float(pose["spin"])
	var want := Vector2(cos(angle) * art._f, sin(angle))
	assert_almost_eq(dir.dot(want), 1.0, 0.001, "the blade turns with the hand that holds it")


func test_a_running_jump_flips_and_a_standing_one_does_not() -> void:
	var art := _art("stick")
	var player := art.get_parent() as Player
	player.velocity = Vector2(Tuning.RUN_SPEED, -Tuning.JUMP_SPEED)
	player.state = Player.State.JUMP
	art._on_jumped()
	assert_true(art._flipping, "a jump at full run flips")
	player.velocity = Vector2(10.0, -Tuning.JUMP_SPEED)
	art._on_jumped()
	assert_false(art._flipping, "a standing jump does not")
	var prince := _art("prince")
	(prince.get_parent() as Player).velocity = Vector2(Tuning.RUN_SPEED, -Tuning.JUMP_SPEED)
	prince._on_jumped()
	assert_false(prince._flipping, "and the prince never does")
