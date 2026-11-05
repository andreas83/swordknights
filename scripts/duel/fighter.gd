class_name Fighter
extends CharacterBody2D
## One duellist: a deterministic state machine with a sword, and no health.
##
## This is the duel's character, not the adventure's. scripts/player/player.gd
## is the prince — weighty, forgiving, three hearts, a guard button. A fighter
## reaches top speed in two frames, stops in three, dies to one clean cut, and
## is defined entirely by where its blade is: HIGH, MID or LOW, changeable with
## zero frames of animation lock. The numbers live in DuelTuning, which the
## match hands over in setup(); nothing here reads scripts/core/tuning.gd.
##
## THE FRAME. The physics tick is a fixed 60 Hz, so one simulate() call is one
## frame and the spec's frame counts are literal. simulate() is a pure function
## of this fighter's state and one input byte — it reads no clock, no device
## and no randomness — which is what lets the host's frame be replayed by a
## client and compared by checksum. The fighter deliberately has no
## _physics_process: the match steps it, exactly once per frame, and may step
## it again to replay a frame it mispredicted.
##
## EVERYTHING IS SNAPSHOT STATE. write_state() carries every field simulate()
## reads, including the private commitment counter, the ducked and grounded
## flags, the input's press-edge memory and the three jump counters (coyote,
## buffer, cut lock) packed into the flags word. A single field hiding outside the
## snapshot produced the one desync this project has had; see docs/netplay.md.
##
## THE ORDER OF A DUEL FRAME, which the match owns:
##
##     a.input.apply_bits(bits_a); b.input.apply_bits(bits_b)
##     a.simulate(DT);             b.simulate(DT)
##     DuelCombat.resolve(a, b)
##
## Hitboxes are read in resolve() before anything is applied, so nothing in the
## outcome depends on which fighter is slot A.

## The only thing the match layer needs to hear. killer_id is -1 for a hazard.
signal died(victim_id: int, killer_id: int)
## Presentation, suppressed while `replaying`. The match may ignore all of them.
signal disarmed(victim_id: int, by_id: int)
signal clashed(at: Vector2)
signal blade_thrown(thrower_id: int)
signal knocked_down(victim_id: int)
signal caught(catcher_id: int, thrower_id: int)

## IDLE, RUNNING, JUMPING and DUCKING are the free states: the only ones that
## read the stance buttons or start anything. ROLLING, RISING, THRUSTING,
## DIVEKICK, SWEEP, POUND, SNATCH and CATCH are commitments — they ignore input
## entirely until they run out. RISING is the getting-up at the end of a roll:
## standing height, blade not yet up, the price of having rolled. DISARMED,
## SWEEP, POUND, DOWNED and SNATCH are the unarmed sub-machine (plus the free
## states with an empty hand, where attack sweeps instead of thrusting and
## throw snatches instead of throwing). CATCH is the
## moment a snatched blade is taken into the hand.
## DEAD overrides every other state and is left only by respawn_at().
##
## SNATCH, CATCH and RISING come after DEAD rather than beside the states they
## belong with because the state travels in the snapshot as its ordinal:
## appending them left every older state's number, and so the layout
## docs/netplay.md describes, exactly as it was.
enum State {
	IDLE, RUNNING, JUMPING, DUCKING,
	ROLLING, THRUSTING, DIVEKICK,
	DISARMED, SWEEP, POUND, DOWNED,
	DEAD,
	SNATCH, CATCH,
	RISING,
}

## What the fighter's feet or fists are doing this frame, for DuelCombat.
enum Strike { NONE, KICK, SWEEP, POUND }

## How many surfaces one frame of motion may slide along before giving up, and
## the steepest normal still counted as floor (cos 45 degrees, matching
## CharacterBody2D's default floor_max_angle).
const MAX_SLIDES := 4
const FLOOR_DOT := 0.7071067811865476

