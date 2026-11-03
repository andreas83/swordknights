extends GutTest
## Endless hides a secret in some of its ruins, and only where the grammar left
## room for one: in the sheer face a terrace leaves when it steps down, with
## the doorway on the lower floor and the room cut back under the terrace.
##
## And it hides it without moving anything else. The secret pass draws from
## its own rng, so the ruin around a secret is the same ruin, cell for cell,
## that the seed built before secrets existed — which is what keeps every seed
## written down in docs/level-generation.md meaning what it says.

const SEEDS := 16
const LENGTH := 170
const DIFFICULTIES: Array[float] = [0.45, 0.85]

var _built: Array[Dictionary] = []


func before_all() -> void:
	for seed_value: int in range(1, SEEDS + 1):
		for difficulty: float in DIFFICULTIES:
			var result := LevelGenerator.build(seed_value, LENGTH, difficulty)
			result["seed"] = seed_value
			result["difficulty"] = difficulty
			_built.append(result)


func _with_secret() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for result: Dictionary in _built:
		if not (result["level"] as AsciiLevel).secrets.is_empty():
			out.append(result)
	return out


func _what(result: Dictionary) -> String:
	return "seed %d at %.2f" % [int(result["seed"]), float(result["difficulty"])]


func test_some_ruins_hide_one_secret_and_none_hides_more() -> void:
	var count := _with_secret().size()
	assert_gt(count, 3, "some of %d ruins hide a secret" % _built.size())
	assert_lt(count, _built.size(), "and some do not")
	for result: Dictionary in _built:
		assert_lte((result["level"] as AsciiLevel).secrets.size(), 1,
			"%s hides at most one" % _what(result))


func test_every_generated_secret_passes_the_proof() -> void:
	for result: Dictionary in _with_secret():
		var report := LevelReachability.audit_secrets(result["level"] as AsciiLevel)
		assert_true(bool(report["ok"]), "%s: %s" % [_what(result), String(report["reason"])])


func test_the_doorway_is_in_a_face_over_the_lower_floor() -> void:
	for result: Dictionary in _with_secret():
		var level := result["level"] as AsciiLevel
		var secret: Dictionary = level.secrets[0]
		var seal: Array = secret["seal"]
		assert_eq(seal.size(), 2, "%s: a doorway two courses tall" % _what(result))
		var foot: Vector2i = seal[0] if (seal[0] as Vector2i).y > (seal[1] as Vector2i).y \
			else seal[1]
		var front := foot + Vector2i.RIGHT
		assert_eq(level.kind_at(front.x, front.y), Tiles.Kind.EMPTY,
			"%s: open floor in front of the doorway" % _what(result))
		assert_true(level.is_solid(front.x, front.y + 1),
			"%s: and ground under it" % _what(result))
		assert_true(level.is_solid(foot.x, foot.y - 2),
			"%s: and a terrace over the doorway" % _what(result))
		for cell: Vector2i in secret["room"]:
			assert_lt(cell.x, foot.x, "%s: the room is cut back under the terrace" % _what(result))
		var prizes := 0
		for mark: Dictionary in level.entities:
			if String(mark["kind"]) == "relic" and level.secret_at(mark["cell"]) == 0:
				prizes += 1
		assert_eq(prizes, 1, "%s: the room holds a relic" % _what(result))


func test_a_secret_moves_nothing_else_in_the_ruin() -> void:
	for result: Dictionary in _with_secret():
		var seed_value := int(result["seed"])
		var difficulty := float(result["difficulty"])
		var stream := LevelGenerator.sub_seed(seed_value, int(result["attempts"]) - 1)
		var plain := AsciiLevel.new()
		plain.parse(String(LevelGenerator._compose(stream, LENGTH, difficulty, seed_value,
			false)["text"]))
		var level := result["level"] as AsciiLevel
		assert_eq(plain.cols, level.cols, "%s: same width" % _what(result))
		assert_eq(plain.spawn_point, level.spawn_point, "%s: same spawn" % _what(result))
		var moved := 0
		for y: int in level.rows:
			for x: int in level.cols:
				if level.secret_at(Vector2i(x, y)) >= 0:
					continue
				if plain.kind_at(x, y) != level.kind_at(x, y):
					moved += 1
		assert_eq(moved, 0, "%s: every cell outside the secret is as it was" % _what(result))
		assert_eq(plain.entities.size() + 1, level.entities.size(),
			"%s: one more entity, the prize" % _what(result))


func test_the_same_seed_hides_the_same_secret() -> void:
	for result: Dictionary in _with_secret():
		var again := LevelGenerator.generate_text(int(result["seed"]), LENGTH,
			float(result["difficulty"]))
		assert_eq(again, String(result["text"]), "%s rebuilds byte for byte" % _what(result))
