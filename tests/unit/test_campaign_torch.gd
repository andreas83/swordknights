extends GutTest
## The run in progress outlives the session: the last torch reached in a
## chapter is saved, and CONTINUE picks the chapter up there
## (scripts/campaign/campaign_progress.gd, "the run in progress").
##
## Progress used to be saved only on a clear, and CONTINUE started the
## chapter over. On a phone a session ends when a call comes in, not when a
## chapter does, so a chapter of the Aqueduct's length was played from its
## first stone every time the app was left. Held here: a torch is saved the
## moment it is reached, with the clock and the wires latched then; CONTINUE
## resumes at it; the chapter's own row, RESTART CHAPTER and a clear each
## forget it; a saved cell the level no longer proves is refused rather than
## trusted; and the file reads forgivingly, as the rest of it does.

var _progress := UserData.at("user://test_campaign_torch.cfg")
var _dir := UserData.at("user://test_campaign_torch")
const SCENE := "res://scenes/campaign_game.tscn"
const CHAPTERS := "res://scenes/chapter_select.tscn"

## Spawn at column 1, a torch at column 6, the door at column 16.
const ALPHA := """;! channel 1 latch
; Alpha



 @    t         D
##################
"""
const TORCH := Vector2i(6, 3)


class ScriptedInput extends PlayerInput:
	var bits := 0

	func poll() -> void:
		apply_bits(bits)


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	var file := FileAccess.open(_dir.path_join("alpha.txt"), FileAccess.WRITE)
	file.store_string(ALPHA)
	file.close()
	_remove(_progress)
	var entries: Array[Dictionary] = [
		{"id": "alpha", "numeral": "I", "title": "Alpha", "epigraph": "", "time": "afternoon",
			"file": _dir.path_join("alpha.txt"), "finale": false},
		{"id": "beta", "numeral": "II", "title": "Beta", "epigraph": "", "time": "dusk",
			"file": "", "finale": false},
	]
	Campaign.use_for_test(entries)


func after_each() -> void:
	Input.action_release("move_right")
	Campaign.reset()
	_remove(_progress)
	_remove(_dir.path_join("alpha.txt"))


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## --- the file -----------------------------------------------------------------

func test_a_torch_survives_a_round_trip_and_a_clear_forgets_it() -> void:
	var progress := CampaignProgress.open(_progress)
	assert_true(progress.torch_of(0).is_empty(), "a fresh campaign has no run to pick up")
	progress.set_torch(0, TORCH, PackedStringArray(["1"]), 42.5)
	assert_eq(progress.save(), OK)
	var again := CampaignProgress.open(_progress)
	var torch := again.torch_of(0)
	assert_eq(torch.get("cell"), TORCH, "the cell")
	assert_eq(torch.get("latched"), PackedStringArray(["1"]), "the wires latched then")
	assert_almost_eq(float(torch.get("time", 0.0)), 42.5, 0.001, "and the clock")
	assert_false(again.is_cleared("alpha"), "a torch is not a clear")

	again.record_clear(0, 80.0, 0, 0, 0, 0)
	assert_true(again.torch_of(0).is_empty(), "out by the door, there is no run to pick up")
	assert_false(again.clear_torch(0), "and nothing left to forget")


func test_a_broken_torch_costs_the_torch_and_nothing_beside_it() -> void:
	var file := FileAccess.open(_progress, FileAccess.WRITE)
	file.store_string("[campaign]\nunlocked=1\n\n[alpha]\ncleared=true\nbest_time=50.0\n"
		+ "torch=\"6,4\"\ntorch_time=12.0\n")
	file.close()
	var progress := CampaignProgress.open(_progress)
	assert_true(progress.torch_of(0).is_empty(), "a torch that is not a cell is no torch")
	assert_true(progress.is_cleared("alpha"), "and the clear beside it stands")


## --- the campaign -------------------------------------------------------------

func test_a_torch_is_saved_when_reached_and_continue_resumes_there() -> void:
	var campaign := await _start(false)
	await _walk_past_the_torch(campaign.game())
	var saved := CampaignProgress.open(_progress).torch_of(0)
	assert_eq(saved.get("cell"), TORCH, "saved the moment it was reached")
	assert_gt(float(saved.get("time", 0.0)), 0.0, "with the clock then")
	var clock := float(saved["time"])
	campaign.free()

	var resumed := await _start(true)
	var game := resumed.game()
	var torch_x := game.level.entity_world_position(TORCH).x
	assert_almost_eq(game.player.global_position.x, torch_x, 1.0, "CONTINUE starts at the torch")
	assert_almost_eq(game.elapsed, clock, 0.5, "with the clock it had there, so a best "
		+ "time from a resumed run is the whole run's")
	assert_false(Campaign.resume, "spent by the chapter it opened")


