class_name Player
extends CharacterBody2D
## The prince: a deterministic state machine on top of a CharacterBody2D.
##
## Every transition lives in one match block so the whole moveset reads in one
## screen. The node origin sits at the character's FEET, which makes spawning,
## ledge snapping and drawing all read directly off `position`.
##
## Nothing here touches rendering — the state, facing and `state_time` are the
## only things the art node reads. All movement runs in _physics_process, which
## Godot steps at a fixed 60 Hz, so jump arcs are identical on every device and
## the simulation stays suitable for lockstep netplay.

signal jumped()
signal landed(impact_speed: float)
signal grabbed_ledge()
signal attacked()
signal hurt(remaining_health: int)
signal died()

enum State {
	IDLE, WALK, RUN, TURN, CROUCH,
	JUMP, FALL, LAND,
	HANG, CLIMB_UP, LADDER,
	ATTACK, HURT, DEAD,
	## --- duel (additive) --- appended so no existing ordinal shifts.
	GUARD, STAGGER,
}

const TILE := 16.0

## Set by the scene that spawns the player; required for ledge and hazard probes.
var level: Level

var state: State = State.IDLE
var state_time: float = 0.0
var facing: int = 1
var health: int = Tuning.MAX_HEALTH
var invulnerable: float = 0.0
var last_impact: float = 0.0

## Input is read through this indirection so a replay, an AI or a network peer
## can drive the character with the exact same code path as a local player.
var input: PlayerInput = LocalInput.new()

var _coyote: float = 0.0
var _jump_buffer: float = 0.0
var _turn_timer: float = 0.0
var _land_timer: float = 0.0
var _hurt_timer: float = 0.0
var _drop_through: float = 0.0
var _climb_from := Vector2.ZERO
var _climb_to := Vector2.ZERO
var _climb_progress: float = 0.0
var _crouched := false

## --- duel (additive) ------------------------------------------------------
##
## Three opt-in fields. All three are inert unless something sets them, so the
## adventure mode behaves exactly as before.
##
## `duel_driven`  — the owner steps the character itself by calling simulate();
##                  _physics_process becomes a no-op. The duel needs this so one
##                  frame is a function it calls, not something the engine does
##                  behind its back (and so a mispredicted frame can be replayed).
## `guard_enabled`— unlocks the GUARD and STAGGER states and the block button.
## `kill_on_lethal_hit` — a duel is first-blood: one clean cut ends the round,
##                  rather than taking one of three hearts.
var duel_driven := false
var guard_enabled := false
var kill_on_lethal_hit := false

## How long the guard has been raised, which is what separates a parry (caught
## it on the way in) from a plain block (standing there holding it).
var guard_time: float = 0.0
var _stagger_timer: float = 0.0
## Whether the feet are on something, as this file worked it out rather than as
## the engine remembers it. Only meaningful while duel_driven; see _move().
var _duel_grounded := false

@onready var _shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_GROUNDED
	up_direction = Vector2.UP
	floor_stop_on_slope = true
	collision_layer = 0
	collision_mask = Tiles.MASK_SOLID | Tiles.MASK_ONE_WAY
	_set_crouched(false)


func respawn(at: Vector2) -> void:
	position = at
	velocity = Vector2.ZERO
	state = State.IDLE
	state_time = 0.0
	health = Tuning.MAX_HEALTH
	invulnerable = 0.0
	_coyote = 0.0
	_jump_buffer = 0.0
	_set_crouched(false)


func is_alive() -> bool:
	return state != State.DEAD


func is_hanging() -> bool:
	return state == State.HANG or state == State.CLIMB_UP


## Body rect in world space, origin at the feet.
func body_rect() -> Rect2:
	var h := _height()
	return Rect2(position.x - Tuning.BODY_WIDTH * 0.5, position.y - h, Tuning.BODY_WIDTH, h)


