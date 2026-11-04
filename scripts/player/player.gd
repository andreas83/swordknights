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
## A heart came back. Only fired when one actually did: a relic picked up at
## full health heals nothing and says nothing.
signal healed(health: int)
signal died()
## A plunge met the floor instead of a guard: the point is in the stone.
signal plunge_landed()
## Back + SWORD came out as a backstep: the feet push off. The dust, the cloth
## and the camera's dip hang off this, so none of them reads the state machine.
signal backstepped()

## New states go on the end, so a state's number never changes under anything
## that has stored one.
enum State {
	IDLE, WALK, RUN, TURN, CROUCH,
	JUMP, FALL, LAND,
	HANG, CLIMB_UP, LADDER,
	ATTACK, HURT, DEAD,
	AIR_SLASH, PLUNGE, PLUNGE_LAND, PARRY, BACKSTEP,
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
var _attack_buffer: float = 0.0
var _turn_timer: float = 0.0
var _land_timer: float = 0.0
var _hurt_timer: float = 0.0
var _drop_through: float = 0.0
var _climb_from := Vector2.ZERO
var _climb_to := Vector2.ZERO
var _climb_progress: float = 0.0
var _crouched := false
var _ladder_lockout: float = 0.0
## Seconds since the current rise began. The jump cut reads this rather than
## state_time, so an air slash in the middle of a jump does not restart the
## MIN_JUMP_HOLD clock: see _enter().
var _rise_time: float = 0.0
## A parry that turned a cut: the next sword press comes out at once.
var _riposte := false
## Counting down from the stick turning him on the spot: a SWORD press now
## still reads the stick against the facing he turned from. See
## _reads_backstep().
var _about_face: float = 0.0
## Counting down from the start of a backstep; another cannot start until it
## is spent. Tuning.BACKSTEP_REARM says why.
var _backstep_rearm: float = 0.0
## --- the fatal fall --- the feet's height where the fall now being measured
## began, and whether the death this body is down with was a fall's. See
## _note_fall_top() and _fall_to_death().
var _fall_top: float = 0.0
var _fell := false

@onready var _shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_GROUNDED
	up_direction = Vector2.UP
	floor_stop_on_slope = true
	collision_layer = 0
	collision_mask = Tiles.MASK_SOLID | Tiles.MASK_ONE_WAY
	_set_crouched(false)
	# Read at full light under any hour a level is set at (WorldGrade).
	add_to_group(MatchDusk.LIT)


func respawn(at: Vector2) -> void:
	position = at
	velocity = Vector2.ZERO
	state = State.IDLE
	state_time = 0.0
	health = Tuning.MAX_HEALTH
	invulnerable = 0.0
	_coyote = 0.0
	_jump_buffer = 0.0
	_attack_buffer = 0.0
	_ladder_lockout = 0.0
	_riposte = false
	_about_face = 0.0
	_backstep_rearm = 0.0
	_fall_top = at.y
	_fell = false
	_set_crouched(false)


func is_alive() -> bool:
	return state != State.DEAD


## Down, and from a fall: the landing killed him (Tuning.FATAL_FALL_TILES). The
## art lays him out by it and the sound gives the landing its own weight, so
## a fall reads as a fall and not as a wound.
func is_fallen() -> bool:
	return state == State.DEAD and _fell


## How far the feet are below the apex of the fall now being measured, in
## pixels: 0 on the ground, on a ladder, hanging, or still going up.
func fall_height() -> float:
	return maxf(0.0, position.y - _fall_top)


func is_hanging() -> bool:
	return state == State.HANG or state == State.CLIMB_UP


## On a ladder: the camera follows the climb as it follows a body on its feet.
func is_climbing() -> bool:
	return state == State.LADDER


## Body rect in world space, origin at the feet.
func body_rect() -> Rect2:
	var h := _height()
	return Rect2(position.x - Tuning.BODY_WIDTH * 0.5, position.y - h, Tuning.BODY_WIDTH, h)


## Sword hitbox for this frame, or a zero-size rect when not connecting.
##
## The plunge's is its own shape: see _plunge_rect().
##
## The ground swing and the air slash share the live window and the reach;
## they differ only in the band. In the air the blade comes down steeply, so
## its band runs from the chest to just past the feet, which is where a guard
## is when the prince is jumping at him.
func attack_rect() -> Rect2:
	if state == State.PLUNGE:
		return _plunge_rect()
	if state != State.ATTACK and state != State.AIR_SLASH:
		return Rect2()
	var phase := state_time / Tuning.ATTACK_TIME
	if phase < 0.25 or phase > 0.8:
		return Rect2()
	var w := Tuning.ATTACK_REACH
	var half := Tuning.BODY_WIDTH * 0.5
	var x := (position.x + half) if facing > 0 else (position.x - half - w)
	if state == State.AIR_SLASH:
		return Rect2(x, position.y - _height() + 5.0, w, Tuning.AIR_SLASH_HEIGHT)
	return Rect2(x, position.y - _height() + 3.0, w, Tuning.ATTACK_HEIGHT)


## The plunge's point, under the feet, live for the whole drop. As wide as the
## body and a pixel more each side: the point is held in both hands at the
## middle, and a plunge is aimed by where the body is, not by facing.
func _plunge_rect() -> Rect2:
	var half := Tuning.BODY_WIDTH * 0.5 + 1.0
	return Rect2(position.x - half, position.y - 4.0, half * 2.0, Tuning.PLUNGE_REACH + 4.0)


## The blade is moving and drawn in front of the body: the trail follows it.
func is_striking() -> bool:
	return state == State.ATTACK or state == State.AIR_SLASH or state == State.PLUNGE


func is_plunging() -> bool:
	return state == State.PLUNGE


## The parry is up and still inside the window where it turns a cut.
func is_parrying() -> bool:
	return state == State.PARRY and state_time < Tuning.PARRY_ACTIVE


## Whether a cut from a blade at `from_x` is turned this frame: the parry is
## live and the prince is facing the blade. A parry is a sword held up in
## front; a cut from behind goes round it. True also arms the riposte.
func deflect(from_x: float) -> bool:
	if not is_parrying():
		return false
	var toward := int(signf(from_x - position.x))
	if toward != 0 and toward != facing:
		return false
	_riposte = true
	return true


## Somewhere in the backstep, slide or recovery. The camera asks, to hold its
## lead: see GameCamera.
func is_backstepping() -> bool:
	return state == State.BACKSTEP


## Whether a cut from a blade at `from_x` misses this frame because the prince
## is stepping back out from under it: inside BACKSTEP_ACTIVE, and only from
## the way he faces. He is leaning away from the blade in front of him with
## his own across his body; one from behind is the blade he is stepping into.
## Unlike deflect() it arms nothing: the backstep survives a cut, it does not
## open the guard, so there is no riposte to earn.
func evades(from_x: float) -> bool:
	if state != State.BACKSTEP or state_time >= Tuning.BACKSTEP_ACTIVE:
		return false
	var toward := int(signf(from_x - position.x))
	return toward == 0 or toward == facing


## A plunge that found a guard springs back off him, the way a stomp does: it
## is the stomp with the sword in it. It comes out as a jump the player can
## steer, so a second plunge is a decision and not a bounce.
func rebound() -> void:
	velocity.y = -Tuning.JUMP_SPEED * Tuning.STOMP_BOUNCE
	_enter(State.JUMP)


func _physics_process(delta: float) -> void:
	input.poll()
	state_time += delta
	invulnerable = maxf(0.0, invulnerable - delta)
	_jump_buffer = maxf(0.0, _jump_buffer - delta)
	_drop_through = maxf(0.0, _drop_through - delta)
	_attack_buffer = maxf(0.0, _attack_buffer - delta)
	_ladder_lockout = maxf(0.0, _ladder_lockout - delta)
	_about_face = maxf(0.0, _about_face - delta)
	_backstep_rearm = maxf(0.0, _backstep_rearm - delta)
	_rise_time += delta
	if input.just_pressed_jump:
		_jump_buffer = Tuning.JUMP_BUFFER
	if input.just_pressed_attack:
		_attack_buffer = Tuning.ATTACK_BUFFER

