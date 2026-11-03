class_name SunShadow
extends RefCounted
## The cast-shadow model: one sun, fixed in the world, raking low from the
## left, and every solid thing throwing a hard black diagonal off it.
##
## This is a projection problem in tile space, not a lighting engine. The whole
## world is static once a level is built, so the shadow is solved ONCE into a
## one-bit-per-pixel mask and then costs a single texture fetch per fragment
## for the rest of the level (assets/world_shadow.gdshader). Nothing is
## re-solved while the game runs.
##
## THE SUN is the integer vector (RUN, RISE) = (2, 1): two pixels across for
## every one down. An integer slope is not an aesthetic choice, it is what
## makes the solve linear. Index each pixel by the lane it belongs to,
##
##     lane = x - RUN * y
##
## and the lanes partition the grid exactly: every pixel is on one, and
## stepping (x += 2, y += 1) walks a lane. So casting a shadow is one sweep per
## lane carrying a countdown, instead of a ray-march per pixel. O(width x
## height), once.
##
## WHAT CASTS. A pixel casts if it is opaque in the atlas — terrain and
## mid-ground architecture alike. Nothing declares its own silhouette, so a
## new decoration casts a correct shadow the moment it is drawn. Background
## filler and water do not cast (they are behind the plane), and neither does
## the foreground plane (it is in front of it).
##
## WHAT IS SPARED, and this is the part that took the longest to get right.
## Two rules, and the picture is wrong without either:
##
##  1. A BODY DOES NOT SHADOW ITSELF. The sweep remembers the height the
##     current shadow was thrown from and only darkens a surface when the
##     caster stands above that surface's own run's top edge. Without it a
##     wall's own cap eats the gold off the wall.
##
##  2. WHAT COUNTS AS ONE BODY HAS TO BE SAID OUT LOUD. Terrain and the
##     architecture carved into it (a cornice, a frieze, an arch) are one
##     body, so a cornice does not shade the floor it belongs to.
##     Architecture that STANDS on a surface — a column, a balustrade, a
##     planter — is its own body, so it does throw its shadow across that
##     surface. Tiles.STANDING_DECOR is the list, and it is the difference
##     between a terrace of flat gold and a terrace banded with the shadows
##     of its own colonnade. Get this wrong in the other direction and a
##     balustrade's own posts comb the whole wall below them into stripes.
##
## CAVEAT, recorded because it is invisible until it bites: a caster one pixel
## wide lands on every other lane and throws a dotted shadow. Keep vertical
## detail two pixels or wider. tools/generate_tiles_png.py does.

## The sun vector, in pixels. Low from the left: shadows run twice as far as
## they fall, so a wall's shadow is always longer than the wall is tall.
const RUN := 2
const RISE := 1

## How far a shadow reaches before it is cut, in tiles of horizontal travel.
## Unbounded shadows are physically honest and look terrible: a six-tile wall
## would black out half a terrace. This is the one art constant in the model.
const REACH_TILES := 3.0

## Above this, the mask is solved and stored at half resolution. GL ES3
## guarantees only 2048 px of texture, and a long generated level is wider
## than that.
const MAX_MASK_PX := 2048

const SHADOW_BIT := 255
const LIT_BIT := 0

## Milliseconds the last build() spent in each phase. Read by
## tests/world_shadow_test.gd and quoted in docs/world.md; keeping the
## measurement in the code means the number in the document can be checked
## rather than believed.
static var timings := {}
## The mask the last build() solved, as a CPU-side image. LevelAmbience reads
## it to keep dust out of the shade; reading the texture back off the GPU
## instead would stall, and fail outright under the headless renderer.
static var last_mask: Image

## The per-tile opacity bitmaps, keyed by the atlas they came from. The atlas
## does not change while the game runs, so this is built once and every level
## after the first skips it.
static var _mask_cache := {}


