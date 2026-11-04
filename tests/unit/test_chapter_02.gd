extends GutTest
## Chapter II, The Long Arcade (levels/chapter_02.txt), proved and played.
##
## Proved, as docs/campaign.md asks of every chapter: the door is reachable,
## the three secrets are never required and never a trap, both torches are
## checkpoints, every relic can be reached, and every race beats its hold
## with 25% to spare -- measured, frame by frame, and set beside the bible's
## arithmetic.
##
## Played: CLEAR_RUN is a fixed input program in tools/trace_level.gd's
## format, [frames, bits] held in turn, authored once by a controller that
## read the game and then frozen. Replayed here blind -- no warp, no kill, no
## state read -- through the real scene under the death watch, it must reach
## the door with no death inside par. That is the check that the physics and
## the proof agree: the proof says the level can be finished by its moves,
## and this finishes it with the prince's.

const GAME_SCENE := "res://scenes/game.tscn"
const LEVEL := "res://levels/chapter_02.txt"
## Par, docs/campaign.md: a good first clear without deaths.
const PAR := 105.0
## The bible's arithmetic for each race, seconds of run against seconds of
## hold, by wire (docs/campaign.md, "Counterweights"). Bay two holds 1.7 s, not
## the draft's 1.6: measured, its kerb hop made the run 76% of 1.6.
const BIBLE := {
	&"2": [2.05, 4.0], &"3": [1.32, 2.2], &"4": [0.78, 1.2], &"5": [1.14, 1.7],
	&"6": [1.14, 1.6], &"7": [0.96, 1.6],
}

const R := PlayerInput.BIT_RIGHT
const L := PlayerInput.BIT_LEFT
const U := PlayerInput.BIT_UP
const D := PlayerInput.BIT_DOWN
const J := PlayerInput.BIT_JUMP
const A := PlayerInput.BIT_ATTACK
## The clear run, authored by a controller that watched the game and then
## frozen: 71 steps, 2001 physics frames. Step one applies on the first frame
## the level plays.
const CLEAR_RUN := [
	[112, R], [1, 0], [13, R | J], [32, R], [163, 0], [20, R], [240, 0], [1, A], [1, 0],
	[1, A], [1, 0], [1, A], [1, 0], [1, A], [1, 0], [1, A], [1, 0], [1, A], [49, 0], [1, A],
	[1, 0], [1, A], [1, 0], [1, A], [1, 0], [1, A], [69, R], [20, R | J], [26, R], [1, D | A],
	[2, D], [10, R | J], [6, J], [1, D], [1, D | A], [3, D], [34, 0], [186, R], [1, R | J],
	[20, R], [4, U], [122, R], [1, 0], [72, R], [1, R | J], [142, R], [1, 0], [20, R | J],
	[8, R], [4, U], [18, R], [1, 0], [81, R], [1, 0], [1, D], [1, D | A], [14, D], [12, 0],
	[1, D], [1, D | A], [2, D], [35, 0], [171, R], [20, R | J], [59, R], [20, R | J], [37, R],
	[20, R | J], [14, R], [16, R | J], [73, R],
]


class ProgramInput extends PlayerInput:
	var bits := 0

	func poll() -> void:
		apply_bits(bits)


var _game: Game


func after_each() -> void:
	Assist.reset()


func _level() -> AsciiLevel:
	return AsciiLevel.from_file(LEVEL)


## --- proved ---------------------------------------------------------------------------

func test_the_chapter_is_whole() -> void:
	var level := _level()
	assert_eq(level.name, "The Long Arcade", "titled")
	assert_eq(level.problems, PackedStringArray(), "parses clean")
	assert_eq(EntityRegistry.problems_in(level), PackedStringArray(), "every mechanism wired")
	assert_eq(TimeOfDay.stop_of(level), "golden", "at the golden hour")
	assert_eq(Campaign.entry(1)["file"], LEVEL, "and the campaign plays it as chapter II")
	assert_eq([level.cols, level.rows], [126, 26], "126 x 26, as drafted")


func test_the_door_the_secrets_and_the_torches_are_proved() -> void:
	var level := _level()
	assert_true(bool(LevelReachability.verify(level)["ok"]), "the door is reachable")
	var audit := LevelReachability.audit_secrets(level)
	assert_true(bool(audit["ok"]), "secrets: %s" % audit["reason"])
	assert_eq(int(audit.get("secrets", 0)), 3, "three of them")
	var torches: Array[Vector2i] = [Vector2i(56, 19), Vector2i(91, 19)]
	assert_eq(Game.checkpoint_cells(level), torches, "both torches lead to the door")


func test_every_relic_can_be_reached() -> void:
	var level := _level()
	var relics: Array[Vector2i] = []
	for mark: Dictionary in level.with_secrets(_all_open(level)).entities:
		if String(mark["kind"]) == "relic":
			relics.append(mark["cell"])
	assert_eq(relics.size(), 5, "five relics")
	var open := level.with_secrets(_all_open(level))
	var reached: Dictionary = LevelReachability.survey(open)["reached"]
	for cell: Vector2i in relics:
		assert_true(reached.has(cell) or reached.has(cell + Vector2i.DOWN),
			"the relic at %s can be stood on" % cell)


