extends GutTest
## Chapter III, The Aqueduct (levels/chapter_03.txt), held to what its draft
## was held to (docs/campaign.md, "Proving a draft") -- now on the level
## itself, with crumbling stone and the Caracal registered rather than
## stood in for:
##
## the door is reached; the three secrets are never required and never a
## trap; both torches are proved, under the authored level a respawn comes
## back to; every relic is reachable, R2 by the one crumbling stone that must
## hold a body for a moment; the design rule holds for every run; the
## collapse audit finds nothing that falls can strand anyone; the hour is the
## catalogue's; and the masons' line is cut in its secret room. With LONGER
## WARNINGS on, every tell in the chapter is stretched and the proof is the
## same proof. The clear run is tests/unit/test_aqueduct_clear.gd.

const LEVEL := "res://levels/chapter_03.txt"
const TORCHES: Array[Vector2i] = [Vector2i(60, 11), Vector2i(101, 15)]
var _assist_path := UserData.at("user://test_chapter_aqueduct_assist.cfg")

var _level: AsciiLevel


func before_all() -> void:
	_level = AsciiLevel.from_file(LEVEL)


func after_each() -> void:
	Assist.reset()
	if FileAccess.file_exists(_assist_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_assist_path))


func test_it_is_the_catalogues_chapter_three() -> void:
	var entry := Campaign.entry(2)
	assert_eq(entry["file"], LEVEL, "the campaign plays this file as chapter III")
	assert_eq(_level.name, "The Aqueduct")
	assert_eq(TimeOfDay.stop_of(_level), "sunset", "at sunset")
	assert_eq(_level.problems, PackedStringArray(), "it parses clean")
	assert_eq(EntityRegistry.problems_in(_level), PackedStringArray(), "every mark is placed")
	assert_eq(Inscription.text_for(_level.name, 0), PackedStringArray(["WE LEFT", "BY NIGHT"]),
		"where the masons went, in secret A")
	var kinds := {}
	for mark: Dictionary in _level.entities:
		kinds[String(mark["kind"])] = int(kinds.get(String(mark["kind"]), 0)) + 1
	assert_eq(int(kinds.get("caracal", 0)), 4,
		"four cats: the doves', the yard's, the deck's, the last")
	assert_eq(int(kinds.get("relic", 0)), 5, "five relics")
	assert_eq(int(kinds.get("crumbling", 0)), 8, "eight runs of crumbling stone")
	assert_eq(_level.secrets.size(), 3, "three secrets")


func test_the_door_is_reached_and_every_torch_proved() -> void:
	var report := LevelReachability.verify(_level)
	assert_true(bool(report["ok"]), "the door: %s" % report["reason"])
	assert_eq(Game.checkpoint_cells(_level), TORCHES, "both torches, on the whole level")
	assert_false(ReachModel.for_level(_level).is_empty(), "proved with its slabs, not without")


func test_every_relic_can_be_reached() -> void:
	var open := _level.with_secrets({0: true, 1: true, 2: true})
	var count := 0
	for mark: Dictionary in _level.entities:
		if String(mark["kind"]) != "relic":
			continue
		count += 1
		var goals: Array[Vector2i] = [mark["cell"]]
		assert_true(bool(LevelReachability.reaches(open, goals)["ok"]),
			"the relic at %s" % str(mark["cell"]))
	assert_eq(count, 5)
	var r2: Array[Vector2i] = [Vector2i(90, 4)]
	var without := _level.copy()
	for mark: Dictionary in without.entities:
		if String(mark["kind"]) == "crumbling" and mark["cell"] == Vector2i(86, 8):
			mark["params"] = {"fallen": "1"}
	assert_false(bool(LevelReachability.reaches(without, r2)["ok"]),
		"R2 is reached only by standing on its crumbling stone for a moment")


func test_the_secrets_are_never_required_and_never_a_trap() -> void:
	var report := LevelReachability.audit_secrets(_level)
	assert_true(bool(report["ok"]), String(report["reason"]))
	assert_eq(int(report["secrets"]), 3)


func test_nothing_that_falls_strands_anyone() -> void:
	assert_eq(CrumbleAudit.check_runs(_level), PackedStringArray(),
		"runs of at most three, between pairs of stone")
	var report := CrumbleAudit.audit(_level)
	assert_true(bool(report["ok"]), String(report["reason"]))
	assert_eq(int(report["runs"]), 8)
	assert_gt(int(report["subsets"]), 8, "each run alone and all together")


func test_longer_warnings_stretch_every_tell_and_change_no_proof() -> void:
	Assist.load_saved(_assist_path)
	assert_eq(Assist.set_longer_warnings(true), OK)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Game
	game.level_path = LEVEL
	add_child_autofree(game)
	await wait_physics_frames(2)
	var seen := {}
	for node: Node in game.get_node("Entities").get_children():
		if node is Caracal:
			assert_almost_eq((node as Caracal).crouch_time(), 0.45 * Assist.LONGER, 0.0001,
				"a cat's crouch")
			seen["cat"] = true
		elif node is Patrol:
			assert_almost_eq((node as Patrol).windup_time(), 0.45 * Assist.LONGER, 0.0001,
				"the sentinel's raise")
			seen["sentinel"] = true
		elif node is CrumblingStone:
			assert_eq((node as CrumblingStone).fuse_frames(), roundi(27 * Assist.LONGER),
				"a slab's fuse")
			assert_eq((node as CrumblingStone).chain_frames(), roundi(15 * Assist.LONGER),
				"and its chain")
			seen["slab"] = true
	assert_eq(seen.size(), 3, "every kind of tell in the chapter was checked")
	assert_true(bool(LevelReachability.verify(_level)["ok"]), "the proof does not move")
