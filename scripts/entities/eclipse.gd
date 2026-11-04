class_name Eclipse
extends Foe
## The King in his eclipse regalia: the finale of The Last Light, fought in the
## Vault of the kept sun (docs/campaign.md, "The Eclipse -- the boss").
##
## ## A final exam, one lesson a phase
##
## Each phase is a foe's lesson from an earlier chapter, and only that lesson
## wounds him. Everything else rings off his bronze -- Game's clang, the
## sentinel's own "no" -- so a wrong answer is heard at once and costs nothing
## but time, and the right one is the only way forward:
##
## | Phase | Lesson | What wounds him | Wounds |
## | --- | --- | --- | --- |
## | SHIELD | the Bastion | a plunge on his crown from a gallery, as he pauses under its lip | 3 |
## | BURNING | the Glassbearer | his own sunbolt, parried back into his chest | 3 |
## | ECLIPSE | the Caracal | a cut while he skids, after a pounce the backstep let by | 2 |
## | FINALE | the parry | the whole kept sun, parried back into the disc | 1 |
##
## The escalation is in what each phase adds to the one before: phase 1 has
## one threat, told by the shove's draw; phase 2 keeps the shove for a prince
## who stands at his feet and throws bolts at everyone else, each faster
## volley than the last; phase 3 puts the vault out and comes for you; the
## finale is one blow, told twice as long as anything else in the game,
## because it is the only one that is the whole fight at once.
##
## ## Fair on a phone
##
## The foe contract's rules hold to the letter (docs/campaign.md, "What every
## foe shares"): harmless to touch, dangerous only in a live window, and every
## live window behind a tell read through warn() -- the shove's draw, a bolt's
## charge, the crouch before a pounce are each Patrol.WINDUP_TIME, and the
## finale's gather is twice it. The plunge window under a gallery's lip is
## read through warn() too: it is short, and it is the phase. One cause per
## death: one danger at a time, never a bolt and a shove on the same frame,
## because he does not charge at a prince within a shove of him.
##
## Phase 2's spacing is the bible's arithmetic made a constant: bolts are
## BOLT_SPACING apart, which is the parry's whole cycle plus its window plus
## six frames, so a press that would have been a riposte has ended before the
## next bolt needs a fresh parry. Under the assist the charge stretches and
## the rest between bolts does not, so the spacing only grows.
##
## A prince standing on a gallery is out of every attack from phase 2 on --
## the bolts and the beam fly at chest height along the floor, and the pounce
## never reaches up a tile. That is on purpose: a breather that wins nothing.
##
## ## Won phases stay won
##
## A death respawns the level, and a respawn puts every foe back whole -- right
## for a guard, wrong for a King you have already beaten twice (an owner
## decision). So the phase he is in is written to his post's memory
## (EntitySite.memory) the moment the last one is won, and a King placed again
## reads it: he waits under the kept sun, and when the prince drops back into
## the vault he rises into the start of that phase. The gallery hearts are
## relics, and relics are taken once.
##
## ## The light
##
## He is lit (the foe contract puts him in the grade's lit group), and his
## third phase is the one runtime darkness in the game: `darkness()` says how
## far the vault is put out, and the art passes it to the world's grade
## (WorldGrade.dim). Everything that must be read is lifted out of it.
##
## ## Simulation and drawing
##
## Everything here is `tick()`, one frame of decision on the fixed step that
## needs no physics world, so the tests step it directly; he walks a flat floor
## read from the level once, at placement (`arena_of()`), and never asks the
## physics engine where he is. Nothing here draws: EclipseArt poses him from
## `phase`, `state`, `state_time` and `facing`.

## A phase began: after the rise out of the kept sun's light.
signal phase_begun(phase: int)
## The last wound of a phase landed.
signal phase_won(phase: int)
## A wound that did not end the phase.
signal staggered()

enum Phase { SHIELD, BURNING, ECLIPSE, FINALE }