## Sword hitbox for this frame, or a zero-size rect when not connecting.
func attack_rect() -> Rect2:
	if state != State.ATTACK:
		return Rect2()
	var phase := state_time / Tuning.ATTACK_TIME
	if phase < 0.25 or phase > 0.8:
		return Rect2()
	var w := Tuning.ATTACK_REACH
	var half := Tuning.BODY_WIDTH * 0.5
	var x := (position.x + half) if facing > 0 else (position.x - half - w)
	return Rect2(x, position.y - _height() + 3.0, w, Tuning.ATTACK_HEIGHT)


func _physics_process(delta: float) -> void:
	# --- duel (additive) --- a duel calls simulate() itself, exactly once per
	# frame, and may call it again to replay a frame it mispredicted. The engine
	# must not also be stepping the character behind its back.
	if duel_driven:
		return
	input.poll()
	simulate(delta)


## One frame of character simulation.
##
## --- duel (additive) --- this is the former body of _physics_process, moved
## out verbatim so a caller other than the engine can advance the character.
## Everything below this line is as it was, apart from the two new states.
func simulate(delta: float) -> void:
	state_time += delta
	invulnerable = maxf(0.0, invulnerable - delta)
	_jump_buffer = maxf(0.0, _jump_buffer - delta)
	_drop_through = maxf(0.0, _drop_through - delta)
	if input.just_pressed_jump:
		_jump_buffer = Tuning.JUMP_BUFFER

	# One-way platforms are a separate physics layer, so dropping through is
	# simply ignoring that layer for a moment.
	if _drop_through > 0.0:
		collision_mask = Tiles.MASK_SOLID
	else:
		collision_mask = Tiles.MASK_SOLID | Tiles.MASK_ONE_WAY

	match state:
		State.DEAD:
			_apply_gravity(delta)
			_move(delta)
		State.HANG:
			_update_hang()
		State.CLIMB_UP:
			_update_climb_up(delta)
		State.LADDER:
			_update_ladder(delta)
		State.HURT:
			_update_hurt(delta)
		State.STAGGER: # --- duel (additive) ---
			_update_stagger(delta)
		_:
			_update_free(delta)


## --- main locomotion -------------------------------------------------------

func _update_free(delta: float) -> void:
	var grounded := is_grounded()
	var want_x := input.axis_x
	var walking := input.walk

	if grounded:
		_coyote = Tuning.COYOTE_TIME
	else:
		_coyote = maxf(0.0, _coyote - delta)

	match state:
		State.ATTACK:
			velocity.x = move_toward(velocity.x, 0.0, Tuning.GROUND_FRICTION * delta)
			if state_time >= Tuning.ATTACK_TIME:
				_enter(State.IDLE if grounded else State.FALL)
		State.LAND:
			_land_timer -= delta
			velocity.x = move_toward(velocity.x, 0.0, Tuning.GROUND_FRICTION * delta)
			if _land_timer <= 0.0:
				_enter(State.IDLE)
		State.TURN:
			_turn_timer -= delta
			velocity.x = move_toward(velocity.x, 0.0, Tuning.GROUND_FRICTION * 1.4 * delta)
			if _turn_timer <= 0.0:
				facing = -facing
				if want_x == 0:
					_enter(State.IDLE)
				else:
					_enter(State.WALK if walking else State.RUN)
		State.GUARD: # --- duel (additive) ---
			_update_guard(delta, want_x, grounded)
		_:
			_free_movement(delta, want_x, walking, grounded)

	_apply_gravity(delta)

	# Coyote time plus a buffered press means both a late and an early tap work.
	var can_jump := (
		_coyote > 0.0 and state != State.ATTACK and state != State.CROUCH
		and state != State.GUARD # --- duel (additive) --- the guard roots you
	)
	if can_jump and _jump_buffer > 0.0:
		_jump_buffer = 0.0
		_coyote = 0.0
		velocity.y = -Tuning.JUMP_SPEED
		_enter(State.JUMP)
		jumped.emit()

	if state == State.JUMP and velocity.y < 0.0 and not input.jump:
		velocity.y *= Tuning.JUMP_CUT_MULTIPLIER

	if grounded and input.down and input.just_pressed_jump:
		_drop_through = 0.25

	var falling_speed := velocity.y
	var was_airborne := not grounded
	_move(delta)

	if was_airborne and is_grounded():
		_on_touch_ground(falling_speed)
	_resolve_air_state()


