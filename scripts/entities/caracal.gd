class_name Caracal
extends Foe
## The King's hunting cat: crouches, pounces to where the prince stood, and
## skids. The foe the backstep is for (docs/campaign.md, "The Caracal").
##
## ## One threat, told once
##
## Like the sentinel it is harmless to touch and dangerous in one state: its
## claws, live for the POUNCE and CLAW_LINGER frames after it lands. It cannot
## pounce except out of a CROUCH, and the crouch is the telegraph -- 27 frames
## through warn(), so LONGER WARNINGS stretches it -- with the body flattened,
## the rear wiggling, the eyes glinting and a hiss. The leap goes to where the
## prince stood when the crouch ended, at most POUNCE_TILES away, 24 px high,
## over POUNCE_TIME. Then SKID: it lands, skids 8 px and shakes its head for
## SKID_TIME, longer than the sentinel's opening.
##
## ## Why the backstep beats it
##
## It lands with its nose at the near edge of where the prince stood, so its
## claws reach CLAW_REACH into that spot. A prince who stayed is raked; the
## backstep slides 22.75 px, leaving his front 18 px short of the claws. In
## the air the claws reach a standing prince only in the leap's last two
## frames, so a backstep thrown any time before that beats it.
## Thrown any time from the end of the crouch to two frames before the landing
## (about 28 frames) the slide carries him out; thrown late, evades() covers
## the claws for its first 15 frames anyway. The claws stay where it landed
## for their lingering frames, so the skid cannot carry them on into him. And
## the backstep's 27 frames are over before the skid's 40: step in and cut.
## A swing meets it in the air too -- the sword's band reaches a body 14 px
## out, ten before its claws reach him -- and a jump clears it. The parry does
## nothing: its danger has no `parry`, because a parry turns blades, not
## bodies, so it comes in under the raised guard.
##
## ## A terrain foe
##
## It never pounces at a target over a hole or a hazard, nor more than a tile
## up. Prowling, it treats crumbling stone as the end of its beat like any
## walker; stalking the prince it is light enough to walk it -- it has no
## weight (has_weight()), so no plate or lift counts it either -- but its
## push-off and its landing break a slab outright (CrumblingStone.
## break_under()), so a cat that crouches on crumbling stone falls through it.
## A cat that falls out of the level is down, as if cut down.
##
## ## The doves
##
## With no prince on its floor it hunts the doves (scripts/entities/
## dove_flock.gd): stalks a settled flock, crouches, pounces -- and they are
## up as it leaves the ground, so it lands on nothing and skids. That is the
## lesson shown safely first: the whole move, on something else.
##
## ## It acts only on screen
##
## Every range here is a maximum. The cat stalks, crouches and pounces only
## while the camera shows it (on_screen, read from the viewport each step), so
## a cat twelve tiles off on a narrow phone waits to be seen.
##
## Everything runs in _physics_process off tick(), which takes `grounded` and
## needs no physics world; CaracalArt poses the figure from `state`,
## `state_time`, `facing` and `velocity`.

## The crouch began: the warning.
signal crouched()
## It left the ground.
signal pounced()
## It came down, and the opening began.
signal landed()

enum State { PROWL, LOOK, STALK, CROUCH, POUNCE, SKID, FALL, DYING }

const WALK_SPEED := 40.0
const GRAVITY := 900.0
const MAX_FALL := 360.0
const BODY := Vector2(16.0, 9.0)
const MAX_HEALTH := 1

const LOOK_TIME := 0.5
## The telegraph: Patrol.WINDUP_TIME, read through crouch_time().
const CROUCH_TIME := Patrol.WINDUP_TIME
const POUNCE_TIME := 0.5
const POUNCE_HEIGHT := 24.0
const POUNCE_TILES := 5
## Lands, skids, shakes its head: the opening. Longer than RECOVER_TIME.
const SKID_TIME := 40.0 / 60.0
const SKID_DISTANCE := 8.0
## Claws stay live this long after the landing, where it landed.
const CLAW_LINGER := 4.0 / 60.0
const CLAW_REACH := 4.0
const DEATH_TIME := 1.0
## The prince counts as on its floor within this of its feet.
const SAME_FLOOR := 16.0
const STALK_TILES := 12
## Never pounces at a target more than this above its feet.
const MAX_RISE := 16.0

