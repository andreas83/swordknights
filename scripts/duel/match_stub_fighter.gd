class_name StubFighter
extends Node2D
## A placeholder fighter, so the match layer can be built and tested before the
## real one exists. DELETE THIS FILE at merge.
##
## It answers the agreed interface and nothing more: run, jump, one thrust that
## kills, death, and the hazards. There is no stance, no clash, no disarm and no
## sword throw — those belong to the fighter and to combat, which are being
## written in parallel, and the match has no opinion about any of them. What the
## match needs from a fighter is that it moves, that it occasionally dies, and
## that it can be serialised exactly; this provides those three things and is
## honest about being a stand-in for everything else.
##
## It is deliberately NOT a CharacterBody2D. It collides against the ASCII strip
## directly, which means the match's tests do not need a physics space and run
## in milliseconds. The real Fighter will be a body and will query the tilemap
## the way scripts/player/player.gd does; nothing in the match cares which,
## because the whole seam is scripts/duel/match_seat.gd.

signal died(victim_id: int, killer_id: int)

enum State { IDLE = 0, THRUST = 1, DEAD = 2 }

const HALF_WIDTH := Tuning.BODY_WIDTH * 0.5
const HEIGHT := Tuning.BODY_HEIGHT
const REACH := Tuning.ATTACK_REACH
## Frames 1-4 of a twelve-frame thrust are the active blade, per the spec's
## combat section. Expressed in seconds because that is what simulate() takes.
const THRUST_TIME := 12.0 / 60.0
const BLADE_FROM := 1.0 / 60.0
const BLADE_TO := 4.0 / 60.0

## Nine float64s. A whole number of doubles, as the checksum requires.
const STATE_DOUBLES := 9

var input := PlayerInput.new()
var strip: ZoneStrip

var id: int = 0
var velocity := Vector2.ZERO
var facing: int = 1
var state: State = State.IDLE
var state_time: float = 0.0
var grounded := false

var _opponent: StubFighter


## --- the interface ---------------------------------------------------------

func setup(at_id: int, _profile: Resource) -> void:
	id = at_id
	# The real fighter is handed its opponent by combat. This one finds its
	# sibling, so the match never has to know that a stub needs one.
	var other := get_parent().get_node_or_null("Fighter%d" % (1 - at_id))
	_opponent = other as StubFighter


func respawn_at(at: Vector2, face: int) -> void:
	position = at
	velocity = Vector2.ZERO
	facing = face if face != 0 else 1
	state = State.IDLE
	state_time = 0.0
	grounded = false
	input.clear()


func is_alive() -> bool:
	return state != State.DEAD


static func state_bytes() -> int:
	return STATE_DOUBLES * 8


func write_state(into: PackedByteArray, at: int) -> void:
	into.encode_double(at + 0, position.x)
	into.encode_double(at + 8, position.y)
	into.encode_double(at + 16, velocity.x)
	into.encode_double(at + 24, velocity.y)
	into.encode_double(at + 32, float(state))
	into.encode_double(at + 40, state_time)
	into.encode_double(at + 48, float(facing))
	into.encode_double(at + 56, 1.0 if grounded else 0.0)
	# The press-edge memory, for the same reason Player carries it: a replayed
	# frame must not re-fire a thrust that already happened.
	into.encode_double(at + 64, float(input.previous_bits()))


func read_state(from: PackedByteArray, at: int) -> void:
	position = Vector2(from.decode_double(at + 0), from.decode_double(at + 8))
	velocity = Vector2(from.decode_double(at + 16), from.decode_double(at + 24))
	state = int(from.decode_double(at + 32)) as State
	state_time = from.decode_double(at + 40)
	facing = int(from.decode_double(at + 48))
	grounded = from.decode_double(at + 56) > 0.5
	input.restore_previous_bits(int(from.decode_double(at + 64)))


## One frame, on whatever input was last applied. The match calls this; the
## engine does not — _physics_process is deliberately absent.
func simulate(delta: float) -> void:
	state_time += delta

	if state == State.DEAD:
		_fall(delta)
		return

	if state == State.THRUST:
		_thrust(delta)
	else:
		_run(delta)

	_fall(delta)

	if strip != null and strip.rect_is_deadly(body_rect()):
		slay(-1)


