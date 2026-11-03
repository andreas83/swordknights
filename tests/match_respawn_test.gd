extends SceneTree
## The respawn algorithm, exactly as specified, and the pacifist line.
##
##     godot --headless --script tests/match_respawn_test.gd
##
## THE SPECIFICATION
##   1. Victim dies.
##   2. A 2.0 second timer starts.
##   3. The spawn point is computed from the LEADER's current position, placed
##      roughly 1.5 screen widths ahead in the leader's direction of travel.
##   4. The respawning fighter faces the leader, to intercept them.
##   5. Edge case: if the leader is already at the edge of the final zone, the
##      opponent spawns directly in front of the exit.
##
## THE PACIFIST LINE
## A leader who killed and ran must be able to jump over or roll under the
## respawn rather than being forced to fight it. That is a claim about the
## ground the spawn is placed on, and it is checked twice over:
##
##   * for every leader position on the whole strip, at four-pixel intervals,
##     the spawn the algorithm produces stands on open ground — five columns of
##     unbroken floor and five clear rows;
##   * and the numbers in scripts/core/tuning.gd say that a jump from that
##     ground clears a standing fighter and lands beyond them, and that a roll
##     fits inside the flat run. If someone retunes gravity or the jump, this
##     is the test that says the pacifist line went with it.

const Support := preload("res://tests/duel_support.gd")
const MANIFEST := "res://levels/duel_zones.txt"

## How far the search may nudge a spawn to find open ground, in pixels. The
## specification says "roughly"; this is what roughly is allowed to mean.
const NUDGE := float(ZoneStrip.SPAWN_SEARCH * ZoneStrip.TILE)

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
		quit(_s.report("match_respawn"))
		return true

	_the_timer()
	_one_and_a_half_screens()
	_facing_the_leader()
	_the_final_zone()
	_the_pacifist_line()
	_the_jump_arithmetic()
	_purity()

	quit(_s.report("match_respawn"))
	return true


func _open_match() -> DuelMatch:
	var fight := DuelMatch.new()
	fight.name = "Match"
	root.add_child(fight)
	if not fight.build(_strip):
		_s.check(false, "the match builds")
	while fight.phase == DuelMatch.Phase.COUNTDOWN:
		fight.step(0, 0)
	return fight


## --- 2. the timer ----------------------------------------------------------

func _the_timer() -> void:
	var fight := _open_match()
	_s.equal(DuelMatch.RESPAWN_DELAY, 2.0, "the timer is 2.0 seconds")

	fight.seats[1].node.call("slay", 0)
	fight.step(0, 0)
	_s.check(not fight.is_fighter_alive(1), "the victim is down")

	# 2.0 s at the fixed 60 Hz step is 120 frames, and the first one has been
	# taken already by the frame the death was reported on.
	var frames := 0
	while not fight.is_fighter_alive(1) and frames < 400:
		fight.step(0, 0)
		frames += 1
	_s.equal(frames, 120, "and the fighter is back 120 frames later")
	_s.equal(fight.respawn_left(1), 0.0, "with the timer cleared")
	fight.free()


## --- 3. one and a half screens --------------------------------------------

func _one_and_a_half_screens() -> void:
	_s.equal(
		DuelMatch.RESPAWN_LEAD, 960.0,
		"the lead is 1.5 screens, and a screen is 640 px"
	)

	var fight := _open_match()
	var spreads := PackedFloat32Array()
	var pinned := 0
	var checked := 0

	for leader: int in 2:
		fight.initiative = (
			DuelMatch.Initiative.PLAYER_1 if leader == 0
			else DuelMatch.Initiative.PLAYER_2
		)
		var direction := ZoneStrip.goal_direction(leader)
		var victim := 1 - leader
		for step: int in range(0, int(_strip.world_size().x), 32):
			var at := float(step)
			fight.seats[leader].set_x(at)
			var plan := fight.respawn_plan(victim)
			if not _s.check(bool(plan["ok"]), "a spawn is found at x=%.0f" % at):
				break
			checked += 1
			if bool(plan["pinned"]):
				pinned += 1
				continue
			var spawn: Vector2 = plan["position"]
			var ahead := (spawn.x - at) * float(direction)
			spreads.append(ahead)
			if not _s.check(
				ahead > 0.0,
				"the spawn is AHEAD of the leader at x=%.0f (%.0f)" % [at, ahead]
			):
				break
			if not _s.check(
				absf(ahead - DuelMatch.RESPAWN_LEAD) <= NUDGE + float(ZoneStrip.TILE),
				"the spawn is roughly 1.5 screens ahead at x=%.0f (%.0f px)"
					% [at, ahead]
			):
				break

	var lowest := 1.0e9
	var highest := -1.0e9
	for value: float in spreads:
		lowest = minf(lowest, value)
		highest = maxf(highest, value)
	print("  lead ahead of the leader: %.0f to %.0f px (wanted %.0f, nudge %.0f)"
		% [lowest, highest, DuelMatch.RESPAWN_LEAD, NUDGE])
	print("  %d placements checked, %d of them pinned against a gate"
		% [checked, pinned])
	_s.check(pinned > 0, "the final-zone edge case is reachable")
	fight.free()