## Snapshot layout. Positions and velocities are doubles for the reason
## docs/netplay.md gives; every timer is an integer frame count, which cannot
## drift at all. Keep write_state and read_state in step.
const OFF_POSITION := 0
const OFF_VELOCITY := 16
const OFF_STATE := 32
const OFF_STATE_FRAME := 36
const OFF_FACING := 40
const OFF_STANCE := 44
const OFF_COMMIT := 48
const OFF_FLAGS := 52
const OFF_BLADE := 56

const FLAG_DUCKED := 1 << 0
const FLAG_GROUNDED := 1 << 1
const FLAG_STANCE_CHANGED := 1 << 2
## The input's press-edge memory lives in the second byte of the flags word.
const FLAG_INPUT_SHIFT := 8
## The jump's three frame counters -- coyote, buffer, cut lock -- live above it,
## four bits each, so the fighter's block stays the 100 bytes docs/netplay.md
## lays out. DuelTuning holds every window under JUMP_COUNTER_MAX.
const FLAG_COYOTE_SHIFT := 16
const FLAG_BUFFER_SHIFT := 20
const FLAG_CUT_LOCK_SHIFT := 24
const JUMP_COUNTER_MAX := 15

## Which seat this fighter is. Set by setup(); reported as victim and killer.
var id: int = 0
## The duel movement profile. Never scripts/core/tuning.gd.
var tuning: DuelTuning = DuelTuning.default()
## The arena. Loose swords and standing up out of a roll are resolved against
## the tile grid rather than with a physics query, so they cost nothing and
## cannot disagree between two machines. The match hands over its ZoneStrip;
## the fighter's tests hand over a LevelWorld. See DuelWorld for why this is a
## type and not a convention.
var world: DuelWorld
## One frame of intent, from a keyboard, a replay, an AI or the wire.
var input: PlayerInput = PlayerInput.new()
## Set by the match while it replays mispredicted frames: the simulation still
## runs, the presentation signals do not fire. `died` always fires, because the
## match's own bookkeeping depends on it.
var replaying := false

var state: State = State.IDLE
## 1 on the frame a state is entered. The spec's windows are closed intervals
## over this: a thrust is active on frames 1..4 of THRUSTING.
var state_frame: int = 1
var facing: int = 1
var stance: int = DuelTuning.Stance.MID
## Whether the stance moved this frame. The disarm read is built on it.
var stance_changed := false
## Whether the feet are on something, as this file worked it out. The engine's
## is_on_floor() is never set, because a duel does not call move_and_slide();
## see docs/netplay.md and _move().
var grounded := false
## This fighter's sword, wherever it is.
var blade := DuelBlade.new()

var _ducked := false
## Frames of mandatory stillness left after a dive kick or a ground pound
## lands. -1 means "still in the air", 0 means "done". While DOWNED it holds
## how long this knockdown lasts, which depends on what knocked the fighter
## down (DuelTuning.downed_frames for a sweep, kick_downed_frames for a kick).
var _commit: int = 0
## The jump's forgiveness, in frames, as the adventure's prince has it and the
## duel did not (docs/duel-combat.md, "The jump"). `_coyote`: frames left in
## which a fighter who walked or was knocked off an edge may still jump as if
## standing. `_buffer`: frames left in which a JUMP pressed too early -- in the
## air, or in a commitment -- still fires on the first frame it can.
## `_cut_lock`: frames left before letting go of JUMP may cut the rise, so a
## thumb's tap is a hop and not a twitch.
var _coyote: int = 0
var _buffer: int = 0
var _cut_lock: int = 0

@onready var _shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_GROUNDED
	up_direction = Vector2.UP
	floor_stop_on_slope = true
	# Fighters collide with the arena and never with each other: in a duel you
	# walk through your opponent, and the sword is what stops you.
	collision_layer = 0
	collision_mask = Tiles.MASK_SOLID | Tiles.MASK_ONE_WAY
	_sync_shape()


## --- the contract with the match layer -------------------------------------

func setup(seat: int, profile: Resource) -> void:
	id = seat
	var duel_profile := profile as DuelTuning
	tuning = duel_profile if duel_profile != null else DuelTuning.default()
	_sync_shape()


