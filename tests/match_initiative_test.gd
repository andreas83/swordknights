extends SceneTree
## The initiative engine: who leads, which way the world scrolls, and the gate.
##
##     godot --headless --script tests/match_initiative_test.gd
##
## This is the spine of the mode, so it is tested against the specification's
## own pseudocode rather than against the implementation's shape:
##
##     onPlayerKilled(killer, victim) { currentLeader = killer.id ... }
##     canScrollToZone(direction) {
##       if (currentLeader === PLAYER_1 && direction === -1) return true;
##       if (currentLeader === PLAYER_2 && direction === 1) return true;
##       return false;
##     }
##
## SEVEN CLAIMS
## 1. A match opens neutral, in the middle zone, with the world locked.
## 2. canScrollToZone is exactly the table above.
## 3. The killer takes initiative, and a hazard gives it to the survivor.
## 4. The leader running at their goal scrolls the world and advances the zone.
## 5. The leader running the WRONG way does not scroll it back. This is the one
##    that matters: the ratchet is the whole mode.
## 6. Initiative flips on the counter-kill and the rope then only moves the
##    other way.
## 7. The leader reaching their gate is consumed, the match ends on them, and
##    the reset puts the rope back in the middle.
##
## Everything runs inside one physics frame. A burst of steps is byte-identical
## to one step per frame (tests/duel_determinism_test.gd asserts exactly that),
## and the match has to be stepped from a physics frame because a fighter is a
## body in the physics space.

const Support := preload("res://tests/duel_support.gd")
const MANIFEST := "res://levels/duel_zones.txt"
## Where the window starts: the left edge of the middle of five zones. Derived,
## because it was written as 1280 and a zone-width change made it silently
## wrong -- `pulled < 1280` would have passed with no rope taken at all.
const MIDDLE_LEFT := 2.0 * ZoneStrip.SCREEN_WIDTH

const LEFT := PlayerInput.BIT_LEFT
const RIGHT := PlayerInput.BIT_RIGHT
const JUMP := PlayerInput.BIT_JUMP

var _s := Support.new()
var _strip: ZoneStrip
var _warm := 0


func _initialize() -> void:
	_strip = ZoneStrip.from_manifest(MANIFEST)


func _physics_process(_delta: float) -> bool:
	_warm += 1
	if _warm < 3:
		return false
	if not _s.check(_strip != null, "the strip loads"):
		quit(_s.report("match_initiative"))
		return true

	_opens_neutral()
	_the_scroll_table()
	_the_killer_takes_it()
	_a_hazard_goes_to_the_survivor()
	_the_leader_drags_the_world()
	_the_wrong_way_does_not_scroll()
	_the_rope_goes_both_ways()
	_the_gate()

	quit(_s.report("match_initiative"))
	return true


## --- scaffolding -----------------------------------------------------------

func _open_match() -> DuelMatch:
	var match_node := DuelMatch.new()
	match_node.name = "Match"
	root.add_child(match_node)
	if not match_node.build(_strip):
		_s.check(false, "the match builds")
	return match_node


func _fight(match_node: DuelMatch) -> void:
	# Step past the countdown; nobody can move or die until it is done.
	var guard := 0
	while match_node.phase == DuelMatch.Phase.COUNTDOWN and guard < 600:
		match_node.step(0, 0)
		guard += 1


func _hold(match_node: DuelMatch, frames: int, bits_a: int, bits_b: int) -> void:
	for i: int in frames:
		match_node.step(bits_a, bits_b)


## Runs one seat in a direction the way a player would: holding it, and jumping
## at a gap or a step rather than on a timer. The lane has stepped terraces in
## it and one four-tile cistern, so a drive that never jumps simply stands
## against the first obstacle for the rest of the test.
func _run_seat(match_node: DuelMatch, frames: int, slot: int, direction: int) -> void:
	var held := LEFT if direction < 0 else RIGHT
	for i: int in frames:
		var bits := held
		if _should_jump(match_node, slot, direction) and i % 6 < 2:
			bits |= JUMP
		match_node.step(bits if slot == 0 else 0, bits if slot == 1 else 0)


func _should_jump(match_node: DuelMatch, slot: int, direction: int) -> bool:
	var at := match_node.fighter_position(slot)
	var here := _strip.ground_row(floori(at.x / ZoneStrip.TILE))
	var ahead := _strip.ground_row(floori(at.x / ZoneStrip.TILE) + direction)
	if ahead < 0:
		return true # a gap: the cistern
	if here > 0 and ahead < here:
		return true # any rise: the stepped terraces
	return false


## A scripted kill. Combat belongs to the fighter, so the match layer is tested
## by telling a fighter it died rather than by staging a sword fight.
func _slay(match_node: DuelMatch, victim: int, killer: int) -> void:
	match_node.seats[victim].node.call("slay", killer)
	match_node.step(0, 0)


## --- 1 --------------------------------------------------------------------