enum State {
	AWAIT, ## under the kept sun, the disc up to it, until the prince comes down
	RISE, ## back to the sun and turned on the prince: a phase's first beat
	WALK, ## phase 1: end to end along the floor
	PAUSE, ## phase 1: under a gallery's lip, before he turns
	DRAW, ## the shove's tell
	SHOVE, ## the shove, live
	RECOVER, ## after a shove
	STAGGER, ## after a wound
	REST, ## phase 2: between bolts, and between volleys
	CHARGE, ## phase 2: a bolt's tell
	STALK, ## phase 3: walking at the prince in the dark
	CROUCH, ## phase 3: the pounce's tell
	LEAP, ## phase 3: in the air
	LAND, ## phase 3: landed on the prince; no opening
	SKID, ## phase 3: landed short; the opening
	GATHER, ## finale: the beam's tell
	POUR, ## finale: the beam is out
	SPENT, ## finale: the beam missed or hit; he gathers again after SPENT_TIME
	WON, ## a phase's last wound: the disc cracks
	FALL, ## the killing blow: he falls, and the kept sun rises
}

## The group the King is in, so the presentation around him -- the kept sun,
## the grade -- finds him without being handed him.
const KING := &"eclipse"

## How many wounds each phase takes.
const WOUNDS: Array[int] = [3, 3, 2, 1]

## The body: half as tall again as the prince, as broad as a Bastion.
const BODY := Vector2(14.0, 32.0)
## Where his crown is: the top of the body, as deep as a plunge's point bites.
const CROWN := 8.0
const SAME_FLOOR := 10.0
const HALF_FRAME := 0.5 / 60.0

## Phase 1. A stately walk, and a pause under each gallery's lip.
const WALK_SPEED := 30.0
const PAUSE_TIME := 0.5
## How far out from a lip he stands to pause: his crown is under the step a
## prince takes off the gallery, so a walk off the edge and a plunge lands.
const PAUSE_INSET := 8.0
## Plunges a pass can take. The rebound off his crown chains a second; a third
## meets the disc, raised over his head until he has turned away.
const PASS_WOUNDS := 2

## The shove: the Bastion's, lower and heavier. Within a tile in front of him
## on his floor, he draws it for the telegraph and lunges SHOVE_LUNGE.
const ENGAGE_GAP := 16.0
const SHOVE_LUNGE := 16.0
const SHOVE_REACH := 12.0
const SHOVE_LOW := 2.0
const SHOVE_HIGH := 26.0

## Phase 2. Three bolts to a volley, faster each volley.
const VOLLEY: Array[float] = [150.0, 180.0, 210.0]
const BOLTS := 3
## Bolt to bolt, unassisted: the parry's cycle (24) and window (12) and six
## frames to spare, so each bolt needs a fresh parry, never a riposte.
const BOLT_SPACING := 0.7
## Between volleys, and before the first.
const VOLLEY_REST := 1.4
## Chest height on a standing prince; clear over a crouching one (13 px).
const BOLT_HEIGHT := 15.0

## Phase 3. A stalk, a crouch, a pounce out of the dark.
const STALK_SPEED := 30.0
## He crouches with the prince this close in front, after stalking at least
## STALK_MIN, and the leap reaches at most POUNCE_RANGE: room for a prince who
## walks away during the crouch, none for one who runs. It never comes down
## further than where the prince stood -- at point-blank he rises and comes
## down where he was -- because a landing past the prince's near edge would be
## one no backstep clears, and the backstep is the phase.
const STRIKE_RANGE := 64.0
const STALK_MIN := 0.3
const POUNCE_RANGE := 96.0
const LEAP_TIME := 0.5
const LEAP_HEIGHT := 28.0
## The slam is live over the last frames of the flight and the first after it.
const SLAM_BEFORE := 0.1
const SLAM_AFTER := 4.0 / 60.0
## How far past his front the slam reaches.
const SLAM_REACH := 4.0
## Landed short: 40 frames, longer than the backstep's remainder plus a
## swing's lead, so the prince who stepped out of it has time to step in.
const SKID_TIME := 40.0 / 60.0
const SKID_SLIDE := 8.0

## Finale. Twice the standard tell, the only one that long.
const GATHER_TIME := 0.9
const BEAM_SPEED := 120.0
const BEAM_HEIGHT := 14.0
## After a beam that was not turned, before the next gather.
const SPENT_TIME := 3.0

