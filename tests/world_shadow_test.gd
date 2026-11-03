extends SceneTree
## Pins the cast-shadow model to the things that make it look right.
##
## The shadow is a projection, not a lighting pass, so it can be asserted
## rather than eyeballed: given a wall of a known height, the shadow it throws
## lands in a place arithmetic can predict. Everything below is a property the
## picture visibly loses when it breaks — each case names the failure.
##
##     godot --headless --script tests/world_shadow_test.gd

const TILE := 16

var _failures := 0
var _atlas: Image


func _initialize() -> void:
	_atlas = (load("res://assets/tiles.png") as Texture2D).get_image()

	_check_sun_direction()
	_check_a_wall_shades_the_floor_to_its_right()
	_check_a_flat_floor_keeps_its_gold()
	_check_a_column_shades_the_terrace_it_stands_on()
	_check_a_cornice_does_not_shade_its_own_floor()
	_check_a_wall_does_not_comb_itself()
	_check_shipping_levels_are_neither_blank_nor_black()
	_check_the_mask_fits_in_a_texture()

	if _failures > 0:
		printerr("world_shadow_test: %d failure(s)" % _failures)
		quit(1)
		return
	print("world_shadow_test: ok")
	quit(0)


## --- the model --------------------------------------------------------------

## The sun has to be low and from the left, and its slope has to be whole
## numbers. A fractional slope would break the lane decomposition the solve is
## built on, and a slope of 1 or less would stop the shadows being long.
func _check_sun_direction() -> void:
	_true(SunShadow.RUN > SunShadow.RISE, "the sun is low: it runs further than it falls")
	_true(SunShadow.RUN == int(SunShadow.RUN), "the sun's slope is whole pixels")
	_true(SunShadow.REACH_TILES > 1.0, "shadows reach past the tile that casts them")


## A wall standing a tile above the floor beside it throws its shadow onto
## that floor, offset to the right by RUN pixels for every pixel it stands
## above it. If this fails the world has no cast shadow in it at all, which is
## what it looked like before any of this existed.
func _check_a_wall_shades_the_floor_to_its_right() -> void:
	var mask := _solve([
		"            ",
		"            ",
		"   ###      ",
		"   ###      ",
		"############",
		"############",
	])
	# The wall's top is row 2, the floor's is row 4: two tiles of rise, so the
	# shadow starts two tiles times RUN to the right of the wall's right edge.
	var wall_right := 6 * TILE - 1
	var floor_top := 4 * TILE
	_true(_shaded(mask, wall_right + 4, floor_top + 1),
		"the floor just right of the wall is in its shadow")
	var reach := int(SunShadow.REACH_TILES * TILE)
	_true(not _shaded(mask, wall_right + reach + 2 * TILE, floor_top + 1),
		"the shadow stops: it does not run the length of the level")
	_true(not _shaded(mask, 1, floor_top + 1),
		"the floor to the LEFT of the wall is lit — the sun is on that side")


## The top of an unbroken floor is the lit path. If a body shadows itself,
## every gold cap in the game turns crimson and the duotone collapses to one
## tone.
func _check_a_flat_floor_keeps_its_gold() -> void:
	var mask := _solve([
		"            ",
		"            ",
		"############",
		"############",
	])
	var lit := 0
	for x: int in 12 * TILE:
		if not _shaded(mask, x, 2 * TILE + 1):
			lit += 1
	_true(lit == 12 * TILE, "a flat floor is lit end to end, not self-shadowed (%d/%d)"
		% [lit, 12 * TILE])


## The colonnade is the rule that puts light back into a composition, and it
## only works if a column counts as its own body. Get this wrong and a terrace
## full of columns is as flat as a bare one.
func _check_a_column_shades_the_terrace_it_stands_on() -> void:
	var lines := ["            ", "            ", "############", "############"]
	var bare := _solve(lines)
	var decor := {}
	for i: int in 3:
		decor[Vector2i(3, 1 - i)] = Tiles.DECOR_ATLAS["column_shaft"]
	var dressed := _solve(lines, decor)

	var bare_shade := _count_shaded(bare, 2 * TILE, 2 * TILE + 3)
	var dressed_shade := _count_shaded(dressed, 2 * TILE, 2 * TILE + 3)
	_true(dressed_shade > bare_shade + TILE,
		"a column throws a shadow across its own terrace (%d px vs %d)"
		% [dressed_shade, bare_shade])


