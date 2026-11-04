class_name CrumblingStone
extends Mechanism
## Crumbling stone: a run of cracked slabs that give way a moment after a foot
## finds them (docs/campaign.md, "Crumbling stone"). Chapter III's verb.
##
## ## The rule is *keep moving*
##
## A slab's fuse lights on the first frame the prince's **feet** touch it --
## hands do not count, so a crumbling ledge can be grabbed and mantled -- and
## burns for FUSE_TIME, 27 frames, the game's one telegraph length
## (Patrol.WINDUP_TIME). A runner is over a slab for about 14 frames, well
## inside it; a walker for about 37, so he goes through. When a slab drops it
## lights its neighbours in the run for CHAIN_TIME, 15 frames, so a run falls
## in a chain at four tiles a second: faster than a walk, slower than a run.
## The fuse and the chain are the windows that stand between the prince and a
## fall, so both are read through warn() and the LONGER WARNINGS assist
## stretches them; the fall itself keeps gravity's time.
##
## Each slab drops on its own, so collision is kept per cell here rather than
## through Mechanism.set_kind(), which sets a whole run at once. The rule that
## set_kind() exists for still holds: a slab's body and its cell in the
## level's overlay change together, in _give_way(), and nowhere else.
##
## ## Who else stands on it
##
## A Caracal is light enough to walk it without lighting anything, but its
## push-off and its landing break a slab outright (break_under()), so a cat
## that crouches on crumbling stone falls through it. Any foe with weight
## that ends up on it -- a Bastion, a guard knocked back onto it -- breaks it
## at once (Weight). Sentinels, and any foe that walks a beat, treat it as
## the end of the floor (gives_way()), so they never choose to.
##
## ## A trap, not a deed
##
## A fallen slab is put back whole by a checkpoint respawn, as every mechanism
## is: all state lives in this node and _setup() is the only reset. That is
## the choice the set piece needs -- the collapse is retried from its start,
## not as a row of holes -- and it is safe because nothing a slab does is ever
## the way: the reach hook proves the level with the most conservative reading
## of every slab, and tells the proof that the wire is a trap, so a torch is
## proved under the authored level a respawn actually comes back to
## (ReachModel.resets_on_respawn()). A latch would have been the other
## reading -- holes kept for good -- and is refused because retrying the
## collapse as a row of three-wide jumps is not retrying it.
##
## ## Telling the proof
##
## reach() gives every run a wire of its own, `crumble@x,y`: the run's cells
## are stone until it is on and air after, and standing above them is a
## transient stand (ReachModel.fuse_on_stand()) -- any move may leave it,
## nothing may wait on it, and the run is gone once it is left. One wire per
## run rather than per slab is exact, not lenient: once one slab of a run
## drops, the chain takes the rest. A run whose mark says `fallen` is air
## outright, which is how CrumbleAudit plays the runs a cat broke.
##
## ## Drawn as the floor's own stone
##
## The terrain and its shadow are built from the level as authored, where a
## slab's cell is air, so a slab draws itself: the atlas tile the cell would
## have as stone, through the same world shader as the tilemap, so it takes
## the light exactly as the floor does -- plus the tell, one ink hairline
## across its cap, the cracked floor's tell (both are stone that gives). Lit,
## it shudders a pixel every three frames and sheds grit; dropped, it falls
## at gravity and breaks into dust on whatever it meets. A slab casts no sun
## shadow, as no mechanism does (docs/world.md).

## The fuse: Patrol.WINDUP_TIME, the game's word for "now".
const FUSE_TIME := 0.45
## A fallen slab lights its neighbours for this long: 15 frames a slab.
const CHAIN_TIME := 0.25
const SHUDDER_FRAMES := 3
const FALL_GRAVITY := 900.0
const MAX_FALL := 420.0
## How far below the level a falling slab is let go of.
const FALL_MARGIN := 64.0
## Grit while a fuse burns: one grain every this many frames, per slab.
const GRIT_FRAMES := 4
const DUST_TIME := 0.5
const CRACK := Palette.INK
const GROUP := &"crumbling_stone"

enum Slab { WHOLE, LIT, FALLING, GONE }

