extends GutTest
## The Last Light played through (scripts/campaign/campaign_game.gd), on a
## campaign of two tiny chapters and a third still being built.
##
## Held here: a clear is recorded the moment it happens -- best time, relics,
## secrets -- and opens the next chapter; jump goes on to the next chapter
## behind the wipe (JUMP TO CONTINUE); past the last chapter built it goes back
## to the chapter select (JUMP TO CHAPTERS); after the last entry of all comes
## the ending card, which holds before anything can dismiss it and then goes
## back too; and sword leaves for the chapter select, not the title screen.

var _progress := UserData.at("user://test_campaign_game.cfg")
var _dir := UserData.at("user://test_campaign_game")
const SCENE := "res://scenes/campaign_game.tscn"

## The door is a few steps right of the spawn.
const ALPHA := """; Alpha



 @    D
########
"""
const BETA := """; Beta



 @    D
########
"""


class ScriptedInput extends PlayerInput:
	var bits := 0

	func poll() -> void:
		apply_bits(bits)


var _left := 0


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	for name: String in ["alpha", "beta"]:
		var file := FileAccess.open(_dir.path_join(name + ".txt"), FileAccess.WRITE)
		file.store_string(ALPHA if name == "alpha" else BETA)
		file.close()
	_remove(_progress)
	_left = 0


func after_each() -> void:
	Campaign.reset()
	_remove(_progress)
	for name: String in ["alpha", "beta"]:
		_remove(_dir.path_join(name + ".txt"))


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _campaign(third_built: bool) -> void:
	var entries: Array[Dictionary] = [
		{"id": "alpha", "numeral": "I", "title": "Alpha", "epigraph": "", "time": "afternoon",
			"file": _dir.path_join("alpha.txt"), "finale": false},
		{"id": "beta", "numeral": "II", "title": "Beta", "epigraph": "", "time": "afternoon",
			"file": _dir.path_join("beta.txt"), "finale": false},
	]
	if third_built:
		Campaign.use_for_test(entries)
		return
	entries.append({"id": "gamma", "numeral": "III", "title": "Gamma", "epigraph": "",
		"time": "dusk", "file": "", "finale": false})
	Campaign.use_for_test(entries)


func _start(at: int) -> CampaignGame:
	Campaign.selected = at
	var campaign := (load(SCENE) as PackedScene).instantiate() as CampaignGame
	campaign.progress_path = _progress
	campaign.leave = func() -> void: _left += 1
	add_child_autofree(campaign)
	await wait_physics_frames(2)
	return campaign


## Walks the current chapter's prince right into its door.
func _finish(campaign: CampaignGame) -> void:
	var input := ScriptedInput.new()
	campaign.game().player.input = input
	input.bits = PlayerInput.BIT_RIGHT
	for _frame: int in 120:
		await wait_physics_frames(1)
		if campaign.game().phase == Game.Phase.COMPLETE:
			break
	input.bits = 0


func test_a_clear_is_recorded_and_jump_goes_on_to_the_next_chapter() -> void:
	_campaign(false)
	var campaign := await _start(0)
	var game := campaign.game()
	assert_eq(game.level.data.name, "Alpha")
	assert_eq(game.quit_scene, CampaignGame.CHAPTER_SELECT, "sword leaves for the chapters")
	assert_eq(game.advance_label, "CONTINUE", "JUMP TO CONTINUE")
	await _finish(campaign)
	assert_eq(game.phase, Game.Phase.COMPLETE, "chapter I cleared")
	var saved := CampaignProgress.open(_progress)
	assert_true(saved.is_cleared("alpha"), "recorded the moment it happened, and saved")
	assert_gt(float(saved.record_of("alpha")["best_time"]), 0.0, "with its time")
	assert_true(saved.is_unlocked(1), "and chapter II is open")

	campaign._advance()
	assert_eq(campaign.index, 1, "jump plays chapter II")
	assert_eq(Campaign.selected, 1)
	await wait_physics_frames(2)
	assert_eq(campaign.game().level.data.name, "Beta")
	assert_eq(campaign.game().advance_label, "CHAPTERS",
		"chapter III is still being built, so chapter II's door leads back")


func test_past_the_last_chapter_built_jump_goes_back_to_the_chapters() -> void:
	_campaign(false)
	var campaign := await _start(1)
	await _finish(campaign)
	campaign._advance()
	assert_eq(_left, 1, "back to the chapter select")
	assert_null(campaign.ending(), "with no ending: the campaign is not over")


func test_after_the_last_entry_comes_the_ending_and_then_the_chapters() -> void:
	_campaign(true)
	var campaign := await _start(1)
	assert_eq(campaign.game().advance_label, "DAWN", "JUMP TO DAWN")
	await _finish(campaign)
	campaign._advance()
	var card := campaign.ending()
	assert_not_null(card, "the ending card")
	assert_null(campaign.game(), "in place of the game")
	assert_false(card.leave(), "a held jump does not skip it")
	assert_eq(_left, 0)
	await wait_seconds(EndingCard.HOLD + 0.1)
	assert_true(card.leave(), "after its hold it goes")
	assert_eq(_left, 1, "back to the chapter select")
	assert_true(CampaignProgress.open(_progress).is_cleared("beta"), "the last clear is kept")