## The beats between phases, and the fall.
const RISE_TIME := 1.5
const RISE_SPEED := 72.0
const WON_TIME := 1.5
const FALL_TIME := 4.2
## When, in the fall, the disc cracks open and the sun starts to rise.
const CRACK_AT := 0.35
const RELEASE_AT := 1.4

var facing := -1
var phase: Phase = Phase.SHIELD
var state: State = State.AWAIT
var state_time := 0.0
## Wounds taken in the current phase.
var wounds := 0
## Phase 1: plunges taken on this pass, and whether the disc is over his crown.
var pass_wounds := 0
var crown_guard := false
## Phase 2: volleys begun in this phase, and bolts left in the current one.
var volley := 0
var bolts_left := BOLTS
var rest_length := VOLLEY_REST
## The arena he walks, in world units (arena_of()).
var floor_y := 0.0
var west_x := 0.0
var east_x := 0.0
var west_lip := 0.0
var east_lip := 0.0
var gallery_y := 0.0
## Where the kept sun hangs over the floor: his post.
var sun_x := 0.0

var _memory: Dictionary = {}
var _leap_from := 0.0
var _leap_to := 0.0
var _slam_landed := false
## Phase 3: this leap is a retreat to the kept sun after a wound, not a pounce.
var _retreat := false
## The finale's rise follows the dark of phase 3, not a respawn.
var _out_of_the_dark := false
var _shove_from := 0.0
var _shots: Array[FoeProjectile] = []
var _beam: EclipseBeam
var _cracked := false
var _released := false


func _ready() -> void:
	super()
	add_to_group(KING)
	add_to_group(ExitDoor.HELD_SHUT)
	if get_node_or_null("Art") == null:
		var art := EclipseArt.new()
		art.name = "Art"
		add_child(art)


## --- placement ----------------------------------------------------------------

func place(site: EntitySite) -> void:
	super(site)
	_memory = site.memory
	sun_x = site.at.x
	floor_y = site.at.y
	if site.level != null and site.level.data != null:
		var arena := arena_of(site.level.data, site.cell)
		set_arena(arena)
	resume(int(_memory.get("phase", Phase.SHIELD)))


## The vault around `cell`, read from the level once: the walls either side of
## the floor his post stands on, the gallery slabs nearest the walls and their
## inner lips. `{floor_y, west_x, east_x, west_lip, east_lip, gallery_y}`; a
## side with no gallery has its lip at the wall.
static func arena_of(data: AsciiLevel, cell: Vector2i) -> Dictionary:
	var tile := Level.TILE
	# The walls are read at his crown, two rows up: a doorway lower than a
	# King -- dawn's, in the east wall -- is no way through for him.
	var crown := cell.y - 2
	var west := cell.x
	while west > 0 and not data.is_solid(west - 1, crown):
		west -= 1
	var east := cell.x
	while east < data.cols - 1 and not data.is_solid(east + 1, crown):
		east += 1
	var out := {
		"floor_y": float((cell.y + 1) * tile),
		"west_x": float(west * tile), "east_x": float((east + 1) * tile),
		"west_lip": float(west * tile), "east_lip": float((east + 1) * tile),
		"gallery_y": float((cell.y + 1) * tile),
	}
	for row: int in range(cell.y - 1, maxi(-1, cell.y - 7), -1):
		if not data.is_solid(west, row):
			continue
		var lip_w := west
		while lip_w < cell.x and data.is_solid(lip_w + 1, row):
			lip_w += 1
		var lip_e := east
		while lip_e > cell.x and not data.is_solid(lip_e, row):
			lip_e -= 1
		while lip_e > cell.x and data.is_solid(lip_e - 1, row):
			lip_e -= 1
		out["west_lip"] = float((lip_w + 1) * tile)
		out["east_lip"] = float(lip_e * tile) if data.is_solid(lip_e, row) else out["east_x"]
		out["gallery_y"] = float(row * tile)
		break
	return out