func _free_movement(delta: float, want_x: int, walking: bool, grounded: bool) -> void:
	if grounded and input.just_pressed_attack:
		_enter(State.ATTACK)
		attacked.emit()
		return

	# --- duel (additive) --- raising the guard is a commitment: it roots the
	# character, which is what makes choosing to block a real decision.
	if guard_enabled and grounded and input.guard:
		guard_time = 0.0
		velocity.x = move_toward(velocity.x, 0.0, Tuning.GROUND_FRICTION * delta)
		_set_crouched(false)
		_enter(State.GUARD)
		return

	if (input.up or input.down) and level != null and level.rect_is_climbable(body_rect()):
		velocity = Vector2.ZERO
		_enter(State.LADDER)
		return

	var crouching := grounded and input.down and want_x == 0
	_set_crouched(crouching)
	if crouching:
		velocity.x = move_toward(velocity.x, 0.0, Tuning.GROUND_FRICTION * delta)
		_enter(State.CROUCH)
		return

	# Turning around has a wind-up on the ground, mirroring the original's weight.
	if grounded and want_x != 0 and want_x != facing and absf(velocity.x) > Tuning.WALK_SPEED:
		_turn_timer = Tuning.TURN_TIME
		_enter(State.TURN)
		return

	var top_speed := Tuning.WALK_SPEED if walking else Tuning.RUN_SPEED
	var accel := Tuning.GROUND_ACCEL if grounded else Tuning.AIR_ACCEL
	var friction := Tuning.GROUND_FRICTION if grounded else Tuning.AIR_FRICTION

	if want_x != 0:
		facing = want_x
		velocity.x = move_toward(velocity.x, want_x * top_speed, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)

	if grounded:
		var speed := absf(velocity.x)
		if speed < 1.0:
			_enter(State.IDLE)
		elif speed <= Tuning.WALK_SPEED + 1.0:
			_enter(State.WALK)
		else:
			_enter(State.RUN)


func _apply_gravity(delta: float) -> void:
	# Reduced gravity near the apex keeps mid-air steering readable.
	var near_apex := absf(velocity.y) < Tuning.APEX_THRESHOLD and not is_grounded()
	var scale := Tuning.APEX_GRAVITY_SCALE if near_apex else 1.0
	velocity.y = minf(velocity.y + Tuning.GRAVITY * scale * delta, Tuning.MAX_FALL_SPEED)


func _on_touch_ground(impact: float) -> void:
	if state == State.DEAD or state == State.HURT:
		return
	last_impact = impact
	landed.emit(impact)
	if impact >= Tuning.HARD_LAND_SPEED:
		_land_timer = Tuning.LAND_RECOVER_TIME * 1.6
		_enter(State.LAND)
	elif impact >= Tuning.SOFT_LAND_SPEED:
		_land_timer = Tuning.LAND_RECOVER_TIME
		_enter(State.LAND)


func _resolve_air_state() -> void:
	if is_grounded() or state == State.ATTACK or state == State.HURT:
		return
	if velocity.y > 0.0:
		if state != State.FALL:
			_enter(State.FALL)
		_try_grab_ledge()
	elif state != State.JUMP:
		_enter(State.JUMP)


## --- ledges ----------------------------------------------------------------