func _all_open(level: AsciiLevel) -> Dictionary:
	var open := {}
	for index: int in level.secrets.size():
		open[index] = true
	return open


func test_every_race_beats_its_hold_with_a_quarter_to_spare() -> void:
	var races := ReachRace.measure(_level())
	var wires := {}
	for race: Dictionary in races:
		var wire := StringName(race["channel"])
		var run := float(race["frames"]) / 60.0
		var hold := float(race["hold"]) / 60.0
		var bible: Array = BIBLE.get(wire, [0.0, 0.0])
		gut.p("race %s: %.2f s of %.2f s (%.0f%%); the bible's arithmetic %.2f of %.2f"
			% [wire, run, hold, 100.0 * run / hold, bible[0], bible[1]])
		assert_true(bool(race["ok"]), "race %s keeps 25%% slack" % wire)
		assert_eq(hold, float(bible[1]), "race %s holds as the bible says" % wire)
		wires[wire] = true
	assert_eq(wires.size(), BIBLE.size(), "all six races were measured")


## The corridor's answer is in the level, not in the player's head: an iron
## grate in its roof right over the Bastion's post, three wide with him
## under the middle so that a plunge through it lands on his helm and no
## stone rim is in reach of a prince bouncing off it -- and a grate seen
## first over a harmless drop, the balcony's, where the street runs under it.
func test_the_corridor_is_answered_by_a_grate_taught_before_it() -> void:
	var level := _level()
	var grates: Array[Dictionary] = []
	var corridor_bastion := Vector2i(-1, -1)
	for mark: Dictionary in level.entities:
		if String(mark["kind"]) == "hatch":
			grates.append(mark)
		if String(mark["kind"]) == "bastion" and (mark["cell"] as Vector2i).x in range(78, 95):
			corridor_bastion = mark["cell"]
	assert_eq(grates.size(), 2, "two grates: the balcony's and the corridor's")
	if grates.size() != 2:
		return
	var first: Array[Vector2i] = Mechanism.mark_cells(grates[0])
	var corridor: Array[Vector2i] = Mechanism.mark_cells(grates[1])
	assert_lt(first[0].x, corridor[0].x, "the balcony's grate comes first")
	assert_eq(level.kind_at(first[0].x, first[0].y), Tiles.Kind.PLATFORM, "a one-way floor")
	assert_eq(corridor.size(), 3, "the corridor's is three wide")
	assert_eq(corridor[1].x, corridor_bastion.x, "with the Bastion under its middle")
	assert_eq(corridor_bastion.y - corridor[0].y, 2, "two courses below it")
	assert_eq(level.kind_at(corridor[0].x - 1, corridor[0].y), Tiles.Kind.SOLID,
		"set flush in a roof of stone, not a notch you sink into")
	assert_eq(level.kind_at(corridor[0].x, corridor[0].y - 1), Tiles.Kind.EMPTY,
		"and walked on like the roof either side of it")


## --- played -----------------------------------------------------------------------------

## The game, with the replay's ticker connected before it enters the tree, so
## step one lands on the level's first physics frame exactly as it did when
## the program was recorded. Returns the frames played, once the door is
## reached or the program has run out.
func _replay() -> int:
	var data := _level()
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Game
	_game.level_source = data
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
	gut.p("clear run: %d ticks, %.2f s on the clock, %d deaths, relics %d/%d"
		% [ticks, _game.elapsed, _game.deaths, _game.relics, _game.relics_total])
	assert_eq(_game.phase, Game.Phase.COMPLETE, "the program reached the door")
	assert_eq(_game.deaths, 0, "without dying")
	assert_lt(_game.elapsed, PAR, "inside par")


func test_with_longer_warnings_the_tells_stretch_and_the_run_still_clears() -> void:
	Assist.load_saved(UserData.at("user://test_chapter_02_assist.cfg"))
	Assist.set_longer_warnings(true)
	var level := _level()
	var bastions := level.entities.filter(func(m: Dictionary) -> bool:
		return m["kind"] == "bastion")
	assert_eq(bastions.size(), 4, "four Bastions")
	var one: Bastion = autofree(Bastion.new())
	assert_almost_eq(one.windup_time(), Bastion.WINDUP_TIME * Assist.LONGER, 0.0001,
		"each Bastion's windup stretches")
	assert_eq(float(level.channels["2"]["seconds"]), 4.0,
		"the holds do not: a race is not a death")
	await _replay()
	assert_eq(_game.phase, Game.Phase.COMPLETE, "and the same run still reaches the door")
	assert_eq(_game.deaths, 0, "without dying")
	var assist_file := UserData.at("user://test_chapter_02_assist.cfg")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(assist_file))