## Back on a mark, armed, with every timer and every press edge cleared. This
## is also the only way out of DEAD.
func respawn_at(at: Vector2, face: int) -> void:
	position = at
	velocity = Vector2.ZERO
	state = State.IDLE
	state_frame = 1
	facing = 1 if face >= 0 else -1
	stance = DuelTuning.Stance.MID
	stance_changed = false
	grounded = false
	_ducked = false
	_commit = 0
	_coyote = 0
	_buffer = 0
	_cut_lock = 0
	# A fighter always comes back with its own sword, wherever that sword was
	# lying. Two records, two swords, never more: see DuelBlade.
	blade.hold()
	input.clear()
	_sync_shape()


func is_alive() -> bool:
	return state != State.DEAD


static func state_bytes() -> int:
	return OFF_BLADE + DuelBlade.BYTES


func write_state(into: PackedByteArray, at: int) -> void:
	if into.size() < at + state_bytes():
		push_error("fighter state does not fit: %d bytes at %d" % [into.size(), at])
		return
	into.encode_double(at + OFF_POSITION, position.x)
	into.encode_double(at + OFF_POSITION + 8, position.y)
	into.encode_double(at + OFF_VELOCITY, velocity.x)
	into.encode_double(at + OFF_VELOCITY + 8, velocity.y)
	into.encode_s32(at + OFF_STATE, int(state))
	into.encode_s32(at + OFF_STATE_FRAME, state_frame)
	into.encode_s32(at + OFF_FACING, facing)
	into.encode_s32(at + OFF_STANCE, stance)
	into.encode_s32(at + OFF_COMMIT, _commit)
	into.encode_s32(at + OFF_FLAGS, _flags())
	blade.write(into, at + OFF_BLADE)


## This fighter's share of the match checksum: every field write_state()
## carries, floats quantised by DuelSim.quantise(), integers as they are.
##
## The fighter writes this itself because only the fighter knows which of its
## bytes are which. The match's fallback reads a fighter's block as a run of
## float64s, which is right for the placeholder and wrong here: this layout
## mixes doubles and int32s, and an int read as a double is a garbage value
## whose quantisation is not something two CPUs are promised to agree on.
func checksum_into(words: PackedInt32Array) -> void:
	for value: float in [
		position.x, position.y, velocity.x, velocity.y,
		blade.position.x, blade.position.y, blade.velocity.x, blade.velocity.y,
	]:
		words.append(DuelSim.quantise(value))
	for value: int in [
		int(state), state_frame, facing, stance, _commit, _flags(),
		int(blade.mode), blade.stance, blade.thrown_by,
	]:
		words.append(value)


func _flags() -> int:
	var flags := input.previous_bits() << FLAG_INPUT_SHIFT
	if _ducked:
		flags |= FLAG_DUCKED
	if grounded:
		flags |= FLAG_GROUNDED
	if stance_changed:
		flags |= FLAG_STANCE_CHANGED
	flags |= _counter(_coyote) << FLAG_COYOTE_SHIFT
	flags |= _counter(_buffer) << FLAG_BUFFER_SHIFT
	flags |= _counter(_cut_lock) << FLAG_CUT_LOCK_SHIFT
	return flags


static func _counter(frames: int) -> int:
	return clampi(frames, 0, JUMP_COUNTER_MAX)


func read_state(from: PackedByteArray, at: int) -> void:
	if from.size() < at + state_bytes():
		push_error("fighter state is short: %d bytes at %d" % [from.size(), at])
		return
	position = Vector2(
		from.decode_double(at + OFF_POSITION), from.decode_double(at + OFF_POSITION + 8)
	)
	velocity = Vector2(
		from.decode_double(at + OFF_VELOCITY), from.decode_double(at + OFF_VELOCITY + 8)
	)
	state = from.decode_s32(at + OFF_STATE) as State
	state_frame = from.decode_s32(at + OFF_STATE_FRAME)
	facing = from.decode_s32(at + OFF_FACING)
	stance = from.decode_s32(at + OFF_STANCE)
	_commit = from.decode_s32(at + OFF_COMMIT)
	var flags := from.decode_s32(at + OFF_FLAGS)
	_ducked = flags & FLAG_DUCKED != 0
	grounded = flags & FLAG_GROUNDED != 0
	stance_changed = flags & FLAG_STANCE_CHANGED != 0
	input.restore_previous_bits((flags >> FLAG_INPUT_SHIFT) & 0xff)
	_coyote = (flags >> FLAG_COYOTE_SHIFT) & JUMP_COUNTER_MAX
	_buffer = (flags >> FLAG_BUFFER_SHIFT) & JUMP_COUNTER_MAX
	_cut_lock = (flags >> FLAG_CUT_LOCK_SHIFT) & JUMP_COUNTER_MAX
	blade.read(from, at + OFF_BLADE)
	_sync_shape()


