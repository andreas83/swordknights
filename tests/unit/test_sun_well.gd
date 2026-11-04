extends GutTest
## Chapter V, The Sun Well (levels/chapter_05.txt), held to what the drafts
## were held to in docs/campaign.md ("Proving a draft") and to the brief it
## was built against: it is the catalogue's chapter V, at night; the door is
## reached and every torch is proved along the route; the secrets are never
## required and never a trap; every relic can be had; every blade crossing
## keeps its window and its slack, and the throat's ride its dance -- and it
## plays. A scripted input, with no warps and no kills, plays the real scene
## from the spawn to the Vault's door with no death, inside par, with LONGER
## WARNINGS off and on.

const GAME_SCENE := "res://scenes/game.tscn"
const LEVEL := "res://levels/chapter_05.txt"
## Par for this chapter alone: a good first clear without deaths. The
## bible's 4:00 is the chapter with the Eclipse, whose first clear runs about
## a minute and three quarters, so the chapter's own is 2:15.
const PAR := 135.0

const R := PlayerInput.BIT_RIGHT
const L := PlayerInput.BIT_LEFT
const U := PlayerInput.BIT_UP
const J := PlayerInput.BIT_JUMP
const A := PlayerInput.BIT_ATTACK

## The clear run, in tools/trace_level.gd's format: `[frames, bits]` held for
## that many physics frames. No warps and no kills: every frame is the
## player's thumbs. The timings are the beat's -- frame 100k on the beat,
## 100k + 50 off it -- read off the level's own clock.
const CLEAR_RUN := [
	# The square: run at the mouth and drop through it. The owl on the flags
	# spreads as he goes over the lip, and folds as he lands under the floor.
	[20, 0],
	[210, R],
	[10, 0],
	# The gallery: torch 1, through the scythe's door in its rest, R1, and
	# down the shaft.
	[200, R],
	[33, 0],
	# The corridor, set off on the beat: both pairs of slots and the scythe
	# without a stop.
	[222, R],
	# The sump: a hop to the shelf and straight on up to the rim, inside the
	# owl's fold.
	[20, 0],
	[10, R],
	[18, R | J],
	[6, R],
	[24, R | J],
	[30, U],
	# Torch 2, and onto the lift's east half.
	[150, R],
	[157, 0],
	# The ride: across the slab after each cut, left, right, left, right.
	[20, L],
	[35, 0],
	[20, R],
	[125, 0],
	[20, L],
	[35, 0],
	[20, R],
	[200, 0],
	# Off at the foot: torch 3. A tapped hop up behind the sentinel as he
	# walks away -- short enough that the owl on the column folds -- and two
	# cuts inside his raise.
	[25, R],
	[90, 0],
	[6, R | J],
	[20, R],
	[6, R],
	[1, R | A],
	[24, 0],
	[8, R],
	[1, R | A],
	[40, 0],
	# Down the hall's end on the beat: the scythe's door in its rest, the
	# slots run under the second owl, and the Vault's door.
	[101, 0],
	[200, R],
]


class ProgramInput extends PlayerInput:
	var bits := 0

	func poll() -> void:
		apply_bits(bits)


## Steps the program once per physics frame, before anything in the scene
## moves -- the order tools/trace_level.gd plays a program in.
class Driver extends Node:
	var input := ProgramInput.new()
	var steps: Array = []
	var step := 0
	var left := 0
	var done := false

	func _ready() -> void:
		process_physics_priority = -1000

	func _physics_process(_delta: float) -> void:
		while left <= 0:
			if step >= steps.size():
				input.bits = 0
				done = true
				return
			left = int(steps[step][0])
			input.bits = int(steps[step][1])
			step += 1
		left -= 1


func before_each() -> void:
	Assist.reset()


func after_each() -> void:
	Assist.reset()


func _level() -> AsciiLevel:
	return AsciiLevel.from_file(LEVEL)


## --- what it is -----------------------------------------------------------------

func test_it_is_the_catalogues_chapter_five_at_night() -> void:
	var index := -1
	for i: int in Campaign.count():
		if String(Campaign.entry(i)["id"]) == "sun_well":
			index = i
	assert_gt(index, -1, "the Sun Well is in the catalogue")
	assert_eq(Campaign.entry(index)["file"], LEVEL, "and is this level")
	var level := _level()
	assert_eq(level.name, "The Sun Well")
	assert_eq(level.problems, PackedStringArray(), "parses clean")
	assert_eq(EntityRegistry.problems_in(level), PackedStringArray(), "every mechanism wired")
	assert_eq(TimeOfDay.stop_of(level), "night", "set at night, as the catalogue says")
	assert_eq(String(Campaign.entry(index + 1)["id"]), "eclipse",
		"and the Eclipse is the entry its door leads to")


func test_the_door_is_reached_and_every_torch_is_proved_along_the_route() -> void:
	var level := _level()
	assert_true(bool(LevelReachability.verify(level)["ok"]), "the Vault's door is reached")
	var torches: Array[Vector2i] = []
	for mark: Dictionary in level.entities:
		if String(mark["kind"]) == "torch":
			torches.append(mark["cell"])
	assert_eq(torches.size(), 3, "three torches")
	assert_eq(Game.checkpoint_cells(level), torches, "every one proved to lead to the door")
	var args: PackedStringArray = level.directive("checkpoints").get("args", PackedStringArray())
	assert_eq(args, PackedStringArray(["route"]), "a tall chapter: checkpoints along the route")
	var left := ReachRoute.remaining(level)
	for i: int in range(1, torches.size()):
		assert_lt(int(left[torches[i]]), int(left[torches[i - 1]]),
			"torch %d is further on than torch %d" % [i + 1, i])


