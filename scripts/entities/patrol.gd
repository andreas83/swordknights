class_name Patrol
extends CharacterBody2D
## A palace sentinel: walks its terrace, turns at walls and drops, and cuts at
## the prince when he comes within a blade's length.
##
## ## Danger has exactly one look
##
## The guard is harmless to touch. It hurts in one state only, STRIKE, and it
## cannot reach STRIKE except through WINDUP: a 27-frame overhead raise with the
## blade glinting and the eye slit burning (scripts/entities/patrol_art.gd).
## That is the whole fairness argument. A player who reads the raise can back
## off a tile, or step in and cut first -- the prince's sword is live six
## frames into a swing, so it lands long before the raise finishes, and a hit
## during the raise staggers the guard out of it. A player who does not read it
## takes the cut and learns what the raise means.
##
## Before this, a guard damaged on contact, which made it a moving spike: no
## warning, nothing to read, and a body that hurts to touch cannot be fenced
## with. The stomp still works the way it did, because a stomp is the
## prince's attack, not the guard's.
##
## ## What the reach numbers are measured against
##
## The guard stops and raises when the prince's body is ENGAGE_GAP or closer
## in front of its own. Its cut reaches REACH past its front. The prince's
## sword reaches Tuning.ATTACK_REACH past his. So at the moment the raise
## starts the two are already inside each other's reach, and the duel is
## decided by who acts on the raise. `tests/unit/test_patrol.gd` pins those
## relationships, so retuning the prince cannot quietly make guards unfair.
##
## ## Simulation and drawing
##
## Everything here runs in `_physics_process` off `tick()`, which is the whole
## decision for one frame and needs no physics world, so the tests drive it
## directly. Nothing here draws; PatrolArt reads `state`, `state_time`,
## `facing` and `velocity` and poses a figure from them, the way PlayerArt
## dresses the Player.

signal defeated()
## The raise began: the one moment a player is warned.
signal alerted()
## The blade came down.
signal struck()
## A hit that did not kill.
signal staggered()

enum State { WALK, LOOK, WINDUP, STRIKE, RECOVER, STAGGER, DYING }

const SPEED := 26.0
const GRAVITY := 900.0
const MAX_FALL := 320.0
const BODY := Vector2(10.0, 20.0)
const MAX_HEALTH := 2

## Paused at the end of its beat before turning back: a guard that turns
## instantly is a ping-pong ball, one that stops and looks is somebody.
const LOOK_TIME := 0.5
## The telegraph. 27 frames: longer than a human reaction, so it is a warning,
## short enough that standing still in front of it is a decision.
const WINDUP_TIME := 0.45
## The cut is live for this long.
const STRIKE_TIME := 0.15
## The opening after a cut. Blade down, body bent: the time to answer it.
const RECOVER_TIME := 0.55
const STAGGER_TIME := 0.4
## How long the body stays after the killing blow, collapsing and flickering
## out, before the node goes. Nothing about it is dangerous or hittable.
const DEATH_TIME := 1.3

## Gap between the guard's front and the prince's body at which it stops and
## raises. A little inside REACH, so a prince standing still at the moment the
## raise starts is cut.
const ENGAGE_GAP := 14.0
## How far past its front the cut reaches.
const REACH := 17.0
## The cut's vertical band, measured up from the feet.
const CUT_LOW := 3.0
const CUT_HIGH := 18.0
## How close behind it the prince must be before the guard hears him and
## turns. Smaller than ENGAGE_GAP: sneaking up is allowed, standing on its
## heels is not.
const HEAR_GAP := 6.0
## How far apart two feet can be and still count as the same floor.
const SAME_FLOOR := 10.0

var level: Level
var facing: int = -1
var health: int = MAX_HEALTH
var state: State = State.WALK
var state_time: float = 0.0

## The prince's body this frame, or an empty rect when there is nobody to
## fight. Game writes it every physics frame; the guard never reaches for the
## player itself, which is what lets a test hand it a rectangle.
var target_rect := Rect2()


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_GROUNDED
	up_direction = Vector2.UP
	collision_layer = 0
	collision_mask = Tiles.MASK_SOLID | Tiles.MASK_ONE_WAY

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = BODY
	shape.shape = rect
	shape.position = Vector2(0.0, -BODY.y * 0.5)
	add_child(shape)

	if get_node_or_null("Art") == null:
		var art := PatrolArt.new()
		art.name = "Art"
		add_child(art)


func bounds() -> Rect2:
	return Rect2(global_position - Vector2(BODY.x * 0.5, BODY.y), BODY)


