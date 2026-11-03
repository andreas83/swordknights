class_name LevelAmbience
extends Node2D
## The air of a level: dust turning in the sunlight, and the odd leaf coming
## down off the ivy and the palms.
##
## ## Dust you can only see in the light
##
## The art direction allows no haze, no bloom and no gradient, which rules out
## the usual way of drawing a shaft of sun. What it does allow is this: a mote
## of dust is one pixel of LIGHT_SOFT, and it is drawn only where the shadow
## mask says the air is lit. Drifting into a cast shadow, it vanishes; drifting
## out, it reappears. Nothing marks the edge of the shadow, and yet with a few
## dozen motes moving the edge is there in the air, at exactly the slope the
## sun throws it. It costs one image lookup per mote per frame, against a mask
## that was solved once when the level was built (scripts/render/sun_shadow.gd).
##
## ## Restraint
##
## Roughly four motes per five columns, living in the band of air just above the
## floors where the eye is, and a leaf from at most LEAF_SOURCES places. A
## screen holds about ten motes and one falling leaf. If a player notices
## the dust, it is too much.
##
## ## Simulation
##
## None. Every mote and leaf is a pure function of the clock and its seed, held
## in one PackedFloat32Array: nothing is spawned or freed, and nothing here can
## touch gameplay. It animates in `_process`, which is the only clock a
## presentation-only node should use.

const MOTE_STRIDE := 5 ## home x, home y, drift phase, speed, twinkle phase
const MOTES_PER_COLUMN := 0.8
const MOTE_BAND := 4 ## rows of air above a floor the dust lives in
const MOTE_ROAM := 26.0 ## how far a mote wanders from home, in pixels
const LEAF_SOURCES := 8
const LEAF_FALL := 30.0 ## pixels a leaf falls before it is gone
const LEAF_PERIOD := 7.0 ## seconds between leaves from one source

## Atlas ids a leaf can come down from.
const LEAF_FROM := ["ivy_top", "palm_top", "planter", "planter_bloom"]

var _motes := PackedFloat32Array()
var _leaves: Array[Vector3] = [] ## x, y, phase
var _mask: Image
var _mask_scale := 1.0
var _time: float = 0.0


## Seeds the air for one level. `mask` is the shadow mask the world shader
## samples, or null where the renderer cannot read it back, in which case the
## dust is simply drawn everywhere it lives.
func setup(level: AsciiLevel, props: Dictionary, mask: Image, tile: int) -> void:
	_mask = mask
	_mask_scale = 1.0
	if mask != null and mask.get_width() > 0:
		_mask_scale = float(mask.get_width()) / float(level.cols * tile)
	_time = 0.0
	_seed_motes(level, tile)
	_seed_leaves(props, tile)
	queue_redraw()


func _seed_motes(level: AsciiLevel, tile: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(level.name) ^ 0x5eed
	var homes: Array[Vector2] = []
	for x: int in level.cols:
		for y: int in range(1, level.rows):
			if level.kind_at(x, y) != Tiles.Kind.EMPTY or not level.is_solid(x, y + 1):
				continue
			# Open air above a floor: the band the character moves through.
			for k: int in MOTE_BAND:
				if level.kind_at(x, y - k) == Tiles.Kind.EMPTY:
					homes.append(Vector2(x, y - k))
	_motes.clear()
	if homes.is_empty():
		return
	var count := int(level.cols * MOTES_PER_COLUMN)
	for i: int in count:
		var home := homes[rng.randi_range(0, homes.size() - 1)]
		_motes.append_array(PackedFloat32Array([
			(home.x + rng.randf()) * tile, (home.y + rng.randf()) * tile,
			rng.randf() * TAU, rng.randf_range(0.6, 1.4), rng.randf() * TAU,
		]))


func _seed_leaves(props: Dictionary, tile: int) -> void:
	_leaves.clear()
	var wanted: Array[Vector2i] = []
	for id: String in LEAF_FROM:
		wanted.append(Tiles.DECOR_ATLAS[id])
	var cells: Array = props.keys()
	cells.sort()
	for cell: Vector2i in cells:
		if _leaves.size() >= LEAF_SOURCES:
			break
		if wanted.has(props[cell]):
			_leaves.append(Vector3((cell.x + 0.5) * tile, (cell.y + 0.4) * tile,
				float(_leaves.size()) * 2.3))


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var view := _view_rect()
	for i: int in range(0, _motes.size(), MOTE_STRIDE):
		var phase := _motes[i + 2]
		var speed := _motes[i + 3]
		var t := _time * speed
		# A slow figure-of-eight around home, rising a little on warm air.
		var at := Vector2(
			_motes[i] + sin(t * 0.31 + phase) * MOTE_ROAM,
			_motes[i + 1] + sin(t * 0.47 + phase * 1.7) * MOTE_ROAM * 0.45)
		at = at.round()
		if not view.has_point(at):
			continue
		# Turning in the light: catches it, loses it.
		if sin(t * 1.3 + _motes[i + 4]) < -0.55:
			continue
		if _in_shadow(at):
			continue
		draw_rect(Rect2(at, Vector2.ONE), Palette.LIGHT_SOFT)

	for leaf: Vector3 in _leaves:
		var cycle := fposmod(_time + leaf.z, LEAF_PERIOD)
		var fall := cycle / LEAF_PERIOD * 2.2
		if fall > 1.0:
			continue
		var at := Vector2(leaf.x + sin(fall * 9.0 + leaf.z) * 4.0 + fall * 6.0,
			leaf.y + fall * LEAF_FALL).round()
		if not view.has_point(at):
			continue
		draw_rect(Rect2(at, Vector2(2.0, 1.0) if int(fall * 12.0) % 2 == 0 else Vector2.ONE),
			Palette.FOLIAGE)


func _in_shadow(at: Vector2) -> bool:
	if _mask == null:
		return false
	var mx := int(at.x * _mask_scale)
	var my := int(at.y * _mask_scale)
	if mx < 0 or my < 0 or mx >= _mask.get_width() or my >= _mask.get_height():
		return false
	return _mask.get_pixel(mx, my).r > 0.5


## What the camera can see, in this node's space, with a margin: motes off
## screen are skipped before the mask is read.
func _view_rect() -> Rect2:
	var canvas := get_canvas_transform().affine_inverse()
	var size := get_viewport_rect().size
	return Rect2(canvas.origin - Vector2(4.0, 4.0), size + Vector2(8.0, 8.0))
