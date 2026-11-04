extends SceneTree
## The fighter's state machine, and the snapshot it has to survive.
##
##     godot --headless --script tests/fighter_states_test.gd
##
## Three things are being pinned here:
##
##   * the prioritised transitions, including DEAD overriding everything and
##     the committed states ignoring input until they run out
##   * the unarmed sub-machine: disarmed, leg sweep, knocked down, ground pound
##   * that one frame is a pure function of the state and the input byte, which
##     is the property the whole netplay design rests on. A field that simulate()
##     reads and write_state() forgets would show up as a replay that diverges,
##     and one such field is exactly what produced this project's only desync.

const Support := preload("res://tests/fighter_support.gd")

const CLEAR := 120.0

var _s := Support.new()
var _warm := 0
var _deaths: Array[Array] = []


func _physics_process(_delta: float) -> bool:
	_warm += 1
	if _warm < 2:
		return false

	_the_free_states_follow_the_feet()
	_the_stance_costs_no_frames()
	_down_and_jump_rolls_on_the_ground_and_dives_in_the_air()
	_a_commitment_ignores_every_button()
	_dead_overrides_everything()
	_the_death_signal_names_the_killer()
	_disarming_opens_the_unarmed_sub_machine()
	_a_sweep_knocks_down_and_a_pound_finishes()
	_a_snapshot_round_trips()
	_a_replayed_frame_lands_on_the_same_bytes()
	_two_fighters_fed_the_same_bytes_agree()

	quit(_s.report("fighter_states"))
	return true


## --- the free states --------------------------------------------------------

func _the_free_states_follow_the_feet() -> void:
	var stage := Support.build(root)
	stage.place(CLEAR)
	_s.equal(stage.a.state, Fighter.State.IDLE, "standing still is IDLE")

	stage.run(1, Support.RIGHT, 0)
	_s.equal(stage.a.state, Fighter.State.RUNNING, "a direction is RUNNING")
	stage.run(1, Support.DOWN, 0)
	stage.run(1, Support.DOWN, 0)
	_s.equal(stage.a.state, Fighter.State.IDLE, "down on the spot is a stance, standing")
	_s.equal(stage.a.posture(), DuelTuning.Stance.LOW, "the LOW guard")
	stage.run(1, Support.DOWN | Support.WALK, 0)
	_s.equal(stage.a.state, Fighter.State.DUCKING, "down with WALK on the spot is DUCKING")
	_s.check(
		stage.a.hurt_rect().size.y < stage.tuning.body_height, "and the hurtbox comes down"
	)
	_s.equal(stage.a.posture(), DuelTuning.DUCKED, "a duck is the matrix's fourth column")

	stage.run(1, Support.JUMP, 0)
	_s.equal(stage.a.state, Fighter.State.JUMPING, "a jump leaves the ground")
	_s.check(stage.a.velocity.y < 0.0, "going up")
	stage.run(1, 0, 0)
	_s.equal(stage.a.state, Fighter.State.JUMPING, "and stays JUMPING on the way down")
	stage.dispose()


## "Stance may change freely between HIGH, MID and LOW. Zero frames of
## animation lock." Not one frame of lock, and not one frame of delay either:
## the stance that the byte asks for is the stance the blade is at.
func _the_stance_costs_no_frames() -> void:
	var stage := Support.build(root)
	stage.place(CLEAR)
	for spec: Array in [
		[Support.UP, DuelTuning.Stance.HIGH], [0, DuelTuning.Stance.MID],
		[Support.DOWN, DuelTuning.Stance.LOW], [Support.UP, DuelTuning.Stance.HIGH],
	]:
		stage.run(1, Support.RIGHT | int(spec[0]), 0)
		_s.equal(stage.a.stance, spec[1], "the stance arrives on the frame it is asked for")
		var band := stage.tuning.band_of(spec[1])
		var blade := stage.a.blade_rect()
		_s.check(
			is_equal_approx(blade.position.y, stage.a.position.y - band.x),
			"and the blade is in that band"
		)
	stage.dispose()


func _down_and_jump_rolls_on_the_ground_and_dives_in_the_air() -> void:
	var stage := Support.build(root)
	stage.place(CLEAR)
	stage.run(1, Support.DOWN | Support.JUMP, 0)
	_s.equal(stage.a.state, Fighter.State.ROLLING, "down and jump on the ground is a roll")
	stage.dispose()

	stage = Support.build(root)
	stage.place(CLEAR)
	stage.run(1, Support.JUMP, 0)
	stage.run(2, 0, 0)
	stage.run(1, Support.DOWN | Support.JUMP, 0)
	_s.equal(stage.a.state, Fighter.State.DIVEKICK, "the same two buttons in the air dive")
	_s.check(stage.a.velocity.y > 0.0, "and the dive goes down")
	stage.dispose()


