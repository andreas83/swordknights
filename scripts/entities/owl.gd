class_name Owl
extends Foe
## The night's hunter (`Y`, docs/campaign.md "The owl"): it takes what is not
## standing on stone, and the move it is for is the air slash.
##
## ## The rule
##
## Perched, it watches: its head and eyes follow the prince, and while he is
## near it hoots softly, so it is heard before it is found in the dark. It
## does nothing to a prince on his feet -- not on the stone, not ever. The
## moment he is **off the stone** (`off_the_stone()`, below: jumping,
## falling, slashing, plunging, hanging, mantling, on a ladder, riding a lift),
## within RANGE, in its sight and with the owl on screen, it spreads its wings
## with a hoot: the 27-frame warning, read through `warn()` like every tell.
##
## - Back on the stone before the spread ends, he is let be: it folds.
## - Still off it at the end, it stoops: a straight dive at STOOP_SPEED to
##   where he was at that moment -- at most RANGE away, so under 37 frames --
##   with its talons live. Talons are not a blade: no parry turns them and no
##   backstep slips them, and the owl never stoops at a body on the ground
##   for either to be needed.
## - Then it pulls up, low past where it struck and back to its perch, for
##   PULL_UP_TIME -- harmless and hittable: the time to climb.
##
## ## Why a decisive climber is safe
##
## A grab and an immediate mantle take 20 frames (Tuning.HANG_HOLD_TIME and
## CLIMB_UP_TIME), and the spread is 27: a prince who is seen only as he
## takes a ledge is up before it can stoop. The jump that took him there is
## off the stone too, so where the owl sees the jump, the spread can end with
## him hanging -- and then it dives at the place he hung, which is beside the
## stone, not on it: a level puts an owl so that line ends at the wall, and
## the climber who did not wait is standing above it when it arrives
## (tests/unit/test_owl.gd plays both).
##
## ## What kills it
##
## One heart. The air slash (the slash's band runs from the chest to below the
## feet, and it is out in front of the talons as the two close), a ground swing
## as it pulls up past, a plunge or a stomp onto it perched -- every blow the
## foe contract referees, the thrown sword among them. The duel's feet never
## wound it: a dive kick that finds it knocks it into its pull-up (`knock()`),
## which spends a stoop and puts a perched owl in the air, hittable. And the
## Well's own machinery: a blade's cut that
## its flight crosses on the beat (BeatBlade.GROUP). The bird does not know
## the machine keeps time; the prince can.
##
## ## Simulation and drawing
##
## `tick()` is the whole decision for a frame and needs no physics world: the
## owl flies, so it moves itself and never slides. `position` is the middle of
## its body, perched or flying. OwlArt draws it from `state`, `state_time`,
## `facing`, `look` and `velocity`.

## Wings open: the warning.
signal spread()
## It let him be.
signal folded()
## The dive began.
signal stooped()

enum State { PERCH, SPREAD, STOOP, PULL_UP, FOLD, DYING }

## How far it hunts, in world units: eight tiles, the bible's maximum.
const RANGE := 8.0 * 16.0
## The dive: 3.5 px a frame.
const STOOP_SPEED := 210.0
## The warning: the sentinel's raise. Read through spread_time().
const SPREAD_TIME := Patrol.WINDUP_TIME
## Back to the perch, low past the strike first.
const PULL_UP_TIME := 1.5
## Folding its wings back: half a second, and it does not spread again until
## it has. A hunter that has just been cheated settles first -- which is what
## makes a hop onto a shelf and straight on up to a ledge the decisive climb
## it should be: the hop draws the spread, the landing folds it, and the
## climb is over before the owl is ready to spread again.
const FOLD_TIME := 0.5
const DEATH_TIME := 1.1
const GRAVITY := 700.0
## The perched body, an upright oval with tufts; and the flying one, a flat
## bar of wing -- nothing else in the game is a bar in the air.
const PERCHED := Vector2(10.0, 12.0)
const FLYING := Vector2(24.0, 6.0)
## The talons, under the middle of the bar.
const TALONS := Vector2(10.0, 7.0)
## Half a physics frame: a span of seconds is counted in whole frames, and
## 27 sixtieths summed one at a time fall a hair short of 0.45.
const HALF_FRAME := 0.5 / 60.0
## The soft hoot while it watches: how often, and how near he must be.
const WATCH_HOOT := 3.4
const WATCH_RANGE := RANGE * 1.5

var state: State = State.PERCH
var state_time := 0.0
var facing := 1
## Where the head is turned, -1 to 1: toward the prince, while it watches.
var look := 0.0
var health := 1
## Where it sits: the middle of its perched body.
var perch := Vector2.ZERO
## Where the dive is going.
var aim := Vector2.ZERO

var _dive_from := Vector2.ZERO
var _from := Vector2.ZERO
var _via := Vector2.ZERO
var _hoot_in := 0.0