## Looks for a corner at hand height in the facing direction. The player has to
## be falling (not too fast) and not pushing down, which keeps grabs
## intentional rather than sticky. Because it is a geometry probe and not a
## trigger volume, every corner in every level is grabbable without authoring.
func _try_grab_ledge() -> void:
	if level == null or velocity.y > Tuning.MAX_GRAB_FALL_SPEED or input.down:
		return

	var direction := input.axis_x if input.axis_x != 0 else facing
	var half := Tuning.BODY_WIDTH * 0.5
	var hand_x := position.x + (half + Tuning.GRAB_REACH) * direction
	var top_y := position.y - _height()
	var cell := level.cell_of(Vector2(hand_x, top_y + Tuning.GRAB_PROBE_Y))

	# A grabbable ledge is a solid tile with nothing solid directly on top.
	if not level.is_solid_cell(cell) or level.is_solid_cell(cell + Vector2i.UP):
		return

	var ledge_top := float(cell.y) * TILE
	var hang_feet_y := ledge_top - Tuning.GRAB_PROBE_Y + _height()
	var hang_x := cell.x * TILE - half if direction > 0 else (cell.x + 1) * TILE + half

	var hang_rect := Rect2(hang_x - half, hang_feet_y - _height(), Tuning.BODY_WIDTH, _height())
	if level.rect_hits_solid(hang_rect):
		return

	position = Vector2(hang_x, hang_feet_y)
	velocity = Vector2.ZERO
	facing = direction
	_enter(State.HANG)
	grabbed_ledge.emit()


func _update_hang() -> void:
	velocity = Vector2.ZERO
	if state_time < Tuning.HANG_HOLD_TIME:
		return

	if input.down:
		velocity.y = 20.0
		_enter(State.FALL)
		return

	if not (input.up or _jump_buffer > 0.0):
		return
	_jump_buffer = 0.0

	var ledge_top := position.y - _height() + Tuning.GRAB_PROBE_Y
	var target := Vector2(position.x + TILE * 0.5 * facing, ledge_top)

	var stand_rect := Rect2(
		target.x - Tuning.BODY_WIDTH * 0.5, target.y - _height(),
		Tuning.BODY_WIDTH, _height()
	)
	if level != null and level.rect_hits_solid(stand_rect):
		_enter(State.FALL) # no room to stand up — let go rather than clip in
		return

	_climb_from = position
	_climb_to = target
	_climb_progress = 0.0
	_enter(State.CLIMB_UP)


func _update_climb_up(delta: float) -> void:
	_climb_progress = clampf(_climb_progress + delta / Tuning.CLIMB_UP_TIME, 0.0, 1.0)
	# Up first, then across: the classic mantle arc.
	var vertical := minf(1.0, _climb_progress * 1.6)
	var horizontal := maxf(0.0, (_climb_progress - 0.45) / 0.55)
	position = Vector2(
		lerpf(_climb_from.x, _climb_to.x, horizontal),
		lerpf(_climb_from.y, _climb_to.y, vertical)
	)
	if _climb_progress >= 1.0:
		velocity = Vector2.ZERO
		_enter(State.IDLE)


## --- ladders ---------------------------------------------------------------

func _update_ladder(delta: float) -> void:
	if level == null or not level.rect_is_climbable(body_rect()):
		_enter(State.FALL)
		return

	velocity = Vector2(input.axis_x * Tuning.WALK_SPEED * 0.5, input.axis_y * Tuning.LADDER_SPEED)
	if input.axis_x != 0:
		facing = input.axis_x
	_move(delta)

	if _jump_buffer > 0.0:
		_jump_buffer = 0.0
		velocity.y = -Tuning.JUMP_SPEED * 0.82
		_enter(State.JUMP)
		jumped.emit()


## --- damage ----------------------------------------------------------------

func _update_hurt(delta: float) -> void:
	_hurt_timer -= delta
	velocity.x = move_toward(velocity.x, 0.0, Tuning.GROUND_FRICTION * 0.5 * delta)
	_apply_gravity(delta)
	_move(delta)
	if _hurt_timer <= 0.0:
		_enter(State.IDLE if is_grounded() else State.FALL)


func damage(amount: int = 1, from_x: float = NAN) -> bool:
	if invulnerable > 0.0 or state == State.DEAD:
		return false

	health = maxi(0, health - amount)
	invulnerable = Tuning.INVULNERABLE_TIME
	var away := -facing if is_nan(from_x) else int(signf(position.x - from_x))
	if away == 0:
		away = 1
	velocity = Vector2(away * Tuning.KNOCKBACK_X, -Tuning.KNOCKBACK_Y)
	_set_crouched(false)

	if health <= 0:
		_enter(State.DEAD)
		died.emit()
	else:
		_hurt_timer = 0.32
		_enter(State.HURT)
		hurt.emit(health)
	return true