## --- 4. facing the leader --------------------------------------------------

func _facing_the_leader() -> void:
	var fight := _open_match()
	for leader: int in 2:
		fight.initiative = (
			DuelMatch.Initiative.PLAYER_1 if leader == 0
			else DuelMatch.Initiative.PLAYER_2
		)
		var victim := 1 - leader
		var wrong := 0
		for step: int in range(0, int(_strip.world_size().x), 32):
			fight.seats[leader].set_x(float(step))
			var plan := fight.respawn_plan(victim)
			var spawn: Vector2 = plan["position"]
			var facing: int = int(plan["facing"])
			var toward := signi(int(float(step) - spawn.x))
			if toward != 0 and facing != toward:
				wrong += 1
		_s.equal(wrong, 0, "seat %d's opponent always spawns facing them" % leader)

	# And the fighter really is turned that way when it comes back.
	fight.reset_match()
	while fight.phase == DuelMatch.Phase.COUNTDOWN:
		fight.step(0, 0)
	fight.seats[1].node.call("slay", 0)
	var planned := fight.respawn_plan(1)
	for i: int in 200:
		fight.step(0, 0)
		if fight.is_fighter_alive(1):
			break
	_s.equal(
		int(fight.seats[1].node.get("facing")), int(planned["facing"]),
		"and respawn_at is given that facing"
	)
	fight.free()


## --- 5. the edge case ------------------------------------------------------

func _the_final_zone() -> void:
	var fight := _open_match()

	for leader: int in 2:
		fight.initiative = (
			DuelMatch.Initiative.PLAYER_1 if leader == 0
			else DuelMatch.Initiative.PLAYER_2
		)
		var direction := ZoneStrip.goal_direction(leader)
		var gate := _strip.goal_x(leader)
		var standoff := float(ZoneStrip.GATE_STANDOFF * ZoneStrip.TILE)

		# "At the edge of the final zone": the leader is deep into their last
		# zone, so nothing is 1.5 screens further on — there is no further on.
		fight.seats[leader].set_x(gate + float(-direction) * (standoff + 112.0))
		var plan := fight.respawn_plan(1 - leader)
		var spawn: Vector2 = plan["position"]
		var leader_x := fight.seats[leader].position().x

		_s.check(bool(plan["pinned"]), "seat %d near the gate pins the spawn" % leader)
		_s.check(
			(spawn.x - gate) * float(-direction) > 0.0,
			"the opponent spawns on the field side of the gate, not behind it"
		)
		_s.check(
			absf(spawn.x - gate) <= standoff + float(ZoneStrip.TILE),
			"and directly in front of it (%.0f px out)" % absf(spawn.x - gate)
		)
		# Which is the whole point of the rule: they stand between the leader
		# and the gate, so the leader has to get past them to win.
		_s.check(
			(spawn.x - leader_x) * float(direction) > 0.0,
			"standing between the leader and the gate"
		)
		_s.check(
			_strip.is_open_ground(int(plan["column"])),
			"on ground the leader can go over the top of"
		)

		# And once the leader is INSIDE the standoff — a stride from winning —
		# the spawn stays at the standoff rather than being pushed behind the
		# gate to block them. A leader that close has earned it.
		fight.seats[leader].set_x(gate + float(-direction) * 24.0)
		var late := fight.respawn_plan(1 - leader)
		var late_spawn: Vector2 = late["position"]
		_s.check(
			(late_spawn.x - gate) * float(-direction) >= standoff - float(ZoneStrip.TILE),
			"a spawn is never pushed between a nearly-won leader and the gate"
		)
	fight.free()


## --- the pacifist line -----------------------------------------------------

