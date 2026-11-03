extends GutTest
## The Eclipse cleared from the antechamber to dawn's door by a fixed input
## program -- `[frames, bits]` in tools/trace_level.gd's format, no warps and
## no kills -- under the death watch (tests/death_watch.gd), which fails the
## test on any death.
##
## The program is open-loop: it cannot see the King, so it can only win the
## fight it was recorded on (CLEAR_RUN in tests/eclipse_support.gd, by the
## steady pilot). That is what it is for. A change that moves a tell by a
## frame, a bolt by a pixel, a wall by a tile turns it red here first, and a
## deliberate change is re-recorded with tools/eclipse_pilot.gd.
##
## Held: every phase won, in order; the King fallen; the level complete
## through the door, with no death; and the fight between 60 and 120 seconds
## on the game's clock -- the bible's done criterion for a scripted player
## (docs/campaign.md, "Build plan", 12; about 85 s for a typical player).

const EclipseSupport := preload("res://tests/eclipse_support.gd")
const GAME_SCENE := "res://scenes/game.tscn"
const SHORTEST := 60.0
const LONGEST := 120.0


func test_the_recorded_program_clears_the_fight_without_a_death() -> void:
	var game := (load(GAME_SCENE) as PackedScene).instantiate() as Game
	game.level_path = EclipseSupport.LEVEL
	add_child_autofree(game)
	var program := EclipseSupport.Program.new(EclipseSupport.CLEAR_RUN)
	game.player.input = program
	var king: Eclipse = null
	for node: Node in game.get_node("Entities").get_children():
		if node is Eclipse:
			king = node as Eclipse
	assert_not_null(king, "the King is in the Vault")
	var won: Array[int] = []
	king.phase_won.connect(func(phase: int) -> void: won.append(phase))
	var fallen := [false]
	king.defeated.connect(func() -> void: fallen[0] = true)
	var clock := [-1.0]
	game.level_completed.connect(func(elapsed: float, _got: int, _of: int) -> void:
		clock[0] = elapsed)

	# Game referees a frame before its children move, so the door is met the
	# frame after the program's last step: a second's grace once it has run out.
	var after := [0]
	await wait_until(func() -> bool:
		if program.done():
			after[0] += 1
		return clock[0] >= 0.0 or after[0] > 60, LONGEST + 20.0, 1.0 / 60.0)

	assert_eq(won, [Eclipse.Phase.SHIELD, Eclipse.Phase.BURNING, Eclipse.Phase.ECLIPSE]
		as Array[int], "the Shield, the Burning and the Eclipse won, in order")
	assert_true(fallen[0], "the beam parried back into the disc: the King fallen")
	assert_eq(game.phase, Game.Phase.COMPLETE, "out through dawn's door")
	assert_eq(game.deaths, 0, "without a death")
	assert_between(clock[0], SHORTEST, LONGEST, "in a fight of a minute to two")
	gut.p("the Eclipse cleared in %.2f s on the game's clock, %d polls" % [clock[0],
		program.polls])
