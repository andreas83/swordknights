extends GutTest
## The duel's zones are dressed and lit by the level path, and that changes
## nothing a match can feel.
##
## scripts/duel/zones_view.gd draws the strip with WorldDresser's architecture
## and SunShadow's cast shadow, as scripts/world/level.gd draws a level
## (docs/world.md). Four claims:
##
## 1. FAITHFUL. The stitched strip ZoneStrip.as_level() hands the dresser and
##    the sun is the strip, cell for cell, in any window of it.
## 2. DRESSED. Every zone gets architecture, the dressing of a symmetric strip
##    is symmetric, and nothing it draws can collide.
## 3. LIT AS ONE WORLD. Each zone's shadow is solved separately, over a short
##    lead to its west, so a phone gets a full-resolution mask. That has to be
##    the same shadow a solve over everything to the west would cast, pixel for
##    pixel -- otherwise a seam shows as a shadow that stops at a zone edge.
## 4. PURELY VISUAL. Setting the view up leaves the strip's identity alone,
##    and no drawn layer of a realised zone collides.

const MANIFEST := "res://levels/duel_zones.txt"
const TILE := ZoneStrip.TILE
## The widest window SunShadow solves at full resolution, in columns:
## SunShadow.MAX_MASK_PX over the tile. Checked in the test that uses it.
const FULL_RES_COLS := 128

var _strip: ZoneStrip


func before_all() -> void:
	_strip = ZoneStrip.from_manifest(MANIFEST)


func _view() -> ZoneView:
	var view := ZoneView.new()
	add_child_autofree(view)
	view.setup(_strip)
	return view


## --- 1. faithful ------------------------------------------------------------

func test_the_stitched_strip_is_the_strip() -> void:
	assert_not_null(_strip, "the strip loads")
	for window: Vector2i in [Vector2i(0, _strip.cols()), Vector2i(22, 68),
			Vector2i(_strip.cols() - 31, _strip.cols())]:
		var level := _strip.as_level(window.x, window.y)
		assert_eq(level.cols, window.y - window.x, "window %s is as wide as asked" % window)
		assert_eq(level.rows, _strip.rows(), "window %s is as tall as the strip" % window)
		var wrong := 0
		for y: int in _strip.rows():
			for x: int in range(window.x, window.y):
				if level.kind_at(x - window.x, y) != _strip.kind_at(x, y):
					wrong += 1
		assert_eq(wrong, 0, "window %s has the strip's tiles" % window)


func test_the_marks_come_across() -> void:
	var level := _strip.as_level()
	var exits := 0
	var torches := 0
	for mark: Dictionary in level.entities:
		match String(mark["kind"]):
			"exit":
				exits += 1
			"torch":
				torches += 1
	assert_eq(exits, 2, "both gates are marked, so nothing is dressed over them")
	assert_gt(torches, 0, "the torches are marked")
	var authored := 0
	for zone: AsciiLevel in _strip.zones:
		authored += zone.decorations.size()
	assert_eq(level.decorations.size(), authored, "authored decoration survives")


## --- 2. dressed -------------------------------------------------------------

func test_every_zone_gets_architecture() -> void:
	var view := _view()
	for zone: int in _strip.zone_count():
		var first := zone * _strip.zone_cols
		var found := ZoneView.cells_between(view.mid_decor, first, first + _strip.zone_cols)
		assert_gt(found.size(), 0, "zone %d has mid-ground architecture" % zone)


func test_a_mirrored_strip_is_dressed_as_a_mirror() -> void:
	var view := _view()
	var cols := _strip.cols()
	for plane: Dictionary in [view.mid_decor, view.fore_decor]:
		var unmatched := 0
		for cell: Vector2i in plane:
			var twin := Vector2i(cols - 1 - cell.x, cell.y)
			if not plane.has(twin) or plane[twin] != Tiles.mirror_atlas(plane[cell]):
				unmatched += 1
		assert_eq(unmatched, 0, "every mark has its mirror across the strip")


func test_decoration_only_stands_where_the_terrain_left_room() -> void:
	var view := _view()
	var misplaced := 0
	for cell: Vector2i in view.fore_decor:
		if _strip.kind_at(cell.x, cell.y) != Tiles.Kind.EMPTY:
			misplaced += 1
	assert_eq(misplaced, 0, "no foreground mark sits in a terrain cell")


## --- 3. lit as one world ----------------------------------------------------

func test_each_zone_casts_the_shadow_the_whole_strip_would() -> void:
	assert_eq(FULL_RES_COLS * TILE, SunShadow.MAX_MASK_PX, "the reference is full resolution")
	var view := _view()
	var atlas := Level.atlas_image()
	for zone: int in _strip.zone_count():
		var first := zone * _strip.zone_cols
		var last := first + _strip.zone_cols
		# The reference: everything to the west that still fits a full
		# resolution mask, which for this strip is all of it but the far
		# west of the last zone's -- ninety columns of lead.
		var from := maxi(0, last - FULL_RES_COLS)
		var reference := SunShadow.build(
			_strip.as_level(from, last), ZoneView.shift_cells(view.mid_decor, from, last),
			TILE, atlas
		).get_image()
		var window := view.shadow_window(zone)
		var mine: Texture2D = view.zone_materials[zone].get_shader_parameter("shadow_mask")
		var image := mine.get_image()
		assert_eq(image.get_width(), (window.y - window.x) * TILE,
			"zone %d's mask is full resolution" % zone)
		var differ := 0
		for y: int in image.get_height():
			for x: int in range(first * TILE, last * TILE):
				var a := image.get_pixel(x - window.x * TILE, y).r
				var b := reference.get_pixel(x - from * TILE, y).r
				if (a > 0.5) != (b > 0.5):
					differ += 1
		assert_eq(differ, 0, "zone %d's shadow matches a solve over everything west" % zone)
		var origin: Vector2 = view.zone_materials[zone].get_shader_parameter("mask_origin")
		assert_eq(origin, Vector2(window.x * TILE, 0), "the shader is told where the mask is")


func test_no_zone_is_blank_or_black() -> void:
	var view := _view()
	for zone: int in _strip.zone_count():
		var mask: Texture2D = view.zone_materials[zone].get_shader_parameter("shadow_mask")
		var image := mask.get_image()
		var shaded := 0
		for y: int in image.get_height():
			for x: int in image.get_width():
				if image.get_pixel(x, y).r > 0.5:
					shaded += 1
		var share := float(shaded) / float(image.get_width() * image.get_height())
		assert_between(share, 0.005, 0.6, "zone %d is lit and shadowed (%.1f%%)"
			% [zone, share * 100.0])


## --- 4. purely visual -------------------------------------------------------

func test_dressing_the_strip_changes_nothing_a_match_reads() -> void:
	var before := _strip.identity()
	var view := _view()
	view.focus(0.0, PackedFloat32Array([_strip.zone_width() * 2.5]))
	assert_eq(_strip.identity(), before, "the strip's identity is untouched")
	assert_gt(view.realized.size(), 0, "zones were realised")
	for zone: int in view.realized:
		for layer_name: String in ["Tiles", "Decor", "Fore"]:
			var layer := view.layer(zone, layer_name)
			assert_not_null(layer, "zone %d has a %s layer" % [zone, layer_name])
			if layer != null:
				assert_false(layer.collision_enabled,
					"zone %d's %s layer does not collide" % [zone, layer_name])
		assert_gt(view.layer(zone, "Decor").get_used_cells().size(), 0,
			"zone %d is drawn with its architecture" % zone)
