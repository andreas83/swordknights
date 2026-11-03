extends GutTest
## The Eclipse under LONGER WARNINGS (scripts/core/assist.gd): every tell
## stretches by the one factor, and the fight still plays to its end.
##
## tests/unit/test_eclipse.gd measures each tell under the assist, frame for
## frame, with no scene. This is the other half: nothing breaks. A fixed
## program cannot play an assisted fight -- its first tell is longer than the
## one it was recorded against -- so the pilot plays it (tests/eclipse_support.gd),
## reading the fight as it goes, from the antechamber to dawn's door, with the
## death watch on. It also counts the tells it sees and how long each one
## lasted, so a tell that forgot the assist fails here as well as there.

const EclipseSupport := preload("res://tests/eclipse_support.gd")
const GAME_SCENE := "res://scenes/game.tscn"
const PATH := "user://test_eclipse_assist_run.cfg"
const FRAME := 1.0 / 60.0


func before_each() -> void:
	Assist.load_saved(PATH)
	Assist.set_longer_warnings(true)


func after_each() -> void:
	Assist.reset()
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_the_fight_plays_to_its_end_with_every_tell_longer() -> void:
	var game := (load(GAME_SCENE) as PackedScene).instantiate() as Game
	game.level_path = EclipseSupport.LEVEL
	add_child_autofree(game)
	var pilot := EclipseSupport.Pilot.new(game)
	game.player.input = pilot
	var king: Eclipse = null
	for node: Node in game.get_node("Entities").get_children():
		if node is Eclipse:
			king = node as Eclipse
	var tells := {}
	var longest := {}
	var watched := [Eclipse.State.DRAW, Eclipse.State.CHARGE, Eclipse.State.CROUCH,
		Eclipse.State.GATHER]
	var last := [-1, 0]
	var clock := [-1.0]
	game.level_completed.connect(func(elapsed: float, _got: int, _of: int) -> void:
		clock[0] = elapsed)

	# Each tell's frames, counted once a physics frame: a state the King stays
	# in, frame on frame.
	var count := func() -> void:
		var state := int(king.state)
		if state == last[0]:
			last[1] += 1
			return
		if watched.has(last[0]):
			tells[last[0]] = int(tells.get(last[0], 0)) + 1
			longest[last[0]] = maxi(int(longest.get(last[0], 0)), int(last[1]))
		last[0] = state
		last[1] = 1
	get_tree().physics_frame.connect(count)
	await wait_until(func() -> bool: return clock[0] >= 0.0, 150.0)
	get_tree().physics_frame.disconnect(count)

	assert_eq(game.phase, Game.Phase.COMPLETE, "the assisted fight played to dawn's door")
	assert_eq(game.deaths, 0, "with no death")
	var standard := Patrol.WINDUP_TIME * Assist.LONGER / FRAME
	for state: int in [Eclipse.State.CHARGE, Eclipse.State.CROUCH]:
		assert_gt(int(tells.get(state, 0)), 0, "%s was seen" % Eclipse.State.keys()[state])
		assert_gte(float(longest.get(state, 0)), standard - 2.0,
			"%s lasted the longer warning" % Eclipse.State.keys()[state])
	assert_gte(float(longest.get(Eclipse.State.GATHER, 0)), standard * 2.0 - 2.0,
		"and the gather twice it")
	gut.p("assisted, the Eclipse cleared in %.2f s on the game's clock" % clock[0])