## Sets the arena by hand: what place() does from the level, for a test that
## steps him with no level at all.
func set_arena(arena: Dictionary) -> void:
	floor_y = float(arena["floor_y"])
	west_x = float(arena["west_x"])
	east_x = float(arena["east_x"])
	west_lip = float(arena["west_lip"])
	east_lip = float(arena["east_lip"])
	gallery_y = float(arena["gallery_y"])


## Waits under the kept sun in `which` phase, for the prince to come down.
## Where a King placed again after a death begins: the start of the phase he
## was in.
func resume(which: int) -> void:
	phase = clampi(which, Phase.SHIELD, Phase.FINALE) as Phase
	position = Vector2(sun_x, floor_y)
	velocity = Vector2.ZERO
	_reset_phase()
	_enter(State.AWAIT)


## --- the contract ---------------------------------------------------------------

func bounds() -> Rect2:
	return Rect2(position - Vector2(BODY.x * 0.5, BODY.y), BODY)


func is_alive() -> bool:
	return state != State.FALL


func is_dangerous() -> bool:
	return state == State.SHOVE or _slam_live()


## Holds the prince's idle from the moment he has seen the King rise.
func is_engaged() -> bool:
	return state != State.AWAIT and is_alive()


func dangers() -> Array[FoeDanger]:
	var out: Array[FoeDanger] = []
	if state == State.SHOVE:
		# A shove is not a blade: nothing to parry. A backstep slides out of
		# it, as out of a Bastion's.
		out.append(FoeDanger.make(shove_rect(), position.x))
	elif _slam_live():
		# A body coming down, not a blade: the parry is simply hit, as a
		# cat's pounce goes under a raised guard. The backstep lets it by.
		var slam := FoeDanger.make(slam_rect(), position.x)
		# A body landing on the floor lands on a body tucked against it:
		# the roll is no answer to the pounce, which stays the backstep's.
		slam.rollable = false
		slam.on_landed = func(_dealt: bool) -> void: _slam_landed = true
		out.append(slam)
	return out


## Every blow is weighed against the phase; only its lesson wounds him.
func take_blow(blow: Blow, _from_x: float) -> Outcome:
	if not is_alive():
		return Outcome.NONE
	if not _opens_to(blow):
		return Outcome.BLOCKED
	return _wound()


## The sound of a wound: a guard's, lower. Game pitches it per blow.
func wound_voice() -> StringName:
	return &"guard_hit"


func impact_point() -> Vector2:
	return Vector2(position.x, position.y - BODY.y)


## Where the shove reaches while it is live.
func shove_rect() -> Rect2:
	var front := position.x + BODY.x * 0.5 * facing
	var x := front if facing > 0 else front - SHOVE_REACH
	return Rect2(x, position.y - SHOVE_HIGH, SHOVE_REACH, SHOVE_HIGH - SHOVE_LOW)


## Where the slam reaches: his body coming down and SLAM_REACH past his front.
func slam_rect() -> Rect2:
	var x := position.x - BODY.x * 0.5 - (SLAM_REACH if facing < 0 else 0.0)
	return Rect2(x, position.y - BODY.y, BODY.x + SLAM_REACH, BODY.y)


## Wounds dealt across the whole fight, won phases included: what the crown
## shows, one spike put out per wound.
func wounds_total() -> int:
	var total := wounds
	for i: int in phase:
		total += WOUNDS[i]
	if state == State.FALL:
		total = 0
		for need: int in WOUNDS:
			total += need
	return total


## How far the vault is put out, 0 to 1: the third phase's darkness, faded in
## as he raises the disc and out as the finale's light comes back.
func darkness() -> float:
	if state == State.AWAIT:
		return 0.0
	match phase:
		Phase.ECLIPSE:
			return smoothstep(0.2, RISE_TIME, state_time) if state == State.RISE else 1.0
		Phase.FINALE:
			# The light comes back over the finale's rise -- when there was a
			# dark to come out of, and not after a respawn into the finale.
			if state == State.RISE and _out_of_the_dark:
				return 1.0 - smoothstep(0.0, RISE_TIME, state_time)
			return 0.0
	return 0.0


## The tells, through the foe contract's warn(): what the art and the tests
## read, so a longer warning is drawn and heard across its whole length.
func draw_time() -> float:
	return warn(Patrol.WINDUP_TIME)