## --- one frame --------------------------------------------------------------

## Advance exactly one frame. Call it inside a physics frame: the fighter is a
## CharacterBody2D and move_and_collide() queries the physics space, which only
## exists while the engine is stepping it.
func simulate(dt: float) -> void:
	state_frame += 1
	var was := posture()
	_update_stance()
	blade.step(dt, tuning, world)
	if state == State.DEAD:
		# DEAD overrides every other state. A corpse still falls — into the
		# pit, off the balcony — and that is all it does.
		_apply_gravity(dt)
		_move(dt)
		stance_changed = false
		return
	_decide()
	_advance(dt)
	_count_jump_windows()
	# What the disarm read is built on: did the blade arrive at a height this
	# frame? The posture, not the button, because standing up out of a duck
	# into LOW, or out of a knockdown into MID, moves the blade into that
	# height as surely as pressing down does -- a duck holds no height at all.
	stance_changed = posture() != was


## The stance is the whole game: up is HIGH, down is LOW, neither is MID, with
## no animation lock whatsoever, standing still or moving. It is read only in
## the free states, so a thrust's height is locked from the frame it starts —
## otherwise a single button could sweep an active blade through all three
## heights, and the disarm read below would be meaningless.
##
## Down is a LOW guard, not a duck: the duck is down with WALK (see
## _advance_free), and docs/duel-combat.md argues why it is that way round.
func _update_stance() -> void:
	if blade.is_held() and is_free():
		if input.up:
			stance = DuelTuning.Stance.HIGH
		elif input.down:
			stance = DuelTuning.Stance.LOW
		else:
			stance = DuelTuning.Stance.MID


## The transition table, in priority order. DEAD never reaches here.
##
##   1. a commitment that has run out ends, and the fighter is free this frame
##   2. a commitment that has not is immune to input: nothing below is read
##   3. throw          — the sword leaves the hand; costs no frames. With an
##                       empty hand the same button is a SNATCH: the hands
##                       open for a thrown sword, and nothing below is read
##   4. attack         — THRUSTING armed, SWEEP or POUND empty-handed
##   5. down + jump    — ROLLING on the ground, DIVEKICK in the air
##   6. jump           — JUMPING, on the ground or inside the coyote window,
##                       from this frame's press or one still in the buffer
##   7. otherwise the free state follows the feet: DUCKING, RUNNING, IDLE,
##      JUMPING, which _advance() settles once the motion is known
func _decide() -> void:
	_expire()
	# A plain JUMP is remembered for `jump_buffer` frames wherever it is
	# pressed, so one pressed in the air or in the last frames of a commitment
	# jumps on the first frame it can. Down + JUMP is not: it is a roll or a
	# dive kick, chosen on the frame, and a commitment is not queued.
	if input.just_pressed_jump and not input.down:
		_buffer = tuning.jump_buffer
	if not is_free():
		return
	if input.just_pressed_throw:
		if not blade.is_held():
			_snatch()
			return
		_throw()
	if input.just_pressed_attack and _begin_attack():
		return
	if input.just_pressed_jump and input.down:
		_begin_commit_down()
	elif _buffer > 0 and (grounded or _coyote > 0):
		_jump()