func kill() -> void:
	if state == State.DEAD:
		return
	health = 0
	velocity = Vector2(0.0, -Tuning.KNOCKBACK_Y * 0.6)
	_enter(State.DEAD)
	died.emit()


## --- internals -------------------------------------------------------------

func _height() -> float:
	return Tuning.CROUCH_HEIGHT if _crouched else Tuning.BODY_HEIGHT


func _set_crouched(crouched: bool) -> void:
	if _crouched == crouched and _shape != null and _shape.shape != null:
		return
	# Standing up into a ceiling is not allowed.
	if not crouched and _crouched and level != null:
		var stand := Rect2(
			position.x - Tuning.BODY_WIDTH * 0.5, position.y - Tuning.BODY_HEIGHT,
			Tuning.BODY_WIDTH, Tuning.BODY_HEIGHT
		)
		if level.rect_hits_solid(stand):
			return

	_crouched = crouched
	if _shape == null:
		return
	var h := _height()
	var rect := _shape.shape as RectangleShape2D
	if rect == null:
		rect = RectangleShape2D.new()
		_shape.shape = rect
	rect.size = Vector2(Tuning.BODY_WIDTH, h)
	_shape.position = Vector2(0.0, -h * 0.5)


func _enter(next: State) -> void:
	if state == next:
		return
	state = next
	state_time = 0.0


## --- movement --------------------------------------------------------------

## How many surfaces one frame of motion may slide along before giving up.
const DUEL_MAX_SLIDES := 4
## cos(45 degrees) — the steepest normal still counted as floor, matching
## CharacterBody2D's default floor_max_angle.
const DUEL_FLOOR_DOT := 0.7071067811865476


## Whether the feet are on something.
##
## Ask this rather than is_on_floor(). For the adventure the two are the same
## thing; in a duel they are not, because a duel does its own moving and the
## engine's flag is never set — see _move().
func is_grounded() -> bool:
	return _duel_grounded if duel_driven else is_on_floor()


## One frame of motion.
##
## The adventure path is unchanged: move_and_slide(), as it always was.
##
## --- duel (additive) --- A duel does not use move_and_slide, and this is the
## load-bearing line of the whole netplay design.
##
## move_and_slide() is not a function of the body's transform, velocity and
## shape. It carries state inside the engine that GDScript can neither read nor
## write, and that state outlives a snapshot restore. Two bodies handed
## byte-identical state and byte-identical input therefore land a few
## thousandths of a pixel apart — measured at 0.0036 px, which is enough to
## cross a checksum boundary. A client then cannot reproduce the host's frame
## no matter how correct both of them are, and the desync detector rightly says
## so. That is not a detector that needs loosening; it is a simulation that
## needs to stop depending on something it cannot see.
##
## move_and_collide() has no such memory: the same query, from the same
## transform, with the same motion, returns bit-identical travel, remainder,
## normal and depth on any body with any history. Running the slide loop here
## rather than letting the engine run it makes a duel frame a true function of
## the duel's state — which is what scripts/net/session.gd claims and what
## tests/duel_determinism_test.gd asserts.
##
## The collision maths is still the engine's, so the character moves and feels
## exactly as it did; only the bookkeeping between the queries moves in here.
func _move(delta: float) -> void:
	if not duel_driven:
		move_and_slide()
		return

	_duel_grounded = false
	var motion := velocity * delta
	for _slide: int in DUEL_MAX_SLIDES:
		if motion == Vector2.ZERO:
			return
		var hit := move_and_collide(motion)
		if hit == null:
			return
		var normal := hit.get_normal()
		if normal.dot(up_direction) >= DUEL_FLOOR_DOT:
			_duel_grounded = true
		# Slide what is left of the frame's motion along the surface, and take
		# the same component out of the velocity, which is what
		# move_and_slide does between its own iterations.
		velocity = velocity.slide(normal)
		motion = hit.get_remainder().slide(normal)


