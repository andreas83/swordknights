extends GutTest
## The Eclipse is the last entry of The Last Light, and defeating him ends the
## campaign through CampaignGame's own ending (scripts/campaign/campaign_game.gd):
## the clear is recorded, the complete screen offers JUMP TO DAWN, and jump
## shows the dawn, with the ending card over it (DawnFrame).
##
## Played in the real catalogue's entry, with the King woken straight into his
## finale -- the phases before it are the business of the other Eclipse tests
## -- and the pilot (tests/eclipse_support.gd) parrying the beam home and
## walking out through dawn's door when it opens. The dawn itself is the
## epilogue's, not this file's: what is held here is only that the finale
## hands over to it.

const EclipseSupport := preload("res://tests/eclipse_support.gd")
const SCENE := "res://scenes/campaign_game.tscn"
const PROGRESS := "user://test_eclipse_finale.cfg"

var _left := 0


func before_each() -> void:
	Campaign.reset()
	_remove(PROGRESS)
	_left = 0


func after_each() -> void:
	Campaign.reset()
	_remove(PROGRESS)


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_the_eclipse_is_the_last_entry_and_built() -> void:
	var last := Campaign.count() - 1
	var entry := Campaign.entry(last)
	assert_eq(String(entry["id"]), "eclipse")
	assert_true(bool(entry["finale"]), "a finale")
	assert_eq(String(entry["file"]), EclipseSupport.LEVEL, "and its arena is its level")
	assert_true(Campaign.is_built(last), "built")


func test_his_fall_records_the_clear_and_jump_goes_to_dawn() -> void:
	var last := Campaign.count() - 1
	Campaign.selected = last
	var campaign := (load(SCENE) as PackedScene).instantiate() as CampaignGame
	campaign.progress_path = PROGRESS
	campaign.leave = func() -> void: _left += 1
	add_child_autofree(campaign)
	await wait_physics_frames(2)
	var game := campaign.game()
	assert_not_null(game, "the arena is played")
	assert_eq(game.level.data.name, "The Eclipse")
	assert_eq(game.advance_label, String(Campaign.ENDING["title"]).to_upper(),
		"the complete screen's jump goes to DAWN")

	var king: Eclipse = null
	for node: Node in game.get_node("Entities").get_children():
		if node is Eclipse:
			king = node as Eclipse
	king.resume(Eclipse.Phase.FINALE)
	game.player.position = Vector2(king.position.x - 96.0, king.floor_y)
	game.player.velocity = Vector2.ZERO
	game.player.input = EclipseSupport.Pilot.new(game)
	await wait_until(func() -> bool: return game.phase == Game.Phase.COMPLETE, 20.0)

	assert_eq(king.state, Eclipse.State.FALL, "he fell to the parry")
	assert_eq(game.phase, Game.Phase.COMPLETE, "and the prince walked out of dawn's door")
	var saved := CampaignProgress.open(PROGRESS)
	assert_true(saved.is_cleared("eclipse"), "the finale's clear is recorded")

	campaign._advance()
	assert_null(campaign.game(), "the arena is gone")
	assert_not_null(campaign.dawn(), "the dawn is shown: the campaign has ended")
	assert_not_null(campaign.ending(), "with the ending's words over it")
	assert_eq(_left, 0, "it has not gone back to the chapters yet")
	await wait_physics_frames(2)