func charge_time() -> float:
	return warn(Patrol.WINDUP_TIME)


func crouch_time() -> float:
	return warn(Patrol.WINDUP_TIME)


func gather_time() -> float:
	return warn(GATHER_TIME)


func pause_time() -> float:
	return warn(PAUSE_TIME)


## The beam in flight, while there is one.
func beam() -> EclipseBeam:
	if _beam == null or not is_instance_valid(_beam) or _beam.is_spent():
		return null
	return _beam


## --- the step ---------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	tick(delta)


## One frame of decision and movement on the fixed step.
func tick(delta: float) -> void:
	state_time += delta
	match state:
		State.AWAIT:
			if _in_arena():
				_rise()
		State.RISE:
			_step_rise(delta)
		State.WALK:
			_step_walk(delta)
		State.PAUSE:
			if not _shove_if_close() and _past(pause_time()):
				facing = -facing
				pass_wounds = 0
				crown_guard = false
				_enter(State.WALK)
		State.DRAW:
			if _past(draw_time()):
				_shove_from = position.x
				_enter(State.SHOVE)
				cue.emit(&"land_hard", {"pitch": 1.1, "volume_db": -6.0})
		State.SHOVE:
			var t := clampf(state_time / Patrol.STRIKE_TIME, 0.0, 1.0)
			position.x = _clamp_x(_shove_from + facing * SHOVE_LUNGE * (1.0 - pow(1.0 - t, 2.0)))
			if _past(Patrol.STRIKE_TIME):
				_enter(State.RECOVER)
		State.RECOVER:
			if _past(Patrol.RECOVER_TIME):
				_carry_on()
		State.STAGGER:
			if _past(Patrol.STAGGER_TIME):
				_after_stagger()
		State.REST, State.CHARGE:
			_step_burning()
		State.STALK, State.CROUCH, State.LEAP, State.LAND, State.SKID:
			_step_eclipse(delta)
		State.GATHER, State.POUR, State.SPENT:
			_step_finale()
		State.WON:
			_step_won()
			if _past(WON_TIME):
				_out_of_the_dark = phase == Phase.ECLIPSE
				phase = (phase + 1) as Phase
				_reset_phase()
				_rise()
		State.FALL:
			_step_fall()


## --- phase 1: the shield ------------------------------------------------------------

func _step_walk(delta: float) -> void:
	if _shove_if_close():
		return
	velocity.x = facing * WALK_SPEED
	var stop := west_lip + PAUSE_INSET if facing < 0 else east_lip - PAUSE_INSET
	position.x += velocity.x * delta
	var reached := position.x <= stop if facing < 0 else position.x >= stop
	if reached:
		position.x = stop
		velocity.x = 0.0
		_enter(State.PAUSE)


## A prince within a tile in front, on his floor: the shove's draw. True when
## it began.
func _shove_if_close() -> bool:
	if not _target_on_floor():
		return false
	var gap := _gap_in_front()
	if gap > ENGAGE_GAP or gap < -BODY.x - target_rect.size.x:
		return false
	velocity.x = 0.0
	_enter(State.DRAW)
	cue.emit(&"cloth", {"pitch": 0.4})
	cue.emit(&"masonry", {"pitch": 1.2, "volume_db": -12.0})
	return true


## --- phase 2: the burning -------------------------------------------------------------

func _step_burning() -> void:
	if state == State.CHARGE:
		if _past(charge_time()):
			_fire()
		return
	# Resting: turned on the prince, and charging when there is one to aim at.
	if not _target_on_floor():
		return
	facing = _toward_target()
	if _shove_if_close():
		return
	if _past(rest_length):
		_enter(State.CHARGE)
		if bolts_left == BOLTS:
			volley += 1
		# The burning's whine: the gather's rising tone at twice the pitch,
		# so it is the same light, told in half the time.
		cue.emit(&"sun_gather", {"pitch": 2.0 * Patrol.WINDUP_TIME / charge_time()})