func _a_commitment_ignores_every_button() -> void:
	var stage := Support.build(root)
	stage.place(CLEAR)
	stage.run(1, Support.DOWN | Support.JUMP, 0)
	# Everything at once, for the whole roll.
	var mash := (
		Support.LEFT | Support.RIGHT | Support.UP | Support.DOWN
		| Support.JUMP | Support.ATTACK | Support.THROW
	)
	for frame: int in range(2, stage.tuning.roll_frames + 1):
		stage.run(1, mash, 0)
		_s.equal(stage.a.state, Fighter.State.ROLLING, "frame %d: still committed" % frame)
	_s.check(stage.a.is_armed(), "and the sword cannot be thrown out of a roll")
	stage.dispose()


## --- DEAD -------------------------------------------------------------------

func _dead_overrides_everything() -> void:
	var stage := Support.build(root)
	stage.place(CLEAR)
	stage.a.kill(1)
	_s.equal(stage.a.state, Fighter.State.DEAD, "killed")
	_s.check(not stage.a.is_alive(), "and not alive")
	_s.check(stage.a.hurt_rect().size == Vector2.ZERO, "a corpse is not a target")
	_s.check(not stage.a.is_armed(), "and it dropped its sword where it fell")

	var mash := (
		Support.LEFT | Support.RIGHT | Support.UP | Support.DOWN
		| Support.JUMP | Support.ATTACK | Support.THROW
	)
	stage.run(40, mash, 0)
	_s.equal(stage.a.state, Fighter.State.DEAD, "no button leaves DEAD")
	_s.equal(stage.a.blade_rect(), Rect2(), "and a corpse has no blade")

	stage.a.respawn_at(Vector2(Support.LEFT_X, stage.ground_y()), 1)
	_s.equal(stage.a.state, Fighter.State.IDLE, "respawn_at is the only way out")
	_s.check(stage.a.is_armed(), "and it comes back armed")
	_s.equal(stage.a.stance, DuelTuning.Stance.MID, "at a neutral stance")
	stage.dispose()


func _the_death_signal_names_the_killer() -> void:
	var stage := Support.build(root)
	stage.place(20.0)
	_deaths.clear()
	stage.a.died.connect(_on_died)
	stage.b.died.connect(_on_died)
	# B holds HIGH against a MID thrust: the table's kill (torso), not a parry.
	stage.run(2, 0, Support.UP)
	stage.run(1, Support.ATTACK, Support.UP)
	stage.run(2, 0, Support.UP)
	_s.equal(_deaths.size(), 1, "one death was reported")
	if _deaths.size() == 1:
		_s.equal(_deaths[0], [1, 0], "died(victim, killer) names both seats")

	_deaths.clear()
	stage.b.respawn_at(Vector2(Support.LEFT_X + 20.0, stage.ground_y()), -1)
	stage.b.kill()
	_s.equal(_deaths.size(), 1, "a hazard kill is reported too")
	if _deaths.size() == 1:
		_s.equal(_deaths[0], [1, -1], "with -1 for the killer")
	stage.dispose()


func _on_died(victim_id: int, killer_id: int) -> void:
	_deaths.append([victim_id, killer_id])


## --- the unarmed sub-machine ------------------------------------------------

func _disarming_opens_the_unarmed_sub_machine() -> void:
	var stage := Support.build(root)
	stage.place(CLEAR)
	stage.a.disarm(1)
	_s.equal(stage.a.state, Fighter.State.DISARMED, "a disarm has its own flinch")
	_s.check(not stage.a.is_armed(), "and the hand is empty")
	_s.check(stage.a.blade.is_loose(), "the sword is on the floor")

	# The flinch is a commitment: no sweep until it is over.
	stage.run(stage.tuning.disarmed_frames - 1, Support.ATTACK, 0)
	_s.equal(stage.a.state, Fighter.State.DISARMED, "still flinching")
	stage.run(2, 0, 0)
	_s.check(stage.a.is_free(), "then free again, empty-handed")

	# Standing over it and pressing down picks it up in one frame.
	var at := stage.a.blade.position
	stage.a.respawn_at(Vector2(at.x, stage.ground_y()), 1)
	stage.a.blade.drop(Vector2(at.x, stage.ground_y() - 4.0), DuelTuning.Stance.LOW, 1,
		stage.tuning)
	_s.check(not stage.a.is_armed(), "standing over a dropped sword, empty-handed")
	stage.run(1, Support.DOWN, 0)
	_s.check(stage.a.is_armed(), "down picks it up in one frame")
	stage.dispose()