## Committed states end on a frame count, or — for the two dives — when the
## landing recovery has run out.
func _expire() -> void:
	match state:
		State.THRUSTING:
			if state_frame > tuning.thrust_frames:
				_enter_free()
		State.ROLLING:
			if state_frame > tuning.roll_frames:
				_rise()
		State.RISING:
			if state_frame > tuning.roll_recover:
				_leave_roll()
		State.SWEEP:
			if state_frame > tuning.sweep_frames:
				_enter_free()
		State.DISARMED:
			if state_frame > tuning.disarmed_frames:
				_enter_free()
		State.DOWNED:
			if state_frame > _commit:
				_leave_roll()
		State.SNATCH:
			if state_frame > tuning.snatch_frames:
				_enter_free()
		State.CATCH:
			if state_frame > tuning.catch_settle:
				_enter_free()
		State.DIVEKICK, State.POUND:
			if _commit == 0:
				_enter_free()
		_:
			pass


## The motion of whatever state the fighter is now in, then gravity, then one
## frame of collision.
func _advance(dt: float) -> void:
	match state:
		State.THRUSTING:
			# "The fighter drifts slightly forward during the thrust."
			if grounded:
				velocity.x = move_toward(
					velocity.x, facing * tuning.thrust_drift, tuning.ground_accel * dt
				)
			_apply_gravity(dt)
		State.ROLLING, State.RISING:
			# The rise is the roll's last frames standing up: still moving.
			velocity.x = facing * tuning.roll_speed
			_apply_gravity(dt)
		State.DIVEKICK:
			_dive(dt, Vector2(facing * tuning.divekick_speed_x, tuning.divekick_speed_y))
		State.POUND:
			_dive(dt, Vector2(0.0, tuning.pound_speed_y))
		State.SWEEP, State.DISARMED, State.DOWNED, State.SNATCH, State.CATCH:
			velocity.x = move_toward(velocity.x, 0.0, tuning.ground_friction * dt)
			_apply_gravity(dt)
		_:
			_advance_free(dt)
	_move(dt)
	if is_free():
		_resolve_free_state()


## IDLE, RUNNING, JUMPING, DUCKING: top speed in two frames, stopped in three.
##
## WALK is footwork. Held, the fighter does not turn round for a direction --
## it shuffles that way at walk_speed, blade still toward the opponent, so a
## guard can give ground without showing its back -- and down with WALK is the
## duck, planted: a fighter folded under a HIGH blade is not going anywhere.
## Without WALK a direction is a run, and the fighter faces where it runs.
func _advance_free(dt: float) -> void:
	var want_x := input.axis_x
	_ducked = grounded and input.down and input.walk
	if _ducked:
		want_x = 0
	var accel := tuning.ground_accel if grounded else tuning.air_accel
	var friction := tuning.ground_friction if grounded else tuning.air_friction
	if want_x != 0:
		var top := tuning.run_speed
		if input.walk:
			if grounded:
				top = tuning.walk_speed
		else:
			facing = want_x
		velocity.x = move_toward(velocity.x, want_x * top, accel * dt)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * dt)
	# Releasing jump on the way up cuts the arc short -- but not before
	# jump_min_hold frames of rise, so a tap is a hop (DuelTuning.jump_min_hold).
	if velocity.y < 0.0 and not input.jump and _cut_lock <= 0:
		velocity.y *= tuning.jump_cut
	_cut_lock = maxi(0, _cut_lock - 1)
	_apply_gravity(dt)


## A dive is a fixed trajectory, not a jump: no gravity on the way down, no
## steering. Landing plants the fighter for the recovery, which is the price of
## the move. Gravity still runs once it is down, because _move() decides
## `grounded` from a collision and a body with no motion collides with nothing.
func _dive(dt: float, through: Vector2) -> void:
	if grounded:
		velocity.x = 0.0
		_apply_gravity(dt)
		if _commit < 0:
			_commit = (
				tuning.divekick_recover if state == State.DIVEKICK else tuning.pound_recover
			)
		else:
			_commit = maxi(0, _commit - 1)
		return
	# A parabola would make the timing unlearnable; a dive is a straight line.
	velocity = through