## --- duel (additive) ======================================================
##
## Everything below this line exists for scripts/duel and is inert in the
## adventure mode: nothing above calls into it, and the three opt-in flags
## near the top default to false.

signal blocked(parried: bool)
signal staggered()

## Press the guard within this window of the sword landing and it is a parry
## rather than a block — a much longer opening on the attacker.
const PARRY_WINDOW := 0.13
const BLOCK_STAGGER := 0.30
const PARRY_STAGGER := 0.62
const CLASH_STAGGER := 0.24
const BLOCK_PUSH := 44.0
const STAGGER_PUSH := 96.0


func is_guarding() -> bool:
	return state == State.GUARD


func is_staggered() -> bool:
	return state == State.STAGGER


## The sword is only dangerous in the middle of the swing; attack_rect() already
## returns an empty rect outside that window, so this is just a readable alias.
func is_swinging() -> bool:
	return state == State.ATTACK and attack_rect().size.x > 0.0


## True when the raised guard faces `from_x` — you cannot block what is behind you.
func guard_covers(from_x: float) -> bool:
	if not is_guarding():
		return false
	var toward := signf(from_x - position.x)
	return is_zero_approx(toward) or int(toward) == facing


## Knocked out of the swing. Used for a blocked hit, a parry and a clash.
func stagger(duration: float, from_x: float) -> void:
	var away := -facing if is_nan(from_x) else int(signf(position.x - from_x))
	if away == 0:
		away = -facing
	_stagger_timer = duration
	velocity = Vector2(away * STAGGER_PUSH, -STAGGER_PUSH * 0.28)
	_set_crouched(false)
	_enter(State.STAGGER)
	staggered.emit()


## Shoved back for holding the line, but still standing and still guarding.
func absorb_block(from_x: float, parried: bool) -> void:
	var away := int(signf(position.x - from_x))
	if away == 0:
		away = -facing
	velocity.x = away * BLOCK_PUSH
	blocked.emit(parried)


## A hit that was not blocked. First blood in a duel, one of three hearts
## everywhere else.
func take_lethal_hit(from_x: float) -> bool:
	if not kill_on_lethal_hit:
		return damage(1, from_x)
	if state == State.DEAD:
		return false
	health = 0
	var away := int(signf(position.x - from_x))
	if away == 0:
		away = -facing
	velocity = Vector2(away * Tuning.KNOCKBACK_X, -Tuning.KNOCKBACK_Y)
	_set_crouched(false)
	_enter(State.DEAD)
	died.emit()
	return true


## Puts the character back on its mark with every timer cleared. respawn() does
## most of it; this also clears the duel-only state and the input edge memory,
## so a fresh round cannot inherit a half-finished swing or a held button.
func duel_reset(at: Vector2, face: int) -> void:
	respawn(at)
	facing = face
	health = 1 if kill_on_lethal_hit else Tuning.MAX_HEALTH
	last_impact = 0.0
	guard_time = 0.0
	_stagger_timer = 0.0
	_turn_timer = 0.0
	_land_timer = 0.0
	_hurt_timer = 0.0
	_drop_through = 0.0
	_climb_from = Vector2.ZERO
	_climb_to = Vector2.ZERO
	_climb_progress = 0.0
	_duel_force_crouched(false)
	input.clear()


func _update_guard(delta: float, want_x: int, grounded: bool) -> void:
	guard_time += delta
	velocity.x = move_toward(velocity.x, 0.0, Tuning.GROUND_FRICTION * delta)
	# Turning on the spot is allowed: facing the attack is the whole skill.
	if want_x != 0:
		facing = want_x
	if input.just_pressed_attack:
		_enter(State.ATTACK)
		attacked.emit()
	elif not input.guard or not grounded:
		_enter(State.IDLE if grounded else State.FALL)


