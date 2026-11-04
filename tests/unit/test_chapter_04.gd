extends GutTest
## Chapter IV, the Mirror Tower (levels/chapter_04.txt): proved the way the
## bible proves a draft (docs/campaign.md, "Proving a draft") and played from
## spawn to door in the real scene.
##
## ## What is proved
##
## The way to the door, with every door shut until a setting of the mirrors
## opens it (SunProof through the doors' reach hooks); the three secrets,
## never required and never a trap; every torch, in route order; every relic
## reachable; every beam and seal (SunProof.audit()); the dressed mask in
## agreement with the proof about every mirror; and each Glassbearer's glass
## lit or dull at his post as the beat sheet needs it.
##
## ## The clear run
##
## A scripted input program -- held buttons for counted frames, the format of
## tools/trace_level.gd, with no warp and no kill -- plays the chapter from the
## spawn to the door: the hall's sentinel, the lift, the grabs up the shaded
## face, the first mirror, the stairwell's two, the lift up the shaft, R5's
## Glassbearer parried home, R6 opened by the Glassbearer's own bolt through
## C and D, the roof, the summit, the great mirror struck until it faces down,
## and the great door. The death watch is installed for the whole of it, so
## a death anywhere fails the test (tests/death_watch.gd). It is played twice:
## as the game ships, and with LONGER WARNINGS on, where the Glassbearers aim
## for longer and the run is a different one -- the programs differ because
## the world does, and each was recorded from its own world.
##
## The programs are the frames a player's thumbs would give; they were
## written against the game with conditions ("until the bolt is 26 px out")
## and recorded as the plain frame counts the conditions came to, so the test
## needs nothing but buttons. A change to the chapter or to anything it plays
## through moves those counts, and then this test fails loudly at the beat
## that moved -- which is the point: the run is the chapter's own regression.
##
## The engine ticks ten times faster than the wall clock while the run plays
## (physics_ticks_per_second x 10, time_scale x 10): every step is still
## exactly 1/60 s of simulation, which is asserted, so the run is the game's
## run, in a tenth of the time.

const GAME_SCENE := "res://scenes/game.tscn"
const LEVEL := "res://levels/chapter_04.txt"
var _assist_path := UserData.at("user://test_chapter04_clear_assist.cfg")
## Par for a good first clear (docs/campaign.md, "The arc").
const PAR := 180.0
## How much faster than the wall clock the run is played.
const FAST := 10

## The clear run as it ships: `frames:buttons`, L R U D J A, `-` for none.
const RUN := """
20:- 140:R 2:- 1:A 19:- 13:R 1:A 19:- 84:R 210:- 121:L 21:LJ 20:U 2:- 11:L 10:- 0:R
1:- 20:RJ 20:U 2:- 1:A 69:- 153:R 5:- 21:L 20:LJ 20:U 2:- 28:L 3:- 1:A 69:- 106:R
3:- 20:RJ 20:U 2:- 10:- 18:R 190:- 10:- 53:L 85:L 1:- 59:- 1:UA 42:- 20:- 10:L 1:U
47:U 0:- 39:- 15:U 10:RJ 6:J 6:- 1:A 17:- 26:R 1:- 154:- 68:- 51:R 12:RJ 109:R 1:U
88:U 8:LJ 17:L 25:L 218:L 2:- 1:A 15:- 12:L 1:A 19:- 2:L 1:- 27:- 1:UA 13:- 54:L 2:-
1:A 17:- 8:- 1:A 17:- 8:- 72:- 295:R 14:RJ 21:R 5:R 14:RJ 17:R 300:R
"""

## The same chapter with LONGER WARNINGS on.
const RUN_ASSISTED := """
20:- 140:R 2:- 1:A 19:- 13:R 1:A 19:- 84:R 210:- 121:L 21:LJ 20:U 2:- 11:L 10:- 0:R
1:- 20:RJ 20:U 2:- 1:A 69:- 153:R 5:- 21:L 20:LJ 20:U 2:- 28:L 3:- 1:A 69:- 106:R
3:- 20:RJ 20:U 2:- 10:- 18:R 190:- 10:- 53:L 85:L 1:- 72:- 1:UA 42:- 20:- 10:L 1:U
47:U 0:- 50:- 15:U 10:RJ 6:J 6:- 1:A 17:- 26:R 1:- 165:- 81:- 51:R 12:RJ 87:R 1:U
88:U 8:LJ 17:L 24:L 277:L 2:- 1:A 19:- 13:L 1:A 17:- 0:- 7:L 2:- 1:A 17:- 8:- 72:-
295:R 14:RJ 21:R 4:R 14:RJ 17:R 300:R
"""


class ProgramInput extends PlayerInput:
	var bits := 0

	func poll() -> void:
		apply_bits(bits)


