extends SceneTree
## A seed has to mean exactly one level, or reporting a seed is worthless.
##
## Checks byte-identical output for repeated calls, independence from call
## order, and — the one that actually catches the mistake — independence from
## the global random state. `randi()` is seeded per process, so a generator
## that reached for it instead of its own RandomNumberGenerator would pass a
## naive same-seed-twice test and still produce a different level tomorrow.
##
##     godot --headless --script tests/level_determinism_test.gd

const Asserts := preload("res://tests/level_asserts.gd")

const LENGTH := 110
const DIFFICULTY := 0.55
const SEEDS := 24

var _check := Asserts.new("level_determinism_test")


func _initialize() -> void:
	_check_repeats_are_identical()
	_check_global_random_state_is_irrelevant()
	_check_call_order_is_irrelevant()
	_check_distinct_seeds_differ()
	_check_parsed_level_round_trips()
	_check_retry_sub_seeds()
	quit(0 if _check.report() else 1)


## A retry must be reproducible and must actually be a different level. If two
## attempts shared a sub-seed the generator would regenerate the candidate it
## had just rejected and burn the attempt, so every attempt's sub-seed has to
## be distinct as well as stable.
func _check_retry_sub_seeds() -> void:
	for i: int in 40:
		var seed_value := -5000 + i * 313
		var seen := {}
		for attempt: int in LevelGenerator.MAX_ATTEMPTS:
			var sub := LevelGenerator.sub_seed(seed_value, attempt)
			_check.equal(LevelGenerator.sub_seed(seed_value, attempt), sub,
				"sub_seed(%d, %d) is stable" % [seed_value, attempt])
			_check.is_false(seen.has(sub),
				"sub_seed(%d, %d) is distinct from earlier attempts"
					% [seed_value, attempt])
			seen[sub] = true


func _check_repeats_are_identical() -> void:
	for i: int in SEEDS:
		var seed_value := 9000 + i * 37
		var first := LevelGenerator.generate_text(seed_value, LENGTH, DIFFICULTY)
		var second := LevelGenerator.generate_text(seed_value, LENGTH, DIFFICULTY)
		_check.is_false(first.is_empty(), "seed %d generated something" % seed_value)
		_check.equal(second, first, "seed %d repeats byte for byte" % seed_value)

		# And the grid itself, not just the header, via the parser's own writer.
		var a := LevelGenerator.generate(seed_value, LENGTH, DIFFICULTY)
		var b := LevelGenerator.generate(seed_value, LENGTH, DIFFICULTY)
		if a == null or b == null:
			_check.fail("seed %d produced no level" % seed_value)
			continue
		_check.equal(b.to_text(), a.to_text(), "seed %d to_text() is stable" % seed_value)
		_check.equal(b.spawn_point, a.spawn_point, "seed %d spawn is stable" % seed_value)
		_check.equal(b.entities.size(), a.entities.size(),
			"seed %d entity count is stable" % seed_value)
		_check.equal(b.name, a.name, "seed %d name is stable" % seed_value)


## Disturbing the global RNG between two generations must change nothing.
func _check_global_random_state_is_irrelevant() -> void:
	for i: int in 8:
		var seed_value := 4100 + i * 11
		seed(1)
		var first := LevelGenerator.generate_text(seed_value, LENGTH, DIFFICULTY)
		seed(0x5EEDBEEF)
		for _spin: int in 25:
			randi()
		randomize()
		var second := LevelGenerator.generate_text(seed_value, LENGTH, DIFFICULTY)
		_check.equal(second, first,
			"seed %d ignores the global random state" % seed_value)


## Generating other levels in between must not shift the result either, which
## is what would happen if any state leaked across calls.
func _check_call_order_is_irrelevant() -> void:
	var baseline := LevelGenerator.generate_text(777, LENGTH, DIFFICULTY)
	for other: int in [1, 2, 3, 500]:
		LevelGenerator.generate_text(other, 64, 0.9)
	_check.equal(LevelGenerator.generate_text(777, LENGTH, DIFFICULTY), baseline,
		"seed 777 is unaffected by other generations in between")


func _check_distinct_seeds_differ() -> void:
	var seen := {}
	for i: int in SEEDS:
		var seed_value := 20000 + i
		var text := LevelGenerator.generate_text(seed_value, LENGTH, DIFFICULTY)
		_check.is_false(seen.has(text),
			"seed %d produced a level no earlier seed produced" % seed_value)
		seen[text] = seed_value


## The emitted text must survive a parse: every grid row has to come back.
## A row that begins with a solid tile and a blank reads as a comment, so this
## is the check that catches a level silently losing a row.
func _check_parsed_level_round_trips() -> void:
	for i: int in 12:
		var seed_value := 31000 + i * 97
		var text := LevelGenerator.generate_text(seed_value, LENGTH, DIFFICULTY)
		var level := AsciiLevel.new()
		level.parse(text)
		_check.equal(level.rows, LevelGrammar.ROWS,
			"seed %d keeps all %d rows through a parse" % [seed_value, LevelGrammar.ROWS])

		# Re-parsing the same text is the same level.
		var again := AsciiLevel.new()
		again.parse(text)
		_check.equal(again.to_text(), level.to_text(),
			"seed %d parses the same way twice" % seed_value)