func _resolve_free_state() -> void:
	if not grounded:
		_enter(State.JUMPING)
	elif _ducked:
		_enter(State.DUCKING)
	elif input.axis_x != 0:
		_enter(State.RUNNING)
	else:
		_enter(State.IDLE)


## --- starting things --------------------------------------------------------

## Returns true when the press was spent on an attack.
##
## A thrust is made standing. Out of a duck the fighter comes up into it, so
## the duck is a dodge and never a stance to stab from: a ducked thrust used to
## keep the 13 px body under a HIGH blade while its own LOW blade killed, and
## two of them met as a double kill instead of a clash.
func _begin_attack() -> bool:
	if blade.is_held():
		_ducked = false
		_enter(State.THRUSTING)
		_sync_shape()
		return true
	# The unarmed sub-machine: a leg sweep from the ground knocks the opponent
	# down, a ground pound from the air finishes one who is already down.
	if grounded:
		_ducked = false
		_enter(State.SWEEP)
		_sync_shape()
		return true
	_commit = -1
	_enter(State.POUND)
	return true


## down + jump: the same commitment on the ground and in the air. A roll on the
## floor, a dive kick off it.
func _begin_commit_down() -> void:
	if grounded:
		_ducked = false
		_enter(State.ROLLING)
		_sync_shape()
		return
	_commit = -1
	_enter(State.DIVEKICK)


func _jump() -> void:
	velocity.y = -tuning.jump_speed
	grounded = false
	_buffer = 0
	_coyote = 0
	_cut_lock = tuning.jump_min_hold
	_ducked = false
	_enter(State.JUMPING)
	_sync_shape()


## Both hands open in front of the chest, for a sword in flight. It stands the
## fighter up out of a duck -- you cannot catch at the chest from a crouch --
## and plants them, so a snatch at nothing is twelve frames standing still in
## front of whatever comes next. DuelCombat._resolve_flight() does the catching.
func _snatch() -> void:
	_ducked = false
	_enter(State.SNATCH)
	_sync_shape()


func _throw() -> void:
	blade.launch(
		tuning.hand_position(position, facing, stance), stance, facing, id, tuning, input.up
	)
	stance = DuelTuning.Stance.MID
	if not replaying:
		blade_thrown.emit(id)


## --- what the combat module does to a fighter -------------------------------

## A clean hit. First and last blood: there is no health anywhere in the duel.
func kill(killer_id: int = -1) -> void:
	if state == State.DEAD:
		return
	_drop_blade()
	velocity = Vector2(-facing * tuning.clash_knockback * 0.5, -tuning.clash_knockback)
	_ducked = false
	_enter(State.DEAD)
	_sync_shape()
	died.emit(id, killer_id)


## The sword is struck out of the hand. The skill ceiling of the whole system:
## see DuelCombat._probe() for the read that earns it.
func disarm(by_id: int = -1) -> void:
	if state == State.DEAD or not blade.is_held():
		return
	_drop_blade()
	_ducked = false
	_enter(State.DISARMED)
	_sync_shape()
	if not replaying:
		disarmed.emit(id, by_id)


## A thrown sword taken out of the air. DuelCombat has already put the record in
## this hand; this is the fighter's half of it. Armed at once, at the height the
## blade came in at, and committed for `catch_settle` frames while the hands
## close on it -- the blade is not up to parry with until they have.
func catch_blade(at_stance: int, thrower_id: int) -> void:
	if state == State.DEAD or not blade.is_held():
		return
	stance = at_stance
	_ducked = false
	_enter(State.CATCH)
	_sync_shape()
	if not replaying:
		caught.emit(id, thrower_id)