func _fire() -> void:
	var speed := VOLLEY[clampi(volley - 1, 0, VOLLEY.size() - 1)]
	var at := Vector2(position.x + facing * (BODY.x * 0.5 + 4.0), floor_y - BOLT_HEIGHT)
	var bolt := Sunbolt.make(at, Vector2(facing, 0.0), speed)
	bolt.kept = true
	launch(bolt)
	var flying: Array[FoeProjectile] = []
	for shot: FoeProjectile in _shots:
		if is_instance_valid(shot) and not shot.is_spent():
			flying.append(shot)
	_shots = flying
	_shots.append(bolt)
	cue.emit(&"sword", {"pitch": 1.8, "volume_db": -6.0})
	bolts_left -= 1
	if bolts_left > 0:
		rest_length = BOLT_SPACING - Patrol.WINDUP_TIME
	else:
		bolts_left = BOLTS
		rest_length = VOLLEY_REST
	_enter(State.REST)


## --- phase 3: the eclipse ----------------------------------------------------------------

func _step_eclipse(delta: float) -> void:
	match state:
		State.STALK:
			if not _target_on_floor():
				return
			facing = _toward_target()
			if _gap_in_front() <= STRIKE_RANGE and _past(STALK_MIN):
				_enter(State.CROUCH)
				cue.emit(&"cloth", {"pitch": 0.45})
				cue.emit(&"sun_gather",
					{"pitch": 2.4 * Patrol.WINDUP_TIME / crouch_time(), "volume_db": -6.0})
				return
			position.x = _clamp_x(position.x + facing * STALK_SPEED * delta)
		State.CROUCH:
			if _past(crouch_time()):
				_leap()
		State.LEAP:
			var t := clampf(state_time / LEAP_TIME, 0.0, 1.0)
			position.x = lerpf(_leap_from, _leap_to, t)
			position.y = floor_y - 4.0 * LEAP_HEIGHT * t * (1.0 - t)
			if _past(LEAP_TIME):
				position = Vector2(_leap_to, floor_y)
				if _retreat:
					_retreat = false
					_enter(State.STALK)
					cue.emit(&"land_soft", {"pitch": 0.6})
					return
				_enter(State.LAND if _slam_landed else State.SKID)
				cue.emit(&"land_hard", {"pitch": 0.7})
		State.LAND:
			if _past(Patrol.RECOVER_TIME):
				_enter(State.STALK)
		State.SKID:
			# A slam that lands in its last live frames was not a miss after all.
			if _slam_landed:
				state = State.LAND
				return
			var t := clampf(state_time / SKID_TIME, 0.0, 1.0)
			position.x = _clamp_x(_leap_to + facing * SKID_SLIDE * (1.0 - pow(1.0 - t, 2.0)))
			if _past(SKID_TIME):
				_enter(State.STALK)


## Back into the dark under the kept sun after a wound: a leap with nothing
## live in it, so the next pounce comes from across the floor, told from a
## distance, never from on top of the prince.
func _retreat_to_the_sun() -> void:
	_leap_from = position.x
	_leap_to = _clamp_x(sun_x)
	_retreat = true
	_slam_landed = false
	facing = 1 if _leap_to >= position.x else -1
	_enter(State.LEAP)
	cue.emit(&"jump", {"pitch": 0.55, "volume_db": -6.0})


## Up and out at where the prince stood when the crouch ended, at most
## POUNCE_RANGE: his front comes down on the near side of that body.
func _leap() -> void:
	_leap_from = position.x
	var near := target_rect.position.x if facing > 0 else target_rect.end.x
	if target_rect.size == Vector2.ZERO:
		near = position.x + facing * BODY.x * 0.5
	var land := near - facing * BODY.x * 0.5
	var reach := clampf((land - position.x) * facing, 0.0, POUNCE_RANGE)
	_leap_to = _clamp_x(position.x + facing * reach)
	_slam_landed = false
	_retreat = false
	_enter(State.LEAP)
	cue.emit(&"jump", {"pitch": 0.6})


func _slam_live() -> bool:
	if _retreat:
		return false
	match state:
		State.LEAP:
			return _past(LEAP_TIME - SLAM_BEFORE)
		State.LAND, State.SKID:
			return not _past(SLAM_AFTER)
	return false


