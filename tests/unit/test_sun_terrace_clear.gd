extends GutTest
## Chapter I, The Sun Terrace (levels/level_01.txt), played from the spawn to
## the door by a scripted thumb: no warps, no kills, under the death watch.
##
## Every other chapter has had a frozen clear run since it was built; the
## first had only tools/trace_level.gd's tour, which warps past what a
## program cannot see. This is its clear run, in tools/trace_level.gd's
## format -- `[frames, bits]` held in turn, step one on the level's first
## physics frame -- authored against the game and then frozen, so the
## campaign's end-to-end run (tests/unit/test_campaign_run.gd) can play the
## whole of The Last Light from its first frame. It is a steady line, not a
## tour: into the cistern and up its ladder, the leap off its top, the grab
## over the spikes, along the upper terrace past its sentinel, the drop, the
## basin at a run, past the lower sentinel and up the platform stair by a
## grab to the door. The secrets and relics are left where they are.

const GAME_SCENE := "res://scenes/game.tscn"
const LEVEL := "res://levels/level_01.txt"
## Par, docs/campaign.md: a good first clear without deaths.
const PAR := 60.0

const R := PlayerInput.BIT_RIGHT
const U := PlayerInput.BIT_UP
const J := PlayerInput.BIT_JUMP

## Spawn to door. Comments name the beat each run of steps plays.
const CLEAR_RUN := [
	# The open terrace at a run, into the cistern: the ladder caught falling.
	[116, R], [6, U],
	# Off the ladder's top with a leap onto the far floor.
	[20, R | J],
	# The terrace, then a running jump at the four-tile wall over the spikes:
	# the ledge grab, and the mantle.
	[142, R], [22, R | J], [20, R], [20, U],
	# The upper terrace past its sentinel, off its end, and the basin at a run.
	[210, R], [16, R | J],
	# Past the lower sentinel to the platform stair: a hop, a hop, and the
	# grab onto the door's terrace.
	[52, R], [14, R | J], [18, R], [14, R | J], [14, R], [20, R | J], [20, R], [20, U],
	# To the door.
	[200, R],
]


class ProgramInput extends PlayerInput:
	var bits := 0

	func poll() -> void:
		apply_bits(bits)


var _game: Game


## The game, with the replay's ticker connected before it enters the tree, so
## step one lands on the level's first physics frame. Returns the frames played.
func _replay() -> int:
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Game
	_game.level_source = AsciiLevel.from_file(LEVEL)
	var input := ProgramInput.new()
	var run := {"step": 0, "left": 0, "tick": 0, "done": false}
	var on_tick := func() -> void:
		if bool(run["done"]) or not is_instance_valid(_game):
			return
		if _game.player.input != input:
			_game.player.input = input
		if _game.phase == Game.Phase.COMPLETE:
			run["done"] = true
			return
		while int(run["left"]) <= 0:
			if int(run["step"]) >= CLEAR_RUN.size():
				run["done"] = true
				input.bits = 0
				return
			var step: Array = CLEAR_RUN[int(run["step"])]
			run["step"] = int(run["step"]) + 1
			run["left"] = int(step[0])
			input.bits = int(step[1])
		run["left"] = int(run["left"]) - 1
		run["tick"] = int(run["tick"]) + 1
	get_tree().physics_frame.connect(on_tick)
	add_child_autofree(_game)
	while not bool(run["done"]):
		await wait_physics_frames(1)
	get_tree().physics_frame.disconnect(on_tick)
	return int(run["tick"])


func test_the_clear_run_reaches_the_door_inside_par_without_a_death() -> void:
	var ticks := await _replay()
	gut.p("The Sun Terrace cleared: %d ticks, %.2f s on the clock (par %.0f s)"
		% [ticks, _game.elapsed, PAR])
	assert_eq(_game.phase, Game.Phase.COMPLETE, "the program reached the door")
	assert_eq(_game.deaths, 0, "without dying")
	assert_eq(_game.player.health, Tuning.MAX_HEALTH, "and without a scratch")
	assert_lt(_game.elapsed, PAR, "inside par")
