extends SceneTree
## Difficulty has to be a dial, not a parameter that gets accepted and ignored.
##
## Checking that the bytes differ is too weak — any change to the rng stream
## would satisfy it. So this checks the things difficulty is supposed to mean:
## which beats are allowed to appear, how wide the hazards get, and how much of
## the level is dangerous.
##
##     godot --headless --script tests/level_difficulty_test.gd

const Asserts := preload("res://tests/level_asserts.gd")

const SEEDS := 20
const LENGTH := 150
const EASY := 0.1
const HARD := 0.95

var _check := Asserts.new("level_difficulty_test")


func _initialize() -> void:
	var easy := _survey(EASY)
	var hard := _survey(HARD)

	print("  easy: %s" % _describe(easy))
	print("  hard: %s" % _describe(hard))

	_check_output_changes()
	_check_hazards_scale(easy, hard)
	_check_vocabulary_is_gated(easy, hard)
	_check_extremes_are_valid()

	quit(0 if _check.report() else 1)


## The same seed at two difficulties must not produce the same level.
func _check_output_changes() -> void:
	for i: int in SEEDS:
		var seed_value := 55000 + i * 211
		var easy_text := LevelGenerator.generate_text(seed_value, LENGTH, EASY)
		var hard_text := LevelGenerator.generate_text(seed_value, LENGTH, HARD)
		_check.is_false(easy_text.is_empty(), "seed %d generates at easy" % seed_value)
		_check.is_false(hard_text.is_empty(), "seed %d generates at hard" % seed_value)
		_check.not_equal(hard_text, easy_text,
			"seed %d produces a different level at difficulty %.2f than %.2f"
				% [seed_value, HARD, EASY])


## Harder levels must actually be more dangerous.
func _check_hazards_scale(easy: Dictionary, hard: Dictionary) -> void:
	_check.greater(float(hard["hazards"]), float(easy["hazards"]),
		"hard levels hold more spike and water tiles than easy ones")
	_check.greater(float(hard["guards"]), float(easy["guards"]),
		"hard levels hold more guards than easy ones")
	_check.is_true(int(hard["widest_gap"]) >= int(easy["widest_gap"]),
		"hard levels gap at least as wide as easy ones (%d vs %d)"
			% [int(hard["widest_gap"]), int(easy["widest_gap"])])
	_check.is_true(int(hard["tallest_rise"]) >= int(easy["tallest_rise"]),
		"hard levels climb at least as high as easy ones (%d vs %d)"
			% [int(hard["tallest_rise"]), int(easy["tallest_rise"])])


## The hardest beats are gated behind difficulty, so an easy level must not
## contain any of them and a hard one must contain some.
func _check_vocabulary_is_gated(easy: Dictionary, hard: Dictionary) -> void:
	var easy_beats: Dictionary = easy["beats"]
	var hard_beats: Dictionary = hard["beats"]

	for id: String in ["grab_wall", "water_basin"]:
		_check.equal(int(easy_beats.get(id, 0)), 0,
			"no '%s' beat appears at difficulty %.2f" % [id, EASY])
		_check.greater(float(hard_beats.get(id, 0)), 0.0,
			"'%s' beats appear at difficulty %.2f" % [id, HARD])

	# And the gentle end of the vocabulary must not vanish entirely, or a hard
	# level is just a wall of hazards with nowhere to stand.
	_check.greater(float(hard_beats.get("terrace", 0)), 0.0,
		"terraces still appear at difficulty %.2f" % HARD)


## Both ends of the dial have to produce a playable level, not just the middle.
func _check_extremes_are_valid() -> void:
	for difficulty: float in [0.0, 1.0]:
		for i: int in 6:
			var seed_value := 61000 + i
			var result := LevelGenerator.build(seed_value, LENGTH, difficulty)
			_check.is_true(bool(result["ok"]),
				"seed %d at difficulty %.1f generates: %s"
					% [seed_value, difficulty, String(result["reason"]).substr(0, 120)])


## Totals across SEEDS levels at one difficulty.
func _survey(difficulty: float) -> Dictionary:
	var hazards := 0
	var guards := 0
	var relics := 0
	var widest_gap := 0
	var tallest_rise := 0
	var beats := {}

	for i: int in SEEDS:
		var seed_value := 55000 + i * 211
		var result := LevelGenerator.build(seed_value, LENGTH, difficulty)
		if not bool(result["ok"]):
			_check.fail("seed %d at difficulty %.2f failed to generate"
				% [seed_value, difficulty])
			continue

		var level := result["level"] as AsciiLevel
		for y: int in level.rows:
			for x: int in level.cols:
				if Tiles.is_deadly(level.kind_at(x, y)):
					hazards += 1
		for mark: Dictionary in level.entities:
			match String(mark["kind"]):
				"patrol":
					guards += 1
				"relic":
					relics += 1

		for spec: Dictionary in result["beats"] as Array:
			var id := String(spec["id"])
			beats[id] = int(beats.get(id, 0)) + 1
			var span := int((spec["params"] as Dictionary).get("span", 0))
			widest_gap = maxi(widest_gap, span)
			tallest_rise = maxi(tallest_rise, int(spec["exit"]) - int(spec["entry"]))

	return {
		"hazards": hazards, "guards": guards, "relics": relics,
		"widest_gap": widest_gap, "tallest_rise": tallest_rise, "beats": beats,
	}


func _describe(survey: Dictionary) -> String:
	return "%d hazard tiles, %d guards, %d relics, widest gap %d, tallest rise %d, beats %s" % [
		int(survey["hazards"]), int(survey["guards"]), int(survey["relics"]),
		int(survey["widest_gap"]), int(survey["tallest_rise"]), str(survey["beats"]),
	]
