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
##
## Secret rooms (docs/world.md, "Secrets") are drawn by a SecretView child:
## everything here paints the level as it really is, except that the picture
## — terrain caps, dressing, the sealed shadow — is taken from the facade, the
## level as it looks before anything is found. The view lays the stone over
## each room and lifts it again.
##
## The duel's zones are drawn by this same path, a zone at a time: the layers,
## the paint and the sun's material are the static helpers below, and
## scripts/duel/zones_view.gd calls them rather than keeping a second copy.
##
## ## The overlay
##
## A mechanism that changes what a cell is -- a gate shutting, a floor giving
## way -- does not repaint the tilemap. It brings its own collision body on
## the solid or one-way layer, which the character's own move_and_slide()
## meets like stone, and it writes the cell's new kind here, which every query
## below reads first. Both halves are needed: the body is what stops the
## character, and the queries are what his ledge grab, his footing, his
## stand-up room and the hazard check ask. A gate that only had a body could
## not be grabbed and could be stood up into; one that only had an overlay
## would let him walk through it. Each entry remembers who wrote it, so a
## mechanism that leaves only takes its own cells with it. Empty -- every
## level without a mechanism -- the queries are exactly what they were.

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
## The secret rooms' covers, tells and reveals; null in a level without any.
var secret_view: SecretView
## Milliseconds the last shadow solve took. Read by tests and docs/world.md.
var shadow_build_ms: float = 0.0

const TILE_SET: TileSet = preload("res://assets/tiles.tres")
const SUN_SHADER: Shader = preload("res://assets/world_shadow.gdshader")

## The atlas as an image, which the shadow solve reads tile opacity from. The
## atlas does not change while the game runs, so it is read once.
static var _atlas_image: Image

## --- mechanisms --- cell -> Tiles.Kind, and cell -> the instance id that set
## it. See "The overlay" above.
var _overlay: Dictionary = {}
var _overlay_owner: Dictionary = {}


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
	if secret_view != null:
		remove_child(secret_view)
		secret_view.queue_free()
		secret_view = null

	# What is drawn is the facade; what is under a secret's cover is the truth.
	var seen := data.facade() if not data.secrets.is_empty() else data
	for y: int in data.rows:
		for x: int in data.cols:
			var hidden := seen.secret_at(Vector2i(x, y)) >= 0 and not data.is_solid(x, y)
			var coords := (data if hidden else seen).atlas_for(x, y)
			if coords.x >= 0:
				tilemap.set_cell(Vector2i(x, y), 0, coords)

	var dressing := WorldDresser.dress(seen)
	SecretView.clear_dressing(data, dressing)
	paint(decor_map, dressing["mid"])
	paint(props_map, dressing["props"])
	paint(foreground_map, dressing["fore"])

	_apply_sun(seen, dressing["mid"], dressing["props"])
	if not data.secrets.is_empty():
		secret_view = SecretView.new()
		secret_view.name = "Secrets"
		add_child(secret_view)
		var texture := tilemap.material.get_shader_parameter("shadow_mask") as ImageTexture \
			if tilemap.material != null else null
		secret_view.setup(self, data, seen, dressing, SunShadow.last_mask, texture,
			atlas_image())

	# The air last: it needs the solved shadow to know where the light is.
	if ambience == null:
		ambience = LevelAmbience.new()
		ambience.name = "Ambience"
		add_child(ambience)
	ambience.setup(seen, dressing["props"], SunShadow.last_mask, TILE)
	level_built.emit(data)


func _ensure_layer(layer: TileMapLayer, layer_name: String, collide: bool,
		z: int) -> TileMapLayer:
	if layer != null:
		return layer
	var made := new_layer(layer_name, collide, z)
	add_child(made)
	return made


## One drawn plane on the shared tile set. Only a level's own terrain collides;
## decoration has no collision to give, and a duel zone's terrain is drawn here
## and collided with elsewhere.
static func new_layer(layer_name: String, collide: bool, z: int) -> TileMapLayer:
	var made := TileMapLayer.new()
	made.name = layer_name
	made.tile_set = TILE_SET
	made.collision_enabled = collide
	made.z_index = z
	return made


static func paint(layer: TileMapLayer, cells: Dictionary) -> void:
	for cell: Vector2i in cells:
		layer.set_cell(cell, 0, cells[cell])


