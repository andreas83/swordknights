extends RefCounted
## Shared scaffolding for the duel and netplay tests.
##
## Deliberately not a `class_name`: these are standalone scripts, run one at a
## time with `godot --headless --script tests/<name>.gd`, and the test support
## has no business in the project's global class registry. Load it with
##
##     const Support := preload("res://tests/duel_support.gd")
##
## TWO RULES THESE TESTS LIVE BY, both learned the hard way:
##
## 1. A Duel has to be inside the tree, and `step()` has to be called from a
##    physics frame. The duellists are CharacterBody2D; move_and_slide() queries
##    the physics space, and outside a physics frame there is no space to query
##    (Godot logs `body->get_space() is null` and the move does nothing).
##
## 2. ONE DUEL AT A TIME, always at the same coordinates. Two duels side by side
##    in one world is the obvious way to compare two simulations and it is
##    wrong: the second arena has to sit somewhere else in global space, and
##    2D physics is single-precision, so a body at y=8192 resolves collisions to
##    a coarser grid than the same body at y=192. The two sims then disagree in
##    the last bits of a float within a couple of hundred frames — a property of
##    the harness, not of the duel. So: build, run, record, free, build again.
##    `checksums_of` does exactly that.
##
## Checksums are 32-bit UNSIGNED. They do not fit in a PackedInt32Array, which
## silently wraps them negative and then compares unequal to the real thing.
## Collect them in PackedInt64Array.

var failures: PackedStringArray = []
var checks := 0


## --- building ---------------------------------------------------------------

static func load_arena() -> AsciiLevel:
	return AsciiLevel.from_file(DuelRules.ARENA_PATH)


## Builds one duel at the world origin. Free it with `duel.free()` before
## building the next, and leave a physics frame in between so the arena's
## collision leaves the space.
static func spawn_duel(root: Node, rounds: int = DuelRules.ROUNDS_TO_WIN) -> Duel:
	var duel := Duel.new()
	duel.name = "Duel"
	root.add_child(duel)
	duel.setup(load_arena(), rounds)
	return duel


## Runs `stream` through a fresh duel and returns its checksum after every
## frame. Must be called from inside a physics frame.
static func checksums_of(root: Node, stream: Array[Vector2i]) -> PackedInt64Array:
	var duel := spawn_duel(root)
	var out := PackedInt64Array()
	for pair: Vector2i in stream:
		duel.step(pair.x, pair.y)
		out.append(duel.checksum())
	duel.free()
	return out


## A repeatable stream of input pairs.
##
## Biased on purpose. A uniform random byte per frame is noise: it almost never
## produces a sword swing that connects, and it never holds a direction long
## enough to reach the other duellist. This holds each choice for a few frames,
## the way hands actually work, and leans on closing the distance.
static func input_stream(length: int, stream_seed: int) -> Array[Vector2i]:
	var rng := RandomNumberGenerator.new()
	rng.seed = stream_seed
	var out: Array[Vector2i] = []
	var held := Vector2i.ZERO
	for i: int in length:
		if i % 5 == 0:
			held = Vector2i(_one_frame(rng, 1), _one_frame(rng, -1))
		out.append(held)
	return out


static func _one_frame(rng: RandomNumberGenerator, toward: int) -> int:
	var bits := 0
	var roll := rng.randf()
	if roll < 0.55:
		bits |= PlayerInput.BIT_RIGHT if toward > 0 else PlayerInput.BIT_LEFT
	elif roll < 0.7:
		bits |= PlayerInput.BIT_LEFT if toward > 0 else PlayerInput.BIT_RIGHT
	if rng.randf() < 0.22:
		bits |= PlayerInput.BIT_JUMP
	if rng.randf() < 0.3:
		bits |= PlayerInput.BIT_ATTACK
	if rng.randf() < 0.18:
		bits |= PlayerInput.BIT_GUARD
	if rng.randf() < 0.12:
		bits |= PlayerInput.BIT_DOWN
	return bits


## --- assertions -------------------------------------------------------------

func check(condition: bool, what: String) -> bool:
	checks += 1
	if not condition:
		failures.append(what)
	return condition


func equal(actual: Variant, expected: Variant, what: String) -> bool:
	return check(
		actual == expected, "%s — expected %s, got %s" % [what, str(expected), str(actual)]
	)


## Returns the process exit code and prints the verdict.
func report(suite: String) -> int:
	# A suite that checked nothing has measured nothing. That is the failure
	# CLAUDE.md names, and it must not print PASS.
	if checks == 0:
		print("FAIL  %s  (no checks ran)" % suite)
		return 1
	if failures.is_empty():
		print("PASS  %s  (%d checks)" % [suite, checks])
		return 0
	print("FAIL  %s  (%d of %d checks failed)" % [suite, failures.size(), checks])
	for line: String in failures:
		print("  - ", line)
	return 1
