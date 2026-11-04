class_name MatchGround
extends DuelWorld
## The strip as a fighter finds it on this frame: the tiles, plus every slab of
## crumbling stone that has not yet fallen.
##
## A fighter asks its world two questions, both on the grid rather than through
## the physics engine (DuelWorld): can it stand up out of a roll here, and
## where does a loose sword come to rest. On a strip with crumbling stone the
## answer changes during a match, so the strip alone -- which is the level, and
## never changes -- would put a dropped sword through a slab that is still
## there. This answers from the strip and the match's own `stones`, which are
## in the snapshot, so two peers that agree on the state agree on where a sword
## lies.
##
## Only built for a strip that has stones. On any other the fighter is handed
## the strip itself, exactly as before (DuelMatch.build()).

var strip: ZoneStrip
var fight: DuelMatch


func _init(on: ZoneStrip = null, of: DuelMatch = null) -> void:
	strip = on
	fight = of


func rect_hits_solid(rect: Rect2) -> bool:
	if strip == null:
		return false
	if strip.rect_hits_solid(rect):
		return true
	return fight != null and strip.hazards.rect_hits_stone(rect, fight.stones)


func world_size() -> Vector2:
	return strip.world_size() if strip != null else Vector2.ZERO


## Every solid and one-way cell of the whole strip, as one hidden tilemap,
## built once per match and never streamed.
##
## The real fighter moves with move_and_collide(), so the ground it stands on
## is whatever the physics space holds. ZoneView streams its cells in and out
## around the camera, which is right for drawing and wrong for this: a fighter
## on a peer whose view had not reached a zone yet would fall through a floor
## that the other peer has, and the two would disagree about a frame. The rule
## the strip already keeps for its own queries -- the geometry the simulation
## reads is never streamed -- holds for the physics space too. ZoneView's
## tilemap has collision switched off; it only draws.
##
## Five zones of 30 x 23 cells is at most 3,450 tiles of static collision,
## and far fewer in practice -- only solid and one-way cells. Hidden, because a
## TileMapLayer collides whether or not it draws.
static func ground_layer(on: ZoneStrip, tiles: TileSet) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = "Ground"
	layer.tile_set = tiles
	layer.visible = false
	for y: int in on.rows():
		for x: int in on.cols():
			var kind := on.kind_at(x, y)
			if kind == Tiles.Kind.SOLID or kind == Tiles.Kind.PLATFORM:
				layer.set_cell(Vector2i(x, y), 0, on.atlas_for(x, y))
	return layer


## One static body per slab of crumbling stone, on collision layer `bits`.
##
## Not cells of the ground layer: a TileMapLayer rebuilds a whole physics
## quadrant when one cell changes, and a rewind may have to put slabs back as
## well as take them away. A body per slab is switched by its collision layer,
## which the physics server reads on the very next query, so a slab that fell
## on frame N is gone for frame N + 1's move and back again the moment a
## snapshot from before it is read. Each match has a layer of its own and its
## fighters are given it as an extra mask bit, so the two matches of a
## networked test, built in one physics space, never stand on each other's
## stone. Nothing about a body is state: DuelMatch._apply_stones() derives
## every one of them from the match's `stones`.
static func stone_bodies(on: ZoneStrip, bits: int) -> Array[StaticBody2D]:
	var bodies: Array[StaticBody2D] = []
	var tile := float(ZoneStrip.TILE)
	for cell: Vector2i in on.hazards.stones:
		var body := StaticBody2D.new()
		body.name = "Stone_%d_%d" % [cell.x, cell.y]
		body.collision_layer = bits
		body.collision_mask = 0
		body.position = Vector2(cell) * tile + Vector2(tile, tile) * 0.5
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(tile, tile)
		shape.shape = rect
		body.add_child(shape)
		bodies.append(body)
	return bodies
