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
	input.poll()
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
			move_and_slide()
		State.HANG:
			_update_hang()
		State.CLIMB_UP:
			_update_climb_up(delta)
		State.LADDER:
			_update_ladder(delta)
		State.HURT:
			_update_hurt(delta)
		_:
			_update_free(delta)


## --- main locomotion -------------------------------------------------------

func _update_free(delta: float) -> void:
	var grounded := is_on_floor()
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
		_:
			_free_movement(delta, want_x, walking, grounded)

	_apply_gravity(delta)

	# Coyote time plus a buffered press means both a late and an early tap work.
	var can_jump := _coyote > 0.0 and state != State.ATTACK and state != State.CROUCH
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
	move_and_slide()

	if was_airborne and is_on_floor():
		_on_touch_ground(falling_speed)
	_resolve_air_state()


func _free_movement(delta: float, want_x: int, walking: bool, grounded: bool) -> void:
	if grounded and input.just_pressed_attack:
		_enter(State.ATTACK)
		attacked.emit()
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
	var near_apex := absf(velocity.y) < Tuning.APEX_THRESHOLD and not is_on_floor()
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
	if is_on_floor() or state == State.ATTACK or state == State.HURT:
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
	move_and_slide()

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
	move_and_slide()
	if _hurt_timer <= 0.0:
		_enter(State.IDLE if is_on_floor() else State.FALL)


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