	# One-way platforms are a separate physics layer, so dropping through is
	# simply ignoring that layer for a moment.
	if _drop_through > 0.0:
		collision_mask = Tiles.MASK_SOLID
	else:
		collision_mask = Tiles.MASK_SOLID | Tiles.MASK_ONE_WAY

	_note_fall_top()
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
		State.AIR_SLASH:
			# Steered by the same code as a jump: see _steer().
			_steer(delta, want_x, walking, false)
			if state_time >= Tuning.ATTACK_TIME:
				_enter(State.JUMP if velocity.y < 0.0 else State.FALL)
		State.PLUNGE:
			# Committed: no steering, no ledge, straight down until something
			# stops it.
			velocity.x = 0.0
		State.PLUNGE_LAND:
			velocity.x = move_toward(velocity.x, 0.0, Tuning.GROUND_FRICTION * delta)
			if state_time >= Tuning.PLUNGE_RECOVER:
				_enter(State.IDLE if grounded else State.FALL)
		State.PARRY:
			_update_parry(delta, grounded)
		State.BACKSTEP:
			_slide_back(delta)
			if state_time >= Tuning.BACKSTEP_TIME:
				_enter(State.IDLE)
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

	# A ladder caught this frame holds. Without this, gravity and
	# _resolve_air_state() ran on top of the grab and turned it straight back
	# into FALL, so a ladder could only be taken from the floor: one caught in
	# the air let the prince slide down it at 9 px/s and never climb. The
	# reachability proof has always assumed the mid-air catch
	# (LevelReachability._trace offers MODE_LADDER on any frame the body
	# overlaps a ladder), so this makes the player do what the proof claims.
	if state == State.LADDER:
		return