## Solves the shadow for one level and returns the mask texture the world
## shader samples. `decor` maps a cell to the atlas coordinates of a
## mid-ground decoration drawn there; `props` is the same for the props plane
## drawn over it. Both are stamped, so an urn in front of a cornice adds its
## shape without taking the cornice's away.
static func build(level: AsciiLevel, decor: Dictionary, tile: int,
		atlas: Image, props: Dictionary = {}) -> ImageTexture:
	var width := level.cols * tile
	var height := level.rows * tile
	var step := 1
	while width / step > MAX_MASK_PX or height / step > MAX_MASK_PX:
		step *= 2

	var mask_w := maxi(1, width / step)
	var mask_h := maxi(1, height / step)
	var clock := Time.get_ticks_usec()
	var masks := _cached_masks(atlas, tile)
	timings["atlas"] = _lap(clock)

	clock = Time.get_ticks_usec()
	var planes := _rasterise_occluders(level, [decor, props], masks, tile, step, mask_w,
		mask_h)
	var geom: PackedByteArray = planes[0]
	var standing: PackedByteArray = planes[1]
	timings["rasterise"] = _lap(clock)

	# Sky is most of a platformer and none of it can be in shadow, so both
	# sweeps start at the first row that has anything in it.
	clock = Time.get_ticks_usec()
	var first := _first_occupied_row(geom, mask_w, mask_h)
	var depth := _run_depth(geom, standing, mask_w, mask_h, first)
	timings["depth"] = _lap(clock)

	clock = Time.get_ticks_usec()
	var shade := _sweep(geom, depth, mask_w, mask_h, first, step, tile)
	timings["sweep"] = _lap(clock)

	clock = Time.get_ticks_usec()
	var image := Image.create_from_data(mask_w, mask_h, false, Image.FORMAT_L8, shade)
	last_mask = image
	var texture := ImageTexture.create_from_image(image)
	timings["upload"] = _lap(clock)
	timings["size"] = Vector2i(mask_w, mask_h)
	timings["step"] = step
	return texture


static func _lap(from_usec: int) -> float:
	return float(Time.get_ticks_usec() - from_usec) / 1000.0


static func _cached_masks(atlas: Image, tile: int) -> Dictionary:
	var key := "%d:%dx%d" % [tile, atlas.get_width(), atlas.get_height()]
	if not _mask_cache.has(key):
		_mask_cache[key] = _tile_masks(atlas, tile)
	return _mask_cache[key]


## --- step 1: who casts ------------------------------------------------------

## One opacity bitmap per atlas tile, keyed by atlas coordinates. A tile's
## silhouette is its alpha, so the shadow of a balustrade has gaps between its
## posts without anyone having to say so.
static func _tile_masks(atlas: Image, tile: int) -> Dictionary:
	var masks := {}
	var columns := atlas.get_width() / tile
	var rows := atlas.get_height() / tile
	for row: int in rows:
		for column: int in columns:
			var bits := PackedByteArray()
			bits.resize(tile * tile)
			var any := false
			for y: int in tile:
				for x: int in tile:
					var opaque := atlas.get_pixel(column * tile + x, row * tile + y).a > 0.5
					bits[y * tile + x] = 1 if opaque else 0
					any = any or opaque
			if any:
				masks[Vector2i(column, row)] = bits
	return masks


static func _casts_terrain(kind: Tiles.Kind) -> bool:
	# Background filler sits behind the plane the sun is lighting, and water
	# is a surface the light goes into rather than off.
	return kind != Tiles.Kind.EMPTY and kind != Tiles.Kind.BACKDROP and kind != Tiles.Kind.WATER


## Terrain that is a thing standing on or against the stone rather than being
## the stone. Same rule as Tiles.STANDING_DECOR and for the same reason: a
## ladder's rails are two pixels wide, so if they counted as part of the wall
## they stand on, every column of that wall under a rail would have a run top
## a dozen pixels higher than its neighbours and the whole face below would
## comb itself into vertical stripes.
static func _standing_terrain(kind: Tiles.Kind) -> bool:
	return kind == Tiles.Kind.LADDER or kind == Tiles.Kind.SPIKES \
		or kind == Tiles.Kind.PLATFORM


## Returns [every occluder, the ones that stand on a surface]. The second is
## only used to decide where one body ends and the next begins.
static func _rasterise_occluders(level: AsciiLevel, planes: Array, masks: Dictionary,
		tile: int, step: int, mask_w: int, mask_h: int) -> Array:
	var geom := PackedByteArray()
	geom.resize(mask_w * mask_h)
	var standing := PackedByteArray()
	standing.resize(mask_w * mask_h)
	var standing_coords := Tiles.standing_atlas_coords()

	for y: int in level.rows:
		for x: int in level.cols:
			var kind := level.kind_at(x, y)
			if _casts_terrain(kind):
				var coords_terrain := level.atlas_for(x, y)
				_stamp(geom, masks, coords_terrain, x, y, tile, step, mask_w, mask_h)
				if _standing_terrain(kind):
					_stamp(standing, masks, coords_terrain, x, y, tile, step, mask_w, mask_h)
			var cell := Vector2i(x, y)
			for decor: Dictionary in planes:
				if not decor.has(cell):
					continue
				var coords: Vector2i = decor[cell]
				_stamp(geom, masks, coords, x, y, tile, step, mask_w, mask_h)
				if standing_coords.has(coords):
					_stamp(standing, masks, coords, x, y, tile, step, mask_w, mask_h)
	return [geom, standing]


