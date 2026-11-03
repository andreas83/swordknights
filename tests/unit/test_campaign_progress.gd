extends GutTest
## What the player has done in The Last Light (scripts/campaign/campaign_progress.gd).
##
## Held here: a first launch, and a file that is missing or broken, is a fresh
## campaign; reading is forgiving to the field, so one bad value costs that
## value and nothing beside it, and what cannot be true is mended; a clear
## keeps the best of each -- time, relics, secrets -- and opens the next
## entry; CONTINUE goes to the first playable entry not yet cleared, and
## never to one still being built; and all of it survives a round trip.

const PATH := "user://test_campaign_progress.cfg"

## Three chapters, the last not built.
var _entries: Array[Dictionary] = [
	{"id": "alpha", "numeral": "I", "title": "Alpha", "epigraph": "", "time": "afternoon",
		"file": "res://levels/level_01.txt", "finale": false},
	{"id": "beta", "numeral": "II", "title": "Beta", "epigraph": "", "time": "golden",
		"file": "res://levels/level_01.txt", "finale": false},
	{"id": "gamma", "numeral": "III", "title": "Gamma", "epigraph": "", "time": "dusk",
		"file": "", "finale": false},
]


func before_each() -> void:
	Campaign.use_for_test(_entries)
	_remove()


func after_each() -> void:
	Campaign.reset()
	_remove()


func _remove() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func _write(text: String) -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_no_file_is_a_fresh_campaign() -> void:
	var progress := CampaignProgress.open(PATH)
	assert_eq(progress.unlocked(), 1, "chapter I is open")
	assert_false(progress.is_unlocked(1), "and nothing after it")
	assert_false(progress.is_cleared("alpha"))
	assert_eq(progress.record_of("alpha")["best_time"], CampaignProgress.NO_TIME)
	assert_eq(progress.continue_index(), 0, "CONTINUE begins at the beginning")


func test_a_broken_file_is_a_fresh_campaign() -> void:
	_write("this is [not a config file\n=== at all")
	var progress := CampaignProgress.new()
	progress.path = PATH
	assert_false(progress.load_from_disk(), "not believed")
	# ConfigFile logs the parse error itself; the progress adds none of its own.
	assert_engine_error("ConfigFile parse error", "the engine noticed the corruption")
	assert_eq(progress.unlocked(), 1)
	assert_false(progress.is_cleared("alpha"))


func test_a_bad_field_costs_that_field_and_nothing_beside_it() -> void:
	_write("""[campaign]
unlocked="lots"

[alpha]
cleared=true
best_time="fast"
relics=4
relics_total=6
secrets=9
secrets_total=3

[beta]
cleared="yes"
best_time=-20.0
relics=-2
relics_total=5
""")
	var progress := CampaignProgress.open(PATH)
	var alpha := progress.record_of("alpha")
	assert_true(bool(alpha["cleared"]), "alpha's clear is kept")
	assert_eq(alpha["best_time"], CampaignProgress.NO_TIME, "its unreadable time is lost")
	assert_eq([alpha["relics"], alpha["relics_total"]], [4, 6], "its relics are not")
	assert_eq(alpha["secrets"], 3, "nine of three secrets is three")
	var beta := progress.record_of("beta")
	assert_false(bool(beta["cleared"]), "a clear that is not a bool is no clear")
	assert_eq(beta["best_time"], CampaignProgress.NO_TIME, "a negative time is no time")
	assert_eq(beta["relics"], 0, "and a negative count is none")
	assert_eq(progress.unlocked(), 2,
		"an unreadable count of open chapters is mended from the clears")


func test_a_clear_keeps_the_best_of_each_and_opens_the_next() -> void:
	var progress := CampaignProgress.open(PATH)
	var first := progress.record_clear(0, 75.0, 2, 6, 0, 3)
	assert_eq(first, {"first": true, "time": true, "relics": true, "secrets": false})
	assert_true(progress.is_unlocked(1), "the next chapter opens")
	var slower := progress.record_clear(0, 90.0, 5, 6, 1, 3)
	assert_eq(slower, {"first": false, "time": false, "relics": true, "secrets": true})
	var worse := progress.record_clear(0, 60.5, 1, 6, 0, 3)
	assert_true(bool(worse["time"]), "a faster clear is a new best time")
	var alpha := progress.record_of("alpha")
	assert_eq(alpha["best_time"], 60.5, "the shortest time")
	assert_eq(alpha["relics"], 5, "the most relics, though the fastest run found one")
	assert_eq(alpha["secrets"], 1, "and the most secrets")


func test_continue_goes_to_the_first_playable_uncleared_entry() -> void:
	var progress := CampaignProgress.open(PATH)
	assert_eq(progress.continue_index(), 0)
	progress.record_clear(0, 70.0, 0, 0, 0, 0)
	assert_eq(progress.continue_index(), 1, "on to chapter II")
	progress.record_clear(1, 70.0, 0, 0, 0, 0)
	assert_true(progress.is_unlocked(2), "chapter III is open")
	assert_false(progress.is_playable(2), "but still being built")
	assert_eq(progress.continue_index(), 1,
		"so CONTINUE stays on the last chapter that can be played")


func test_progress_survives_a_round_trip() -> void:
	var progress := CampaignProgress.open(PATH)
	progress.record_clear(0, 61.25, 3, 6, 2, 3)
	assert_eq(progress.save(), OK)
	var again := CampaignProgress.open(PATH)
	assert_eq(again.record_of("alpha"), progress.record_of("alpha"))
	assert_eq(again.unlocked(), 2)
	assert_eq(again.continue_index(), 1)