## Feeds a program to the prince, one physics step at a time, ahead of every
## node's own step -- as tools/trace_level.gd does.
class Driver extends RefCounted:
	var steps: Array[Vector2i] = []
	var input := ProgramInput.new()
	var at := 0
	var left := 0
	var started := false
	var done := false
	var bad_delta := false

	func tick() -> void:
		if not started:
			started = true
			return
		if absf(Engine.get_main_loop().root.get_physics_process_delta_time() - 1.0 / 60.0) > 0.0:
			bad_delta = true
		while left <= 0:
			if at >= steps.size():
				done = true
				input.bits = 0
				return
			left = steps[at].x
			input.bits = steps[at].y
			at += 1
		left -= 1


var _ticks := 0
var _scale := 1.0
var _steps := 0


func before_all() -> void:
	_ticks = Engine.physics_ticks_per_second
	_scale = Engine.time_scale
	_steps = Engine.max_physics_steps_per_frame


func after_each() -> void:
	Engine.physics_ticks_per_second = _ticks
	Engine.time_scale = _scale
	Engine.max_physics_steps_per_frame = _steps
	Assist.reset()
	if FileAccess.file_exists(_assist_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_assist_path))


func _level() -> AsciiLevel:
	return AsciiLevel.from_file(LEVEL)


## --- the proof ----------------------------------------------------------------

func test_the_chapter_parses_wired_and_is_set_at_dusk() -> void:
	var level := _level()
	assert_eq(level.problems, PackedStringArray(), "it parses clean")
	assert_eq(EntityRegistry.problems_in(level), PackedStringArray(), "and is wired")
	assert_eq(TimeOfDay.stop_of(level), "dusk")
	assert_eq(level.cols, 46, "46 wide")
	assert_eq(level.rows, 52, "52 tall")
	var entry := Campaign.entry(3)
	assert_eq(entry["file"], LEVEL, "chapter IV of the catalogue is this file")


func test_the_door_is_reached_and_the_secrets_are_never_required_or_traps() -> void:
	var level := _level()
	var report := LevelReachability.verify(level)
	assert_true(bool(report["ok"]), "the door: %s" % report["reason"])
	var audit := LevelReachability.audit_secrets(level)
	assert_true(bool(audit["ok"]), String(audit["reason"]))
	assert_eq(int(audit["secrets"]), 3, "three secrets")
	var kinds := {}
	for secret: Dictionary in level.secrets:
		kinds[secret["kind"]] = int(kinds.get(secret["kind"], 0)) + 1
	assert_eq(kinds, {"cracked": 2, "sun": 1}, "two cracked, one sun-sealed")


func test_every_torch_is_proved_along_the_route() -> void:
	var level := _level()
	var torches: Array[Vector2i] = []
	for mark: Dictionary in level.entities:
		if String(mark["kind"]) == "torch":
			torches.append(mark["cell"])
	assert_eq(torches.size(), 4, "four torches")
	var proved := Game.checkpoint_cells(level)
	assert_eq(proved.size(), torches.size(), "every one a checkpoint: %s" % str(proved))
	var route := ReachRoute.remaining(level)
	var left: Array[int] = []
	for torch: Vector2i in [Vector2i(13, 39), Vector2i(25, 31), Vector2i(26, 20),
			Vector2i(30, 6)]:
		assert_true(route.has(torch), "torch %s is on the proved route" % torch)
		left.append(int(route.get(torch, 0)))
	for i: int in range(1, left.size()):
		assert_lt(left[i], left[i - 1], "and each is further on than the last, bottom to top")


func test_every_relic_can_be_reached() -> void:
	var level := _level()
	var all := {}
	for index: int in level.secrets.size():
		all[index] = true
	var open := level.with_secrets(all)
	var relics := 0
	for mark: Dictionary in level.entities:
		if String(mark["kind"]) != "relic":
			continue
		relics += 1
		var cell: Vector2i = mark["cell"]
		var report := LevelReachability.reaches(open, [cell] as Array[Vector2i])
		assert_true(bool(report["ok"]), "the relic at %s: %s" % [cell, report["reason"]])
	assert_eq(relics, 5, "five relics")


func test_every_beam_and_seal_holds_to_the_bible() -> void:
	var level := _level()
	var audit := SunProof.audit(level)
	assert_true(bool(audit["ok"]), String(audit["reason"]))
	assert_gt(int(audit["checks"]), 20, "having checked every seal, rule and beam")
	var analysis := SunProof.analyse(level)
	assert_eq((analysis["puzzles"] as Array).size(), 3,
		"three puzzles: the great mirror, R6's three, the first light and the stairwell's")
	for puzzle: Array in analysis["puzzles"]:
		assert_lte(puzzle.size(), SunProof.MAX_MIRRORS, "at most three mirrors to a puzzle")


## --- the picture's half -------------------------------------------------------