static func _stamp(geom: PackedByteArray, masks: Dictionary, coords: Vector2i,
		cell_x: int, cell_y: int, tile: int, step: int, mask_w: int, mask_h: int) -> void:
	if not masks.has(coords):
		return
	var bits: PackedByteArray = masks[coords]
	var ox := cell_x * tile
	var oy := cell_y * tile
	if step == 1:
		# Full resolution is the common case; keep the division out of it.
		for y: int in tile:
			var my := oy + y
			if my < 0 or my >= mask_h:
				continue
			var row := my * mask_w
			var source := y * tile
			for x: int in tile:
				if bits[source + x] != 0:
					var mx := ox + x
					if mx >= 0 and mx < mask_w:
						geom[row + mx] = 1
		return
	# Coarser than one mask texel per pixel: step over the tile at the same
	# stride instead of rasterising pixels that land on the same texel.
	for y: int in range(0, tile, step):
		var my := (oy + y) / step
		if my < 0 or my >= mask_h:
			continue
		var row := my * mask_w
		var source := y * tile
		for x: int in range(0, tile, step):
			if bits[source + x] == 0:
				continue
			var mx := (ox + x) / step
			if mx >= 0 and mx < mask_w:
				geom[row + mx] = 1


static func _first_occupied_row(geom: PackedByteArray, mask_w: int, mask_h: int) -> int:
	for y: int in mask_h:
		var row := y * mask_w
		for x: int in mask_w:
			if geom[row + x] != 0:
				return y
	return mask_h


## --- step 2: how far below its own top edge each solid pixel sits ------------

## Saturates at 255. A run taller than that is 16 tiles of unbroken stone;
## anything standing on top of it is far enough above to shadow it anyway.
static func _run_depth(geom: PackedByteArray, standing: PackedByteArray, mask_w: int,
		mask_h: int, first: int) -> PackedByteArray:
	var depth := PackedByteArray()
	depth.resize(mask_w * mask_h)
	# Row-major with one running counter per column. Walking this column by
	# column instead reads the array with a stride of mask_w and costs about
	# a third more on a level the size of level 01.
	var running := PackedInt32Array()
	running.resize(mask_w)
	# Which body the run belongs to: 0 nothing, 1 standing decoration, 2
	# stone. A change of body starts a new run, which is how a column stops
	# being part of the terrace it is standing on.
	var body := PackedByteArray()
	body.resize(mask_w)
	for y: int in range(first, mask_h):
		var row := y * mask_w
		for x: int in mask_w:
			var i := row + x
			if geom[i] == 0:
				running[x] = 0
				body[x] = 0
				continue
			var here: int = 1 if standing[i] != 0 else 2
			if body[x] != here:
				body[x] = here
				running[x] = 0
			var d: int = running[x]
			depth[i] = d
			if d < 255:
				running[x] = d + 1
	return depth


## --- step 3: the sweep ------------------------------------------------------

static func _sweep(geom: PackedByteArray, depth: PackedByteArray, mask_w: int,
		mask_h: int, first: int, step: int, tile: int) -> PackedByteArray:
	var shade := PackedByteArray()
	shade.resize(mask_w * mask_h)

	# Shadow length, counted in lane steps. Each step travels RUN pixels
	# across, so the reach in tiles divides out by that.
	var reach := int(REACH_TILES * float(tile) / float(RUN * step))

	# Lanes are x - RUN*y. Walking a lane means x += RUN, y += 1, so a lane is
	# fixed by where it crosses y = 0: every integer x from -RUN*(mask_h-1)
	# (lanes that enter from the left wall) up to mask_w.
	var first_lane := -RUN * (mask_h - 1)
	for lane: int in range(first_lane, mask_w):
		var counter := 0
		var source_top := 0
		# Lanes that start off the left edge are joined where they cross it,
		# rather than stepped through empty space to get there, and no lane
		# starts above the first row that has anything in it.
		var y0 := maxi(first, 0 if lane >= 0 else (-lane + RUN - 1) / RUN)
		var x := lane + RUN * y0
		for y: int in range(y0, mask_h):
			if x < mask_w:
				var i := y * mask_w + x
				if geom[i] != 0:
					var top := y - int(depth[i])
					if counter > 0 and source_top < top:
						# Something above this surface's own top edge is in
						# the way: this is a cast shadow landing on stone.
						shade[i] = SHADOW_BIT
						counter -= 1
					else:
						# Lit stone, or stone the shadow has no business
						# darkening. Either way it is what casts from here.
						source_top = top
						counter = reach
				elif counter > 0:
					shade[i] = SHADOW_BIT
					counter -= 1
			else:
				break
			x += RUN
	return shade
