class_name Patrol
extends CharacterBody2D
## A hooded guard that walks its ledge and turns at walls and at drops.
##
## Deliberately minimal: it exists so the damage, hit reaction and combat
## plumbing is exercised end to end by something in the level.

signal defeated()

const SPEED := 26.0
const GRAVITY := 900.0
const MAX_FALL := 320.0
const STAGGER_TIME := 0.4
const BODY := Vector2(10.0, 20.0)

var level: Level
var facing: int = -1
var health: int = 2

var _stagger: float = 0.0
var _walk_phase: float = 0.0


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


func bounds() -> Rect2:
	return Rect2(global_position - Vector2(BODY.x * 0.5, BODY.y), BODY)


## Returns true when this hit killed it.
func hit(from_x: float) -> bool:
	health -= 1
	_stagger = STAGGER_TIME
	var away := signf(global_position.x - from_x)
	velocity = Vector2((away if away != 0.0 else 1.0) * 120.0, -110.0)
	if health <= 0:
		defeated.emit()
		queue_free()
		return true
	return false


func _physics_process(delta: float) -> void:
	velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)

	if _stagger > 0.0:
		_stagger -= delta
		velocity.x *= 0.88
	else:
		velocity.x = facing * SPEED
		_walk_phase += delta * 6.0
		if level != null:
			var ahead_x := global_position.x + (BODY.x * 0.5 + 2.0) * facing
			var wall := level.is_solid_at(Vector2(ahead_x, global_position.y - 4.0))
			var ground_kind := level.kind_at_world(Vector2(ahead_x, global_position.y + 2.0))
			var ground := ground_kind == Tiles.Kind.SOLID or ground_kind == Tiles.Kind.PLATFORM
			if wall or (not ground and is_on_floor()):
				facing = -facing
				velocity.x = 0.0

	move_and_slide()
	if is_on_wall() and _stagger <= 0.0:
		facing = -facing

	if level != null and global_position.y > level.world_size().y + 64.0:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var sway := 0.0 if _stagger > 0.0 else sin(_walk_phase) * 0.8
	var hem := 0.0
	var top := -BODY.y

	draw_colored_polygon(PackedVector2Array([
		Vector2(sway, top + 2.0),
		Vector2(BODY.x * 0.78 + sway * 0.4, hem),
		Vector2(-BODY.x * 0.78 + sway * 0.4, hem),
	]), Palette.CLOTH_DARK)
	draw_colored_polygon(PackedVector2Array([
		Vector2(sway, top + 2.0),
		Vector2(BODY.x * 0.78 * facing + sway * 0.4, hem),
		Vector2(sway * 0.4, hem),
	]), Palette.CLOTH)
	draw_circle(Vector2(sway, top + 4.0), 3.4, Palette.INK)
	draw_rect(Rect2(sway - 0.6 + facing * 1.4, top + 3.2, 1.4, 1.2), Palette.LIGHT)
