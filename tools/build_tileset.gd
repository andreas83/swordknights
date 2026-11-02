extends SceneTree
## Builds assets/tiles.tres from assets/tiles.png.
##
## The TileSet is configuration, not art, so it is generated from code rather
## than clicked together in the editor: the collision shapes, the one-way flag
## and the custom "kind" data all derive from scripts/world/tiles.gd and cannot
## drift away from the gameplay queries that read them.
##
##     python3 tools/generate_tiles_png.py
##     godot --headless --script tools/build_tileset.gd

const OUTPUT := "res://assets/tiles.tres"
const TEXTURE := "res://assets/tiles.png"
const TILE_SIZE := Vector2i(16, 16)

## A full-tile collision square. Not a const: GDScript will not fold Vector2
## constructors into a constant expression.
static func full_square() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8),
	])


func _initialize() -> void:
	if not ResourceLoader.exists(TEXTURE):
		push_error("%s missing — run tools/generate_tiles_png.py first" % TEXTURE)
		quit(1)
		return

	var tile_set := TileSet.new()
	tile_set.tile_size = TILE_SIZE

	tile_set.add_physics_layer()
	tile_set.set_physics_layer_collision_layer(Tiles.PHYSICS_SOLID, Tiles.MASK_SOLID)
	tile_set.add_physics_layer()
	tile_set.set_physics_layer_collision_layer(Tiles.PHYSICS_ONE_WAY, Tiles.MASK_ONE_WAY)

	tile_set.add_custom_data_layer()
	tile_set.set_custom_data_layer_name(0, Tiles.CUSTOM_DATA_KIND)
	tile_set.set_custom_data_layer_type(0, TYPE_INT)

	var source := TileSetAtlasSource.new()
	source.texture = load(TEXTURE)
	source.texture_region_size = TILE_SIZE
	tile_set.add_source(source, 0)

	for coords: Vector2i in Tiles.ALL_ATLAS_COORDS:
		source.create_tile(coords)
		var data := source.get_tile_data(coords, 0)
		var kind := Tiles.kind_of_atlas(coords)
		data.set_custom_data(Tiles.CUSTOM_DATA_KIND, int(kind))

		match kind:
			Tiles.Kind.SOLID:
				data.add_collision_polygon(Tiles.PHYSICS_SOLID)
				data.set_collision_polygon_points(Tiles.PHYSICS_SOLID, 0, full_square())
			Tiles.Kind.PLATFORM:
				data.add_collision_polygon(Tiles.PHYSICS_ONE_WAY)
				data.set_collision_polygon_points(Tiles.PHYSICS_ONE_WAY, 0, full_square())
				data.set_collision_polygon_one_way(Tiles.PHYSICS_ONE_WAY, 0, true)
			_:
				pass # hazards, ladders and backdrop are queried, not collided with

	var err := ResourceSaver.save(tile_set, OUTPUT)
	if err != OK:
		push_error("could not save %s: %d" % [OUTPUT, err])
		quit(1)
		return

	print("wrote %s — %d tiles, 2 physics layers" % [OUTPUT, Tiles.ALL_ATLAS_COORDS.size()])
	quit(0)
