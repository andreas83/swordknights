class_name Bastion
extends Foe
## The Bastion: a posted guard behind a tall shield, the foe Chapter II is
## built to teach the plunge with (docs/campaign.md, "The Bastion").
##
## Where the sentinel walks a beat, a Bastion holds a spot -- a doorway, a
## corridor, a plate -- and is a living wall. Everything about him says one
## thing: his front is closed, and the way in is over the top.
##
## ## A wall that pushes back
##
## Foes have no collision in this game (Foe: every meeting is the referee's,
## by rectangles), which is right for a guard you can walk round and wrong for
## a wall. So the Bastion's front is a danger that does no harm: the shield's
## face, while it is set, pushes a body that touches it back WALL_PUSH, about
## six pixels, and a sword that clangs off it throws the prince back the same
## way. Through Game's shove (FoeDanger.push), never a wound and never a grace
## that would let a hit prince walk through him. A two-tile corridor with a
## Bastion in it is therefore shut, which is the corridor's whole lesson.
##
## ## States and their numbers (all the sentinel's, so one player reads both)
##
## | State | Frames | What happens |
## | --- | --- | --- |
## | STAND | -- | posted, facing where he was put; walks back to his post if moved |
## | BRACE | -- | the prince within BRACE_GAP in front: shield set lower |
## | WINDUP | 27, warn() | the prince within SHOVE_GAP: shield back, knees bent, rim glints |
## | SHOVE | 9 | lunges LUNGE px; a prince in it is thrown about two tiles: no heart |
## | RECOVER | 33 | the shield stays up: the front never opens |
## | TURN | 30 | the prince got behind him: his back is open for the whole turn |
## | STAGGER | 24 | after a wound; not knocked back, so a plunge's rebound comes down on him again |
## | OPENED | 54 | a dive kick knocked the shield wide: no wall, no shove; a front blade wounds |
##
## Two hearts. The plunge wounds him from any side, and its rebound puts the
## prince back in the air for the second: the double plunge kills. A swing
## at his back -- in the turn, or before it starts -- wounds. A swing, an air
## slash or a shot from the front clangs; a stomp rings off the hat and wounds
## nothing, but bounces, which is a second chance to plunge. There is nothing
## to parry -- a shove is not a blade -- and a backstep slides out of the
## shove and gains nothing.
##
## ## The duel's moves against him (docs/character.md)
##
## - **The roll** goes under the shield's face and under the shove: both are
##   set against a standing man, and their dangers keep FoeDanger's default
##   `rollable`. So a roll is the corridor's answer from the front: it comes
##   up behind him, where his back is open while he shoves at nothing,
##   recovers and turns.
## - **The dive kick**, from either side, knocks the pavise wide: OPENED,
##   54 frames (a parried reel's length), in which his front is no wall and a
##   blade from the front wounds. It wounds nothing itself. It is a way in
##   over the top, which is his lesson; the plunge is still the one that
##   kills.
## - **The sweep** clangs off the foot of the shield from the front and
##   rocks him from behind, for a wound's stagger with no wound.
## - **The thrown sword** clangs off the front and drops at his feet -- it
##   has to be fetched from inside his shove -- and wounds his back.
##
## ## Weight
##
## He is heavy (Foe.has_weight()), so a plate he stands on is held: Chapter
## II's weighed gate is open for exactly as long as he lives on its plate.
## His lunge carries him off it, and he steps back onto it while he recovers.
##
## ## Sound, through Game and GameAudio.cue
##
## The clang is Game's, with the shield's own low ring under it; the windup's
## feet grinding; the shove's thump. The wound is Game's.

## The windup began: the one warning.
signal alerted()
## The shove came.
signal shoved()
## A wound that did not kill.
signal staggered()
## A blow turned by the shield.
signal clanged()

enum State { STAND, BRACE, WINDUP, SHOVE, RECOVER, TURN, STAGGER, DYING, OPENED }

const BODY := Vector2(14.0, 22.0)
const MAX_HEALTH := 2
const GRAVITY := 900.0
const MAX_FALL := 320.0

## The sentinel's clock, so a player who has learned him reads this one.
const WINDUP_TIME := Patrol.WINDUP_TIME
const SHOVE_TIME := Patrol.STRIKE_TIME
const RECOVER_TIME := Patrol.RECOVER_TIME
const TURN_TIME := Patrol.LOOK_TIME
const STAGGER_TIME := Patrol.STAGGER_TIME
const DEATH_TIME := Patrol.DEATH_TIME
## A dive kick's opening: the parried sentinel's reel, the game's word for
## "a big opening".
const OPENED_TIME := Patrol.PARRIED_TIME

