extends GutTest
## The rope's fairness: a double kill that favours neither seat, and a comeback
## for the fighter the runner got past (scripts/duel/match.gd,
## match_placement.gd; docs/duel-match.md, "Initiative and the window" and
## "Passed").
##
## Before: DuelCombat applies a double kill as two deaths, seat two's first,
## and each death handed the initiative to its killer -- so every double kill
## left seat two leading, and seat two then came back on its start mark, a zone
## or two from the window. And a defender the runner had passed was dragged
## along by the trailing edge with nothing to do: at EASY the first kill won
## eleven matches in twelve.
##
## On the real fighter, in a match, inside a physics frame (await one, then run).

const Support := preload("res://tests/duel_support.gd")

const L := PlayerInput.BIT_LEFT
const R := PlayerInput.BIT_RIGHT
const U := PlayerInput.BIT_UP
const D := PlayerInput.BIT_DOWN
const A := PlayerInput.BIT_ATTACK

var _strip: ZoneStrip


func before_all() -> void:
	_strip = Support.load_strip()


## Neutral, seat one leading and seat two leading; and each with seat one on
## the left and on the right. Whoever held the initiative holds it after both
## fall on one frame, and both come back in the window as it was: facing each
## other, the leader on the side away from its gate.
func test_a_double_kill_leaves_the_initiative_where_it_was() -> void:
	await wait_physics_frames(1)
	for leader: int in [-1, 0, 1]:
		for left: int in [0, 1]:
			var fight := _fighting()
			var label := "leader %d, seat %d on the left" % [leader, left]
			_lead(fight, leader)
			var scroll := fight.scroll
			var right := 1 - left
			_face_off(fight, left, 20.0)
			var bits := PackedInt32Array([0, 0])
			bits[left] = U
			bits[right] = D
			_run(fight, 3, bits)
			bits[left] = U | A
			bits[right] = D | A
			_run(fight, 1, bits)
			assert_false(fight.is_fighter_alive(0) or fight.is_fighter_alive(1),
				"%s: both fell on one frame" % label)
			assert_eq(fight.leader_slot(), leader, "%s: the initiative did not move" % label)
			_run(fight, roundi(DuelMatch.RESPAWN_DELAY / DuelMatch.DT) + 2, PackedInt32Array([0, 0]))
			assert_true(fight.is_fighter_alive(0) and fight.is_fighter_alive(1),
				"%s: both are back" % label)
			# The leader comes back where open ground is, and the window follows a
			# leader standing off its middle; what it must not do is jump zones.
			assert_almost_eq(fight.scroll, scroll, _strip.zone_width() * 0.25,
				"%s: the window did not jump" % label)
			var window := fight.window_rect()
			for slot: int in 2:
				var x := fight.fighter_position(slot).x
				assert_between(x, window.position.x, window.end.x,
					"%s: seat %d came back in the window" % [label, slot])
			var west := 0 if fight.fighter_position(0).x < fight.fighter_position(1).x else 1
			assert_eq(_fighter(fight, west).facing, 1, "%s: facing each other" % label)
			assert_eq(_fighter(fight, 1 - west).facing, -1, "%s: facing each other" % label)
			if leader < 0:
				for slot: int in 2:
					assert_almost_eq(fight.fighter_position(slot), _strip.start_position(slot),
						Vector2(0.01, 0.01), "%s: in neutral, back on the marks" % label)
			else:
				var way := float(ZoneStrip.goal_direction(leader))
				var ahead := fight.fighter_position(1 - leader).x - fight.fighter_position(leader).x
				assert_gt(ahead * way, 0.0,
					"%s: the other stands between the leader and its gate" % label)
			fight.free()


## One death still hands the initiative to the killer, as the spec says.
func test_a_single_kill_still_hands_over_the_initiative() -> void:
	await wait_physics_frames(1)
	for killer: int in [0, 1]:
		var fight := _fighting()
		_face_off(fight, killer, 20.0)
		var bits := PackedInt32Array([0, 0])
		bits[1 - killer] = U
		_run(fight, 3, bits)
		bits[killer] = A
		_run(fight, 1, bits)
		assert_false(fight.is_fighter_alive(1 - killer), "seat %d killed" % killer)
		assert_eq(fight.leader_slot(), killer, "and seat %d leads" % killer)
		fight.free()