## Per cell, in `cells` order.
var _state: Array[int] = []
## The physics frame a lit fuse runs out on: the slab holds a body on every
## frame before it, so one lit on frame N holds for N to N + 26.
var _due: Array[int] = []
## A falling slab's drop so far, and its speed, in world units.
var _drop: Array[float] = []
var _speed: Array[float] = []
var _frame := 0
## Engine.get_physics_frames() when this node last stepped.
var _stepped_at := -1
## Atlas coordinates of each cell drawn as stone.
var _coords: Array[Vector2i] = []
var _stone: Node2D
## Presentation only: grit and dust, `{at, v, life, size}`.
var _bits: Array[Dictionary] = []
var _random := RandomNumberGenerator.new()


func _setup() -> void:
	add_to_group(GROUP)
	_state.clear()
	_due.clear()
	_drop.clear()
	_speed.clear()
	for _cell: Vector2i in cells:
		_state.append(Slab.WHOLE)
		_due.append(0)
		_drop.append(0.0)
		_speed.append(0.0)
	_frame = 0
	_random.seed = hash(post)
	_build_bodies()
	_apply_overlay()
	_coords = _stone_coords()


## Feet on a whole slab light it. Any part of the feet: a body standing on the
## stone beside a slab but overhanging it lights it too, and the slab goes
## from under the part of him it held.
##
## A foe with weight (Foe.has_weight(): a guard, a Bastion) is too heavy for
## it at all, and the slab under him goes at once; a cat has none, and walks it.
func meet(contact: Contact) -> void:
	for index: int in cells.size():
		if not holds(index):
			continue
		var box := cell_rect(cells[index])
		for foe: Foe in Weight.foes(self):
			if Weight.foe_on(foe, box.position.y, box.position.x, box.end.x):
				_give_way(index)
				break
		if _state[index] == Slab.WHOLE and contact.alive and contact.grounded \
				and _feet_on(contact, cells[index]):
			_light(index, fuse_frames())


## The fuse, in frames, through the assist.
func fuse_frames() -> int:
	return roundi(warn(FUSE_TIME) * 60.0)


## The chain's step, in frames, through the assist.
func chain_frames() -> int:
	return roundi(warn(CHAIN_TIME) * 60.0)


## Whether slab `index` still holds a body.
func holds(index: int) -> bool:
	return _state[index] == Slab.WHOLE or _state[index] == Slab.LIT


func is_lit(index: int) -> bool:
	return _state[index] == Slab.LIT


## Frames a lit slab will still hold a body for, counting this one.
func frames_left(index: int) -> int:
	return _due[index] - _now() if _state[index] == Slab.LIT else 0


## The slab under `at` (world units, feet), or -1.
func slab_at(at: Vector2) -> int:
	return cells.find(Vector2i(floori(at.x / TILE), floori(at.y / TILE)))


## --- for foes ------------------------------------------------------------------

## Whether the point `at` is crumbling stone that still holds: the end of a
## walker's beat. Sentinels and Glassbearers ask before every step.
static func gives_way(level_node: Level, at: Vector2) -> bool:
	var found := _find(level_node, at)
	return found != null and found.holds(found.slab_at(at))


## A body too heavy for it came down on, or pushed off, the slab under `at`:
## it drops now, and lights the run's chain. True when there was one to break.
static func break_under(level_node: Level, at: Vector2) -> bool:
	var found := _find(level_node, at)
	if found == null:
		return false
	var index := found.slab_at(at)
	if not found.holds(index):
		return false
	found._give_way(index)
	return true


static func _find(level_node: Level, at: Vector2) -> CrumblingStone:
	if level_node == null or not level_node.is_inside_tree():
		return null
	for node: Node in level_node.get_tree().get_nodes_in_group(GROUP):
		var stone := node as CrumblingStone
		if stone != null and stone.level == level_node and stone.slab_at(at) >= 0:
			return stone
	return null


## --- the clock ------------------------------------------------------------------

## Game meets every entity before their own step, so a fuse lit in meet() on
## this physics frame belongs to `_frame + 1`, the frame being stepped
## (_now()). Counting against an absolute frame rather than down a counter is
## what makes "holds for exactly the fuse" true whichever runs first.
func _physics_process(_delta: float) -> void:
	_frame += 1
	_stepped_at = Engine.get_physics_frames()
	for index: int in cells.size():
		match _state[index]:
			Slab.LIT:
				if _frame >= _due[index]:
					_give_way(index)
				elif _frame % GRIT_FRAMES == index % GRIT_FRAMES:
					_shed_grit(index)
			Slab.FALLING:
				_speed[index] = minf(_speed[index] + FALL_GRAVITY / 60.0, MAX_FALL)
				_drop[index] += _speed[index] / 60.0
				_fall_on(index)


