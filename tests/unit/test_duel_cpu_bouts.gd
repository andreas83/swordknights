extends GutTest
## Whole matches against the computer opponent, headless, on the real fighter:
## it replays from its seed, it beats a dumb opponent in proportion to its
## level, and two of it always finish.
##
## Each test plays its matches inside one physics frame (await one, then run):
## the fighters are bodies and move_and_collide() queries the physics space,
## which only answers inside one -- the rule tests/cpu_support.gd and
## tests/duel_support.gd both state. The win rates are printed, because
## docs/duel-match.md quotes them and a number nobody can see drift is a
## number nobody will notice drifting.

const Cpu := preload("res://tests/cpu_support.gd")
const Support := preload("res://tests/duel_support.gd")

## Seeded matches per level against the closing bot.
const BOT_MATCHES := 10
## Three minutes of play at 60 Hz. A match the computer is in has to end well
## inside that: the longest HARD against HARD measured while tuning was about
## two and a half.
const LIMIT := 10800
## A bad jump now and then is human; this is the most hazard deaths allowed as
## a share of all deaths across the matches below.
const HAZARD_SHARE := 0.05

var _strip: ZoneStrip


func before_all() -> void:
	_strip = Support.load_strip()


## The same seed and the same human hands give the same match, frame for
## frame: every checksum equal. And a different seed gives a different match,
## or the seed is decoration and the first half proved nothing.
func test_a_match_replays_from_its_seed_and_the_human_inputs() -> void:
	await wait_physics_frames(1)
	var frames := 1500
	var first := _traced(frames, 41)
	var again := _traced(frames, 41)
	var other := _traced(frames, 42)
	var sums: PackedInt64Array = first["checksums"]
	assert_eq(sums.size(), int(first["frames"]), "a checksum for every frame stepped")
	assert_gt(sums.size(), 600, "long enough to have fought, not just walked")
	assert_eq(first["checksums"], again["checksums"], "seed 41 twice: every checksum equal")
	assert_eq(first["bits"], again["bits"], "and every byte the computer pressed")
	assert_ne(first["checksums"], other["checksums"], "seed 42 plays a different match")
	var kills := first["kills"] as PackedInt32Array
	assert_gt(kills[0] + kills[1], 0, "somebody died, so the replay covered a death")


## HARD beats the closing bot in most matches, EASY loses some, MEDIUM is in
## between, and none of them walks into the water to do it.
func test_each_level_beats_a_dumb_opponent_in_proportion() -> void:
	await wait_physics_frames(1)
	var wins := PackedInt32Array([0, 0, 0])
	var deaths := 0
	var drowned := 0
	for level: int in 3:
		for i: int in BOT_MATCHES:
			var seed_value := 1000 + i
			var cpu := DuelCpu.new(1, level as DuelBrain.Difficulty, seed_value)
			var bout := Cpu.bout(get_tree().root, _strip,
				[Cpu.closing_bot(0, seed_value), cpu], LIMIT)
			if int(bout["winner"]) == 1:
				wins[level] += 1
			deaths += (bout["deaths"] as PackedInt32Array)[1]
			drowned += (bout["hazards"] as PackedInt32Array)[1]
	gut.p("against the closing bot, of %d each: EASY won %d, MEDIUM %d, HARD %d"
		% [BOT_MATCHES, wins[0], wins[1], wins[2]])
	gut.p("the computer died %d times, %d of them to the ground" % [deaths, drowned])
	assert_gte(wins[2] * 10, BOT_MATCHES * 8, "HARD wins at least eight in ten")
	assert_lt(wins[0], BOT_MATCHES, "EASY loses some")
	assert_gt(wins[0], 0, "and wins some: easy is not a punchbag")
	assert_between(wins[1], wins[0], wins[2], "MEDIUM sits between EASY and HARD")
	assert_lte(float(drowned), float(deaths) * HAZARD_SHARE, "hazard deaths are rare")


## Two computers, every pairing of levels the menu can produce in a mirror and
## the two extremes against each other: each match reaches its end inside the
## limit. A standoff that never resolves is the failure a mode like this has.
func test_cpu_against_cpu_always_finishes() -> void:
	await wait_physics_frames(1)
	var pairings := [[0, 0], [1, 1], [2, 2], [0, 2], [2, 0], [1, 2]]
	var longest := 0
	var deaths := 0
	var drowned := 0
	var line := PackedStringArray()
	for pairing: Array in pairings:
		for i: int in 2:
			var a := DuelCpu.new(0, int(pairing[0]) as DuelBrain.Difficulty, 2000 + i)
			var b := DuelCpu.new(1, int(pairing[1]) as DuelBrain.Difficulty, 3000 + i)
			var bout := Cpu.bout(get_tree().root, _strip, [a, b], LIMIT)
			var name := "%s v %s #%d" % [DuelBrain.level_name(int(pairing[0]) as
				DuelBrain.Difficulty), DuelBrain.level_name(int(pairing[1]) as
				DuelBrain.Difficulty), i]
			assert_true(bool(bout["over"]), "%s finished (%d frames)" % [name, bout["frames"]])
			longest = maxi(longest, int(bout["frames"]))
			var both := bout["deaths"] as PackedInt32Array
			var ground := bout["hazards"] as PackedInt32Array
			deaths += both[0] + both[1]
			drowned += ground[0] + ground[1]
			line.append("%s: seat %d in %d" % [name, bout["winner"], bout["frames"]])
	gut.p("computer against computer: " + ", ".join(line))
	gut.p("longest %d frames; %d deaths, %d to the ground" % [longest, deaths, drowned])
	assert_gt(deaths, 0, "they fought")
	assert_lte(float(drowned), float(deaths) * HAZARD_SHARE, "hazard deaths are rare")


## A human who takes the initiative and then does not run home -- the input
## stream below wanders east, away from seat one's gate, sweeping and
## snatching -- has to be gone and got. The computer used to wait for them on
## its respawn ground for as long as they stood there in a sweep, and then
## refuse to cross the spike pit nine hundred pixels away to reach them: half
## of these matches never ended.
func test_a_leader_who_will_not_run_is_fetched() -> void:
	await wait_physics_frames(1)
	for i: int in 4:
		var cpu := DuelCpu.new(1, DuelBrain.Difficulty.EASY, 5000 + i)
		var bout := Cpu.bout(get_tree().root, _strip,
			[Cpu.scripted_human(LIMIT, 600 + i), cpu], LIMIT)
		assert_true(bool(bout["over"]), "against wandering hands #%d: over in %d frames"
			% [i, bout["frames"]])


## A human who presses things -- the stream the determinism suites use -- against
## a MEDIUM computer, seed by seed.
func _traced(frames: int, seed_value: int) -> Dictionary:
	var cpu := DuelCpu.new(1, DuelBrain.Difficulty.MEDIUM, seed_value)
	var human := Cpu.scripted_human(frames, 7)
	return Cpu.bout(get_tree().root, _strip, [human, cpu], frames, true)