## How close in front, body to body, before he sets the shield, and before he
## shoves.
const BRACE_GAP := 2.0 * Tuning.TILE
const SHOVE_GAP := Tuning.TILE
## How far behind him a prince on his floor is heard, and turned to.
const HEAR_GAP := 3.0 * Tuning.TILE
## The lunge, and the walk back to his post.
const LUNGE := 16.0
const RETURN_SPEED := 20.0
## A shove: thrown back about two tiles and staggered, as the bible has it.
const SHOVE_PUSH := Vector2(180.0, -120.0)
const SHOVE_STAGGER := 0.32
## The shield's face, and a blade off it: about six pixels back.
const WALL_PUSH := Vector2(80.0, 0.0)
const WALL_STAGGER := 0.12
## How far past his front the shove reaches, and the clang's recoil.
const SHOVE_REACH := 12.0
const RECOIL_REACH := 26.0
const FRAME := 1.0 / 60.0
## Feet within this of his are on his floor.
const SAME_FLOOR := 10.0

var facing: int = -1
var health: int = MAX_HEALTH
var state: State = State.STAND
var state_time: float = 0.0
## Where he was posted: he walks back to it.
var post_x := 0.0

## Frames left on a clang's recoil. A blade that clangs is refereed on a
## frame when Game checks no danger, and this foe's own tick comes between
## that frame and the next, so the recoil is set for two and spent on the
## next frame's referee.
var _recoil := 0


func _ready() -> void:
	super()
	motion_mode = CharacterBody2D.MOTION_MODE_GROUNDED
	up_direction = Vector2.UP
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(BODY.x - 4.0, BODY.y)
	shape.shape = rect
	shape.position = Vector2(0.0, -BODY.y * 0.5)
	add_child(shape)
	if get_node_or_null("Art") == null:
		var art := BastionArt.new()
		art.name = "Art"
		add_child(art)


func place(site: EntitySite) -> void:
	super(site)
	post_x = site.at.x
	var face := site.param("facing", "")
	if face == "right":
		facing = 1


## --- the contract -----------------------------------------------------------

func bounds() -> Rect2:
	return Rect2(global_position - Vector2(BODY.x * 0.5, BODY.y), BODY)


func is_alive() -> bool:
	return state != State.DYING


## His front is a wall in every state but the turn, and the shove is live in
## its nine frames.
func is_dangerous() -> bool:
	return is_alive() and state != State.TURN and state != State.OPENED


func is_engaged() -> bool:
	return state in [State.BRACE, State.WINDUP, State.SHOVE, State.RECOVER, State.OPENED]


func dangers() -> Array[FoeDanger]:
	var out: Array[FoeDanger] = []
	var front := global_position.x + BODY.x * 0.5 * facing
	var top := global_position.y - BODY.y
	if state == State.SHOVE:
		var x := front if facing > 0 else front - SHOVE_REACH
		var shove := FoeDanger.make(Rect2(x, top, SHOVE_REACH, BODY.y), global_position.x, 0)
		shove.push = SHOVE_PUSH
		shove.stagger = SHOVE_STAGGER
		out.append(shove)
	if _recoil > 0:
		var x := front if facing > 0 else front - RECOIL_REACH
		out.append(_wall(Rect2(x, top, RECOIL_REACH, BODY.y)))
	var face := front - 3.0 if facing > 0 else front - 1.0
	out.append(_wall(Rect2(face, top, 4.0, BODY.y)))
	return out


func _wall(rect: Rect2) -> FoeDanger:
	var wall := FoeDanger.make(rect, global_position.x, 0)
	wall.push = WALL_PUSH
	wall.stagger = WALL_STAGGER
	wall.evadable = false
	return wall


## The plunge from anywhere; a blade at his back; nothing through the shield.
func take_blow(blow: Blow, from_x: float) -> Outcome:
	if not is_alive():
		return Outcome.NONE
	match blow:
		Blow.PLUNGE:
			return Outcome.KILLED if hit(from_x) else Outcome.WOUNDED
		Blow.STOMP:
			_clang()
			return Outcome.BLOCKED
		Blow.KICK:
			_enter(State.OPENED)
			velocity.x = 0.0
			cue.emit(&"sword_hit", {"pitch": 0.45, "volume_db": -6.0})
			return Outcome.STAGGERED
	if _from_front(from_x) and state != State.OPENED:
		_clang()
		# A blade off the face throws back the hand that held it; one that
		# was thrown has no hand behind it, and simply drops.
		if blow != Blow.THROWN:
			_recoil = 2
		return Outcome.BLOCKED
	if blow == Blow.SWEEP:
		_enter(State.STAGGER)
		staggered.emit()
		return Outcome.STAGGERED
	return Outcome.KILLED if hit(from_x) else Outcome.WOUNDED