var facing: int = -1
var health: int = MAX_HEALTH
var state: State = State.PROWL
var state_time: float = 0.0
## Whether the camera shows it: written each step from the viewport, and by a
## test that steps tick() by hand.
var on_screen := true
## Where the pounce goes: set through the crouch, fixed as it leaves.
var target := Vector2.ZERO
## The flock it is after, when it is hunting doves rather than the prince.
var quarry: DoveFlock = null

var _claws := Rect2()
var _landed_at := 0.0
var _fall_cued := false


func _ready() -> void:
	super()
	motion_mode = CharacterBody2D.MOTION_MODE_GROUNDED
	up_direction = Vector2.UP
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = BODY
	shape.shape = rect
	shape.position = Vector2(0.0, -BODY.y * 0.5)
	add_child(shape)
	if get_node_or_null("Art") == null:
		var art := CaracalArt.new()
		art.name = "Art"
		add_child(art)


## --- the contract -----------------------------------------------------------

func bounds() -> Rect2:
	return Rect2(global_position - Vector2(BODY.x * 0.5, BODY.y), BODY)


func is_alive() -> bool:
	return state != State.DYING


func has_weight() -> bool:
	return false


func is_dangerous() -> bool:
	return claw_rect().size != Vector2.ZERO


func is_engaged() -> bool:
	return state == State.CROUCH or state == State.POUNCE or state == State.SKID


## Its claws while they are live: the body and CLAW_REACH past its nose in the
## air, and where it landed for CLAW_LINGER after. Empty otherwise.
func claw_rect() -> Rect2:
	match state:
		State.POUNCE:
			var body := bounds()
			if facing > 0:
				return Rect2(body.position, body.size + Vector2(CLAW_REACH, 0.0))
			return Rect2(body.position - Vector2(CLAW_REACH, 0.0),
				body.size + Vector2(CLAW_REACH, 0.0))
		State.SKID:
			if state_time < CLAW_LINGER:
				return _claws
	return Rect2()


## Its claws: let by by a backstep, never turned by a parry.
func dangers() -> Array[FoeDanger]:
	var claws := FoeDanger.make(claw_rect(), global_position.x)
	claws.on_landed = _raked
	var out: Array[FoeDanger] = [claws]
	return out


## The claws found him: it springs back off him and the claws are spent. Were
## it to fly on and land where he stood, his knockback would drop him on its
## back -- a free stomp for being caught.
func _raked(_dealt: bool) -> void:
	_claws = Rect2()
	velocity = Vector2(-facing * 70.0, -110.0)
	_enter(State.FALL)


func hit(from_x: float) -> bool:
	if not is_alive():
		return false
	health -= 1
	var away := signf(global_position.x - from_x)
	velocity = Vector2((away if away != 0.0 else 1.0) * 110.0, -120.0)
	_enter(State.DYING)
	cue.emit(&"yowl", {})
	defeated.emit()
	return true


## The crouch, through the assist.
func crouch_time() -> float:
	return warn(CROUCH_TIME)


## --- the step -----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	on_screen = _in_view()
	tick(delta, is_on_floor())
	move_and_slide()
	if is_on_wall() and state == State.PROWL:
		_enter(State.LOOK)
	if state == State.POUNCE and state_time > 0.05 and is_on_floor():
		_land()
	if state == State.DYING and state_time >= DEATH_TIME:
		queue_free()
	elif level != null and global_position.y > level.world_size().y + 32.0:
		if is_alive():
			_enter(State.DYING)
			defeated.emit()
		queue_free()