func test_the_secrets_are_never_required_and_never_a_trap() -> void:
	var audit := LevelReachability.audit_secrets(_level())
	assert_true(bool(audit["ok"]), String(audit.get("reason", "")))
	assert_eq(_level().secrets.size(), 3, "A by the ladder, B in the sump, C at the foot")


func test_every_relic_can_be_had() -> void:
	var level := _level()
	var open := {}
	for i: int in level.secrets.size():
		open[i] = true
	var reached: Dictionary = LevelReachability.survey(level.with_secrets(open))["reached"]
	var relics := 0
	for mark: Dictionary in level.entities:
		if String(mark["kind"]) == "relic":
			relics += 1
			assert_true(reached.has(mark["cell"]), "the relic at %s" % mark["cell"])
	assert_eq(relics, 5, "R1, R2 and one in each secret")


func test_every_blade_keeps_its_window_and_the_throat_its_dance() -> void:
	var proof := BeatProof.prove(_level())
	assert_true(bool(proof["ok"]), "the beat proof: %s" % [proof["problems"]])
	var ways := {}
	for blade: Dictionary in proof["blades"]:
		ways[blade["way"]] = int(ways.get(blade["way"], 0)) + 1
	assert_eq(ways, {"run": 6, "ride": 5}, "six blades crossed on foot, five ridden past")
	assert_eq((proof["runs"] as Array).size(), 2, "the corridor's rhythm and the antechamber's")
	var rides: Array = proof["rides"]
	assert_eq(rides.size(), 1, "one ride: the throat")
	assert_gte(float(rides[0]["gap"]), BeatProof.NO_TWO_ANSWERS,
		"cuts from opposite walls never ask for two answers inside 20 frames")


## --- it plays ---------------------------------------------------------------------

func _clear_run() -> Game:
	var game := (load(GAME_SCENE) as PackedScene).instantiate() as Game
	game.level_path = LEVEL
	var driver := Driver.new()
	driver.steps = CLEAR_RUN
	add_child_autofree(driver)
	add_child_autofree(game)
	game.player.input = driver.input
	var frames := 0
	for step: Array in CLEAR_RUN:
		frames += int(step[0])
	for _frame: int in frames + 120:
		await wait_physics_frames(1)
		if game.phase == Game.Phase.COMPLETE:
			break
	return game


func test_the_clear_run_reaches_the_vault_door_with_no_death_inside_par() -> void:
	var game := await _clear_run()
	assert_eq(game.phase, Game.Phase.COMPLETE, "through the Vault's door")
	assert_eq(game.deaths, 0, "with no death")
	assert_eq(game.player.health, Tuning.MAX_HEALTH, "and not a heart lost")
	assert_lt(game.elapsed, PAR, "inside the chapter's par")
	assert_eq(game.checkpoint, Vector2(72.0 * 16.0 + 8.0, 44.0 * 16.0), "torch 3 the last held")
	gut.p("The Sun Well, cleared in %.2f s (par %d s)" % [game.elapsed, roundi(PAR)])


func test_with_longer_warnings_nothing_breaks() -> void:
	Assist.load_saved("user://test_sun_well_assist.cfg")
	Assist.set_longer_warnings(true)
	var game := await _clear_run()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_sun_well_assist.cfg"))
	assert_eq(game.phase, Game.Phase.COMPLETE, "the same run clears it")
	assert_eq(game.deaths, 0, "with no death")
	assert_eq(game.player.health, Tuning.MAX_HEALTH, "and not a heart lost")
	assert_true(bool(BeatProof.prove(_level())["ok"]),
		"and the proof, which checks the widened tells fit, holds")


## The twist (docs/campaign.md, the owl's table): at the scythe's door, a
## half-height jump between the cut and the off-beat, and a step back. The owl
## on the hall's column stoops at where he was, its wing reaches into the
## doorway as the blade comes through on the beat, and the machine kills it.
## Timed off the level's own beat, at frame 34 to 40 of it -- the middle of
## the window, which runs from about 26 to 47.
func test_the_machine_kills_the_first_owl() -> void:
	var game := (load(GAME_SCENE) as PackedScene).instantiate() as Game
	game.level_path = LEVEL
	add_child_autofree(game)
	var input := ProgramInput.new()
	game.player.input = input
	await wait_physics_frames(2)
	game.player.position = Vector2(80.5 * 16.0, 45.0 * 16.0)
	game.camera.setup(game.player, game.level.world_size())
	var owl: Owl = null
	for node: Node in game.get_node("Entities").get_children():
		if node is Owl and absf((node as Owl).perch.x - 76.5 * 16.0) < 8.0:
			owl = node as Owl
	assert_not_null(owl, "the owl on the hall's column")
	# The window is twenty frames wide, so a test that resumes a frame or two
	# late (an await is not frame-exact) still jumps inside it.
	var jumped := [-1]
	for _frame: int in 400:
		await wait_physics_frames(1)
		var now: int = game._bus.frame
		if jumped[0] < 0 and now > 100 and now % 100 >= 34 and now % 100 <= 40:
			jumped[0] = now
		var since: int = now - int(jumped[0])
		if jumped[0] < 0 or since >= 30 + 14:
			input.bits = 0
		elif since < 10:
			input.bits = J
		elif since >= 30:
			input.bits = L
		else:
			input.bits = 0
		if not owl.is_alive():
			break
	assert_false(owl.is_alive(), "the scythe cut it out of its stoop")
	assert_eq(game.player.health, Tuning.MAX_HEALTH, "and the prince was never touched")
