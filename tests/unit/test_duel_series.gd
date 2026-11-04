extends GutTest
## The duel as a series: first to two rounds, a best of three, inside the
## simulation (scripts/duel/match.gd, SERIES_WINS; docs/duel-match.md, "The
## series"). Reaching a gate wins a round; after the beat the crowd takes the
## winner away, the next round starts on the same strip from the marks, with
## no rematch and no handshake, until a seat has two. The score is snapshot
## state, so a client steps into the next round with the host.
##
## On the placeholder fighter: the rope is what is under test, and a round is
## won here by a scripted kill and a step into the gate's mouth.

var _strip: ZoneStrip


func before_all() -> void:
	_strip = DuelStrips.open(DuelStrips.TUG)


func test_first_to_two_rounds_takes_the_duel() -> void:
	var fight := _match()
	var rounds: Array[int] = []
	var overs: Array[int] = []
	fight.round_started.connect(func(number: int) -> void: rounds.append(number))
	fight.match_over.connect(func(who: int) -> void: overs.append(who))
	assert_eq(fight.series_wins, DuelMatch.SERIES_WINS, "a duel is a series")
	assert_eq(DuelMatch.SERIES_WINS, 2, "of first to two: a best of three")

	_win_round(fight, 0)
	assert_eq(fight.series, PackedInt32Array([1, 0]), "the round is seat one's")
	var frame := fight.frame
	_through_the_beat(fight)
	assert_eq(fight.phase, DuelMatch.Phase.COUNTDOWN, "and the next round counts down")
	assert_gt(fight.frame, frame, "on the same clock: the frame runs on")
	assert_eq(fight.leader_slot(), -1, "nobody leading")
	for slot: int in 2:
		assert_eq(fight.fighter_position(slot), _strip.start_position(slot),
			"seat %d back on its mark" % (slot + 1))
	assert_eq(rounds, [2] as Array[int], "round two is announced")
	assert_eq(overs, [] as Array[int], "and the duel is not over")

	_win_round(fight, 1)
	_through_the_beat(fight)
	assert_eq(fight.series, PackedInt32Array([1, 1]), "one round each")
	assert_eq(rounds, [2, 3] as Array[int], "round three")

	_win_round(fight, 0)
	_through_the_beat(fight)
	assert_eq(fight.phase, DuelMatch.Phase.MATCH_OVER, "two rounds take it")
	assert_eq(fight.winner, 0, "seat one's duel")
	assert_eq(fight.series, PackedInt32Array([2, 1]), "two to one")
	assert_eq(overs, [0] as Array[int], "said once")


## The same for seat two, two rounds straight: no seat is the series' default.
func test_either_seat_takes_it_the_same_way() -> void:
	var fight := _match()
	_win_round(fight, 1)
	_through_the_beat(fight)
	_win_round(fight, 1)
	_through_the_beat(fight)
	assert_eq(fight.phase, DuelMatch.Phase.MATCH_OVER, "over at two")
	assert_eq(fight.winner, 1, "seat two's")
	assert_eq(fight.series, PackedInt32Array([0, 2]), "two to nil")


## The score is in the snapshot and the checksum, and a rewind across the turn
## from one round to the next replays it byte for byte.
func test_the_series_is_snapshot_state() -> void:
	var fight := _match()
	_win_round(fight, 0)
	var snapshot := fight.write_state()
	var sum := fight.checksum()
	fight.series[1] += 1
	assert_ne(fight.checksum(), sum, "the checksum covers the score")
	fight.series[1] -= 1
	var states: Array[PackedByteArray] = []
	for _frame: int in roundi(DuelMatch.CONSUMED_TIME / DuelMatch.DT) + 30:
		fight.step(0, 0)
		states.append(fight.write_state())
	assert_eq(fight.phase, DuelMatch.Phase.COUNTDOWN, "into round two")
	assert_true(fight.read_state(snapshot), "the snapshot reads back")
	assert_eq(fight.series, PackedInt32Array([1, 0]), "with the score in it")
	var parted := -1
	for i: int in states.size():
		fight.step(0, 0)
		if fight.write_state() != states[i]:
			parted = i
			break
	assert_eq(parted, -1, "and replays the turn into the next round exactly")


## A rematch is a new duel; and a test that measures one round sets one win.
func test_a_rematch_starts_a_new_series_and_one_round_can_be_asked_for() -> void:
	var fight := _match()
	_win_round(fight, 0)
	_through_the_beat(fight)
	fight.reset_match()
	assert_eq(fight.series, PackedInt32Array([0, 0]), "a rematch is a new series")

	fight.series_wins = 1
	_win_round(fight, 1)
	_through_the_beat(fight)
	assert_eq(fight.phase, DuelMatch.Phase.MATCH_OVER, "one round, when one is asked for")


## --- staging ----------------------------------------------------------------

func _match() -> DuelMatch:
	var fight := DuelMatch.new()
	add_child_autofree(fight)
	assert_true(fight.build(_strip), "the match builds")
	return fight


## Through the countdown, the other seat killed, and `seat` stepped into its
## gate's mouth: the round is won on the next frame.
func _win_round(fight: DuelMatch, seat: int) -> void:
	while fight.phase == DuelMatch.Phase.COUNTDOWN:
		fight.step(0, 0)
	fight.seats[1 - seat].kill(seat)
	var x := _strip.goal_x(seat) - ZoneStrip.goal_direction(seat) * 8.0
	var row := _strip.ground_row(floori(x / ZoneStrip.TILE))
	fight.seats[seat].set_position(Vector2(x, float(row * ZoneStrip.TILE)))
	fight.step(0, 0)
	assert_eq(fight.phase, DuelMatch.Phase.CONSUMED, "seat %d reached its gate" % (seat + 1))


func _through_the_beat(fight: DuelMatch) -> void:
	while fight.phase == DuelMatch.Phase.CONSUMED:
		fight.step(0, 0)