## --- the fighter -----------------------------------------------------------

func body_rect() -> Rect2:
	return Rect2(position.x - HALF_WIDTH, position.y - HEIGHT,
		Tuning.BODY_WIDTH, HEIGHT)


func _run(delta: float) -> void:
	var want := input.axis_x
	if want != 0:
		facing = want
	var target := float(want) * Tuning.RUN_SPEED
	var rate := Tuning.GROUND_ACCEL if want != 0 else Tuning.GROUND_FRICTION
	velocity.x = move_toward(velocity.x, target, rate * delta)

	if input.just_pressed_jump and grounded:
		velocity.y = -Tuning.JUMP_SPEED
		grounded = false
	if input.just_pressed_attack:
		state = State.THRUST
		state_time = 0.0


func _thrust(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, Tuning.GROUND_FRICTION * delta)
	if state_time >= BLADE_FROM and state_time <= BLADE_TO:
		_swing()
	if state_time >= THRUST_TIME:
		state = State.IDLE
		state_time = 0.0


func _swing() -> void:
	if _opponent == null or not _opponent.is_alive():
		return
	var blade := Rect2(
		position.x + (HALF_WIDTH if facing > 0 else -HALF_WIDTH - REACH),
		position.y - HEIGHT + 3.0, REACH, Tuning.ATTACK_HEIGHT
	)
	if blade.intersects(_opponent.body_rect()):
		_opponent.slay(id)


## Kills this fighter and credits `killer_id` (-1 for a hazard).
##
## Not part of the agreed interface: the match never calls it. The tests and the
## attract demo do, because a scripted kill is the only way to drive the match
## layer before combat exists.
func slay(killer: int) -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	state_time = 0.0
	velocity = Vector2(float(-facing) * Tuning.KNOCKBACK_X, -Tuning.KNOCKBACK_Y)
	died.emit(id, killer)


## --- moving against the strip ----------------------------------------------

func _fall(delta: float) -> void:
	# The apex is softened exactly as the real character's is, so the zones'
	# vertical grammar — a 2-tile rise is a plain hop — holds for this stand-in
	# too. Without it the stub jumps 35 px and a 32 px step is a coin toss.
	var gravity := Tuning.GRAVITY
	if absf(velocity.y) < Tuning.APEX_THRESHOLD:
		gravity *= Tuning.APEX_GRAVITY_SCALE
	velocity.y = minf(velocity.y + gravity * delta, Tuning.MAX_FALL_SPEED)
	if strip == null:
		position += velocity * delta
		return

	position.x += velocity.x * delta
	if strip.rect_hits_solid(body_rect()):
		_unstick_x()

	var was := position.y
	position.y += velocity.y * delta
	grounded = false
	if velocity.y >= 0.0:
		_land(was)
	elif strip.rect_hits_solid(body_rect()):
		position.y = float(floori((position.y - HEIGHT) / ZoneStrip.TILE) + 1) \
			* ZoneStrip.TILE + HEIGHT
		velocity.y = 0.0


func _unstick_x() -> void:
	if velocity.x > 0.0:
		var edge := position.x + HALF_WIDTH
		position.x = float(floori(edge / ZoneStrip.TILE)) * ZoneStrip.TILE - HALF_WIDTH
	elif velocity.x < 0.0:
		var edge := position.x - HALF_WIDTH
		position.x = float(floori(edge / ZoneStrip.TILE) + 1) * ZoneStrip.TILE + HALF_WIDTH
	velocity.x = 0.0


## Lands on solid ground, and on a one-way platform whose top was crossed this
## frame — which is how the stepping stone over the cistern works.
func _land(was_y: float) -> void:
	if strip.rect_hits_solid(body_rect()):
		position.y = float(floori(position.y / ZoneStrip.TILE)) * ZoneStrip.TILE
		velocity.y = 0.0
		grounded = true
		return

	var column := floori(position.x / ZoneStrip.TILE)
	var row := floori(position.y / ZoneStrip.TILE)
	if strip.kind_at(column, row) != Tiles.Kind.PLATFORM:
		return
	var top := float(row) * ZoneStrip.TILE
	if was_y <= top and position.y >= top:
		position.y = top
		velocity.y = 0.0
		grounded = true