## --- the finale ------------------------------------------------------------------------

func _step_finale() -> void:
	match state:
		State.GATHER:
			# He tracks the prince until the beam is poured: it goes where he is.
			if target_rect.size != Vector2.ZERO:
				facing = _toward_target()
			if _past(gather_time()):
				_pour()
		State.POUR:
			if beam() == null:
				_enter(State.SPENT)
		State.SPENT:
			if _past(SPENT_TIME):
				_gather()


func _gather() -> void:
	_enter(State.GATHER)
	cue.emit(&"sun_gather", {"pitch": GATHER_TIME / gather_time()})


func _pour() -> void:
	_beam = EclipseBeam.new()
	var origin := position.x + facing * (BODY.x * 0.5 + 2.0)
	_beam.origin_x = origin
	_beam.position = Vector2(origin, floor_y - BEAM_HEIGHT)
	_beam.velocity = Vector2(facing * BEAM_SPEED, 0.0)
	launch(_beam)
	_shots.append(_beam)
	_enter(State.POUR)
	cue.emit(&"sword_hit", {"pitch": 0.5, "volume_db": -4.0})


## --- wounds, and the beats between phases ------------------------------------------------

## Whether `blow` is the one this phase opens him to, now.
func _opens_to(blow: Blow) -> bool:
	match phase:
		Phase.SHIELD:
			var standing := state == State.PAUSE or state == State.STAGGER or state == State.WALK
			return blow == Blow.PLUNGE and standing and not crown_guard \
				and pass_wounds < PASS_WOUNDS
		Phase.BURNING:
			return blow == Blow.SHOT and state != State.RISE and state != State.WON
		Phase.ECLIPSE:
			return blow == Blow.SWORD and state == State.SKID
		Phase.FINALE:
			return blow == Blow.SHOT and state == State.POUR
	return false


func _wound() -> Outcome:
	wounds += 1
	pass_wounds += 1
	velocity = Vector2.ZERO
	if phase == Phase.FINALE:
		_fall()
		return Outcome.KILLED
	if wounds >= WOUNDS[phase]:
		_win_phase()
		return Outcome.WOUNDED
	if phase == Phase.SHIELD and pass_wounds >= PASS_WOUNDS:
		crown_guard = true
	if phase == Phase.BURNING:
		# The wound puts out the volley: what is left of it in the air dies
		# with his light, so every volley is played out, faster each time.
		_snuff()
	_enter(State.STAGGER)
	staggered.emit()
	return Outcome.WOUNDED


func _after_stagger() -> void:
	match phase:
		Phase.SHIELD:
			if crown_guard:
				# Two plunges is a pass: the disc goes up over the crown and he
				# turns away from the gallery that hurt him.
				facing = 1 if position.x < sun_x else -1
				_enter(State.WALK)
			else:
				_enter(State.PAUSE)
		Phase.BURNING:
			# The volley is broken: the next one starts afresh, faster.
			bolts_left = BOLTS
			rest_length = VOLLEY_REST
			_enter(State.REST)
		_:
			_retreat_to_the_sun()


## Back to what the phase does when nothing is happening.
func _carry_on() -> void:
	match phase:
		Phase.SHIELD:
			_enter(State.WALK)
		Phase.BURNING:
			rest_length = VOLLEY_REST
			_enter(State.REST)
		Phase.ECLIPSE:
			_enter(State.STALK)
		Phase.FINALE:
			_gather()


## The phase's last wound: the light in the air goes out, and the phase is
## remembered as won before anything else can happen.
func _win_phase() -> void:
	_memory["phase"] = phase + 1
	_snuff()
	_cracked = false
	_enter(State.WON)
	phase_won.emit(phase)


## The disc cracks a beat after the wound, on a frame of its own: on the
## wound's frame Game's impact cooldown would swallow one or the other.
func _step_won() -> void:
	if _cracked or not _past(CRACK_AT):
		return
	_cracked = true
	impact.emit(position + Vector2(facing * 8.0, -BODY.y * 0.7), 0, 2.4, 0.8)
	cue.emit(&"masonry", {"pitch": 0.8})
	cue.emit(&"sword_hit", {"pitch": 0.7, "volume_db": -3.0})


