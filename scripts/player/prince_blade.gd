class_name PrinceBlade
extends RefCounted
## The prince's sword as a thing in the world: in his hand, thrown, lying
## where it fell, or coming back to him.
##
##   HELD       in the hand -- he is armed
##   FLYING     thrown: level, at Tuning.THROW_SPEED, for Tuning.THROW_RANGE,
##              and the first foe it reaches takes it as Foe.Blow.THROWN
##   LOOSE      tumbling or lying: harmless, and his to pick up (down, over it)
##   RETURNING  flying back to the hand by itself: harmless, through anything
##
## The duel's DuelBlade is the model -- one record per sword, never a third --
## and the duel's file is not touched or shared: that blade lives in a rollback
## snapshot and is stepped by DuelCombat, this one is stepped by the Player
## that owns it, on the adventure's fixed tick, against the level's tiles.
## Because the Player steps it, a hitstop or a pause holds it with him, and a
## respawn puts it back in his hand without anyone else having to know.
##
## ## Why it comes back by itself
##
## A thrown sword must never cost the game. A blade that falls into a pit,
## into water, onto spikes, off the edge of the level, onto a ledge he cannot
## reach any more, or behind a gate that has shut, would leave a prince who
## cannot plunge through a Bastion or parry the King's beam for the rest of
## the attempt -- and only some of those places can be told from a tile. Two
## remedies were weighed:
##
## - **Back at the last checkpoint.** Leaves the sword where a proof can see
##   it, but the proof only says a torch reaches the door, not that he can
##   reach the torch from wherever he is now: a drop he has already taken can
##   strand him from it, and then it is a soft lock with extra steps.
## - **Back to the hand after a while.** Needs no proof of anything: wherever
##   he is, it comes to him.
##
## So it is the second. A blade left lying for Tuning.RECALL_TIME flies back
## to the hand, and one that is plainly lost -- in a hazard, below the level,
## outside it -- after Tuning.RECALL_LOST. The throw keeps its price, which is
## those seconds unarmed in a fight, and that price has a ceiling. Walking
## over and stooping for it is still the quicker way to have it back.

enum Mode { HELD, FLYING, LOOSE, RETURNING }

const GRAVITY := 900.0
const MAX_FALL := 360.0
## How fast a lying blade's slide dies, and how hard one that met stone or a
## foe is knocked back off it.
const SLIDE_FRICTION := 400.0
const KNOCK_BACK := Vector2(40.0, -70.0)
## Close enough to the hand to be caught.
const CATCH_DISTANCE := 4.0

var mode := Mode.HELD
## The centre of the blade, in world units.
var position := Vector2.ZERO
var velocity := Vector2.ZERO
## Which way it was thrown: the side a foe it reaches is struck from.
var direction := 1
## Pixels of level flight so far.
var flown := 0.0
## Seconds since it stopped flying, toward the recall.
var idle := 0.0
## In a hazard, below or outside the level: comes back after RECALL_LOST.
var lost := false
## On the floor and still.
var resting := false
## Where it bit into stone this step, for a cracked wall to answer
## (SecretKeeper.resolve()); empty on every other step.
var bite := Rect2()


func is_held() -> bool:
	return mode == Mode.HELD


func is_flying() -> bool:
	return mode == Mode.FLYING


func is_loose() -> bool:
	return mode == Mode.LOOSE


## Where it is, centred on its position; empty while it is in the hand.
func rect() -> Rect2:
	if mode == Mode.HELD:
		return Rect2()
	return Rect2(position - Tuning.THROW_SIZE * 0.5, Tuning.THROW_SIZE)


## The x a blow from it comes from: upstream of its flight, so a foe reads the
## side it was thrown from, as a parried shot is read (FoeProjectile.danger()).
func strike_from_x() -> float:
	return position.x - float(direction) * Tuning.TILE


