class_name DuelBlade
extends RefCounted
## One sword, as a thing in the world rather than a property of a fighter.
##
## Every fighter owns exactly one of these for the whole match. It is in one of
## three places:
##
##   HELD    in that fighter's hand — the fighter is armed
##   FLYING  thrown: a straight line, no gravity, lethal on contact
##   LOOSE   dropped or landed: falls to the floor and lies there to be picked up
##
## There are therefore never more than two swords in the arena, which is what
## lets the whole of the duel's sword state ride inside the two fighters'
## snapshots with nothing hiding in a third place. Swords are indistinguishable,
## so when a fighter picks one up that belongs to the other fighter's record,
## DuelCombat swaps the two records rather than inventing a third slot: the
## count is conserved and the player cannot tell the difference.
##
## A fighter always respawns holding its own record's blade, wherever that
## blade was lying — see Fighter.respawn_at().

enum Mode { HELD, FLYING, LOOSE }

## Bytes this record occupies in a snapshot. Positions and velocities are
## doubles for the reason docs/netplay.md gives: half of what a duel compares
## against a threshold is a GDScript float, and rounding those to 32 bits moves
## a transition by a frame often enough to matter.
const BYTES := 44

var mode: Mode = Mode.HELD
var position := Vector2.ZERO
var velocity := Vector2.ZERO
## The height band a thrown blade flies at, and the stance it was thrown from.
var stance: int = DuelTuning.Stance.MID
## Whose throw this was, for `died(victim_id, killer_id)`. -1 when nobody's.
var thrown_by: int = -1


## Back in the hand, with every world field cleared so two fighters holding
## their swords have byte-identical blade records.
func hold() -> void:
	mode = Mode.HELD
	position = Vector2.ZERO
	velocity = Vector2.ZERO
	thrown_by = -1


func is_held() -> bool:
	return mode == Mode.HELD


func is_loose() -> bool:
	return mode == Mode.LOOSE


## Leaves the hand on a straight line. No gravity: the spec asks for a
## trajectory parallel to the ground, angled slightly up with `up`.
func launch(from: Vector2, at_stance: int, direction: int, by: int, tuning: DuelTuning,
		rising: bool) -> void:
	mode = Mode.FLYING
	position = from
	stance = at_stance
	thrown_by = by
	velocity = Vector2(direction * tuning.throw_speed, -tuning.throw_rise if rising else 0.0)


## Falls out of the hand, with a little scatter backwards so a disarm reads as
## one and the blade does not land exactly under the fighter who lost it.
func drop(from: Vector2, at_stance: int, away: int, tuning: DuelTuning) -> void:
	mode = Mode.LOOSE
	position = from
	stance = at_stance
	thrown_by = -1
	velocity = Vector2(away * tuning.clash_knockback * 0.5, -tuning.clash_knockback * 0.5)


func rect(tuning: DuelTuning) -> Rect2:
	if mode == Mode.HELD:
		return Rect2()
	return tuning.loose_blade_rect(position)


## One frame of a loose or flying sword. Axis by axis against the arena grid —
## a pure data lookup, no physics query and no engine state, so a replayed
## frame lands the blade on the same pixel.
func step(dt: float, tuning: DuelTuning, world: DuelWorld) -> void:
	if mode == Mode.HELD or world == null:
		return
	if mode == Mode.LOOSE:
		# A sword that has landed stays exactly where it landed. It does not
		# skid: a dropped sword is a landmark both fighters are navigating
		# toward, so it being where it fell matters more than it sliding.
		if _is_supported(tuning, world):
			velocity = Vector2.ZERO
			return
		velocity.y = minf(velocity.y + tuning.blade_fall_gravity * dt, tuning.max_fall_speed)
	elif velocity == Vector2.ZERO:
		mode = Mode.LOOSE
		return

	var step_x := Vector2(velocity.x * dt, 0.0)
	if world.rect_hits_solid(tuning.loose_blade_rect(position + step_x)):
		velocity.x = 0.0
		mode = Mode.LOOSE
	else:
		position += step_x

	var step_y := Vector2(0.0, velocity.y * dt)
	if world.rect_hits_solid(tuning.loose_blade_rect(position + step_y)):
		velocity.y = 0.0
		mode = Mode.LOOSE
	else:
		position += step_y

	# A throw that leaves the arena is gone rather than flying forever: the
	# position is in the checksum, so an unbounded coordinate is a real bug.
	var bounds := world.world_size()
	if position.x < -tuning.blade_length or position.x > bounds.x + tuning.blade_length \
			or position.y > bounds.y:
		velocity = Vector2.ZERO
		mode = Mode.LOOSE


## Whether something solid is directly under the blade. A grid lookup, not a
## physics query: the position is in the checksum, so this has to be the same
## answer on every machine.
func _is_supported(tuning: DuelTuning, world: DuelWorld) -> bool:
	return world.rect_hits_solid(tuning.loose_blade_rect(position + Vector2(0.0, 1.0)))


func write(into: PackedByteArray, at: int) -> void:
	into.encode_double(at + 0, position.x)
	into.encode_double(at + 8, position.y)
	into.encode_double(at + 16, velocity.x)
	into.encode_double(at + 24, velocity.y)
	into.encode_s32(at + 32, int(mode))
	into.encode_s32(at + 36, stance)
	into.encode_s32(at + 40, thrown_by)


func read(from: PackedByteArray, at: int) -> void:
	position = Vector2(from.decode_double(at + 0), from.decode_double(at + 8))
	velocity = Vector2(from.decode_double(at + 16), from.decode_double(at + 24))
	mode = from.decode_s32(at + 32) as Mode
	stance = from.decode_s32(at + 36)
	thrown_by = from.decode_s32(at + 40)