## The runner gets past and runs; the one passed stands still. Held against the
## trailing edge for PASSED_HOLD frames it is put back ahead of the runner,
## facing them, armed -- not killed, not scored, and the initiative unmoved.
func test_a_fighter_held_at_the_trailing_edge_is_put_back_ahead() -> void:
	await wait_physics_frames(1)
	for leader: int in [0, 1]:
		var fight := _fighting()
		var run := _passing(fight, leader)
		var passed := -1
		var first_held := -1
		for frame: int in 200:
			fight.step(run[0], run[1])
			if first_held < 0 and fight.held[1 - leader] > 0:
				first_held = frame
			for event: Dictionary in fight.events:
				if String(event["kind"]) == "respawned" and bool(event.get("passed", false)):
					passed = frame
			if passed >= 0:
				break
		var label := "leader %d" % leader
		assert_gte(passed, 0, "%s: the one passed was put back" % label)
		assert_eq(passed - first_held + 1, DuelMatch.PASSED_HOLD,
			"%s: after PASSED_HOLD frames at the edge" % label)
		var way := float(ZoneStrip.goal_direction(leader))
		var runner := fight.fighter_position(leader).x
		var back := fight.fighter_position(1 - leader).x
		assert_gt((back - runner) * way, 0.0, "%s: ahead of the runner" % label)
		assert_eq(_fighter(fight, 1 - leader).facing, -int(way), "%s: facing them" % label)
		assert_true(_fighter(fight, 1 - leader).is_armed(), "%s: armed" % label)
		assert_eq(fight.kills, PackedInt32Array([0, 0]), "%s: nobody scored" % label)
		assert_eq(fight.leader_slot(), leader, "%s: the initiative did not move" % label)
		assert_eq(fight.held[1 - leader], 0, "%s: the count starts again" % label)
		fight.free()


## A chaser who keeps up with the runner is never at the trailing edge, and is
## never moved: only being left behind is.
func test_a_chaser_who_keeps_up_is_left_alone() -> void:
	await wait_physics_frames(1)
	var fight := _fighting()
	_lead(fight, 1)
	var centre := fight.scroll + _strip.zone_width() * 0.5
	_place(fight, 1, centre, -1)
	_place(fight, 0, centre - 90.0, 1)
	for _frame: int in 90:
		fight.step(R, R)
		for event: Dictionary in fight.events:
			assert_false(bool(event.get("passed", false)), "the chaser was not moved")
	assert_eq(fight.held[0], 0, "and never held")
	fight.free()


## The count is simulation: in the snapshot and the checksum, and a rewind to
## the middle of it re-places on the same frame at the same spot.
func test_the_trailing_count_is_snapshot_state() -> void:
	await wait_physics_frames(1)
	var fight := _fighting()
	var run := _passing(fight, 1)
	while fight.held[0] < DuelMatch.PASSED_HOLD / 2:
		fight.step(run[0], run[1])
	var snapshot := fight.write_state()
	var sum := fight.checksum()
	fight.held[0] += 1
	assert_ne(fight.checksum(), sum, "the checksum covers the count")
	fight.held[0] -= 1
	var first := _until_passed(fight, run)
	assert_true(fight.read_state(snapshot), "the snapshot reads back")
	assert_eq(fight.held[0], DuelMatch.PASSED_HOLD / 2, "with the count in it")
	var again := _until_passed(fight, run)
	assert_eq(again, first, "the replay re-places on the same frame, at the same spot")
	fight.free()


## --- staging ----------------------------------------------------------------

## A match on the real fighter, through the countdown.
func _fighting() -> DuelMatch:
	var fight := Support.spawn_match(get_tree().root, _strip)
	while fight.phase != DuelMatch.Phase.FIGHTING:
		fight.step(0, 0)
	return fight


## Gives `leader` the initiative (or none) and moves the window a zone toward
## its gate, as a run there would have.
func _lead(fight: DuelMatch, leader: int) -> void:
	@warning_ignore("integer_division")
	var zone := _strip.zone_count() / 2
	if leader >= 0:
		fight.initiative = DuelMatch.Initiative.PLAYER_1 if leader == 0 \
			else DuelMatch.Initiative.PLAYER_2
		zone += ZoneStrip.goal_direction(leader)
	fight.scroll = _strip.zone_left(zone)
	fight.zone_index = zone


## `left` on open ground in the middle of the window, the other `gap` east of
## it; facing each other.
func _face_off(fight: DuelMatch, left: int, gap: float) -> void:
	var centre := fight.scroll + _strip.zone_width() * 0.5
	var spot: Vector2 = _strip.find_open_ground(centre, centre)["position"]
	_place(fight, left, spot.x, 1)
	_place(fight, 1 - left, spot.x + gap, -1)


## The runner in the middle of the window, running for its gate; the other
## near the trailing edge behind it, standing.
func _passing(fight: DuelMatch, leader: int) -> PackedInt32Array:
	_lead(fight, leader)
	var way := ZoneStrip.goal_direction(leader)
	var centre := fight.scroll + _strip.zone_width() * 0.5
	_place(fight, leader, centre, way)
	_place(fight, 1 - leader, centre - way * 200.0, way)
	var bits := PackedInt32Array([0, 0])
	bits[leader] = R if way > 0 else L
	return bits


func _place(fight: DuelMatch, slot: int, x: float, facing: int) -> void:
	var spot: Vector2 = _strip.find_open_ground(x, x)["position"]
	fight.seats[slot].respawn_at(Vector2(x, spot.y), facing)


func _run(fight: DuelMatch, frames: int, bits: PackedInt32Array) -> void:
	for _frame: int in frames:
		fight.step(bits[0], bits[1])


func _until_passed(fight: DuelMatch, run: PackedInt32Array) -> Array:
	for frame: int in 200:
		fight.step(run[0], run[1])
		for event: Dictionary in fight.events:
			if bool(event.get("passed", false)):
				return [frame, fight.fighter_position(0), fight.checksum()]
	return []


func _fighter(fight: DuelMatch, slot: int) -> Fighter:
	return fight.seats[slot].node as Fighter