## One frame of decision. Takes `grounded` rather than asking the body, so a
## test can step it with no physics world.
func tick(delta: float, grounded: bool) -> void:
	state_time += delta
	var gravity := _pounce_gravity() if state == State.POUNCE else GRAVITY
	velocity.y = minf(velocity.y + gravity * delta, MAX_FALL)
	match state:
		State.PROWL:
			velocity.x = facing * WALK_SPEED
			if grounded and _hunt():
				return
			if _beat_ends(grounded, false):
				_enter(State.LOOK)
				velocity.x = 0.0
		State.LOOK:
			velocity.x = 0.0
			if grounded and _hunt():
				return
			if state_time >= LOOK_TIME:
				facing = -facing
				_enter(State.PROWL)
		State.STALK:
			if not grounded:
				return
			if not _hunt():
				_enter(State.PROWL)
			elif state == State.STALK:
				# At a gap it waits, facing him: a cat does not jump to stalk.
				velocity.x = 0.0 if _beat_ends(grounded, true) else facing * WALK_SPEED
		State.CROUCH:
			velocity.x = 0.0
			_aim()
			if state_time >= crouch_time():
				_pounce(grounded)
		State.POUNCE:
			# Still in the air long after it meant to land: it went over a
			# drop, and it is falling now, claws or no.
			if state_time >= POUNCE_TIME * 2.0:
				_enter(State.FALL)
		State.SKID:
			# Dig in and slide to a stop: SKID_DISTANCE in about a fifth of
			# a second, then the head shake.
			var slide := 2.0 * SKID_DISTANCE / 0.2
			velocity.x = facing * maxf(0.0, slide * (1.0 - state_time / 0.2))
			if state_time >= SKID_TIME:
				_enter(State.STALK if _sees_prince() else State.PROWL)
		State.FALL:
			velocity.x *= 0.9
			if not _fall_cued:
				_fall_cued = true
				cue.emit(&"yowl", {"pitch": 1.25, "volume_db": -4.0})
			if grounded and state_time > 0.1:
				_enter(State.SKID)
				_claws = Rect2()
				state_time = CLAW_LINGER
		State.DYING:
			velocity.x *= 0.86


## Picks what to hunt this frame and acts on it. True when it committed to a
## crouch or a stalk; false leaves it prowling.
func _hunt() -> bool:
	if not on_screen:
		return false
	if _sees_prince():
		quarry = null
		var feet := _prince_feet()
		_face(feet.x)
		if _in_reach(feet) and _can_land(feet):
			_crouch(feet)
			return true
		if state != State.STALK:
			_enter(State.STALK)
		return true
	var flock := _nearest_flock()
	if flock == null:
		return false
	quarry = flock
	_face(flock.spot().x)
	if _in_reach(flock.spot()):
		_crouch(flock.spot())
		return true
	if state != State.STALK:
		_enter(State.STALK)
	return true


func _crouch(at: Vector2) -> void:
	target = at
	velocity.x = 0.0
	_enter(State.CROUCH)
	crouched.emit()
	cue.emit(&"cloth", {"pitch": 1.6, "volume_db": -10.0})
	cue.emit(&"hiss", {})


## Through the crouch it keeps its eyes on what it will leap at.
func _aim() -> void:
	if quarry != null:
		if quarry.is_settled():
			target = quarry.spot()
		return
	if target_rect.size == Vector2.ZERO:
		return
	var feet := _prince_feet()
	if absf(feet.y - global_position.y) <= SAME_FLOOR and _can_land(feet):
		_face(feet.x)
		target = feet


func _pounce(grounded: bool) -> void:
	var reach := POUNCE_TILES * Level.TILE + BODY.x * 0.5
	target.x = clampf(target.x, global_position.x - reach, global_position.x + reach)
	if quarry != null:
		quarry.startle(global_position.x)
	if grounded and _break_under_feet():
		# No purchase: the slab goes instead of the cat.
		_enter(State.FALL)
		velocity = Vector2.ZERO
		return
	var flight := POUNCE_TIME
	# Its nose comes down at his near edge, so the claws reach CLAW_REACH
	# into where he stood: a prince who stays is raked, one who backstepped
	# is not, and the claws touch him only in the leap's last two frames.
	var land_x := target.x - facing * (BODY.x + Tuning.BODY_WIDTH) * 0.5
	velocity.x = (land_x - global_position.x) / flight
	var dy := target.y - global_position.y
	velocity.y = (dy - 0.5 * _pounce_gravity() * flight * flight) / flight
	_enter(State.POUNCE)
	pounced.emit()
	cue.emit(&"jump", {"pitch": 1.5})


