class_name FireLight
extends Node2D
## A torch's light on the stone around it, at night: the Sun Well's whole
## lighting (docs/campaign.md, "V. The Sun Well": underground, the only light
## is fire).
##
## ## Light on surfaces, not in the air
##
## The art direction allows no glow, no bloom and no gradient, which rules out
## the usual halo. What it allows is what fire does to a wall: the masonry
## within reach of the flame is lit, hard-edged, and the air is not. So the
## pool is two flat discs -- an inner one in LIGHT_WARM and a wider one in MID,
## added onto the stone -- cut to the level's stone and backdrop cells, and
## nothing is drawn over open air. Standing in the pool, a ledge's edge is a
## warm line against the dark: the night is dark, and the way on is lit.
##
## ## Stepping, not shimmering
##
## The radii step with the torch's own flame clock (Torch.FLAME_FPS, twelve
## drawings a second, at integer radii), so the pool changes shape the way the
## flame does: three drawings, cut once when the level is built, and chosen
## by the clock.
##
## ## Under everything that moves
##
## It is a child of the Level, after the tile layers, so it is drawn on the
## terrain and under the prince, the foes and the mechanisms, which keep their
## own light (MatchDusk.LIT); it is in that group itself, so the night's grade
## does not take the fire down with the stone it lights. Presentation only:
## nothing here touches the simulation. An hour that is not night gets none --
## the sun is still the light there.

## Per flicker step: the inner and outer radius, in pixels.
const STEPS := [Vector2(40.0, 66.0), Vector2(42.0, 69.0), Vector2(39.0, 64.0)]
const INNER := Color(Palette.LIGHT_WARM, 0.2)
const OUTER := Color(Palette.MID, 0.12)
## Points on a disc's rim: enough that the steps between them do not read.
const SEGMENTS := 40

var level: Level
## Per step: [inner polygons, outer polygons], each cut to the stone.
var _shapes: Array = []
var _time := 0.0
var _phase := 0.0


## Lights `torch`'s stone if `level` is set at night, and puts the light out
## with the torch. Returns the light, or null for an hour with a sun.
static func kindle(torch: Node2D, at_level: Level) -> FireLight:
	if at_level == null or at_level.data == null:
		return null
	if TimeOfDay.stop_of(at_level.data) != "night":
		return null
	var light := FireLight.new()
	light.name = "FireLight"
	light.level = at_level
	light.position = torch.position + Vector2(0.0, Torch.TOP + 1.0)
	at_level.add_child(light)
	torch.tree_exiting.connect(light.queue_free)
	return light


func _ready() -> void:
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = add
	add_to_group(MatchDusk.LIT)
	_phase = fmod(position.x * 0.37 + position.y * 0.11, TAU)
	for radii: Vector2 in STEPS:
		_shapes.append([_cut(radii.x), _cut(radii.y)])


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if _shapes.is_empty():
		return
	var step := posmod(floori(_time * Torch.FLAME_FPS + _phase * 3.0), _shapes.size())
	var shape: Array = _shapes[step]
	for polygon: PackedVector2Array in shape[1]:
		draw_colored_polygon(polygon, OUTER)
	for polygon: PackedVector2Array in shape[0]:
		draw_colored_polygon(polygon, INNER)


## The disc of `radius` round this light, cut to the stone and backdrop
## cells it covers, in local coordinates.
func _cut(radius: float) -> Array[PackedVector2Array]:
	var disc := PackedVector2Array()
	for i: int in SEGMENTS:
		var a := TAU * float(i) / float(SEGMENTS)
		disc.append(Vector2(cos(a), sin(a)) * radius)
	var out: Array[PackedVector2Array] = []
	if level == null or level.data == null:
		return out
	var tile := Level.TILE
	var reach := ceili(radius / tile) + 1
	var home := Vector2i(floori(position.x / tile), floori(position.y / tile))
	for y: int in range(home.y - reach, home.y + reach + 1):
		for x: int in range(home.x - reach, home.x + reach + 1):
			var kind := level.data.kind_at(x, y)
			if kind != Tiles.Kind.SOLID and kind != Tiles.Kind.BACKDROP:
				continue
			var cell := Rect2(Vector2(x, y) * tile - position, Vector2(tile, tile))
			var square := PackedVector2Array([cell.position, Vector2(cell.end.x, cell.position.y),
				cell.end, Vector2(cell.position.x, cell.end.y)])
			for part: PackedVector2Array in Geometry2D.intersect_polygons(disc, square):
				if part.size() >= 3:
					out.append(part)
	return out
