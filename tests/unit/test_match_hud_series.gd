extends GutTest
## The series score on the result plate (scripts/duel/match_hud.gd, THE SERIES):
## YOU 2 - 1 CPU against the computer, ONE 2 - 1 TWO on one keyboard, read
## from the match's own `series` -- simulation state, so on a client it is the
## host's -- and never counted by the HUD itself.
##
## On the placeholder fighter: nothing here steps a body.

var _fight: DuelMatch


func before_each() -> void:
	_fight = DuelMatch.new()
	add_child_autofree(_fight)
	assert_true(_fight.build(DuelStrips.open(DuelStrips.TUG)), "the match builds")


func test_one_keyboard_reads_ones_and_twos() -> void:
	var hud := _hud()
	assert_eq(hud.series_text(), "ONE 0 - 0 TWO", "nothing yet")
	_fight.series = PackedInt32Array([2, 1])
	assert_eq(hud.series_text(), "ONE 2 - 1 TWO", "the match's score, in strip order")


func test_against_the_computer_it_is_you_and_cpu() -> void:
	var hud := _hud([PackedStringArray(["YOU"]), PackedStringArray(["CPU", "HARD"])], 0)
	_fight.series = PackedInt32Array([1, 0])
	assert_eq(hud.series_text(), "YOU 1 - 0 CPU")


## The HUD keeps no count of its own: a match_over it hears changes nothing,
## and a rematch's empty series is what it shows.
func test_it_is_the_match_score_and_nothing_else() -> void:
	var hud := _hud()
	_fight.series = PackedInt32Array([1, 1])
	_fight.match_over.emit(0)
	assert_eq(hud.series_text(), "ONE 1 - 1 TWO", "not counted twice")
	_fight.reset_match()
	assert_eq(hud.series_text(), "ONE 0 - 0 TWO", "a rematch starts at nothing")


func _hud(tags: Array[PackedStringArray] = [], slot: int = -1) -> MatchHud:
	var hud := MatchHud.new()
	add_child_autofree(hud)
	hud.seat_tags = tags
	hud.your_slot = slot
	hud.fight = _fight
	return hud
