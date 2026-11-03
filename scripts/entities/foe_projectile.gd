class_name FoeProjectile
extends Node2D
## Something a foe looses -- an arrow, a knife, a stone -- that is a danger in
## its own right once it leaves the hand.
##
## A foe makes one, sets its `velocity` (and `size` and `damage` if it means
## something else) and hands it to Foe.launch(). From there it belongs to the
## level: Game adopts it into the entities, so a hitstop holds it in the air,
## a restart or a checkpoint respawn clears it, and the prince meets it
## through the same three outcomes as a cut (scripts/entities/foe_danger.gd):
##
## - **Parried**, it goes back the way it came, RETURN_SPEED times faster, and
##   is now the prince's: it no longer hurts him and it wounds the first foe
##   it meets -- its own archer included -- as `Foe.Blow.SHOT`. That is the
##   hook a boss fight is built on.
## - **Evaded**, it flies on; by default it cannot be. A backstep is a step
##   out from under a blade coming down, and an arrow at chest height is
##   still at chest height a step later.
## - **Landed**, it is spent, whether or not his grace refused the damage: it
##   struck him either way.
##
## It is spent, too, on the first solid cell it flies into, when LIFE runs
## out, and when it leaves the level. Moved in `_physics_process` at the fixed
## step, never on the display clock, so where it is is a fact of the frame.
##
## The default look is a shaft and a steel head along its flight, in the
## palette's ink and steel, so a toy arrow in a test is visible in a
## screenshot. A real one overrides `_draw()`.

## Emitted once, when it is done for any reason.
signal spent()

## A parried projectile goes back this much faster than it came.
const RETURN_SPEED := 1.25
## Seconds of flight before it is spent on its own.
const LIFE := 4.0

var velocity := Vector2.ZERO
var size := Vector2(10.0, 2.0)
var damage := 1
var level: Level
## Who loosed it. May be freed while it flies; check with is_instance_valid().
var source: Foe
## Sent back by a parry: it hurts foes now, not the prince.
var reflected := false
var life := LIFE

var _spent := false


## Where it is, in world units, centred on its position.
## A shot is a danger, so the hour never dims it (WorldGrade).
func _ready() -> void:
	add_to_group(MatchDusk.LIT)


func rect() -> Rect2:
	return Rect2(global_position - size * 0.5, size)


func is_spent() -> bool:
	return _spent


## What it threatens this frame, or null once it is spent or turned. Comes
## from a point upstream of its flight, so the parry and the backstep read
## the prince's facing against the side it was loosed from.
func danger() -> FoeDanger:
	if _spent or reflected:
		return null
	var threat := FoeDanger.make(rect(), global_position.x - velocity.x, damage)
	threat.evadable = false
	threat.parry = reflect
	threat.on_landed = func(_dealt: bool) -> void: spend()
	return threat


## A parry met it: back the way it came, faster, and the prince's now.
func reflect() -> bool:
	if _spent or reflected:
		return false
	reflected = true
	velocity = -velocity * RETURN_SPEED
	queue_redraw()
	return true


## Done: the signal, then gone.
func spend() -> void:
	if _spent:
		return
	_spent = true
	spent.emit()
	queue_free()


## --- the entity protocol ------------------------------------------------------

## Straight back to Game, which resolves it as a danger, or, once reflected,
## against the foes.
func meet(contact: Contact) -> void:
	contact.meet_shot(self)


func _physics_process(delta: float) -> void:
	if _spent:
		return
	position += velocity * delta
	life -= delta
	if life <= 0.0:
		spend()
		return
	if level == null:
		return
	var world := level.world_size()
	var out := global_position.x < 0.0 or global_position.x > world.x \
		or global_position.y > world.y + 64.0
	if out or level.is_solid_at(global_position):
		spend()


func _draw() -> void:
	var half := roundf(size.x * 0.5)
	draw_rect(Rect2(-half, 0.0, half * 2.0, 1.0), Palette.INK)
	# The head leads: at the end it flies toward.
	var tip := half - 2.0 if velocity.x >= 0.0 else -half
	draw_rect(Rect2(tip, -1.0, 2.0, 3.0), Palette.STEEL)