	_apply_gravity(delta)

	# Coyote time plus a buffered press means both a late and an early tap work.
	var can_jump := _coyote > 0.0 and _jump_allowed()
	if can_jump and _jump_buffer > 0.0:
		_jump_buffer = 0.0
		_coyote = 0.0
		velocity.y = -Tuning.JUMP_SPEED
		_enter(State.JUMP)
		jumped.emit()

	# Not before MIN_JUMP_HOLD: a tap, or a buffered press already released by
	# the frame it fires, is a short hop rather than a twitch. An air slash is
	# still the same jump, so letting go cuts it exactly as it would have.
	var cut_allowed := _rise_time >= Tuning.MIN_JUMP_HOLD
	var rising := state == State.JUMP or state == State.AIR_SLASH
	if rising and velocity.y < 0.0 and not input.jump and cut_allowed:
		velocity.y *= Tuning.JUMP_CUT_MULTIPLIER

	if grounded and input.down and input.just_pressed_jump:
		_drop_through = 0.25
		# The press asked for the drop, not a jump: spent here, or it waits
		# in the buffer and coyote time fires it on the next frame, back up
		# through the floor (tests/unit/test_drop_through.gd).
		_jump_buffer = 0.0
		_coyote = 0.0

	var falling_speed := velocity.y
	var was_airborne := not grounded
	_move(delta)

	if was_airborne and is_grounded():
		_on_touch_ground(falling_speed)
	_resolve_air_state()


func _free_movement(delta: float, want_x: int, walking: bool, grounded: bool) -> void:
	# Buffered, like jump: a press from the end of a fall, a turn, a landing or
	# the tail of the last swing comes out here, on the first frame it can.
	if _attack_buffer > 0.0 and _start_sword(delta, want_x, walking, grounded):
		return

	var reaching := (input.up or input.down) and _ladder_lockout <= 0.0
	if reaching and level != null and level.rect_is_climbable(body_rect()):
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

	if want_x != 0:
		if want_x != facing and grounded:
			# On the spot: remember it for BACKSTEP_READ, so a SWORD press a
			# few frames behind the stick can still take it back. A second
			# turn inside that time is a wiggle, and cancels the first.
			_about_face = Tuning.BACKSTEP_READ if _about_face <= 0.0 else 0.0
		facing = want_x
	else:
		_about_face = 0.0
	_steer(delta, want_x, walking, grounded)