## True when it killed. He is not knocked back: the shield's weight is planted.
func hit(_from_x: float) -> bool:
	if not is_alive():
		return false
	health -= 1
	velocity.x = 0.0
	if health <= 0:
		_enter(State.DYING)
		defeated.emit()
		return true
	_enter(State.STAGGER)
	staggered.emit()
	return false


func windup_time() -> float:
	return warn(WINDUP_TIME)


## --- simulation ---------------------------------------------------------------

func _physics_process(delta: float) -> void:
	tick(delta, is_on_floor())
	move_and_slide()
	if state == State.DYING and state_time >= DEATH_TIME:
		queue_free()
	elif level != null and global_position.y > level.world_size().y + 64.0:
		queue_free()


## One frame of decision. Takes `grounded` so a test can run it without a
## physics world.
func tick(delta: float, grounded: bool) -> void:
	state_time += delta
	_recoil = maxi(0, _recoil - 1)
	velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)
	match state:
		State.STAND, State.BRACE:
			_hold_post(grounded)
		State.WINDUP:
			velocity.x = 0.0
			if state_time >= windup_time():
				_enter(State.SHOVE)
				shoved.emit()
				cue.emit(&"land_hard", {"pitch": 1.3, "volume_db": -6.0})
		State.SHOVE:
			velocity.x = facing * LUNGE / SHOVE_TIME
			if state_time >= SHOVE_TIME:
				velocity.x = 0.0
				_enter(State.RECOVER)
		State.RECOVER:
			# The lunge is taken back inside the recovery, shield still up:
			# he holds a spot. Left where it landed, every shove was a step,
			# and the first one played herded the prince eight tiles back
			# across the courtyard.
			var home := post_x - global_position.x
			velocity.x = signf(home) * minf(absf(home) / FRAME, LUNGE / RECOVER_TIME)
			if state_time >= RECOVER_TIME:
				_enter(State.STAND)
		State.TURN:
			velocity.x = 0.0
			if state_time >= TURN_TIME:
				facing = -facing
				_enter(State.STAND)
		State.STAGGER:
			velocity.x = 0.0
			if state_time >= STAGGER_TIME:
				_enter(State.STAND)
		State.OPENED:
			velocity.x = 0.0
			if state_time >= OPENED_TIME:
				_enter(State.STAND)
		State.DYING:
			velocity.x *= 0.86


## Posted: turn to a prince behind, shove one at the shield, brace for one
## coming, and otherwise walk back to the post.
func _hold_post(grounded: bool) -> void:
	velocity.x = 0.0
	if grounded and _on_my_floor():
		if gap_behind(target_rect) <= HEAR_GAP and gap_behind(target_rect) > -BODY.x:
			_enter(State.TURN)
			return
		var gap := gap_to(target_rect)
		if gap <= SHOVE_GAP and gap > -target_rect.size.x - BODY.x * 0.5:
			_enter(State.WINDUP)
			alerted.emit()
			cue.emit(&"cloth", {"pitch": 0.5})
			cue.emit(&"masonry", {"pitch": 1.5, "volume_db": -12.0})
			return
		if gap <= BRACE_GAP and gap > -target_rect.size.x:
			if state != State.BRACE:
				_enter(State.BRACE)
			return
	if state == State.BRACE:
		_enter(State.STAND)
	var home := post_x - global_position.x
	if absf(home) > 0.5:
		velocity.x = signf(home) * RETURN_SPEED


func _on_my_floor() -> bool:
	if target_rect.size == Vector2.ZERO:
		return false
	return absf(target_rect.end.y - global_position.y) <= SAME_FLOOR


## From his front edge to the near side of `rect`, along the way he faces.
func gap_to(rect: Rect2) -> float:
	if rect.size == Vector2.ZERO:
		return INF
	var front := global_position.x + BODY.x * 0.5 * facing
	if facing > 0:
		return rect.position.x - front
	return front - rect.end.x


## From his back edge to the near side of `rect`, away from the way he faces.
func gap_behind(rect: Rect2) -> float:
	if rect.size == Vector2.ZERO:
		return INF
	var back := global_position.x - BODY.x * 0.5 * facing
	if facing > 0:
		return back - rect.end.x
	return rect.position.x - back


func _from_front(from_x: float) -> bool:
	var side := signf(from_x - global_position.x)
	return side == 0.0 or int(side) == facing


func _clang() -> void:
	clanged.emit()
	cue.emit(&"sword_hit", {"pitch": 0.55, "volume_db": -4.0})


func _enter(next: State) -> void:
	state = next
	state_time = 0.0