func _ready() -> void:
	super()
	if get_node_or_null("Art") == null:
		var art := OwlArt.new()
		art.name = "Art"
		add_child(art)


func place(site: EntitySite) -> void:
	super(site)
	perch = site.at + Vector2(0.0, -PERCHED.y * 0.5)
	position = perch


## --- the contract ---------------------------------------------------------------

func bounds() -> Rect2:
	var size := FLYING if is_flying() else PERCHED
	return Rect2(global_position - size * 0.5, size)


func is_flying() -> bool:
	return state == State.STOOP or state == State.PULL_UP or (
		state == State.DYING and not velocity.is_zero_approx())


func is_alive() -> bool:
	return state != State.DYING


## Too light to hold a plate down or to count as a lift's rider.
func has_weight() -> bool:
	return false


## Off the stone: jumping, falling, slashing, plunging, hanging, mantling, on a
## ladder, knocked into the air, or riding something that moves under him --
## anything but standing on the city's own floor. The owl's whole rule, asked
## in one place: Game asks it once a frame for every foe (`target_off_stone`),
## so no foe works it out from a rectangle. It lives here rather than on the
## Player because it is the owl's question, not something the prince is. The
## feet decide, not the state's name: on the frame he lands he is still FALL,
## and he is on the stone.
static func off_the_stone(prince: Player) -> bool:
	match prince.state:
		Player.State.HANG, Player.State.CLIMB_UP, Player.State.LADDER:
			return true
	if not prince.is_grounded():
		return true
	# Standing, but on something that is carrying him: a lift's slab.
	return not prince.get_platform_velocity().is_zero_approx()


func is_dangerous() -> bool:
	return state == State.STOOP


func is_engaged() -> bool:
	return state == State.SPREAD or state == State.STOOP or state == State.PULL_UP


## The talons. No parry and no backstep: they are not a blade.
func dangers() -> Array[FoeDanger]:
	var talons := FoeDanger.make(talons_rect(), global_position.x)
	talons.evadable = false
	# A body coming down on him: a roll does not pass under it (FoeDanger).
	talons.rollable = false
	talons.on_landed = func(dealt: bool) -> void:
		if dealt and state == State.STOOP:
			_pull_up()
	var out: Array[FoeDanger] = [talons]
	return out


func talons_rect() -> Rect2:
	return Rect2(global_position + Vector2(-TALONS.x * 0.5, -1.0), TALONS)


func hit(from_x: float) -> bool:
	if not is_alive():
		return false
	health = 0
	var away := signf(global_position.x - from_x)
	_die(Vector2((away if away != 0.0 else 1.0) * 70.0, -60.0))
	return true


## A dive kick's heel: no wound, but off its perch or out of its stoop and
## into the pull-up -- thrown up and away from the heel, then home, in the
## air and hittable for PULL_UP_TIME. Up, not low as after a stoop: a perched
## owl sits on stone, and a loop drawn under it would be drawn through it.
## Already pulling up, it is going where a kick would send it, and the kick
## rings off.
func knock(from_x: float) -> bool:
	if not is_alive() or state == State.PULL_UP:
		return false
	var away := signf(global_position.x - from_x)
	_from = global_position
	_via = _from + Vector2((away if away != 0.0 else float(-facing)) * 24.0, -16.0)
	if not _open(_from, _via, perch):
		_via = _from.lerp(perch, 0.5) + Vector2(0.0, -16.0)
	_enter(State.PULL_UP)
	return true


## How long the spread lasts: the warning, with the assist as the player set it.
func spread_time() -> float:
	return warn(SPREAD_TIME)


## The spread in whole physics frames, rounded as a blade's tell is: 27, or 41
## with the assist on.
func spread_frames() -> int:
	return roundi(spread_time() * 60.0)


## --- the hunt -------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	tick(delta)
	if state == State.DYING and state_time >= DEATH_TIME:
		queue_free()


