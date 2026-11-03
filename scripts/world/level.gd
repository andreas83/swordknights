class_name Level
extends Node2D
## Builds a level's world from an ASCII file and answers the geometry
## questions the character asks.
##
## Three drawn planes, which is the art direction's depth model:
##
##   Tiles  the terrain the player touches. Carries the collision (solid and
##          one-way are separate physics layers) and the queried "kind".
##   Decor  mid-ground architecture: cornices, arcades, balustrades, columns.
##          Behind the player, in front of the terrain, no collision.
##   Props  the room moods (WorldDresser): wear and ivy over the stone, jars,
##          palms and lanterns in front of the architecture. Same plane as
##          Decor, one layer up, so an urn does not cost a cornice its cell.
##   Fore   the foreground plane: railings, column bases, arch soffits,
##          hanging cloth. z_index puts it in FRONT of the player, which is
##          the cheapest depth cue there is.
##
## Over the first two lies the cast-shadow mask (scripts/render/sun_shadow.gd):
## one sun, solved once, sampled by assets/world_shadow.gdshader. The
## foreground plane is already near-silhouette and does not sample it.
##
## The logical queries read the tilemap's custom "kind" data, so a level hand
## edited in the Godot editor works exactly like a parsed or generated one.

signal level_built(level: AsciiLevel)

const TILE := 16
## In front of the player, whose z_index is 0.
const FOREGROUND_Z := 10

@export_file("*.txt") var level_path: String = "res://levels/level_01.txt"

var data: AsciiLevel
var tilemap: TileMapLayer
var decor_map: TileMapLayer
var props_map: TileMapLayer
var foreground_map: TileMapLayer
## Dust in the light and falling leaves; scripts/render/ambience.gd.
var ambience: LevelAmbience
## Milliseconds the last shadow solve took. Read by tests and docs/world.md.
var shadow_build_ms: float = 0.0

var _tile_set: TileSet = preload("res://assets/tiles.tres")
var _shader: Shader = preload("res://assets/world_shadow.gdshader")
var _atlas_image: Image


func _ready() -> void:
	if data == null:
		build(AsciiLevel.from_file(level_path))


func build(level: AsciiLevel) -> void:
	if level == null:
		push_error("Level.build called with no data")
		return
	data = level

	tilemap = _ensure_layer(tilemap, "Tiles", true, 0)
	decor_map = _ensure_layer(decor_map, "Decor", false, 0)
	props_map = _ensure_layer(props_map, "Props", false, 0)
	foreground_map = _ensure_layer(foreground_map, "Fore", false, FOREGROUND_Z)

	for layer: TileMapLayer in [tilemap, decor_map, props_map, foreground_map]:
		layer.clear()

	for y: int in data.rows:
		for x: int in data.cols:
			var coords := data.atlas_for(x, y)
			if coords.x >= 0:
				tilemap.set_cell(Vector2i(x, y), 0, coords)

	var dressing := WorldDresser.dress(data)
	_paint(decor_map, dressing["mid"])
	_paint(props_map, dressing["props"])
	_paint(foreground_map, dressing["fore"])

	_apply_sun(dressing["mid"], dressing["props"])

	# The air last: it needs the solved shadow to know where the light is.
	if ambience == null:
		ambience = LevelAmbience.new()
		ambience.name = "Ambience"
		add_child(ambience)
	ambience.setup(data, dressing["props"], SunShadow.last_mask, TILE)
	level_built.emit(data)


func _ensure_layer(layer: TileMapLayer, layer_name: String, collide: bool,
		z: int) -> TileMapLayer:
	if layer != null:
		return layer
	var made := TileMapLayer.new()
	made.name = layer_name
	made.tile_set = _tile_set
	made.collision_enabled = collide
	made.z_index = z
	add_child(made)
	return made


static func _paint(layer: TileMapLayer, cells: Dictionary) -> void:
	for cell: Vector2i in cells:
		layer.set_cell(cell, 0, cells[cell])


## Solves the cast shadow and hands the mask to the two planes that receive
## it. Everything here happens once per level build and nothing re-runs it.
func _apply_sun(mid_decor: Dictionary, props: Dictionary) -> void:
	if _atlas_image == null:
		var atlas := _tile_set.get_source(0) as TileSetAtlasSource
		if atlas == null or atlas.texture == null:
			push_error("Level: tile set has no atlas texture; no shadows")
			return
		_atlas_image = atlas.texture.get_image()

	var started := Time.get_ticks_usec()
	var mask := SunShadow.build(data, mid_decor, TILE, _atlas_image, props)
	shadow_build_ms = float(Time.get_ticks_usec() - started) / 1000.0

	var material := ShaderMaterial.new()
	material.shader = _shader
	material.set_shader_parameter("shadow_mask", mask)
	material.set_shader_parameter("level_px", world_size())
	material.set_shader_parameter(
		"shade_v", float(Tiles.SHADE_ROW_OFFSET * TILE) / float(_atlas_image.get_height())
	)
	tilemap.material = material
	decor_map.material = material
	props_map.material = material


## --- geometry queries ------------------------------------------------------

func world_size() -> Vector2:
	return Vector2(data.cols * TILE, data.rows * TILE)


func cell_of(world_position: Vector2) -> Vector2i:
	return Vector2i(floori(world_position.x / TILE), floori(world_position.y / TILE))


func kind_at_cell(cell: Vector2i) -> Tiles.Kind:
	return data.kind_at(cell.x, cell.y)


func kind_at_world(world_position: Vector2) -> Tiles.Kind:
	return kind_at_cell(cell_of(world_position))


func is_solid_cell(cell: Vector2i) -> bool:
	return data.is_solid(cell.x, cell.y)


func is_solid_at(world_position: Vector2) -> bool:
	return is_solid_cell(cell_of(world_position))


## True if any tile of one of `kinds` overlaps the rect.
func rect_has_kind(rect: Rect2, kinds: Array) -> bool:
	var x0 := floori(rect.position.x / TILE)
	var x1 := floori((rect.position.x + rect.size.x - 0.001) / TILE)
	var y0 := floori(rect.position.y / TILE)
	var y1 := floori((rect.position.y + rect.size.y - 0.001) / TILE)
	for y: int in range(y0, y1 + 1):
		for x: int in range(x0, x1 + 1):
			if kinds.has(data.kind_at(x, y)):
				return true
	return false


func rect_is_deadly(rect: Rect2) -> bool:
	return rect_has_kind(rect, [Tiles.Kind.SPIKES, Tiles.Kind.WATER])


func rect_is_climbable(rect: Rect2) -> bool:
	return rect_has_kind(rect, [Tiles.Kind.LADDER])


func rect_hits_solid(rect: Rect2) -> bool:
	return rect_has_kind(rect, [Tiles.Kind.SOLID])


func spawn_world_position() -> Vector2:
	## Bottom centre of the spawn cell, which is where the character's feet go.
	return Vector2(data.spawn_point.x * TILE + TILE * 0.5, (data.spawn_point.y + 1) * TILE)


func entity_world_position(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE + TILE * 0.5, (cell.y + 1) * TILE)
