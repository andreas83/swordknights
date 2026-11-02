extends SceneTree
## Generates a lot of levels and insists every one of them can be finished.
##
## `LevelGenerator.build` already verifies its own output, so a seed that gets
## here unsolvable means the generator returned something it had rejected.
## This suite re-verifies independently anyway — a self-check that is never
## checked from outside is a self-check that quietly stops running.
##
##     godot --headless --script tests/level_solvability_test.gd

const Asserts := preload("res://tests/level_asserts.gd")

## Well past the 200 the brief asks for, across a spread of lengths and
## difficulties so the hard beats are actually exercised.
const SEED_COUNT := 240
const LENGTHS: Array[int] = [40, 90, 140, 200]
const DIFFICULTIES: Array[float] = [0.0, 0.2, 0.45, 0.7, 0.9, 1.0]

var _check := Asserts.new("level_solvability_test")


func _initialize() -> void:
	var started := Time.get_ticks_msec()
	var attempts_used := 0
	var retried := 0
	var explored_total := 0
	var failed := PackedStringArray()

	for i: int in SEED_COUNT:
		var seed_value := 100000 + i * 7919
		var length: int = LENGTHS[i % LENGTHS.size()]
		var difficulty: float = DIFFICULTIES[i % DIFFICULTIES.size()]

		var result := LevelGenerator.build(seed_value, length, difficulty)
		if not bool(result["ok"]):
			failed.append("seed %d (len %d, diff %.2f)" % [seed_value, length, difficulty])
			_check.fail("seed %d len %d diff %.2f could not be generated"
				% [seed_value, length, difficulty])
			continue

		var attempts := int(result["attempts"])
		attempts_used += attempts
		if attempts > 1:
			retried += 1

		# Independent re-verification of what the generator handed back.
		var level := result["level"] as AsciiLevel
		var report := LevelReachability.verify(level)
		explored_total += int(report.get("explored", 0))
		_check.is_true(bool(report["ok"]),
			"seed %d len %d diff %.2f verifies as solvable: %s"
				% [seed_value, length, difficulty, String(report.get("reason", ""))])

	var elapsed := Time.get_ticks_msec() - started
	print("  %d seeds, %d needed a retry, %.2f attempts each on average" % [
		SEED_COUNT, retried, float(attempts_used) / float(maxi(SEED_COUNT, 1))])
	print("  %d states explored in total, %d ms" % [explored_total, elapsed])
	if not failed.is_empty():
		printerr("  unsolvable: " + ", ".join(failed))

	# Retries are legitimate, but a generator that needs one most of the time
	# is a generator whose grammar is fighting its own verifier.
	_check.is_true(retried <= SEED_COUNT / 4,
		"at most a quarter of seeds need a retry (%d of %d did)" % [retried, SEED_COUNT])

	quit(0 if _check.report() else 1)