## Swept or kicked off the feet. Keeps the sword — losing it as well would make
## one read end the fight, and the spec gives the finisher to the ground pound.
##
## `frames` is how long this knockdown lasts: the sweep's downed_frames by
## default, the kick's shorter kick_downed_frames when DuelCombat says it was
## a kick. It is held in the commitment counter, so it is snapshot state.
func knock_down(from_x: float, frames: int = -1) -> void:
	if state == State.DEAD or state == State.DOWNED:
		return
	velocity = Vector2(_away_from(from_x) * tuning.clash_knockback, -tuning.clash_knockback * 0.4)
	_ducked = false
	_commit = frames if frames > 0 else tuning.downed_frames
	_enter(State.DOWNED)
	_sync_shape()
	if not replaying:
		knocked_down.emit(id)


## Blade on blade: both fighters bounce off, which is applyKnockback(-2.0) in
## the spec's pseudocode. An attack in progress is over — that is what makes a
## held stance worth holding.
func push_back(from_x: float) -> void:
	if state == State.DEAD:
		return
	velocity.x = _away_from(from_x) * tuning.clash_knockback
	if state == State.THRUSTING or state == State.SWEEP:
		_enter_free()
	if not replaying:
		clashed.emit(position)


## --- hitboxes ---------------------------------------------------------------

## The body. AABB, origin at the feet, compressed by a duck and by a roll.
func hurt_rect() -> Rect2:
	if state == State.DEAD:
		return Rect2()
	var h := _height()
	return Rect2(position.x - tuning.body_width * 0.5, position.y - h, tuning.body_width, h)


## The sword, or an empty rect when there is nothing to parry with: no sword,
## tucked into a roll, committed to a dive, or — the important one — in the
## recovery frames of a thrust that missed.
func blade_rect() -> Rect2:
	if not blade.is_held() or not _blade_up():
		return Rect2()
	var reach := tuning.blade_reach if is_attacking() else tuning.blade_rest
	return tuning.blade_rect(position, facing, stance, reach)


## Feet and fists: the dive kick, the leg sweep and the ground pound.
func strike_kind() -> int:
	match state:
		State.DIVEKICK:
			return Strike.KICK if _commit < 0 else Strike.NONE
		State.POUND:
			return Strike.POUND if _commit < 0 else Strike.NONE
		State.SWEEP:
			if state_frame >= tuning.sweep_active_from \
					and state_frame <= tuning.sweep_active_to:
				return Strike.SWEEP
	return Strike.NONE


func strike_rect() -> Rect2:
	var kind := strike_kind()
	if kind == Strike.NONE:
		return Rect2()
	if kind == Strike.POUND:
		# Straight down, under the body: a finisher for something lying there.
		var half := tuning.body_width * 0.5 + 2.0
		return Rect2(position.x - half, position.y - 5.0, half * 2.0, 7.0)
	# A kick and a sweep are both low attacks in front of the body.
	return tuning.blade_rect(position, facing, DuelTuning.Stance.LOW, tuning.sweep_reach)


## Which column of the combat matrix this fighter presents. A ducking, rolling
## or downed fighter has no stance at all — the blade is not up at any height —
## which is exactly what the matrix's fourth column says. A RISING fighter is
## standing and presents its stance, but with no blade up to turn anything
## (blade_rect is empty), so every height cuts it.
func posture() -> int:
	if _ducked or state == State.ROLLING or state == State.DOWNED:
		return DuelTuning.DUCKED
	return stance


func is_armed() -> bool:
	return blade.is_held()


## True only on the opening frames of a snatch, with nothing already in hand.
## The window is a closed interval over state_frame like every other one.
func hands_open() -> bool:
	return (
		state == State.SNATCH and state_frame <= tuning.catch_window and not blade.is_held()
	)


## Where the open hands can take a thrown blade, or an empty rect when they are
## not open. See DuelTuning.catch_rect() for why it stops above LOW.
func catch_rect() -> Rect2:
	if not hands_open():
		return Rect2()
	return tuning.catch_rect(position, facing)


## True only in the frames where the blade is extended and lethal.
func is_attacking() -> bool:
	return state == State.THRUSTING and state_frame <= tuning.thrust_active


## True in the four states that read input: IDLE, RUNNING, JUMPING, DUCKING.
## Everything else is a commitment that has to run out first.
func is_free() -> bool:
	return (
		state == State.IDLE or state == State.RUNNING
		or state == State.JUMPING or state == State.DUCKING
	)