func _opens_neutral() -> void:
	var fight := _open_match()
	_s.equal(fight.initiative, DuelMatch.Initiative.NEUTRAL, "a match opens neutral")
	_s.equal(fight.leader_slot(), -1, "nobody is leading")
	_s.equal(fight.zone_index, 2, "the rope starts in the middle zone")
	_s.equal(fight.scroll, MIDDLE_LEFT, "the window starts on the middle zone")
	_s.equal(fight.phase, DuelMatch.Phase.COUNTDOWN, "and it starts on the marks")
	_s.equal(fight.winner, DuelRules.DRAW, "with no winner")
	_s.equal(fight.kills[0], 0, "and no kills")

	# Neutral: the court is closed. Neither of them can move the world, however
	# hard they run, and both are held inside the zone.
	_fight(fight)
	var before := fight.scroll
	_hold(fight, 240, LEFT, LEFT)
	_s.equal(fight.scroll, before, "neutral: running west does not scroll")
	_hold(fight, 240, RIGHT, RIGHT)
	_s.equal(fight.scroll, before, "neutral: running east does not scroll either")

	var window := fight.window_rect()
	for slot: int in 2:
		var x := fight.fighter_position(slot).x
		_s.check(
			x >= window.position.x and x <= window.end.x,
			"neutral: seat %d is held inside the zone (%.1f)" % [slot, x]
		)
	fight.free()


## --- 2 --------------------------------------------------------------------

func _the_scroll_table() -> void:
	var fight := _open_match()
	fight.initiative = DuelMatch.Initiative.NEUTRAL
	_s.check(not fight.can_scroll(-1), "neutral cannot scroll west")
	_s.check(not fight.can_scroll(1), "neutral cannot scroll east")

	fight.initiative = DuelMatch.Initiative.PLAYER_1
	_s.check(fight.can_scroll(-1), "player one scrolls west")
	_s.check(not fight.can_scroll(1), "player one does not scroll east")
	_s.equal(fight.leader_direction(), -1, "player one pushes west")

	fight.initiative = DuelMatch.Initiative.PLAYER_2
	_s.check(fight.can_scroll(1), "player two scrolls east")
	_s.check(not fight.can_scroll(-1), "player two does not scroll west")
	_s.equal(fight.leader_direction(), 1, "player two pushes east")
	fight.free()


## --- 3 --------------------------------------------------------------------

func _the_killer_takes_it() -> void:
	var fight := _open_match()
	_fight(fight)
	_slay(fight, 1, 0)
	_s.equal(fight.initiative, DuelMatch.Initiative.PLAYER_1, "the killer takes initiative")
	_s.equal(fight.leader_slot(), 0, "and leads")
	_s.equal(fight.kills[0], 1, "and is credited with the kill")
	_s.equal(fight.kills[1], 0, "the victim is credited with nothing")
	_s.check(fight.respawn_left(1) > 0.0, "the victim's respawn timer is running")
	_s.check(not fight.is_fighter_alive(1), "and the victim is down")

	# A second report of the same death must not score twice.
	fight.seats[1].node.call("slay", 0)
	fight.step(0, 0)
	_s.equal(fight.kills[0], 1, "a death reported twice is still one kill")
	fight.free()


func _a_hazard_goes_to_the_survivor() -> void:
	var fight := _open_match()
	_fight(fight)
	_slay(fight, 0, -1)
	_s.equal(
		fight.initiative, DuelMatch.Initiative.PLAYER_2,
		"walking into the cistern hands initiative to the survivor"
	)
	_s.equal(fight.kills[1], 1, "the survivor is credited with it")
	fight.free()


## --- 4 --------------------------------------------------------------------

func _the_leader_drags_the_world() -> void:
	var fight := _open_match()
	_fight(fight)
	_slay(fight, 1, 0)
	var opened := fight.scroll
	var zone := fight.zone_index

	_run_seat(fight, 540, 0, -1)
	_s.check(fight.scroll < opened, "the leader running west drags the window west")
	_s.check(fight.zone_index < zone, "and the zone index follows (%d)" % fight.zone_index)
	_s.equal(
		fight.zone_index, _strip.zone_of_x(fight.scroll + _strip.zone_width() * 0.5),
		"the zone index is where the window is"
	)
	# The leader is held near the middle of their own window, so there is always
	# half a screen of warning ahead of them.
	var middle := fight.scroll + _strip.zone_width() * DuelMatch.WINDOW_ANCHOR
	_s.check(
		absf(fight.fighter_position(0).x - middle) < 24.0,
		"the leader rides the middle of the window (%.1f vs %.1f)"
			% [fight.fighter_position(0).x, middle]
	)
	fight.free()


## --- 5, the one that matters ----------------------------------------------