## The blade's rect while it is live, or a zero rect. The only way this guard
## can hurt anybody.
func strike_rect() -> Rect2:
	if state != State.STRIKE:
		return Rect2()
	var front := global_position.x + BODY.x * 0.5 * facing
	var x := front if facing > 0 else front - REACH
	return Rect2(x, global_position.y - CUT_HIGH, REACH, CUT_HIGH - CUT_LOW)


func is_dangerous() -> bool:
	return state == State.STRIKE


## False from the killing blow on: a falling body is scenery.
func is_alive() -> bool:
	return state != State.DYING


## Returns true when this hit killed it.
func hit(from_x: float) -> bool:
	if not is_alive():
		return false
	health -= 1
	var away := signf(global_position.x - from_x)
	velocity = Vector2((away if away != 0.0 else 1.0) * 120.0, -110.0)
	if health <= 0:
		_enter(State.DYING)
		defeated.emit()
		return true
	_enter(State.STAGGER)
	staggered.emit()
	return false


func _physics_process(delta: float) -> void:
	tick(delta, is_on_floor())
	move_and_slide()
	if is_on_wall() and state == State.WALK:
		facing = -facing

	if state == State.DYING and state_time >= DEATH_TIME:
		queue_free()
	elif level != null and global_position.y > level.world_size().y + 64.0:
		queue_free()


## One frame of decision: state, facing and velocity. Takes `grounded` rather
## than asking the physics body, so it runs without a physics world.
func tick(delta: float, grounded: bool) -> void:
	state_time += delta
	velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)

	match state:
		State.WALK:
			velocity.x = facing * SPEED
			if grounded and _engage():
				return
			if _beat_ends(grounded):
				_enter(State.LOOK)
				velocity.x = 0.0
		State.LOOK:
			velocity.x = 0.0
			if grounded and _engage():
				return
			if state_time >= LOOK_TIME:
				facing = -facing
				_enter(State.WALK)
		State.WINDUP:
			velocity.x = 0.0
			if state_time >= WINDUP_TIME:
				_enter(State.STRIKE)
				struck.emit()
		State.STRIKE:
			# A half step into the cut: weight behind it, not a lunge that
			# carries the guard off its ledge.
			velocity.x = facing * SPEED * 0.6
			if state_time >= STRIKE_TIME:
				_enter(State.RECOVER)
		State.RECOVER:
			velocity.x = 0.0
			if state_time >= RECOVER_TIME:
				_enter(State.WALK)
		State.STAGGER:
			velocity.x *= 0.88
			if state_time >= STAGGER_TIME:
				_enter(State.WALK)
		State.DYING:
			velocity.x *= 0.86


## Turns toward a prince on its heels, and raises on one in front. True when
## the guard committed to the raise this frame.
func _engage() -> bool:
	if target_rect.size == Vector2.ZERO:
		return false
	var feet := target_rect.position.y + target_rect.size.y
	if absf(feet - global_position.y) > SAME_FLOOR:
		return false
	var gap := gap_to(target_rect)
	if gap <= ENGAGE_GAP and gap > -BODY.x - target_rect.size.x:
		_enter(State.WINDUP)
		velocity.x = 0.0
		alerted.emit()
		return true
	var behind := gap_behind(target_rect)
	if behind <= HEAR_GAP and behind > -BODY.x - target_rect.size.x and state == State.WALK:
		_enter(State.LOOK)
		# Already most of the way round: hearing someone is not a stroll.
		state_time = LOOK_TIME * 0.6
	return false


## Distance from the guard's front edge to the near side of `rect`, along the
## way it faces. Negative once they overlap.
func gap_to(rect: Rect2) -> float:
	var front := global_position.x + BODY.x * 0.5 * facing
	if facing > 0:
		return rect.position.x - front
	return front - (rect.position.x + rect.size.x)


func gap_behind(rect: Rect2) -> float:
	var back := global_position.x - BODY.x * 0.5 * facing
	if facing > 0:
		return back - (rect.position.x + rect.size.x)
	return rect.position.x - back


## A wall ahead, or the floor running out under the next step.
func _beat_ends(grounded: bool) -> bool:
	if level == null or not grounded:
		return false
	var ahead_x := global_position.x + (BODY.x * 0.5 + 2.0) * facing
	var wall := level.is_solid_at(Vector2(ahead_x, global_position.y - 4.0))
	var ground_kind := level.kind_at_world(Vector2(ahead_x, global_position.y + 2.0))
	var ground := ground_kind == Tiles.Kind.SOLID or ground_kind == Tiles.Kind.PLATFORM
	return wall or not ground


func _enter(next: State) -> void:
	state = next
	state_time = 0.0