## --- internals --------------------------------------------------------------

func _blade_up() -> bool:
	return is_free() or is_attacking()


func _height() -> float:
	if state == State.ROLLING or state == State.DOWNED:
		return tuning.roll_height
	return tuning.duck_height if _ducked else tuning.body_height


func _away_from(from_x: float) -> int:
	var away := int(signf(position.x - from_x))
	return away if away != 0 else -facing


func _drop_blade() -> void:
	if not blade.is_held():
		return
	blade.drop(tuning.hand_position(position, facing, stance), stance, -facing, tuning)
	stance = DuelTuning.Stance.MID


func _enter(next: State) -> void:
	# DEAD overrides every other state, and respawn_at() is the only way out.
	if state == State.DEAD and next != State.DEAD:
		return
	if state == next:
		return
	state = next
	state_frame = 1
	_sync_shape()


func _enter_free() -> void:
	_enter(State.JUMPING if not grounded else State.IDLE)


## The end of a roll: the body unfolds to standing (or to a duck under a low
## ceiling) for roll_recover frames before the blade is up and the buttons are
## read again. Without it a roll chained into a roll kept a fighter 7 px tall
## for 116 frames in 120, under every HIGH and MID blade there is.
func _rise() -> void:
	if tuning.roll_recover <= 0:
		_leave_roll()
		return
	_ducked = not _can_stand()
	_enter(State.RISING)
	_sync_shape()


## Coming up out of a roll or off the floor under a low ceiling: stand into
## whatever fits. The duel's one piece of forgiveness, and it is geometric
## rather than generous.
func _leave_roll() -> void:
	_ducked = not _can_stand()
	_enter_free()


func _can_stand() -> bool:
	if world == null:
		return true
	var rect := Rect2(
		position.x - tuning.body_width * 0.5, position.y - tuning.body_height,
		tuning.body_width, tuning.body_height
	)
	return not world.rect_hits_solid(rect)


## After the frame's motion: a fighter on the floor may jump for coyote_frames
## more once it leaves it, and a buffered press has one frame less to wait. A
## jump spends both (_jump()), so the coyote window is only ever an edge's.
func _count_jump_windows() -> void:
	if grounded and is_free():
		_coyote = tuning.coyote_frames
	else:
		_coyote = maxi(0, _coyote - 1)
	_buffer = maxi(0, _buffer - 1)


func _apply_gravity(dt: float) -> void:
	# No apex float: the spec asks for high gravity and no floaty moon jumps.
	velocity.y = minf(velocity.y + tuning.gravity * dt, tuning.max_fall_speed)


func _sync_shape() -> void:
	if _shape == null:
		return
	var h := _height()
	var rect := _shape.shape as RectangleShape2D
	if rect == null:
		rect = RectangleShape2D.new()
		_shape.shape = rect
	rect.size = Vector2(tuning.body_width, h)
	_shape.position = Vector2(0.0, -h * 0.5)


## One frame of motion, over move_and_collide() rather than move_and_slide().
##
## This is not an eccentricity, it is the load-bearing line of the netplay
## design, and it is here for the reason docs/netplay.md gives: move_and_slide
## carries state inside the engine that GDScript can neither read nor write,
## and that state survives a snapshot restore. Two bodies handed byte-identical
## state and byte-identical input step to positions thousandths of a pixel
## apart, which is enough to cross a checksum boundary — so a client could
## never reproduce the host's frame, however correct both of them were.
## move_and_collide() has no such memory. The collision mathematics is still
## the engine's; only the bookkeeping between the queries lives here.
func _move(dt: float) -> void:
	grounded = false
	var motion := velocity * dt
	for _slide: int in MAX_SLIDES:
		if motion == Vector2.ZERO:
			return
		var hit := move_and_collide(motion)
		if hit == null:
			return
		var normal := hit.get_normal()
		if normal.dot(up_direction) >= FLOOR_DOT:
			grounded = true
		velocity = velocity.slide(normal)
		motion = hit.get_remainder().slide(normal)