## Solves the cast shadow and hands the mask to the two planes that receive
## it. Everything here happens once per level build and nothing re-runs it.
func _apply_sun(seen: AsciiLevel, mid_decor: Dictionary, props: Dictionary) -> void:
	var atlas := atlas_image()
	if atlas == null:
		return

	var started := Time.get_ticks_usec()
	var mask := SunShadow.build(seen, mid_decor, TILE, atlas, props)
	shadow_build_ms = float(Time.get_ticks_usec() - started) / 1000.0

	var material := sun_material(mask, Rect2(Vector2.ZERO, world_size()))
	tilemap.material = material
	decor_map.material = material
	props_map.material = material


## The atlas image the shadow solve reads, or null with an error.
static func atlas_image() -> Image:
	if _atlas_image == null:
		var atlas := TILE_SET.get_source(0) as TileSetAtlasSource
		if atlas == null or atlas.texture == null:
			push_error("Level: tile set has no atlas texture; no shadows")
			return null
		_atlas_image = atlas.texture.get_image()
	return _atlas_image


## The world shader over a solved mask. `covers` is the rectangle of the world,
## in pixels, the mask was solved for: the whole level from the origin for a
## level, one duel zone and its western lead for a zone.
static func sun_material(mask: Texture2D, covers: Rect2) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SUN_SHADER
	material.set_shader_parameter("shadow_mask", mask)
	material.set_shader_parameter("mask_origin", covers.position)
	material.set_shader_parameter("level_px", covers.size)
	var atlas := atlas_image()
	if atlas != null:
		material.set_shader_parameter(
			"shade_v", float(Tiles.SHADE_ROW_OFFSET * TILE) / float(atlas.get_height())
		)
	return material


## Finds secret `index` in play, from `from` in world pixels: the data opens,
## and the view repaints the terrain around it — which is also what takes a
## cracked seal's collision away — and lifts the cover.
func open_secret(index: int, from: Vector2) -> void:
	if data == null or data.opened.has(index):
		return
	data.open_secret(index)
	if secret_view != null:
		secret_view.reveal(index, from)


## --- geometry queries ------------------------------------------------------

func world_size() -> Vector2:
	return Vector2(data.cols * TILE, data.rows * TILE)


func cell_of(world_position: Vector2) -> Vector2i:
	return Vector2i(floori(world_position.x / TILE), floori(world_position.y / TILE))


func kind_at_cell(cell: Vector2i) -> Tiles.Kind:
	return _kind(cell.x, cell.y)


func kind_at_world(world_position: Vector2) -> Tiles.Kind:
	return kind_at_cell(cell_of(world_position))


func is_solid_cell(cell: Vector2i) -> bool:
	return _kind(cell.x, cell.y) == Tiles.Kind.SOLID


func is_solid_at(world_position: Vector2) -> bool:
	return is_solid_cell(cell_of(world_position))


## Solid, or part of a secret nobody has found yet: what the level looks like
## rather than what it is. For the guards, never for the character.
func looks_solid_at(world_position: Vector2) -> bool:
	var cell := cell_of(world_position)
	if is_solid_cell(cell):
		return true
	var index := data.secret_at(cell)
	return index >= 0 and not data.opened.has(index)


## True if any tile of one of `kinds` overlaps the rect.
func rect_has_kind(rect: Rect2, kinds: Array) -> bool:
	var x0 := floori(rect.position.x / TILE)
	var x1 := floori((rect.position.x + rect.size.x - 0.001) / TILE)
	var y0 := floori(rect.position.y / TILE)
	var y1 := floori((rect.position.y + rect.size.y - 0.001) / TILE)
	for y: int in range(y0, y1 + 1):
		for x: int in range(x0, x1 + 1):
			if kinds.has(_kind(x, y)):
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


## --- the overlay (mechanisms) ------------------------------------------------

## `cell` is `kind` now, as far as every query is concerned, on `owner`'s say.
func set_overlay(cell: Vector2i, kind: Tiles.Kind, owner: Object) -> void:
	_overlay[cell] = kind
	_overlay_owner[cell] = owner.get_instance_id()


## Gives back every cell `owner` set, and only those.
func clear_overlay(owner: Object) -> void:
	var id := owner.get_instance_id()
	for cell: Vector2i in _overlay_owner.keys():
		if int(_overlay_owner[cell]) == id:
			_overlay.erase(cell)
			_overlay_owner.erase(cell)


## The kind a mechanism made of `cell`, or -1 when none did.
func overlay_at(cell: Vector2i) -> int:
	return int(_overlay.get(cell, -1))


func _kind(x: int, y: int) -> Tiles.Kind:
	if not _overlay.is_empty():
		var cell := Vector2i(x, y)
		if _overlay.has(cell):
			return _overlay[cell] as Tiles.Kind
	return data.kind_at(x, y)