func _a_sweep_knocks_down_and_a_pound_finishes() -> void:
	var stage := Support.build(root)
	stage.place(14.0)
	# A is unarmed and close: a leg sweep is its way back into the fight.
	stage.a.disarm(1)
	stage.run(stage.tuning.disarmed_frames + 1, 0, 0)
	stage.run(1, Support.ATTACK, 0)
	_s.equal(stage.a.state, Fighter.State.SWEEP, "attack on the ground is a leg sweep")
	stage.run(stage.tuning.sweep_active_to, 0, 0)
	_s.equal(stage.b.state, Fighter.State.DOWNED, "the sweep knocks the opponent down")
	_s.check(stage.b.is_alive(), "a knockdown is not a kill")
	_s.check(stage.b.is_armed(), "and the opponent keeps the sword")
	_s.check(stage.saw("knockdown"), "the knockdown is reported")

	# And the pound finishes what the sweep started. A is put directly over the
	# downed fighter and emptied of its sword again, because what is being
	# tested is the finisher, not the walk to it.
	stage.a.respawn_at(Vector2(stage.b.position.x, stage.ground_y()), 1)
	stage.a.disarm(-1)
	stage.run(stage.tuning.disarmed_frames + 1, 0, 0)
	stage.run(1, Support.JUMP, 0)
	stage.run(2, 0, 0)
	_s.equal(stage.b.state, Fighter.State.DOWNED, "the opponent is still down")
	stage.run(1, Support.ATTACK, 0)
	_s.equal(stage.a.state, Fighter.State.POUND, "attack in the air is a ground pound")
	stage.run(10, 0, 0)
	_s.check(not stage.b.is_alive(), "the ground pound finishes a downed opponent")
	stage.dispose()


## --- the snapshot -----------------------------------------------------------

func _a_snapshot_round_trips() -> void:
	var stage := Support.build(root)
	stage.place(20.0)
	_s.equal(Fighter.state_bytes(), 100, "a fighter is 100 bytes of state")

	stage.run(1, Support.ATTACK | Support.UP, Support.DOWN | Support.JUMP)
	stage.run(3, Support.UP, 0)
	var before := _snapshot(stage)
	_restore(stage, before)
	var after := _snapshot(stage)
	_s.check(before == after, "write -> read -> write is byte-identical")

	# And a restore really does restore: wander off, come back, compare.
	stage.run(20, Support.LEFT | Support.ATTACK, Support.RIGHT)
	_s.check(_snapshot(stage) != before, "twenty frames moved the fighters")
	_restore(stage, before)
	_s.check(_snapshot(stage) == before, "and the restore put them back exactly")
	stage.dispose()


## The property the client's reconciliation needs: replaying the same frames
## from the same bytes arrives at the same bytes. Anything simulate() reads and
## write_state() forgets fails here — including the input's press-edge memory,
## which is why a held attack must not re-fire after a restore.
func _a_replayed_frame_lands_on_the_same_bytes() -> void:
	var stage := Support.build(root)
	stage.place(20.0)
	var stream := _stream(90)

	for frame: int in 30:
		stage.step(stream[frame].x, stream[frame].y)
	var checkpoint := _snapshot(stage)

	for frame: int in range(30, 90):
		stage.step(stream[frame].x, stream[frame].y)
	var played := _snapshot(stage)

	_restore(stage, checkpoint)
	for frame: int in range(30, 90):
		stage.step(stream[frame].x, stream[frame].y)
	_s.check(_snapshot(stage) == played, "sixty replayed frames land on the same bytes")
	stage.dispose()


## And two fighters built from scratch, fed the same bytes, agree — one stage
## at a time, at the same coordinates, for the reason in fighter_support.gd.
func _two_fighters_fed_the_same_bytes_agree() -> void:
	var stream := _stream(120)
	var first := _play(stream)
	var second := _play(stream)
	_s.check(first == second, "the same input byte stream is the same duel twice")


func _play(stream: Array[Vector2i]) -> PackedByteArray:
	var stage := Support.build(root)
	stage.place(20.0)
	for pair: Vector2i in stream:
		stage.step(pair.x, pair.y)
	var out := _snapshot(stage)
	stage.dispose()
	return out


## --- scaffolding ------------------------------------------------------------

func _snapshot(stage: Support.Stage) -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(Fighter.state_bytes() * 2)
	stage.a.write_state(buf, 0)
	stage.b.write_state(buf, Fighter.state_bytes())
	return buf


func _restore(stage: Support.Stage, bytes: PackedByteArray) -> void:
	stage.a.read_state(bytes, 0)
	stage.b.read_state(bytes, Fighter.state_bytes())


## A repeatable stream of input pairs, biased the way hands are: each choice is
## held for a few frames, and both fighters lean toward each other, so swords
## actually meet instead of waving at thin air.
func _stream(length: int) -> Array[Vector2i]:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20251103
	var out: Array[Vector2i] = []
	var held := Vector2i.ZERO
	for frame: int in length:
		if frame % 4 == 0:
			held = Vector2i(_one_frame(rng, 1), _one_frame(rng, -1))
		out.append(held)
	return out


func _one_frame(rng: RandomNumberGenerator, toward: int) -> int:
	var bits := 0
	var roll := rng.randf()
	if roll < 0.55:
		bits |= Support.RIGHT if toward > 0 else Support.LEFT
	elif roll < 0.7:
		bits |= Support.LEFT if toward > 0 else Support.RIGHT
	if rng.randf() < 0.3:
		bits |= Support.ATTACK
	if rng.randf() < 0.2:
		bits |= Support.JUMP
	if rng.randf() < 0.25:
		bits |= Support.UP
	elif rng.randf() < 0.3:
		bits |= Support.DOWN
	if rng.randf() < 0.06:
		bits |= Support.THROW
	return bits