func test_the_chapters_own_row_starts_over_and_forgets_the_torch() -> void:
	_save_torch(TORCH, 30.0)
	var campaign := await _start(false)
	var game := campaign.game()
	assert_almost_eq(game.player.global_position.x,
		game.level.spawn_world_position().x, 1.0, "from the chapter's row: the start")
	assert_lt(game.elapsed, 1.0, "with a clock from nothing")
	assert_true(CampaignProgress.open(_progress).torch_of(0).is_empty(),
		"and the old run's torch is gone: this is a new run")


func test_restart_chapter_forgets_the_torch() -> void:
	_save_torch(TORCH, 30.0)
	var campaign := await _start(true)
	campaign.game()._restart()
	assert_true(CampaignProgress.open(_progress).torch_of(0).is_empty(),
		"RESTART CHAPTER is a new run")


func test_a_clear_forgets_the_torch() -> void:
	var campaign := await _start(false)
	var input := ScriptedInput.new()
	campaign.game().player.input = input
	input.bits = PlayerInput.BIT_RIGHT
	for _frame: int in 240:
		await wait_physics_frames(1)
		if campaign.game().phase == Game.Phase.COMPLETE:
			break
	assert_eq(campaign.game().phase, Game.Phase.COMPLETE, "the door was reached")
	var progress := CampaignProgress.open(_progress)
	assert_true(progress.is_cleared("alpha"))
	assert_true(progress.torch_of(0).is_empty(), "past the torch and out: nothing to resume")


func test_a_torch_the_level_no_longer_proves_is_refused() -> void:
	_save_torch(Vector2i(12, 3), 30.0)
	var campaign := await _start(true)
	var game := campaign.game()
	assert_almost_eq(game.player.global_position.x,
		game.level.spawn_world_position().x, 1.0, "a cell with no torch on it is not trusted")
	assert_true(CampaignProgress.open(_progress).torch_of(0).is_empty(), "and is forgotten")


func test_resuming_keeps_only_the_wires_the_level_declares() -> void:
	var campaign := await _start(false)
	var game := campaign.game()
	assert_true(game.resume_at(TORCH, PackedStringArray(["1", "9"]), 12.0))
	assert_eq(game._bus.latched(), PackedStringArray(["1"]),
		"the level's latch held, and a wire it does not have left out")
	assert_false(game.resume_at(Vector2i(2, 3), PackedStringArray(), 0.0),
		"and a cell that is no proved torch refused")


## --- the chapter select -------------------------------------------------------

func test_continue_resumes_and_says_so_and_a_chapter_row_does_not() -> void:
	_save_torch(TORCH, 30.0)
	var page := (load(CHAPTERS) as PackedScene).instantiate() as ChapterSelect
	page.store_path = _progress
	page.play = func(_at: int) -> void: pass
	add_child_autofree(page)
	await wait_process_frames(2)
	assert_eq(page.index(), 0, "on CONTINUE")
	assert_eq(page.caption(0)[1][0], "FROM THE LAST TORCH REACHED",
		"which says where it carries on from")
	page.confirm()
	assert_true(Campaign.resume, "CONTINUE resumes")
	page.move(1)
	page.confirm()
	assert_false(Campaign.resume, "the chapter's own row starts it")


## --- helpers ------------------------------------------------------------------

func _start(resuming: bool) -> CampaignGame:
	Campaign.selected = 0
	Campaign.resume = resuming
	var campaign := (load(SCENE) as PackedScene).instantiate() as CampaignGame
	campaign.progress_path = _progress
	campaign.leave = func() -> void: pass
	add_child_autofree(campaign)
	await wait_physics_frames(3)
	return campaign


func _save_torch(cell: Vector2i, seconds: float) -> void:
	var progress := CampaignProgress.open(_progress)
	progress.set_torch(0, cell, PackedStringArray(), seconds)
	progress.save()


func _walk_past_the_torch(game: Game) -> void:
	var input := ScriptedInput.new()
	game.player.input = input
	var past := game.level.entity_world_position(TORCH).x + 6.0
	input.bits = PlayerInput.BIT_RIGHT
	for _frame: int in 240:
		await wait_physics_frames(1)
		if game.player.global_position.x > past:
			break
	input.bits = 0
	await wait_physics_frames(4)
