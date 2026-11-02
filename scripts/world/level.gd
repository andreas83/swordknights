class_name Level
extends Node2D
## Builds a TileMapLayer from an ASCII level and answers the geometry
## questions the character asks.
##
## The tilemap carries the collision (solid and one-way are separate physics
## layers) while the logical queries below read the tile's custom "kind" data.
## That keeps a level hand-edited in the Godot editor working exactly like a
## parsed or generated one.

signal level_built(level: AsciiLevel)

const TILE := 16

@export_file("*.txt") var level_path: String = "res://levels/level_01.txt"

var data: AsciiLevel
var tilemap: TileMapLayer

var _tile_set: TileSet = preload("res://assets/tiles.tres")


func _ready() -> void:
	if data == null:
		build(AsciiLevel.from_file(level_path))


func build(level: AsciiLevel) -> void:
	if level == null:
		push_error("Level.build called with no data")
		return
	data = level

	if tilemap == null:
		tilemap = TileMapLayer.new()
		tilemap.name = "Tiles"
		tilemap.tile_set = _tile_set
		tilemap.collision_enabled = true
		add_child(tilemap)
	tilemap.clear()

	for y: int in data.rows:
		for x: int in data.cols:
			var coords := data.atlas_for(x, y)
			if coords.x >= 0:
				tilemap.set_cell(Vector2i(x, y), 0, coords)

	level_built.emit(data)


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
