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
## 1. A match has to be inside the tree, and `step()` has to be called from a
##    physics frame. The fighters are bodies; move_and_collide() queries the
##    physics space, and outside a physics frame there is no space to query
##    (Godot logs `body->get_space() is null` and the move does nothing).
##
## 2. EVERY MATCH AT THE SAME COORDINATES. Two simulations side by side in one
##    world is the obvious way to compare them, and wrong if "side by side"
##    means somewhere else in global space: 2D physics is single-precision, so
##    a body at y=8192 resolves collisions to a coarser grid than the same body
##    at y=192, and the two disagree in the last bits of a float within a couple
##    of hundred frames -- a property of the harness, not of the duel. The round
##    duel this repository started with taught that. Every match builds its
##    ground at the strip's own origin, and a fighter collides with the ground
##    and never with the other match's fighters, so two matches can share the
##    world as long as both are built by `spawn_match`.
##
## Checksums are 32-bit UNSIGNED. They do not fit in a PackedInt32Array, which
## silently wraps them negative and then compares unequal to the real thing.
## Collect them in PackedInt64Array.

const MANIFEST := "res://levels/duel_zones.txt"
const FIGHTER_SCENE := "res://scenes/fighter.tscn"

var failures: PackedStringArray = []
var checks := 0


## --- building ---------------------------------------------------------------

static func load_strip() -> ZoneStrip:
	return ZoneStrip.from_manifest(MANIFEST)


## Builds one match on the real fighter, at the world origin. Free it with
## `fight.free()`. Returns null if it would not build.
static func spawn_match(root: Node, strip: ZoneStrip = null) -> DuelMatch:
	var fight := DuelMatch.new()
	fight.name = "Match"
	fight.fighter_scene = load(FIGHTER_SCENE)
	root.add_child(fight)
	if not fight.build(strip if strip != null else load_strip()):
		fight.free()
		return null
	return fight


## Runs `stream` through a fresh match and returns its checksum after every
## frame. Must be called from inside a physics frame.
static func checksums_of(root: Node, stream: Array[Vector2i]) -> PackedInt64Array:
	var out := PackedInt64Array()
	var fight := spawn_match(root)
	if fight == null:
		return out
	for pair: Vector2i in stream:
		fight.step(pair.x, pair.y)
		out.append(fight.checksum())
	fight.free()
	return out


## A repeatable stream of input pairs.
##
## Biased on purpose. A uniform random byte per frame is noise: it almost never
## produces a sword swing that connects, and it never holds a direction long
## enough to reach the other fighter. This holds each choice for a few frames,
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