func _play(assisted: bool = false) -> Game:
	if assisted:
		Assist.load_saved(_assist_path)
		Assist.set_longer_warnings(true)
	var game := (load(GAME_SCENE) as PackedScene).instantiate() as Game
	game.level_path = LEVEL
	add_child_autofree(game)
	await wait_physics_frames(2)
	return game


func test_the_dressed_mask_agrees_with_the_proof_on_every_mirror() -> void:
	var game := await _play()
	var checks := preload("res://tests/unit/test_mirrors.gd").MirrorChecks
	assert_eq(checks.disagreements(game), PackedStringArray(),
		"what the player sees lit is what the proof calls lit")


func test_each_glassbearer_s_glass_is_lit_or_dull_as_his_beat_needs() -> void:
	var game := await _play()
	var expected := {
		Vector2i(11, 47): false, ## the square, in the city's shadow: introduce
		Vector2i(11, 20): true, ## R5, outside the window: develop
		Vector2i(14, 15): true, ## R6, outside the doorway: twist
		Vector2i(9, 6): true, ## the summit, in the last gold: master
	}
	var seen := 0
	for node: Node in game.get_node("Entities").get_children():
		var bearer := node as Glassbearer
		if bearer == null:
			continue
		var post := Vector2i(int(bearer.post.split("@")[1].split(",")[0]),
			int(bearer.post.split(",")[1]))
		assert_true(expected.has(post), "a Glassbearer posted at %s is in the beat sheet" % post)
		assert_eq(bearer.glass_lit(), bool(expected.get(post, false)),
			"the glass at %s is %s" % [post, "lit" if expected.get(post) else "dull"])
		seen += 1
	assert_eq(seen, 4, "four Glassbearers")


## --- the clear run ------------------------------------------------------------

func _program(text: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var letters := {"L": PlayerInput.BIT_LEFT, "R": PlayerInput.BIT_RIGHT,
		"U": PlayerInput.BIT_UP, "D": PlayerInput.BIT_DOWN, "J": PlayerInput.BIT_JUMP,
		"A": PlayerInput.BIT_ATTACK}
	for word: String in text.replace("\n", " ").split(" ", false):
		var pair := word.split(":")
		var bits := 0
		for letter: String in pair[1]:
			bits |= int(letters.get(letter, 0))
		out.append(Vector2i(int(pair[0]), bits))
	return out


## Plays `text` from the spawn; returns the game when the program runs out.
func _clear_run(text: String, assisted: bool) -> Game:
	var game := await _play(assisted)
	var driver := Driver.new()
	driver.steps = _program(text)
	game.player.input = driver.input
	Engine.max_physics_steps_per_frame = 8 * FAST
	Engine.physics_ticks_per_second = 60 * FAST
	Engine.time_scale = float(FAST)
	get_tree().physics_frame.connect(driver.tick)
	while not driver.done and is_instance_valid(game):
		await wait_physics_frames(30)
		if game.phase == Game.Phase.COMPLETE:
			break
	get_tree().physics_frame.disconnect(driver.tick)
	Engine.physics_ticks_per_second = _ticks
	Engine.time_scale = _scale
	assert_false(driver.bad_delta, "every step was exactly 1/60 s of simulation")
	return game


func _assert_cleared(game: Game) -> void:
	assert_eq(game.phase, Game.Phase.COMPLETE, "the door was reached")
	assert_eq(game.deaths, 0, "with no death")
	assert_lt(game.elapsed, PAR, "inside par: %.2f s of %.0f" % [game.elapsed, PAR])
	gut.p("cleared in %.2f s (par %.0f s)" % [game.elapsed, PAR])
	var open := 0
	for node: Node in game.get_node("Entities").get_children():
		var seal := node as SunSeal
		if seal != null and not seal.secret:
			assert_eq(seal.phase, SunSeal.Phase.OPEN, "the door at %s was opened" % seal.cells[0])
			open += 1
	assert_eq(open, 5, "doors 1, 2 and 3, the Well's mouth and the great door")
	assert_eq(game.checkpoint, game.level.entity_world_position(Vector2i(30, 6)),
		"and the last torch claimed was the roof's")
	assert_true(SunField.sun_is_down(game.level),
		"the sun went under after the last ray went down the Well")


func test_a_clear_run_from_spawn_to_door_inside_par() -> void:
	_assert_cleared(await _clear_run(RUN, false))


func test_with_longer_warnings_the_tells_stretch_and_the_run_still_clears() -> void:
	var game := await _clear_run(RUN_ASSISTED, true)
	_assert_cleared(game)
	var bearer := Glassbearer.new()
	assert_almost_eq(bearer.aim_time(), Patrol.WINDUP_TIME * Assist.LONGER, 0.0001,
		"his aim was the longer one")
	bearer.free()