func _process(delta: float) -> void:
	for bit: Dictionary in _bits:
		bit["life"] = float(bit["life"]) - delta
		var v: Vector2 = bit["v"]
		v.y += FALL_GRAVITY * 0.5 * delta
		bit["v"] = v
		bit["at"] = (bit["at"] as Vector2) + v * delta
	_bits = _bits.filter(func(bit: Dictionary) -> bool: return float(bit["life"]) > 0.0)
	queue_redraw()
	if _stone != null:
		_stone.queue_redraw()


## The frame being stepped: `_frame` once this node's own step has run, one
## past it before (from meet(), or a foe that steps first).
func _now() -> int:
	return _frame + (0 if _stepped() else 1)


func _stepped() -> bool:
	return _stepped_at == Engine.get_physics_frames()


func _light(index: int, frames: int) -> void:
	if _state[index] == Slab.WHOLE:
		_state[index] = Slab.LIT
		_due[index] = _now() + frames
		# The crack opening is heard as well as seen: a slab lit off-screen
		# by a cat or the chain is still a floor about to go.
		cue.emit(&"masonry", {"pitch": 2.2, "volume_db": -14.0})
	elif _state[index] == Slab.LIT:
		_due[index] = mini(_due[index], _now() + frames)


## Slab `index` drops: out of the world's collision and the overlay together,
## and its neighbours' fuses lit for the chain.
func _give_way(index: int) -> void:
	_state[index] = Slab.FALLING
	_due[index] = 0
	_speed[index] = 0.0
	_drop[index] = 0.0
	_body_of(index).collision_layer = 0
	_apply_overlay()
	cue.emit(&"masonry", {"pitch": 1.25, "volume_db": -6.0})
	for step: int in [-1, 1]:
		var next := cells.find(cells[index] + Vector2i(step, 0))
		if next >= 0:
			_light(next, chain_frames())


## A falling slab meets whatever is under it, or leaves the level.
func _fall_on(index: int) -> void:
	var box := cell_rect(cells[index])
	var bottom := Vector2(box.get_center().x, box.end.y + _drop[index])
	var through_floor := level != null and _drop[index] > 2.0 \
		and level.is_solid_at(bottom + Vector2(0.0, 1.0))
	var gone := level == null or bottom.y > level.world_size().y + FALL_MARGIN
	if not through_floor and not gone:
		return
	_state[index] = Slab.GONE
	if through_floor:
		_burst(Vector2(box.position.x, box.position.y + _drop[index]))
		cue.emit(&"masonry", {"pitch": 0.9, "volume_db": -10.0})


## --- collision: per cell, body and overlay together --------------------------

func _build_bodies() -> void:
	for child: Node in get_children():
		if child is StaticBody2D:
			remove_child(child)
			child.free()
	for index: int in cells.size():
		var body := StaticBody2D.new()
		body.name = "Slab%d" % index
		body.collision_layer = Tiles.MASK_SOLID
		body.collision_mask = 0
		body.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(TILE, TILE)
		shape.shape = rect
		shape.position = cell_rect(cells[index]).get_center() - position
		body.add_child(shape)
		add_child(body)


func _body_of(index: int) -> StaticBody2D:
	return get_node("Slab%d" % index) as StaticBody2D


func _apply_overlay() -> void:
	if level == null:
		return
	level.clear_overlay(self)
	for index: int in cells.size():
		if holds(index):
			level.set_overlay(cells[index], Tiles.Kind.SOLID, self)


func _feet_on(contact: Contact, cell: Vector2i) -> bool:
	var box := cell_rect(cell)
	if absf(contact.feet.y - box.position.y) > 1.0:
		return false
	return contact.body.position.x < box.end.x and contact.body.end.x > box.position.x


## --- the proof --------------------------------------------------------------------

## The wire a run is proved on: one per run, named by its anchor cell.
static func wire_of(mark: Dictionary) -> StringName:
	var at: Vector2i = mark["cell"]
	return StringName("crumble@%d,%d" % [at.x, at.y])