	if grounded:
		var speed := absf(velocity.x)
		if speed < 1.0:
			_enter(State.IDLE)
		elif speed <= Tuning.WALK_SPEED + 1.0:
			_enter(State.WALK)
		else:
			_enter(State.RUN)


## The sword button, read with the stick. On the ground it swings, with up held
## raises the parry, and with the stick held back steps back out of a cut; in
## a jump or a fall it slashes there and then, or with down held plunges. Each
## direction points at where its move happens: the parry goes up to meet an
## overhead cut, the plunge goes down, the backstep goes back. Up wins over
## back, because a diagonal held up-and-back is a thumb reaching for the parry
## past a stick that has drifted. False when the sword cannot come out from
## this state, so the press stays buffered.
func _start_sword(delta: float, want_x: int, walking: bool, grounded: bool) -> bool:
	if grounded:
		_attack_buffer = 0.0
		if input.up:
			_enter(State.PARRY)
			return true
		if _reads_backstep(want_x):
			_start_backstep(delta)
			return true
		if input.down and _on_one_way_floor():
			_plunge_through()
			return true
		_enter(State.ATTACK)
		attacked.emit()
		return true
	if state != State.JUMP and state != State.FALL:
		return false
	_attack_buffer = 0.0
	if input.down:
		velocity = Vector2(0.0, maxf(velocity.y, Tuning.MAX_FALL_SPEED))
		_enter(State.PLUNGE)
	else:
		_enter(State.AIR_SLASH)
		# The press frame is an airborne frame like any other: steered, not held.
		_steer(delta, want_x, walking, false)
	attacked.emit()
	return true


## Down + SWORD on a one-way floor: through it, point first. The plunge is
## the move that beats what is under a floor -- a Bastion under a hatch --
## and asking a thumb for down + JUMP and then down + SWORD inside a two-tile
## fall made it a move nobody found (docs/campaign.md, Chapter II, "As
## built"). On stone, down + SWORD is the swing it always was; down + JUMP is
## still the plain drop.
func _plunge_through() -> void:
	_drop_through = 0.25
	_jump_buffer = 0.0
	_coyote = 0.0
	velocity = Vector2(0.0, Tuning.MAX_FALL_SPEED)
	_enter(State.PLUNGE)
	attacked.emit()


## Every cell under the feet is a one-way floor: none of it stone, so there
## is something to plunge through.
func _on_one_way_floor() -> bool:
	if level == null:
		return false
	var half := Tuning.BODY_WIDTH * 0.5
	var row := floori((position.y + 1.0) / TILE)
	var found := false
	for column: int in range(floori((position.x - half) / TILE),
			floori((position.x + half - 0.001) / TILE) + 1):
		var kind := level.kind_at_cell(Vector2i(column, row))
		if kind == Tiles.Kind.SOLID:
			return false
		found = found or kind == Tiles.Kind.PLATFORM
	return found


## Whether this press of SWORD, on the ground, is a backstep: the stick held
## away from the way he faces. Read BEFORE the turn, which is the point -- the
## stick going back is what turns a standing prince, and a backstep that
## turned him first would step back facing away from the blade.
##
## Three cases. The stick went back on this very frame: the turn has not
## happened yet, so the facing is still the old one, and it is a backstep if
## that turn would have been on the spot (standing or walking). The stick went
## back a few frames ago and turned him on the spot: inside BACKSTEP_READ the
## turn is taken back and it is a backstep all the same, because a thumb never
## lands the stick and the button together. The stick went back at a run: that
## turn is planted (TURN), and the press waits out the turn in the buffer and
## swings the new way, as it always has -- a running prince has his weight
## going forward, and a backstep is a move from a stance.
##
## Inside BACKSTEP_REARM none of this applies and the press is whatever it was
## before the backstep existed.
func _reads_backstep(want_x: int) -> bool:
	if want_x == 0 or _backstep_rearm > 0.0:
		return false
	if want_x != facing:
		return absf(velocity.x) <= Tuning.WALK_SPEED
	if _about_face > 0.0:
		facing = -facing
		return true
	return false


func _start_backstep(delta: float) -> void:
	_about_face = 0.0
	_backstep_rearm = Tuning.BACKSTEP_TIME + Tuning.BACKSTEP_REARM
	_enter(State.BACKSTEP)
	_slide_back(delta)
	backstepped.emit()


## One frame of the backstep: Tuning.backstep_speed(), away from the facing,
## and never past the lip of a drop. Facing does not change and nothing is
## steered; the stick has already said what it had to.
func _slide_back(delta: float) -> void:
	var speed := -float(facing) * Tuning.backstep_speed(state_time)
	velocity.x = _careful(speed, delta)


## The careful step's rule, applied to the backstep: the body ends the frame
## with the whole of it over floor and none of it in a hazard, or it stops at
## the lip -- the far edge of the last floor tile -- and goes no further.
##
## That is a decision, not a convenience. The backstep is thrown looking the
## other way, at a blade, and it is fast; one that slid off a ledge would turn
## a dodge into a fall nobody chose. Stopping at the lip also keeps it out of
## the traversal grammar entirely: it can cross no gap of any width, so no
## level can come to depend on it and Tuning's jump numbers stay the only
## horizontal reach there is. A backstep that starts already overhanging a
## lip goes nowhere, and still has its window.
func _careful(speed: float, delta: float) -> float:
	if level == null or speed == 0.0:
		return speed
	var next := position.x + speed * delta
	if _footing(next):
		return speed
	var half := Tuning.BODY_WIDTH * 0.5
	var lip: float
	if speed < 0.0:
		lip = floorf((position.x - half) / TILE) * TILE + half
	else:
		lip = (floorf((position.x + half - 0.001) / TILE) + 1.0) * TILE - half
	if not _footing(lip):
		return 0.0
	return (lip - position.x) / delta


## Whether a standing body with its feet at `x` would be entirely over floor
## (solid or one-way) and clear of every hazard.
func _footing(x: float) -> bool:
	var half := Tuning.BODY_WIDTH * 0.5
	var body := Rect2(x - half, position.y - _height(), Tuning.BODY_WIDTH, _height())
	if level.rect_is_deadly(body):
		return false
	var row := floori((position.y + 1.0) / TILE)
	for column: int in range(floori((x - half) / TILE), floori((x + half - 0.001) / TILE) + 1):
		var kind := level.kind_at_cell(Vector2i(column, row))
		if kind != Tiles.Kind.SOLID and kind != Tiles.Kind.PLATFORM:
			return false
	return true


## Feet planted, blade up. A parry that turned a cut lets the next sword press
## out at once -- the riposte -- instead of waiting out the recovery; one that
## turned nothing waits it out, which is what makes throwing it on sight a
## mistake.
func _update_parry(delta: float, grounded: bool) -> void:
	velocity.x = move_toward(velocity.x, 0.0, Tuning.GROUND_FRICTION * delta)
	if _riposte and _attack_buffer > 0.0:
		_attack_buffer = 0.0
		_enter(State.ATTACK)
		attacked.emit()
	elif state_time >= Tuning.PARRY_TIME:
		_enter(State.IDLE if grounded else State.FALL)


## Horizontal speed toward the stick, or friction toward rest.
##
## Shared by the free states and the air slash on purpose. The slash changes no
## velocity -- no hang at the apex, no brake, no lunge -- so a jump with a
## slash in it traces the same arc, frame for frame, as the same jump without
## (tests/unit/test_air_slash.gd). That is the decision, and two arguments
## made it. A slash that stalled or carried the prince would stretch every gap
## past Tuning.gap_tiles(), which is derived from the plain arc and must stay
## the only derivation. And a slash that braked would drop a swing thrown
## halfway across a gap into the pit: on a phone, SWORD sits next to JUMP.
func _steer(delta: float, want_x: int, walking: bool, grounded: bool) -> void:
	var top_speed := Tuning.WALK_SPEED if walking else Tuning.RUN_SPEED
	var accel := Tuning.GROUND_ACCEL if grounded else Tuning.AIR_ACCEL
	var friction := Tuning.GROUND_FRICTION if grounded else Tuning.AIR_FRICTION
	if want_x != 0:
		velocity.x = move_toward(velocity.x, want_x * top_speed, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)


## Whether a jump may fire from the current state: not out of a swing, a slash,
## a crouch, or any special -- a special is a commitment, and one a jump could
## cancel would have no price. For the backstep there is a second reason: a
## jump out of its slide would carry its speed into the air, and that is a
## longer jump than Tuning.gap_tiles() is derived from.
func _jump_allowed() -> bool:
	match state:
		State.ATTACK, State.AIR_SLASH, State.CROUCH, State.PLUNGE, State.PLUNGE_LAND, \
		State.PARRY, State.BACKSTEP:
			return false
		_:
			return true


func _apply_gravity(delta: float) -> void:
	# Reduced gravity near the apex keeps mid-air steering readable.
	var near_apex := absf(velocity.y) < Tuning.APEX_THRESHOLD and not is_grounded()
	var scale := Tuning.APEX_GRAVITY_SCALE if near_apex else 1.0
	velocity.y = minf(velocity.y + Tuning.GRAVITY * scale * delta, Tuning.MAX_FALL_SPEED)


func _on_touch_ground(impact: float) -> void:
	if state == State.DEAD or state == State.HURT:
		return
	# Before anything a landing can turn into: a plunge, a slash finishing on
	# the feet, a hard landing. Ten tiles kills whatever the body was doing.
	if Tuning.is_fatal_fall(position.y - _fall_top):
		_fall_to_death(impact)
		return
	last_impact = impact
	landed.emit(impact)
	if state == State.PLUNGE:
		# The point meets stone instead of a guard and bites. This replaces
		# LAND: the landing is always hard, and this is its recovery.
		_enter(State.PLUNGE_LAND)
		plunge_landed.emit()
		return
	if state == State.AIR_SLASH and impact < Tuning.SOFT_LAND_SPEED:
		# A slash that lands finishes on the feet: the same swing at the same
		# phase, now planted. Not re-entered, so the clock carries on and Game
		# sees no new swing -- one swing still wounds a guard once. A landing
		# heavy enough to cost recovery takes over instead: the fall's weight
		# wins, as it does for every other state.
		state = State.ATTACK
		return
	if impact >= Tuning.HARD_LAND_SPEED:
		_land_timer = Tuning.LAND_RECOVER_TIME * 1.6
		_enter(State.LAND)
	elif impact >= Tuning.SOFT_LAND_SPEED:
		_land_timer = Tuning.LAND_RECOVER_TIME
		_enter(State.LAND)


## --- the fatal fall ---------------------------------------------------------
##
## Tuning.FATAL_FALL_TILES says why the rule is a height and not a speed. This
## is where the height is measured, from the top of the fall: the body's feet
## on the last frame that began with it held up or going up. Read at the
## start of the frame, before it moves, so the frame that turns a rise into a
## fall leaves the apex where it was, and a warp or a respawn -- a body put
## somewhere at rest -- starts a fall from where it was put.
##
## What resets it, and so does not count toward a fall:
##
## - **The floor**, and a lift with it: the lift's slab is a moving floor
##   (scripts/mechanisms/lift.gd), and the feet on it are held up, so an
##   eleven-tile ride down is no fall. Only the drop after leaving it counts.
##   move_and_slide() leaves a body on a floor at rest vertically -- a
##   slab's motion is the platform's, not the body's velocity -- so the first
##   clause already holds there; is_grounded() is named anyway, because that
##   is the engine's promise and the rule should not lean on it unsaid.
## - **A ladder**, climbed down or caught in mid-air: the rungs hold him, so a
##   long fall caught on one is two short ones, and a long ladder is no fall.
##   This one has to be named: climbing down moves him at LADDER_SPEED.
## - **A ledge grab**: hanging, the hands hold him at rest (_update_hang()
##   zeroes the velocity every frame, which is what resets it), so a grab that
##   catches a fall ends it, and letting go starts another from the hang.
## - **Going up**: a stomp's or a plunge's bounce off a guard is a new arc,
##   so a guard at the foot of a drop breaks the fall. So does a hit's
##   knockback, which always throws him up -- and HURT lasts 0.32 s, too short
##   to fall ten tiles from rest, which is why a landing in HURT (which skips
##   _on_touch_ground) needs no check of its own.
##
## What does not reset it: **the plunge**. It is the same fall at the hardest
## speed the game has, and it kills like one. Exempting it would make down +
## SWORD a way to cancel any fall, so the rule would only ever kill a player
## who had not found the trick -- a rule about knowledge, where the owner's
## is about mistakes -- and the proof, which offers no plunge, would be
## pruning landings any player who knew could take.
##
## Water is not excepted because it does not need to be: it kills on contact
## (Level.rect_is_deadly()), and a body falls into it a frame or more before
## its feet can reach the bed, so a fall into water is a death by water, with
## that one cause. Spikes likewise.
func _note_fall_top() -> void:
	if velocity.y <= 0.0 or is_grounded() or state == State.LADDER:
		_fall_top = position.y


## The landing is the death: one cause, told by the landing itself. The body
## stops where it hit -- no knockback hop, which is a wound's -- and the
## landing beat fires at full weight before `died`, with the state already
## DEAD, so whatever hangs off `landed` (the dust, the camera's settle, the
## thud) can tell this landing from one that is walked away from. `died` is
## the ordinary death: the hold, the wipe and the checkpoint respawn are
## Game's, unchanged.
func _fall_to_death(impact: float) -> void:
	last_impact = impact
	health = 0
	velocity = Vector2.ZERO
	_fell = true
	_set_crouched(false)
	_enter(State.DEAD)
	landed.emit(impact)
	died.emit()


func _resolve_air_state() -> void:
	if is_grounded():
		return
	# A swing or a hit is not interrupted by the arc it happens in, and a slash
	# keeps its hands off ledges: they are holding a sword.
	match state:
		State.ATTACK, State.AIR_SLASH, State.HURT, State.PLUNGE, State.PLUNGE_LAND, \
		State.PARRY:
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

