class_name Sunbolt
extends FoeProjectile
## A sunbolt: the sun gathered in a burning glass and thrown, 8 x 2 pixels of
## light at 150 px/s (docs/campaign.md, "The Glassbearer").
##
## ## It is light
##
## What sets it apart from an arrow is that the world treats it as light:
##
## - **A mirror redirects it.** Entering a sun mirror's cell, it is turned to
##   fly from the mirror's pivot the way the mirror's face points, at the same
##   speed. A mirror mid-turn swallows it. That is Chapter IV's twist: where
##   no sun reaches, a Glassbearer's bolts are the light, and a mirror in his
##   line of fire throws them wherever it points -- and is cover while it
##   does.
## - **A sun-seal takes it as a full fill** (SunSeal.take_bolt()): the bolt
##   is spent on the seal's stone, and the seal opens.
## - **It stops where a beam stops** -- stone and one-way platforms -- by the
##   same test (SunField.stops_light()), and passes everything a beam passes.
##
## ## Whose it is
##
## Until a parry turns it, it hurts any body it reaches, one heart: the
## prince through Game's danger rules (FoeProjectile), and any other foe --
## a sentinel in the line, another Glassbearer -- here, because a bolt that
## only ever hurt the prince would make "stand where a sentinel takes it" a
## lie. Not the hand that threw it: a bolt leaves its own glass. Parried, it
## goes back RETURN_SPEED times faster and is the prince's, and Game sends it
## into the first foe it meets, its own Glassbearer included -- the kill the
## parry is for.
##
## Kept to what any thrower needs -- a speed, a direction, a size -- so the
## boss's volleys can be the same bolt thrown harder (`make()`).

## Presentation, through Game: GameAudio.cue and the impact budget.
signal cue(voice: StringName, options: Dictionary)
signal impact(at: Vector2, frames: int, shake: float, weight: float)

## 150 px/s: 2.5 px a frame.
const SPEED := 150.0
## Along its flight, and across it.
const LENGTH := 8.0
const THICK := 2.0

## The mirror cell it was last turned in, so it is not turned again while it
## is still crossing that cell.
var _turned_in := Vector2i(-1, -1)


## A bolt at `at` flying along `direction` (a unit step) at `speed`.
static func make(at: Vector2, direction: Vector2, speed: float = SPEED) -> Sunbolt:
	var bolt := Sunbolt.new()
	bolt.position = at
	bolt.velocity = direction.normalized() * speed
	bolt._fit()
	return bolt


## Long along its flight: a bolt turned up a shaft by a mirror is tall.
func _fit() -> void:
	size = Vector2(LENGTH, THICK) if absf(velocity.x) >= absf(velocity.y) \
		else Vector2(THICK, LENGTH)


func reflect() -> bool:
	if not super():
		return false
	_fit()
	return true


func meet(contact: Contact) -> void:
	if is_spent():
		return
	if not reflected and _strike_bystander():
		return
	contact.meet_shot(self)


## The first foe it is touching that did not throw it takes it, one heart.
func _strike_bystander() -> bool:
	if not is_inside_tree():
		return false
	var box := rect()
	for node: Node in get_tree().get_nodes_in_group(Foe.GROUP):
		var foe := node as Foe
		if foe == null or foe == source or not foe.is_alive():
			continue
		if level != null and foe.level != level:
			continue
		if not box.intersects(foe.hurt_rect()):
			continue
		var outcome := foe.take_blow(Foe.Blow.SHOT, global_position.x - velocity.x)
		if outcome == Foe.Outcome.WOUNDED or outcome == Foe.Outcome.KILLED:
			cue.emit(foe.wound_voice(), {})
			impact.emit(foe.global_position, 2, 1.0, 0.4)
		spend()
		return true
	return false


func _physics_process(delta: float) -> void:
	if is_spent():
		return
	life -= delta
	if life <= 0.0:
		spend()
		return
	var next := global_position + velocity * delta
	if level == null:
		position = next
		return
	var world := level.world_size()
	if next.x < 0.0 or next.x > world.x or next.y > world.y + 64.0 or next.y < -64.0:
		spend()
		return
	var cell := level.cell_of(next)
	if cell != _turned_in and _meet_mirror(cell):
		return
	if SunField.stops_light(level.kind_at_cell(cell)):
		_strike_stone(cell, next)
		return
	position = next


## Entering a mirror's cell: turned along its face from its pivot, or
## swallowed by one that is mid-turn. True when a mirror took it.
func _meet_mirror(cell: Vector2i) -> bool:
	var mirror := SunField.mirror_at(level, cell)
	if mirror == null:
		return false
	if mirror.is_turning():
		spend()
		return true
	_turned_in = cell
	global_position = SunLight.pivot(cell)
	velocity = Vector2(SunLight.step_of(mirror.face)) * velocity.length()
	_fit()
	cue.emit(&"sword_hit", {"pitch": 2.1, "volume_db": -14.0})
	return true


## Stone: a seal is filled by it; anything else only rings.
func _strike_stone(cell: Vector2i, at: Vector2) -> void:
	var seal := SunField.seal_at(level, cell)
	if seal != null:
		seal.take_bolt()
	else:
		cue.emit(&"sword_hit", {"pitch": 1.9, "volume_db": -12.0})
	global_position = at
	spend()


## A streak of light: PAPER at the head, LIGHT_SOFT behind it.
func _draw() -> void:
	var along := velocity.normalized() if velocity != Vector2.ZERO else Vector2.RIGHT
	var half := LENGTH * 0.5
	var tail := (-along * half).floor()
	var head := (along * (half - 1.0)).floor()
	var across := Vector2(absf(along.y), absf(along.x))
	var body := Rect2(Vector2(minf(tail.x, head.x), minf(tail.y, head.y)),
		(head - tail).abs() + Vector2.ONE + across)
	draw_rect(body, Palette.LIGHT_SOFT)
	draw_rect(Rect2(head - across * 0.0, Vector2.ONE + across), Palette.PAPER)
	if reflected:
		# Sent back, it carries the parry's steel at its tail: the prince's now.
		draw_rect(Rect2(tail, Vector2.ONE + across), Palette.STEEL)