## Back in the hand, with every world field cleared.
func hold() -> void:
	mode = Mode.HELD
	position = Vector2.ZERO
	velocity = Vector2.ZERO
	flown = 0.0
	idle = 0.0
	lost = false
	resting = false
	bite = Rect2()


func launch(from: Vector2, toward: int) -> void:
	mode = Mode.FLYING
	direction = 1 if toward >= 0 else -1
	position = from
	velocity = Vector2(direction * Tuning.THROW_SPEED, 0.0)
	flown = 0.0
	idle = 0.0
	lost = false
	resting = false


## It met something -- a foe, or stone -- and falls from where it is, knocked
## a little back the way it came.
func knock_down() -> void:
	mode = Mode.LOOSE
	velocity = Vector2(-direction * KNOCK_BACK.x, KNOCK_BACK.y)
	resting = false


## One fixed step. `hand` is where the prince's hand is, for the way back.
## True on the step it is back in the hand by itself.
func step(dt: float, level: Level, hand: Vector2) -> bool:
	bite = Rect2()
	match mode:
		Mode.FLYING:
			_fly(dt, level)
		Mode.LOOSE:
			_tumble(dt, level)
			_count_down(dt)
		Mode.RETURNING:
			var to_hand := hand - position
			var reach := Tuning.RETURN_SPEED * dt
			if to_hand.length() <= reach + CATCH_DISTANCE:
				hold()
				return true
			velocity = to_hand.normalized() * Tuning.RETURN_SPEED
			position += velocity * dt
	return false


func _fly(dt: float, level: Level) -> void:
	var travel := velocity * dt
	var tip := position + Vector2(direction * Tuning.THROW_SIZE.x * 0.5, 0.0) + travel
	if level != null and level.is_solid_at(tip):
		# The point goes into the stone by a pixel, which is what a cracked
		# wall's seal is checked against, and the blade drops off it.
		bite = Rect2(tip.x if direction > 0 else tip.x - 2.0, tip.y - 1.0, 2.0, 2.0)
		knock_down()
		return
	position += travel
	flown += absf(travel.x)
	if flown >= Tuning.THROW_RANGE:
		# Spent: it tumbles from here, harmless, and lies where it lands.
		mode = Mode.LOOSE
		velocity = Vector2(direction * Tuning.THROW_SPEED * 0.2, 0.0)
	if level != null and _outside(level):
		mode = Mode.LOOSE
		lost = true


func _tumble(dt: float, level: Level) -> void:
	if resting:
		return
	velocity.y = minf(velocity.y + GRAVITY * dt, MAX_FALL)
	velocity.x = move_toward(velocity.x, 0.0, SLIDE_FRICTION * dt)
	if level == null:
		position += velocity * dt
		return
	var next_x := position.x + velocity.x * dt
	if level.is_solid_at(Vector2(next_x, position.y)):
		velocity.x = 0.0
	else:
		position.x = next_x
	var half := Tuning.THROW_SIZE.y * 0.5
	var bottom := position.y + half
	var next_bottom := bottom + velocity.y * dt
	var floor_y := floorf(next_bottom / Level.TILE) * Level.TILE
	var kind := level.kind_at_world(Vector2(position.x, next_bottom))
	var lands := kind == Tiles.Kind.SOLID or (kind == Tiles.Kind.PLATFORM and bottom <= floor_y)
	if velocity.y > 0.0 and lands:
		position.y = floor_y - half
		velocity = Vector2.ZERO
		resting = true
	else:
		position.y += velocity.y * dt
	if level.rect_is_deadly(rect()) or _outside(level):
		lost = true


func _count_down(dt: float) -> void:
	idle += dt
	if idle >= (Tuning.RECALL_LOST if lost else Tuning.RECALL_TIME):
		mode = Mode.RETURNING
		resting = false


func _outside(level: Level) -> bool:
	var world := level.world_size()
	return position.x < 0.0 or position.x > world.x or position.y > world.y + Level.TILE