func _the_pacifist_line() -> void:
	var fight := _open_match()
	var placements := 0
	var closed := 0
	var in_a_hazard := 0

	for leader: int in 2:
		fight.initiative = (
			DuelMatch.Initiative.PLAYER_1 if leader == 0
			else DuelMatch.Initiative.PLAYER_2
		)
		var victim := 1 - leader
		for step: int in range(0, int(_strip.world_size().x), 4):
			fight.seats[leader].set_x(float(step))
			var plan := fight.respawn_plan(victim)
			var column: int = int(plan["column"])
			placements += 1
			if not _strip.is_open_ground(column):
				closed += 1
			var spawn: Vector2 = plan["position"]
			if _strip.rect_is_deadly(Rect2(spawn.x - 4.5, spawn.y - 22.0, 9.0, 22.0)):
				in_a_hazard += 1

	print("  %d respawn placements across the strip, all open ground: %s"
		% [placements, str(closed == 0)])
	_s.equal(
		closed, 0,
		"every respawn the algorithm can produce is on open ground"
	)
	_s.equal(in_a_hazard, 0, "and never inside the cistern")
	fight.free()


## Can a leader actually get past it? Asked of scripts/core/tuning.gd rather
## than of the level, because the level is only half the answer.
func _the_jump_arithmetic() -> void:
	# Rise from JUMP_SPEED to the apex threshold at full gravity, then the rest
	# under the softened apex gravity. Same two phases the character uses.
	var threshold := Tuning.APEX_THRESHOLD
	var apex_gravity := Tuning.GRAVITY * Tuning.APEX_GRAVITY_SCALE
	var first := (Tuning.JUMP_SPEED * Tuning.JUMP_SPEED - threshold * threshold) \
		/ (2.0 * Tuning.GRAVITY)
	var second := (threshold * threshold) / (2.0 * apex_gravity)
	var apex := first + second
	var rise_time := (Tuning.JUMP_SPEED - threshold) / Tuning.GRAVITY \
		+ threshold / apex_gravity
	var airborne := rise_time * 2.0
	var reach := Tuning.RUN_SPEED * airborne

	print("  a jump: %.1f px high, %.2f s airborne, %.1f px across" % [
		apex, airborne, reach,
	])

	_s.check(
		apex > Tuning.BODY_HEIGHT + 8.0,
		"a jump clears a standing fighter with room (%.1f over %.1f)"
			% [apex, Tuning.BODY_HEIGHT]
	)
	_s.check(
		reach > Tuning.BODY_WIDTH * 3.0,
		"and lands clear on the other side of them (%.1f px)" % reach
	)

	# The flat run the respawn is guaranteed is wide enough to take off from and
	# land on, and wide enough to roll the whole length of.
	var flat := float(ZoneStrip.FLAT_RUN * 2 + 1) * ZoneStrip.TILE
	_s.check(
		flat >= reach,
		"the guaranteed flat run holds the whole jump (%.0f px of %.0f)"
			% [flat, reach]
	)
	# A roll is 25 frames with the hurtbox compressed, per the specification.
	var roll := Tuning.RUN_SPEED * (25.0 / 60.0)
	_s.check(
		flat >= roll,
		"and holds a whole roll (%.0f px of %.0f)" % [flat, roll]
	)
	# And the headroom is enough for the jumper's own head.
	var headroom := float(ZoneStrip.HEADROOM) * ZoneStrip.TILE
	_s.check(
		headroom >= apex + Tuning.BODY_HEIGHT,
		"the guaranteed headroom clears the jumper's head (%.0f px of %.0f)"
			% [headroom, apex + Tuning.BODY_HEIGHT]
	)


## --- purity ----------------------------------------------------------------

func _purity() -> void:
	var fight := _open_match()
	fight.initiative = DuelMatch.Initiative.PLAYER_2
	fight.seats[1].set_x(900.0)

	var once := fight.respawn_plan(0)
	var twice := fight.respawn_plan(0)
	_s.equal(once, twice, "the plan is a function of the state, not of the clock")

	# And it survives the wire: the same state in, the same spawn out, which is
	# what stops a client putting a fighter somewhere the host did not.
	var blob := fight.write_state()
	fight.seats[1].set_x(1800.0)
	_s.check(
		fight.respawn_plan(0) != once, "moving the leader moves the spawn"
	)
	_s.check(fight.read_state(blob), "the state reads back")
	_s.equal(
		fight.respawn_plan(0), once,
		"and the spawn is the one the host would have chosen"
	)
	fight.free()