	# Before moving, so the frame the thumb taps JUMP is a leap, not a rung.
	if _jump_buffer > 0.0:
		_leap_off_ladder()
		return

	velocity = Vector2(input.axis_x * Tuning.WALK_SPEED * 0.5, input.axis_y * Tuning.LADDER_SPEED)
	if input.axis_x != 0:
		facing = input.axis_x
	_move(delta)


## Leaves the rungs with a jump: sideways at full stride when a direction is
## held, straight up off the rungs when none is. The sideways leap takes the
## run's speed rather than the ladder's half-walk shuffle, because a jump that
## drifts off a ladder at 20 px/s is still on the ladder when it lands.
##
## Either way the hands are kept off every ladder for LADDER_REGRAB_TIME. A
## ladder jump existed before this, and on a phone it did nothing: the stick
## was still pushed up when JUMP was tapped, and on the very next frame
## _free_movement() saw a vertical input over a ladder and put the prince back
## on it. The lockout is what makes the jump a jump.
func _leap_off_ladder() -> void:
	_jump_buffer = 0.0
	_ladder_lockout = Tuning.LADDER_REGRAB_TIME
	var stride := Tuning.WALK_SPEED if input.walk else Tuning.RUN_SPEED
	velocity = Vector2(input.axis_x * stride, -Tuning.JUMP_SPEED * Tuning.LADDER_JUMP_SCALE)
	if input.axis_x != 0:
		facing = input.axis_x
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


## Thrown back at `push` -- x away from `from_x` -- and staggered for
## `seconds`: a shield's shove, a wall that pushes back. Not damage: no heart,
## no grace after it, no `hurt`, so nothing on the HUD and nothing that lets
## a body walk through the next one. False for a body that is down.
func shove(push: Vector2, from_x: float, seconds: float) -> bool:
	if state == State.DEAD:
		return false
	var away := int(signf(position.x - from_x))
	if away == 0:
		away = -facing
	velocity = Vector2(away * push.x, push.y)
	_set_crouched(false)
	_hurt_timer = seconds
	_enter(State.HURT)
	return true


## Gives back up to `amount` hearts, never past MAX_HEALTH. Returns whether
## anything was restored, so a caller can tell a heal from a pickup at full
## health. A body that is down stays down: healing is not a revival, and the
## respawn is the only way back from DEAD.
func heal(amount: int = 1) -> bool:
	if state == State.DEAD or health >= Tuning.MAX_HEALTH or amount <= 0:
		return false
	health = mini(Tuning.MAX_HEALTH, health + amount)
	healed.emit(health)
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
	# A slash that ends while still rising hands back a jump that has been in
	# the air all along, so the jump-cut clock carries on rather than starting
	# again; anything else entering JUMP is a new rise.
	if next == State.JUMP and state != State.AIR_SLASH:
		_rise_time = 0.0
	if next == State.PARRY:
		_riposte = false
	state = next
	state_time = 0.0


## --- movement --------------------------------------------------------------

## Whether the feet are on something. The art and the camera ask this rather
## than is_on_floor(), so a body that does its own moving can answer for itself
## (the duel fighter, scripts/duel/fighter.gd, does).
func is_grounded() -> bool:
	return is_on_floor()


## One frame of motion. The adventure is not simulated over a network, so the
## engine's slide loop is fine here; the duel fighter runs its own over
## move_and_collide(), for the reason docs/netplay.md gives.
func _move(_delta: float) -> void:
	move_and_slide()