func _land() -> void:
	_claws = claw_rect()
	_landed_at = global_position.x
	_enter(State.SKID)
	landed.emit()
	cue.emit(&"land_soft", {"pitch": 1.4})
	cue.emit(&"step_run", {"pitch": 1.3})
	if _break_under_feet():
		_enter(State.FALL)
		velocity = Vector2.ZERO


## Breaks every crumbling slab under its feet, fore and hind: a push-off or
## a landing comes down on all four. True when any broke.
func _break_under_feet() -> bool:
	var broke := false
	for side: float in [-0.4, 0.4]:
		var foot := global_position + Vector2(BODY.x * side, 2.0)
		broke = CrumblingStone.break_under(level, foot) or broke
	return broke


## Gravity through the leap: what makes a level pounce peak POUNCE_HEIGHT up
## at half of POUNCE_TIME.
static func _pounce_gravity() -> float:
	return 8.0 * POUNCE_HEIGHT / (POUNCE_TIME * POUNCE_TIME)


## --- what it can see ----------------------------------------------------------

func _prince_feet() -> Vector2:
	return Vector2(target_rect.get_center().x, target_rect.end.y)


## The prince on its floor, within STALK_TILES.
func _sees_prince() -> bool:
	if target_rect.size == Vector2.ZERO:
		return false
	var feet := _prince_feet()
	return absf(feet.y - global_position.y) <= SAME_FLOOR \
		and absf(feet.x - global_position.x) <= STALK_TILES * Level.TILE


## Within POUNCE_TILES in front of its nose: close enough to leap at.
## Measured from the nose, not the middle, so a cat that stalked onto a run
## of crumbling stone to get in reach is on it with all four feet.
func _in_reach(at: Vector2) -> bool:
	var ahead := (at.x - global_position.x) * facing - BODY.x * 0.5
	return ahead > 0.0 and ahead <= POUNCE_TILES * Level.TILE


## Floor under `feet`, no hazard in the body there, and not more than a tile
## up: somewhere a cat would land.
func _can_land(feet: Vector2) -> bool:
	if level == null:
		return true
	if feet.y < global_position.y - MAX_RISE:
		return false
	var under := level.kind_at_world(feet + Vector2(0.0, 2.0))
	if under != Tiles.Kind.SOLID and under != Tiles.Kind.PLATFORM:
		return false
	return not level.rect_is_deadly(Rect2(feet - Vector2(BODY.x * 0.5, BODY.y), BODY))


func _nearest_flock() -> DoveFlock:
	if not is_inside_tree():
		return null
	var best: DoveFlock = null
	var best_d := INF
	for node: Node in get_tree().get_nodes_in_group(DoveFlock.GROUP):
		var flock := node as DoveFlock
		if flock == null or not flock.is_settled() or flock.level != level:
			continue
		var at := flock.spot()
		var d := absf(at.x - global_position.x)
		if absf(at.y - global_position.y) <= SAME_FLOOR and d <= STALK_TILES * Level.TILE \
				and d < best_d:
			best = flock
			best_d = d
	return best


func _face(x: float) -> void:
	var toward := int(signf(x - global_position.x))
	if toward != 0:
		facing = toward


## A wall ahead, or the floor running out. Crumbling stone runs out a
## prowling cat's beat but not a stalking one's.
func _beat_ends(grounded: bool, trusting: bool) -> bool:
	if level == null or not grounded:
		return false
	var ahead_x := global_position.x + (BODY.x * 0.5 + 2.0) * facing
	var wall := level.looks_solid_at(Vector2(ahead_x, global_position.y - 4.0))
	var below := Vector2(ahead_x, global_position.y + 2.0)
	var kind := level.kind_at_world(below)
	var ground := kind == Tiles.Kind.SOLID or kind == Tiles.Kind.PLATFORM
	if ground and not trusting and CrumblingStone.gives_way(level, below):
		ground = false
	return wall or not ground


func _in_view() -> bool:
	var viewport := get_viewport()
	if viewport == null:
		return true
	var view := viewport.get_canvas_transform().affine_inverse() * viewport.get_visible_rect()
	return view.intersects(bounds())


func _enter(next: State) -> void:
	state = next
	state_time = 0.0