## The mirror image of the rule above. A cornice is carved into the terrace,
## not standing on it, so it must NOT shade the cap below it — if it does,
## every dressed lip in the game loses its gold.
func _check_a_cornice_does_not_shade_its_own_floor() -> void:
	var lines := ["            ", "            ", "############", "############"]
	var bare := _count_shaded(_solve(lines), 2 * TILE, 2 * TILE + 3)
	var decor := {}
	for x: int in 12:
		decor[Vector2i(x, 1)] = Tiles.DECOR_ATLAS["cornice"]
	var dressed := _count_shaded(_solve(lines, decor), 2 * TILE, 2 * TILE + 3)
	_true(dressed <= bare, "a cornice leaves its own cap lit (%d px vs %d)" % [dressed, bare])


## The bug this exists to catch, because it is spectacular and it does not
## look like a shadow bug. If anything standing on a wall counts as part of
## that wall, then every column of the wall under it has a run top higher than
## its neighbours' — at EVERY depth — and the whole face combs itself into
## vertical stripes all the way to the ground. A shadow must die out below the
## thing that cast it.
func _check_a_wall_does_not_comb_itself() -> void:
	var lines: Array[String] = ["            ", "            "]
	for _y: int in 6:
		lines.append("############")
	var decor := {}
	for x: int in range(2, 10, 3):
		decor[Vector2i(x, 1)] = Tiles.DECOR_ATLAS["balustrade"]

	var mask := _solve(lines, decor)
	var deep := 6 * TILE # four tiles below the wall's top, well past any reach
	var stripes := 0
	for x: int in 12 * TILE:
		if _shaded(mask, x, deep):
			stripes += 1
	_true(stripes == 0,
		"a wall face four tiles down is clean, not combed (%d px of stripe)" % stripes)


## --- the levels that ship ---------------------------------------------------

## Two failure modes, both of which have happened: a mask of all zeroes (no
## shadows anywhere, the world reads flat) and a mask of all ones (everything
## in shade, the world reads black). Neither errors; both are obvious on
## screen and invisible to a test that only checks the thing ran.
func _check_shipping_levels_are_neither_blank_nor_black() -> void:
	for path: String in ["res://levels/level_01.txt", "res://levels/arena_01.txt",
			"res://levels/feel_lab.txt"]:
		var level := AsciiLevel.from_file(path)
		if level == null:
			_fail("could not load %s" % path)
			continue
		var dressing := WorldDresser.dress(level)
		var texture := SunShadow.build(level, dressing["mid"], TILE, _atlas)
		var image := texture.get_image()
		var shaded := _count_shaded(image, 0, image.get_height() - 1)
		var total := image.get_width() * image.get_height()
		var fraction := float(shaded) / float(total)
		_true(fraction > 0.02 and fraction < 0.6,
			"%s is lit AND shadowed (%.1f%% in shade)" % [path, fraction * 100.0])


## GL ES3 only promises 2048 px of texture, and a long generated level is
## wider than that. The solve drops to half resolution rather than handing the
## driver something it may refuse.
func _check_the_mask_fits_in_a_texture() -> void:
	var level := AsciiLevel.new()
	level.parse("\n".join(_long_level()))
	var texture := SunShadow.build(level, {}, TILE, _atlas)
	_true(texture.get_width() <= SunShadow.MAX_MASK_PX,
		"a 300-tile level's mask stays inside the texture limit (%d px)" % texture.get_width())
	_true(SunShadow.timings.get("step", 1) > 1, "and it got there by halving resolution")


func _long_level() -> Array[String]:
	var row := ""
	for _x: int in 300:
		row += "#"
	return ["", "", row, row]


## --- helpers ----------------------------------------------------------------

func _solve(lines: Array, decor: Dictionary = {}) -> Image:
	var level := AsciiLevel.new()
	level.parse("\n".join(lines))
	return SunShadow.build(level, decor, TILE, _atlas).get_image()


func _shaded(mask: Image, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= mask.get_width() or y >= mask.get_height():
		return false
	return mask.get_pixel(x, y).r > 0.5


func _count_shaded(mask: Image, from_y: int, to_y: int) -> int:
	var count := 0
	for y: int in range(maxi(0, from_y), mini(mask.get_height(), to_y + 1)):
		for x: int in mask.get_width():
			if mask.get_pixel(x, y).r > 0.5:
				count += 1
	return count


func _true(condition: bool, what: String) -> void:
	if condition:
		return
	_fail(what)


func _fail(what: String) -> void:
	_failures += 1
	printerr("  FAIL: %s" % what)
