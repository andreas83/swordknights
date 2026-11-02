extends SceneTree
## The duelling rules.
##
##     godot --headless --script tests/duel_combat.gd
##
## Each case builds its own duel, puts the two duellists on a known patch of
## ground facing a known way, and then plays a scripted sequence of input
## frames. Nothing here reads a clock or a device, which is the whole reason
## these rules can be pinned down at all.

const Support := preload("res://tests/duel_support.gd")

## How far apart two duellists stand to be exactly within sword reach: the
## sword reaches ATTACK_REACH past the edge of the body.
const SWORD_RANGE := 18.0
## How far below the ground surface counts as "in the pit shaft".
const PIT_DEPTH := 8.0

## Read off the arena rather than written down, so moving a tile in
## levels/arena_01.txt cannot quietly turn these cases into nonsense.
var _ground_y := 0.0
var _left_x := 0.0
var _pit_left_x := 0.0
var _pit_right_x := 0.0
var _pit_y := 0.0

const A := DuelRules.SLOT_A
const B := DuelRules.SLOT_B
const ATTACK := PlayerInput.BIT_ATTACK
const GUARD := PlayerInput.BIT_GUARD

var _s := Support.new()
var _warm := 0


func _physics_process(_delta: float) -> bool:
	_warm += 1
	if _warm < 2:
		return false

	_measure_the_arena()
	_clean_hit_kills()
	_block_does_not()
	_a_parry_opens_a_longer_window_than_a_block()
	_a_guard_only_covers_the_side_it_faces()
	_simultaneous_swings_clash()
	_the_pit_kills()
	_a_double_death_is_a_draw()
	_a_round_ends_and_the_match_advances()

	quit(_s.report("duel_combat"))
	return true


## --- cases ------------------------------------------------------------------

## The spawn mark sits on the ground, and the spike pit is dead centre: both
## follow from the arena being a mirror of itself about the middle.
func _measure_the_arena() -> void:
	var duel := Support.spawn_duel(root)
	var spawn := duel.spawn_of(A)
	_ground_y = spawn.y
	_left_x = spawn.x
	var middle := duel.arena_size().x * 0.5
	_pit_left_x = middle - 8.0
	_pit_right_x = middle + 8.0
	_pit_y = _ground_y + PIT_DEPTH

	_s.check(
		duel.level.rect_is_deadly(
			Rect2(_pit_left_x - 4.0, _ground_y + 20.0, 8.0, 20.0)
		),
		"the middle of the arena is a deadly pit"
	)
	_s.check(
		not duel.level.rect_is_deadly(
			Rect2(_left_x - 4.0, _ground_y - 22.0, 9.0, 22.0)
		),
		"the spawn mark is not standing in anything deadly"
	)
	duel.free()


func _clean_hit_kills() -> void:
	var duel := _staged()
	# B is facing away and not guarding: nothing between him and the sword.
	_run(duel, 1, ATTACK, 0)
	_run(duel, 12, 0, 0)

	_s.check(not duel.players[B].is_alive(), "a clean cut kills")
	_s.check(duel.players[A].is_alive(), "the attacker survives a clean cut")
	_s.equal(duel.scores[A], 1, "a clean cut scores for the attacker")
	_s.equal(duel.phase, Duel.Phase.ROUND_OVER, "a kill ends the round")
	_s.equal(duel.last_round_winner, A, "the round is awarded to the attacker")
	duel.free()


func _block_does_not() -> void:
	var duel := _staged(-1)
	# B raises the guard and holds it long past the parry window, then A swings.
	_run(duel, 14, 0, GUARD)
	_run(duel, 1, ATTACK, GUARD)
	_run(duel, 12, 0, GUARD)

	_s.check(duel.players[B].is_alive(), "a blocked cut does not kill")
	_s.equal(duel.scores[A], 0, "a blocked cut scores nothing")
	_s.equal(duel.scores[B], 0, "a blocked cut scores nothing for the defender either")
	_s.equal(duel.phase, Duel.Phase.FIGHTING, "a blocked cut does not end the round")
	_s.check(duel.players[A].is_staggered(), "a blocked cut staggers the attacker")
	duel.free()


func _a_parry_opens_a_longer_window_than_a_block() -> void:
	# Same exchange twice, differing only in when the guard went up.
	var blocked := _measure_stagger(14)
	var parried := _measure_stagger(1)

	_s.check(blocked > 0, "a block staggers the attacker at all")
	_s.check(
		parried > blocked,
		"a parry (%d frames of stagger) opens longer than a block (%d)"
			% [parried, blocked]
	)


func _a_guard_only_covers_the_side_it_faces() -> void:
	# B holds the guard, but faces away from the sword.
	var duel := _staged(1)
	_run(duel, 14, 0, GUARD)
	_run(duel, 1, ATTACK, GUARD)
	_run(duel, 12, 0, GUARD)

	_s.check(
		not duel.players[B].is_alive(),
		"a guard raised the wrong way does not stop the sword"
	)
	duel.free()