## One frame of decision and flight.
func tick(delta: float) -> void:
	state_time += delta
	match state:
		State.PERCH:
			_watch(delta)
			if _hunted() != Vector2.INF:
				_enter(State.SPREAD)
				spread.emit()
				cue.emit(&"hoot", {})
				cue.emit(&"cloth", {"pitch": 0.9})
		State.SPREAD:
			_watch(0.0)
			if not target_off_stone or target_rect.size == Vector2.ZERO:
				_fold()
			elif state_time >= float(spread_frames()) / 60.0 - HALF_FRAME:
				var at := _hunted()
				if at == Vector2.INF:
					_fold()
				else:
					aim = at
					_dive_from = global_position
					_enter(State.STOOP)
					stooped.emit()
					cue.emit(&"jump", {"pitch": 0.7, "volume_db": -8.0})
		State.STOOP:
			var to := aim - global_position
			var step := STOOP_SPEED * delta
			velocity = to.normalized() * STOOP_SPEED
			if to.length() <= step:
				global_position = aim
				_pull_up()
			else:
				global_position += to.normalized() * step
		State.PULL_UP:
			var s := clampf(state_time / PULL_UP_TIME, 0.0, 1.0)
			var eased := s * s * (3.0 - 2.0 * s)
			var before := global_position
			global_position = _bezier(_from, _via, perch, eased)
			velocity = (global_position - before) / maxf(delta, 0.0001)
			if s >= 1.0:
				global_position = perch
				velocity = Vector2.ZERO
				_enter(State.PERCH)
		State.FOLD:
			if state_time >= FOLD_TIME - HALF_FRAME:
				_enter(State.PERCH)
		State.DYING:
			# Down to the first stone under it, and still there.
			velocity.y += GRAVITY * delta
			velocity.x *= 0.96
			var next := global_position + velocity * delta
			if level != null and level.is_solid_at(next + Vector2(0.0, PERCHED.y * 0.25)):
				velocity = Vector2.ZERO
			else:
				global_position = next
	if is_flying() and is_alive():
		_meet_the_machine()


## Turns the head toward him, and hoots now and then while he is near.
func _watch(delta: float) -> void:
	if target_rect.size == Vector2.ZERO:
		look = move_toward(look, 0.0, 0.1)
		return
	var dx := target_rect.get_center().x - global_position.x
	look = clampf(dx / (RANGE * 0.5), -1.0, 1.0)
	facing = 1 if dx >= 0.0 else -1
	if delta <= 0.0:
		return
	_hoot_in -= delta
	var near := global_position.distance_to(target_rect.get_center()) <= WATCH_RANGE
	if near and _hoot_in <= 0.0 and CameraView.shows(self, bounds()):
		_hoot_in = WATCH_HOOT
		cue.emit(&"hoot", {"volume_db": -12.0})


## Where it would dive now, or Vector2.INF: he is off the stone, in range, in
## sight, and the owl is on screen. Of his body it aims at the first point it
## can see -- the middle, then the feet, then the head -- so the dive's line
## is always open air.
func _hunted() -> Vector2:
	if not target_off_stone or target_rect.size == Vector2.ZERO:
		return Vector2.INF
	if not CameraView.shows(self, bounds()):
		return Vector2.INF
	var body := target_rect
	var points: Array[Vector2] = [
		body.get_center(),
		Vector2(body.get_center().x, body.end.y - 3.0),
		Vector2(body.get_center().x, body.position.y + 3.0),
	]
	for point: Vector2 in points:
		if global_position.distance_to(point) <= RANGE and sees(point):
			return point
	return Vector2.INF


## Whether nothing that looks like stone stands between its eyes and `point`.
## An unfound false wall is stone to an owl as it is to a guard.
func sees(point: Vector2) -> bool:
	if level == null:
		return true
	var from := global_position
	var span := from.distance_to(point)
	var steps := maxi(1, ceili(span / 4.0))
	for i: int in range(1, steps):
		if level.looks_solid_at(from.lerp(point, float(i) / float(steps))):
			return false
	return true


## Back up from wherever the dive ended: low past the strike, then home. The
## swoop is drawn through open air; where a wall stands in its way, it goes
## straight back up the line it came down, which is open by construction.
func _pull_up() -> void:
	_from = global_position
	var dive := (aim - _dive_from).normalized()
	_via = _from + Vector2(dive.x * 26.0, 10.0)
	if not _open(_from, _via, perch):
		_via = _from.lerp(perch, 0.5)
	_enter(State.PULL_UP)


func _open(a: Vector2, via: Vector2, b: Vector2) -> bool:
	if level == null:
		return true
	for i: int in 17:
		if level.looks_solid_at(_bezier(a, via, b, float(i) / 16.0)):
			return false
	return true


static func _bezier(a: Vector2, via: Vector2, b: Vector2, s: float) -> Vector2:
	return a.lerp(via, s).lerp(via.lerp(b, s), s)


func _fold() -> void:
	_enter(State.FOLD)
	folded.emit()


## A blade's cut that the flight crosses: the machine kills it.
func _meet_the_machine() -> void:
	if not is_inside_tree():
		return
	for node: Node in get_tree().get_nodes_in_group(BeatBlade.GROUP):
		var blade := node as BeatBlade
		if blade != null and blade.cut_rect().intersects(bounds()):
			health = 0
			cue.emit(&"guard_hit", {"pitch": 1.6})
			_die(Vector2(signf(velocity.x) * 40.0, -30.0))
			return


func _die(push: Vector2) -> void:
	velocity = push
	_enter(State.DYING)
	cue.emit(&"hoot", {"pitch": 1.6, "volume_db": -4.0})
	defeated.emit()


func _enter(next: State) -> void:
	state = next
	state_time = 0.0
