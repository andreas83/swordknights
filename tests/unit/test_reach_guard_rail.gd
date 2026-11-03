extends GutTest
## A level without mechanisms is proved exactly as it was before mechanisms
## existed: verify, the secret audit, the checkpoint proof and the Endless
## generator alike.
##
## The masked search is separate code (scripts/levels/reach_search.gd),
## reached only through a non-empty ReachModel, and these tests hold that
## line from both sides:
##
## - **Nothing shipping takes the new path.** Every level in levels/ and every
##   ruin the generator builds has an empty model.
## - **The old path gives the old answers.** The Sun Terrace's proof and four
##   Endless ruins are pinned to numbers taken from the proof on the commit
##   before the framework landed: states explored, the audit's states, the
##   torches proved, the very text of each ruin. A deliberate retune of
##   Tuning moves these, and should re-pin them in the same commit and say
##   so; anything else that moves them changed the proof for levels with no
##   mechanism in them, which is what this file is here to stop.
## - **The new path agrees where nothing changes.** Forced onto the Sun
##   Terrace with a model whose only wire changes no cell, the masked flood
##   reaches exactly the cells the plain one does.

## Taken on the commit before the mechanism framework, with the proof as it
## was then.
const SUN_TERRACE := {
	"verify_explored": 27, "verify_states": 76,
	"audit_states": 746, "survey_states": 91, "survey_reached": 86,
}
const SUN_TERRACE_CHECKPOINTS: Array[Vector2i] = [
	Vector2i(69, 6), Vector2i(34, 11), Vector2i(7, 15),
]
## seed, difficulty, states the generator's proof explored, md5 of the text.
const RUINS := [
	[1, 0.5, 60, "57eea82095fb927bbcdc41828e12ee2c"],
	[2024, 0.6, 59, "e83d284ba8d7de390a77b2dca5a82d88"],
	[51759241, 0.9, 56, "2aee442f482ba89cae1b9cf99e7cc886"],
	[225741179, 0.55, 57, "c023a629fb49f2238c85a42faef502bd"],
]


func _sun_terrace() -> AsciiLevel:
	return AsciiLevel.from_file("res://levels/level_01.txt")


func test_no_shipping_level_or_ruin_takes_the_masked_path() -> void:
	var checked := 0
	for name: String in DirAccess.get_files_at("res://levels"):
		if name.get_extension() != "txt" or name == "duel_zones.txt":
			continue
		var level := AsciiLevel.from_file("res://levels".path_join(name))
		assert_true(ReachModel.for_level(level).is_empty(), "%s has no mechanism" % name)
		checked += 1
	for ruin: Array in RUINS:
		var level := LevelGenerator.build(int(ruin[0]), 170, float(ruin[1]))["level"] as AsciiLevel
		assert_true(ReachModel.for_level(level).is_empty(), "ruin %d has none" % int(ruin[0]))
		checked += 1
	assert_gt(checked, 4, "found levels to check")


func test_the_sun_terrace_is_proved_exactly_as_before() -> void:
	var level := _sun_terrace()
	var verify := LevelReachability.verify(level)
	assert_true(bool(verify["ok"]))
	assert_eq(int(verify["explored"]), SUN_TERRACE["verify_explored"], "states explored")
	assert_eq(int(verify["states"]), SUN_TERRACE["verify_states"], "states seen")
	var audit := LevelReachability.audit_secrets(level)
	assert_true(bool(audit["ok"]), String(audit["reason"]))
	assert_eq(int(audit["states"]), SUN_TERRACE["audit_states"], "the secret audit's states")
	var survey := LevelReachability.survey(level)
	assert_eq(int(survey["states"]), SUN_TERRACE["survey_states"], "the flood's states")
	assert_eq((survey["reached"] as Dictionary).size(), SUN_TERRACE["survey_reached"])
	assert_eq(Game.checkpoint_cells(level), SUN_TERRACE_CHECKPOINTS, "the same torches proved")


func test_endless_builds_exactly_the_ruins_it_built_before() -> void:
	for ruin: Array in RUINS:
		var result := LevelGenerator.build(int(ruin[0]), 170, float(ruin[1]))
		var level := result["level"] as AsciiLevel
		var report: Dictionary = result["report"]
		assert_eq(int(report["explored"]), int(ruin[2]),
			"ruin %d's proof explored what it did" % int(ruin[0]))
		assert_eq(level.to_text().md5_text(), String(ruin[3]),
			"and the ruin is the same, cell for cell")


func test_the_masked_flood_agrees_with_the_plain_one_where_nothing_changes() -> void:
	var level := _sun_terrace()
	var model := ReachModel.new()
	var spawn: Array[Vector2i] = [level.spawn_point]
	model.latch_on_stand(spawn, &"inert")
	assert_false(model.is_empty(), "a wire that changes no cell, forcing the masked path")

	var goals: Array[Vector2i] = []
	for mark: Dictionary in level.entities:
		if String(mark["kind"]) == "exit":
			goals.append(mark["cell"])
			goals.append(mark["cell"] + Vector2i.UP)
	var solver := LevelReachability.Solver.new(level, model)
	var masked := ReachSearch.survey(solver, level.spawn_point, goals)
	var plain := LevelReachability.survey(level)
	assert_eq(masked["ok"], plain["ok"])
	assert_eq((masked["reached"] as Dictionary).keys(), (plain["reached"] as Dictionary).keys(),
		"the same cells reached")
	assert_eq((masked["stranded"] as Dictionary).size(), 0, "and none stranded")
	var search := ReachSearch.search(solver, level.spawn_point, goals, [] as Array[Vector2i])
	assert_true(bool(search["ok"]), "and the masked search finds the door")