static func reach(mark: Dictionary, model: ReachModel) -> void:
	var slabs := Mechanism.mark_cells(mark)
	if String((mark.get("params", {}) as Dictionary).get("fallen", "")) != "":
		model.fixed_cells(slabs, Tiles.Kind.EMPTY)
		return
	var wire := wire_of(mark)
	model.switch_cells(slabs, wire, Tiles.Kind.SOLID, Tiles.Kind.EMPTY)
	model.fuse_on_stand(Mechanism.cells_above(slabs), wire)
	model.resets_on_respawn(wire)


## --- drawing -----------------------------------------------------------------------

## The tile each cell would be if the run were the stone it looks like.
func _stone_coords() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if level == null or level.data == null:
		for _cell: Vector2i in cells:
			out.append(Tiles.ATLAS_SOLID_CAPPED)
		return out
	var stone := level.data.copy()
	for cell: Vector2i in cells:
		stone.set_kind(cell.x, cell.y, Tiles.Kind.SOLID)
	for cell: Vector2i in cells:
		out.append(stone.atlas_for(cell.x, cell.y))
	return out


func _ready() -> void:
	_stone = Node2D.new()
	_stone.name = "Stone"
	_stone.show_behind_parent = true
	if level != null and level.tilemap != null:
		_stone.material = level.tilemap.material
	_stone.draw.connect(_draw_stone)
	add_child(_stone)


## Where slab `index` is drawn this frame, in this node's space: shuddering
## while its fuse burns, dropping once it has gone.
func _slab_rect(index: int) -> Rect2:
	var box := cell_rect(cells[index])
	box.position -= position
	match _state[index]:
		Slab.LIT:
			var beat := (_frame / SHUDDER_FRAMES) % 4
			box.position.x += [0.0, 1.0, 0.0, -1.0][beat]
			# The last third of the fuse it has settled a pixel: going.
			if frames_left(index) * 3 < fuse_frames():
				box.position.y += 1.0
		Slab.FALLING:
			box.position.y += roundf(_drop[index])
	return box


func _draw_stone() -> void:
	var atlas := Level.TILE_SET.get_source(0) as TileSetAtlasSource
	if atlas == null or atlas.texture == null:
		return
	for index: int in cells.size():
		if _state[index] == Slab.GONE:
			continue
		var source := Rect2(Vector2(_coords[index]) * TILE, Vector2(TILE, TILE))
		_stone.draw_texture_rect_region(atlas.texture, _slab_rect(index), source)


func _draw() -> void:
	for index: int in cells.size():
		if _state[index] == Slab.GONE:
			continue
		_draw_crack(index, _slab_rect(index))
	for bit: Dictionary in _bits:
		var at := (bit["at"] as Vector2) - position
		var size := float(bit["size"])
		draw_rect(Rect2(at.round(), Vector2(size, size)), bit["colour"] as Color)


## One ink hairline across the cap, the cracked floor's tell, the same on
## every visit (seeded by the cell). Lit, it opens a pixel wider: the slab is
## splitting along it.
func _draw_crack(index: int, box: Rect2) -> void:
	var seed_of := absi(cells[index].x * 7 + cells[index].y * 13)
	var rise := [3.0, 4.0, 5.0, 4.0]
	var points := PackedVector2Array()
	for step: int in 5:
		var x := box.position.x + 1.0 + float(step) * 3.5
		var y := box.position.y + float(rise[(seed_of + step) % 4])
		points.append(Vector2(roundf(x), y))
	draw_polyline(points, CRACK, 1.0)
	if _state[index] != Slab.WHOLE:
		draw_line(points[2], points[2] + Vector2(0.0, 5.0), CRACK, 1.0)


func _shed_grit(index: int) -> void:
	var box := cell_rect(cells[index])
	_bits.append({
		"at": Vector2(box.position.x + 2.0 + _random.randf() * 12.0, box.end.y),
		"v": Vector2(_random.randf_range(-6.0, 6.0), _random.randf_range(10.0, 30.0)),
		"life": 0.45, "size": 1.0, "colour": Palette.SHADOW_DEEP,
	})


func _burst(at: Vector2) -> void:
	for i: int in 10:
		var dust := i % 3 == 0
		_bits.append({
			"at": at + Vector2(_random.randf() * TILE, _random.randf() * 4.0),
			"v": Vector2(_random.randf_range(-40.0, 40.0), _random.randf_range(-70.0, -20.0)),
			"life": DUST_TIME * (0.6 + _random.randf() * 0.6),
			"size": 1.0 if dust else 2.0,
			"colour": Palette.SURFACE_EDGE if dust else Palette.SHADOW,
		})