func _the_wrong_way_does_not_scroll() -> void:
	var fight := _open_match()
	_fight(fight)
	_slay(fight, 1, 0)
	_run_seat(fight, 540, 0, -1)
	# Let the leader come to rest first. High friction stops them in two or
	# three frames, but those frames are still genuine westward travel and the
	# window is entitled to follow them.
	_hold(fight, 60, 0, 0)
	var pulled := fight.scroll
	var zone := fight.zone_index
	_s.check(pulled < MIDDLE_LEFT, "the leader has taken some rope")

	# Now the leader turns round and sprints the other way, for nine seconds.
	_run_seat(fight, 540, 0, 1)
	_s.check(
		fight.scroll <= pulled,
		"running the wrong way does not scroll the world back (%.1f vs %.1f)"
			% [fight.scroll, pulled]
	)
	_s.equal(fight.zone_index, zone, "and does not give the zone back")
	# The sharp version of the same claim: the leader really did cross the
	# window, from its middle to its far edge, and the window did not move.
	var trailing := fight.scroll + _strip.zone_width() - DuelMatch.WINDOW_WALL
	_s.check(
		fight.fighter_position(0).x >= trailing - 1.0,
		"the leader is pressed against the trailing edge (%.1f of %.1f)"
			% [fight.fighter_position(0).x, trailing]
	)

	# And the fighter who is NOT leading cannot move it at all, either way.
	_hold(fight, 60, 0, 0)
	var resting := fight.scroll
	_run_seat(fight, 300, 1, -1)
	_s.equal(fight.scroll, resting, "the follower cannot scroll west")
	_run_seat(fight, 300, 1, 1)
	_s.equal(fight.scroll, resting, "the follower cannot scroll east")
	fight.free()


## --- 6 --------------------------------------------------------------------

func _the_rope_goes_both_ways() -> void:
	var fight := _open_match()
	_fight(fight)
	_slay(fight, 1, 0)
	_run_seat(fight, 420, 0, -1)
	_hold(fight, 60, 0, 0)
	var west := fight.scroll

	_slay(fight, 0, 1)
	_s.equal(fight.initiative, DuelMatch.Initiative.PLAYER_2, "the counter-kill flips it")
	_s.equal(fight.scroll, west, "and does not move the rope by itself")

	_run_seat(fight, 540, 1, 1)
	_hold(fight, 60, 0, 0)
	_s.check(fight.scroll > west, "the new leader pulls it back east")
	var east := fight.scroll
	_run_seat(fight, 420, 1, -1)
	_s.check(
		fight.scroll >= east,
		"and cannot pull it west either (%.1f vs %.1f)" % [fight.scroll, east]
	)
	fight.free()


## --- 7 --------------------------------------------------------------------

func _the_gate() -> void:
	var fight := _open_match()
	# One round: the series that a duel is (tests/unit/test_duel_series.gd) would
	# go on to a second one after the beat, and this is about the gate.
	fight.series_wins = 1
	_fight(fight)
	_slay(fight, 1, 0)

	var guard := 0
	while fight.phase == DuelMatch.Phase.FIGHTING and guard < 3600:
		var bits := LEFT
		if _should_jump(fight, 0, -1) and guard % 6 < 2:
			bits |= JUMP
		fight.step(bits, 0)
		guard += 1

	_s.equal(fight.phase, DuelMatch.Phase.CONSUMED, "the leader reaches the gate")
	_s.equal(fight.winner, 0, "and the match is theirs")
	_s.equal(fight.zone_index, 0, "in the final zone")
	_s.check(
		absf(fight.fighter_position(0).x - _strip.goal_x(0)) <= DuelMatch.ENDPOINT_REACH,
		"standing in the gate's mouth"
	)
	print("  the gate was reached on frame %d" % fight.frame)

	# Being consumed takes a moment, and then the match is over.
	var over := [false]
	fight.match_over.connect(func(_who: int) -> void: over[0] = true)
	guard = 0
	while fight.phase == DuelMatch.Phase.CONSUMED and guard < 600:
		fight.step(LEFT, RIGHT)
		guard += 1
	_s.equal(fight.phase, DuelMatch.Phase.MATCH_OVER, "then the match is over")
	_s.check(bool(over[0]), "and it says so once")
	_s.equal(fight.winner, 0, "the winner does not change")

	# A match that is over does not keep scrolling.
	var rest := fight.scroll
	_hold(fight, 120, LEFT, RIGHT)
	_s.equal(fight.scroll, rest, "a finished match does not scroll")

	fight.reset_match()
	_s.equal(fight.initiative, DuelMatch.Initiative.NEUTRAL, "the reset is neutral again")
	_s.equal(fight.zone_index, 2, "back in the middle zone")
	_s.equal(fight.scroll, MIDDLE_LEFT, "with the window back in the middle")
	_s.equal(fight.frame, 0, "and the clock back at zero")
	_s.equal(fight.winner, DuelRules.DRAW, "and no winner")
	_s.equal(fight.kills[0], 0, "and the kills cleared")
	_s.equal(fight.phase, DuelMatch.Phase.COUNTDOWN, "on the marks")
	for slot: int in 2:
		_s.equal(
			fight.fighter_position(slot), _strip.start_position(slot),
			"seat %d is back on its mark" % slot
		)
	fight.free()