func _simultaneous_swings_clash() -> void:
	var duel := _staged(-1)
	_run(duel, 1, ATTACK, ATTACK)
	_run(duel, 10, 0, 0)

	_s.check(duel.players[A].is_alive(), "a clash leaves the first duellist standing")
	_s.check(duel.players[B].is_alive(), "a clash leaves the second duellist standing")
	_s.check(duel.players[A].is_staggered(), "a clash staggers the first duellist")
	_s.check(duel.players[B].is_staggered(), "a clash staggers the second duellist")
	_s.equal(duel.scores[A] + duel.scores[B], 0, "a clash scores nothing")
	duel.free()


func _the_pit_kills() -> void:
	var duel := _fighting()
	# In the pit shaft, below the one-way bridge that spans the middle.
	duel.players[A].duel_reset(Vector2(_pit_left_x, _pit_y), 1)
	duel.players[B].duel_reset(Vector2(_left_x, _ground_y), 1)
	_run(duel, 40, 0, 0)

	_s.check(not duel.players[A].is_alive(), "the spike pit kills")
	_s.equal(duel.scores[B], 1, "falling in scores for the other duellist")
	duel.free()


func _a_double_death_is_a_draw() -> void:
	var duel := _fighting()
	duel.players[A].duel_reset(Vector2(_pit_left_x, _pit_y), 1)
	duel.players[B].duel_reset(Vector2(_pit_right_x, _pit_y), -1)
	_run(duel, 40, 0, 0)

	_s.check(not duel.players[A].is_alive(), "both fell: the first is down")
	_s.check(not duel.players[B].is_alive(), "both fell: the second is down")
	_s.equal(duel.last_round_winner, DuelRules.DRAW, "two deaths at once is a draw")
	_s.equal(duel.scores[A], 0, "a draw scores for nobody")
	_s.equal(duel.scores[B], 0, "a draw scores for nobody")
	duel.free()


func _a_round_ends_and_the_match_advances() -> void:
	var duel := _staged(1, 2) # first to two

	# Round one.
	_run(duel, 1, ATTACK, 0)
	_run(duel, 12, 0, 0)
	_s.equal(duel.scores[A], 1, "round one is scored")
	_s.equal(duel.round_index, 0, "the round index has not moved yet")

	# Let the round-over pause run out: a new round, back on the marks.
	_step_until(duel, Duel.Phase.COUNTDOWN, 240)
	_s.equal(duel.round_index, 1, "the match moved on to round two")
	_s.equal(duel.scores[A], 1, "the score carries into the next round")
	_s.check(duel.players[B].is_alive(), "the loser is back on his feet")
	_s.check(
		is_equal_approx(duel.players[B].position.x, duel.spawn_of(B).x),
		"a new round puts both duellists back on their marks"
	)

	# Round two, from the marks this time, so re-stage and swing again.
	_step_until(duel, Duel.Phase.FIGHTING, 240)
	_mark(duel, 1)
	_run(duel, 1, ATTACK, 0)
	_run(duel, 12, 0, 0)
	_s.equal(duel.scores[A], 2, "round two is scored")

	_step_until(duel, Duel.Phase.MATCH_OVER, 240)
	_s.equal(duel.phase, Duel.Phase.MATCH_OVER, "reaching the target ends the match")
	_s.equal(duel.match_winner, A, "the match goes to the duellist who won both rounds")
	duel.free()


## --- scaffolding ------------------------------------------------------------

## A duel stepped forward to the FIGHTING phase.
func _fighting(rounds: int = DuelRules.ROUNDS_TO_WIN) -> Duel:
	var duel := Support.spawn_duel(root, rounds)
	_step_until(duel, Duel.Phase.FIGHTING, 240)
	return duel


## Fighting, with both duellists settled on their marks a sword's length apart.
## `b_facing` is which way the right-hand duellist looks: -1 is toward the
## sword, +1 is away from it.
func _staged(b_facing: int = 1, rounds: int = DuelRules.ROUNDS_TO_WIN) -> Duel:
	var duel := _fighting(rounds)
	_mark(duel, b_facing)
	return duel


func _mark(duel: Duel, b_facing: int) -> void:
	duel.players[A].duel_reset(Vector2(_left_x, _ground_y), 1)
	duel.players[B].duel_reset(Vector2(_left_x + SWORD_RANGE, _ground_y), b_facing)
	# A few still frames so both are reported as standing on the floor; the
	# guard cannot be raised in mid-air.
	_run(duel, 4, 0, 0)


func _run(duel: Duel, frames: int, bits_a: int, bits_b: int) -> void:
	for i: int in frames:
		duel.step(bits_a, bits_b)


func _step_until(duel: Duel, phase: Duel.Phase, limit: int) -> bool:
	for i: int in limit:
		if duel.phase == phase:
			return true
		duel.step(0, 0)
	return duel.phase == phase


## How many frames the attacker spends staggered after swinging into a guard
## that went up `lead` frames earlier. Short lead = parry, long lead = block.
func _measure_stagger(lead: int) -> int:
	var duel := _staged(-1)
	_run(duel, lead, 0, GUARD)
	_run(duel, 1, ATTACK, GUARD)

	var frames := 0
	var saw_stagger := false
	for i: int in 120:
		duel.step(0, GUARD)
		if duel.players[A].is_staggered():
			saw_stagger = true
			frames += 1
		elif saw_stagger:
			break
	duel.free()
	return frames