## The prince is in the vault: back to the kept sun, turned on him.
func _rise() -> void:
	_enter(State.RISE)
	cue.emit(&"masonry", {"pitch": 0.55, "volume_db": -8.0})


func _step_rise(delta: float) -> void:
	var gap := sun_x - position.x
	position.x += clampf(gap, -RISE_SPEED * delta, RISE_SPEED * delta)
	if target_rect.size != Vector2.ZERO:
		facing = _toward_target()
	if not _past(RISE_TIME) or not is_equal_approx(position.x, sun_x):
		return
	_begin()


## The phase's first move, from under the kept sun.
func _begin() -> void:
	phase_begun.emit(phase)
	match phase:
		Phase.SHIELD:
			_enter(State.WALK)
		Phase.BURNING:
			rest_length = VOLLEY_REST
			_enter(State.REST)
		Phase.ECLIPSE:
			_enter(State.STALK)
			cue.emit(&"masonry", {"pitch": 0.5})
		Phase.FINALE:
			_gather()


func _reset_phase() -> void:
	wounds = 0
	pass_wounds = 0
	crown_guard = false
	volley = 0
	bolts_left = BOLTS
	rest_length = VOLLEY_REST
	_slam_landed = false


## The killing blow: the beam went back into the disc.
func _fall() -> void:
	_snuff()
	_cracked = false
	_enter(State.FALL)
	defeated.emit()


func _step_fall() -> void:
	if not _cracked and _past(CRACK_AT):
		_cracked = true
		# The disc gives: the heaviest beat in the game, on its own frame
		# after the wound's, so the hitstop budget spends it in full.
		impact.emit(position + Vector2(facing * 8.0, -BODY.y * 0.7),
			Flow.PLUNGE_FRAMES, 3.2, 1.0)
		cue.emit(&"masonry", {"pitch": 0.7})
		cue.emit(&"sword_hit", {"pitch": 0.55})
	if not _released and _past(RELEASE_AT):
		_released = true
		cue.emit(&"sunrise", {})
	if _past(FALL_TIME) and is_in_group(ExitDoor.HELD_SHUT):
		# The kept sun is out of the Well: dawn's door is his no longer.
		remove_from_group(ExitDoor.HELD_SHUT)
		cue.emit(&"exit", {})


## Every bolt still in the air goes out with the phase.
func _snuff() -> void:
	for shot: FoeProjectile in _shots:
		if is_instance_valid(shot) and not shot.is_spent():
			shot.spend()
	_shots.clear()


## --- reading the prince ------------------------------------------------------------------

## Inside the vault: what wakes him. A foe acts only while the camera shows
## it, and the whole vault is in the frame once the prince is down in it.
func _in_arena() -> bool:
	if target_rect.size == Vector2.ZERO:
		return false
	var feet := target_rect.end.y
	var x := target_rect.get_center().x
	return x > west_x and x < east_x and feet > gallery_y - Level.TILE and feet <= floor_y + 1.0


func _target_on_floor() -> bool:
	if target_rect.size == Vector2.ZERO:
		return false
	return absf(target_rect.end.y - floor_y) <= SAME_FLOOR and _in_arena()


func _toward_target() -> int:
	return 1 if target_rect.get_center().x >= position.x else -1


## From his front edge to the near side of the prince, along the way he
## faces. Negative once they overlap.
func _gap_in_front() -> float:
	var front := position.x + BODY.x * 0.5 * facing
	if facing > 0:
		return target_rect.position.x - front
	return front - target_rect.end.x


func _clamp_x(x: float) -> float:
	return clampf(x, west_x + BODY.x * 0.5, east_x - BODY.x * 0.5)


## Whether `seconds` of the current state have gone by, to the frame. The
## clock is a sum of fixed steps, and 27 of them come to a hair under 0.45, so
## every timed change is read half a frame early: a 27-frame tell lasts 27
## frames, never 28.
func _past(seconds: float) -> bool:
	return state_time >= seconds - HALF_FRAME


func _enter(next: State) -> void:
	state = next
	state_time = 0.0