func _update_stagger(delta: float) -> void:
	_stagger_timer -= delta
	velocity.x = move_toward(velocity.x, 0.0, Tuning.GROUND_FRICTION * 0.7 * delta)
	_apply_gravity(delta)
	_move(delta)
	if _stagger_timer <= 0.0:
		_enter(State.IDLE if is_grounded() else State.FALL)


func _duel_force_crouched(crouched: bool) -> void:
	# _set_crouched refuses to stand up into a ceiling and short-circuits when
	# nothing changed. Restoring a saved frame has to be unconditional.
	_crouched = crouched
	if _shape == null:
		return
	var h := _height()
	var rect := _shape.shape as RectangleShape2D
	if rect == null:
		rect = RectangleShape2D.new()
		_shape.shape = rect
	rect.size = Vector2(Tuning.BODY_WIDTH, h)
	_shape.position = Vector2(0.0, -h * 0.5)


## --- duel state, for snapshots and for replaying a mispredicted frame -----
##
## Everything a frame of simulate() reads has to be in here, including the
## private timers and the input's press-edge memory — otherwise a replayed
## frame would re-fire a press that already happened, or forget a coyote
## window, and the client would never converge on the host.
##
## 26 values, written in a fixed order. Keep write and read in step.
##
## They are doubles, and the wire carries doubles, because half of them are
## GDScript floats (64-bit) that the simulation compares against thresholds:
## state_time against the length of a swing, _land_timer against zero, and so
## on. Rounding those to 32 bits can move a transition by a whole frame, which
## in a duel is the difference between a sword landing and missing. Positions
## and velocities are Vector2, already 32-bit, and lose nothing either way —
## they are written as doubles only so the layout stays uniform and the cost of
## getting it wrong stays zero. See docs/netplay.md for what it costs.

const DUEL_STATE_FLOATS := 26


func duel_write_state(into: PackedFloat64Array, at: int) -> void:
	into[at + 0] = position.x
	into[at + 1] = position.y
	into[at + 2] = velocity.x
	into[at + 3] = velocity.y
	into[at + 4] = float(state)
	into[at + 5] = state_time
	into[at + 6] = float(facing)
	into[at + 7] = float(health)
	into[at + 8] = invulnerable
	into[at + 9] = last_impact
	into[at + 10] = _coyote
	into[at + 11] = _jump_buffer
	into[at + 12] = _turn_timer
	into[at + 13] = _land_timer
	into[at + 14] = _hurt_timer
	into[at + 15] = _drop_through
	into[at + 16] = _climb_from.x
	into[at + 17] = _climb_from.y
	into[at + 18] = _climb_to.x
	into[at + 19] = _climb_to.y
	into[at + 20] = _climb_progress
	into[at + 21] = 1.0 if _crouched else 0.0
	into[at + 22] = guard_time
	into[at + 23] = _stagger_timer
	into[at + 24] = float(input.previous_bits())
	# Whether the feet were on something. simulate() reads this before it
	# moves, so it has to travel with the snapshot.
	into[at + 25] = 1.0 if is_grounded() else 0.0


func duel_read_state(from: PackedFloat64Array, at: int) -> void:
	position = Vector2(from[at + 0], from[at + 1])
	velocity = Vector2(from[at + 2], from[at + 3])
	state = int(from[at + 4]) as State
	state_time = from[at + 5]
	facing = int(from[at + 6])
	health = int(from[at + 7])
	invulnerable = from[at + 8]
	last_impact = from[at + 9]
	_coyote = from[at + 10]
	_jump_buffer = from[at + 11]
	_turn_timer = from[at + 12]
	_land_timer = from[at + 13]
	_hurt_timer = from[at + 14]
	_drop_through = from[at + 15]
	_climb_from = Vector2(from[at + 16], from[at + 17])
	_climb_to = Vector2(from[at + 18], from[at + 19])
	_climb_progress = from[at + 20]
	_duel_force_crouched(from[at + 21] > 0.5)
	guard_time = from[at + 22]
	_stagger_timer = from[at + 23]
	input.restore_previous_bits(int(from[at + 24]))
	_duel_grounded = from[at + 25] > 0.5

