extends GutTest
## Chapter III, The Aqueduct, played from the spawn to the door in the real
## game scene by a scripted thumb: no warps, no kills, under the death watch
## (tests/death_watch.gd), which fails the test if the prince dies even once.
##
## The program is in tools/trace_level.gd's format -- `[frames, bits]` held
## for that many physics frames -- and the trace tool plays it too
## (`--program aqueduct`), so a change to the chapter can be traced frame by
## frame. It takes the line the chapter teaches: over the first crumble at a
## run, up onto the walk past the cat on the doves, the yard cat backstepped
## and cut in its skid, the bridge run, the deck cat waited out until it
## crouches on the slabs and falls through them, the floor that is the door,
## past the sentinel in the channel, the collapse at a run, and the last cat
## cut out of the air. It must finish inside par (2:15, docs/campaign.md).
##
## Every number in it was found by playing, so a change that moves a slab,
## a cat's reach or the prince's run will break it -- which is the point: it
## is the chapter's proof that it plays, not only that it can be solved.

const LEVEL := "res://levels/chapter_03.txt"
const PAR := 135.0
const R := PlayerInput.BIT_RIGHT
const L := PlayerInput.BIT_LEFT
const U := PlayerInput.BIT_UP
const J := PlayerInput.BIT_JUMP
const A := PlayerInput.BIT_ATTACK

## Spawn to door. Comments name the beat each run of steps plays.
const RUN := [
	# The masons' gate and the first crumble, at a run; the grab onto the walk.
	[128, R], [16, R | J], [12, R], [20, U],
	# The walk, past R1 and the cat on the doves; off its end into the yard.
	[245, R],
	# The yard cat: wait for its leap, backstep it, step in and cut the skid.
	[89, 0], [1, L | A], [27, 0], [3, R], [1, A], [30, 0],
	# House A by a grab; the bridge at a run; torch 1; the deck by a hop.
	[86, R], [16, R | J], [12, R], [20, U], [110, R], [20, R | J], [30, 0], [20, U],
	# The deck: wait at its west end until the cat falls through the slabs.
	[204, 0],
	# Leap the broken run from its lip; run to the slabs before the tower.
	[54, R], [18, R | J], [196, R],
	# Stand on them: the floor is the door.
	[60, 0],
	# Through the channel, torch 2, the collapse at a run, onto the stone.
	[355, R],
	# The last cat: let it leap, cut it out of the air; then the door.
	[37, 0], [1, A], [20, 0], [150, R],
]


class ProgramInput extends PlayerInput:
	var bits := 0

	func poll() -> void:
		apply_bits(bits)


func test_the_aqueduct_is_cleared_without_a_death_inside_par() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Game
	game.level_path = LEVEL
	add_child_autofree(game)
	var input := ProgramInput.new()
	await get_tree().physics_frame
	game.player.input = input
	var lowest_health := game.player.health
	for step: Array in RUN:
		input.bits = int(step[1])
		for _frame: int in int(step[0]):
			await get_tree().physics_frame
			lowest_health = mini(lowest_health, game.player.health)
			if game.phase == Game.Phase.COMPLETE:
				break
		if game.phase == Game.Phase.COMPLETE:
			break
	input.bits = 0
	assert_eq(game.phase, Game.Phase.COMPLETE, "he reached the door")
	assert_eq(game.deaths, 0, "without dying")
	assert_lt(game.elapsed, PAR, "inside par")
	assert_eq(lowest_health, Tuning.MAX_HEALTH, "and without a scratch: every threat was read")
	gut.p("The Aqueduct cleared in %.2f s (par %.0f s)" % [game.elapsed, PAR])
