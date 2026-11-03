extends GutTest
## The dawn (scripts/campaign/dawn_frame.gd): the one frame of The Last Light
## lit from the east (docs/campaign.md, "Decided by the owner").
##
## Held here, on the frame as the game builds it: its shadow mask, read back
## through the reflection, puts the shade WEST of what casts it -- the wall
## that frames the doorway throws its shadow onto the floor on its west side
## and leaves the floor on its east side lit, which an ordinary solve does
## the other way round, and that is checked too, on the same level unmirrored,
## so the test cannot pass by finding no shade at all; the sun disc is on the
## right; the swordknight faces it; the words are Campaign.ENDING's and cast
## their shadow to the left; and the frame is dressed by its author alone.

const VIEW := Vector2(320, 180)


func _dawn() -> DawnFrame:
	var dawn := DawnFrame.new()
	add_child_autofree(dawn)
	await wait_physics_frames(2)
	return dawn


## The doorway wall: the frame's one solid column of stone above its floor,
## as [its west edge, its east edge, the floor's top] in screen coordinates.
func _wall(dawn: DawnFrame) -> Array[float]:
	var data := dawn.level.data
	var floor_row := data.spawn_point.y + 1
	var cols: Array[int] = []
	for x: int in data.cols:
		if data.is_solid(x, floor_row - 1):
			cols.append(x)
	assert_gt(cols.size(), 0, "the frame has a wall standing on its floor")
	var a := dawn.world.to_global(Vector2(cols.min() * Level.TILE, floor_row * Level.TILE))
	var b := dawn.world.to_global(Vector2((cols.max() + 1) * Level.TILE, 0.0))
	return [minf(a.x, b.x), maxf(a.x, b.x), a.y]


func test_the_light_comes_from_the_right() -> void:
	var dawn := await _dawn()
	var wall := _wall(dawn)
	var floor_y := wall[2] + 1.0
	var west := 0
	var east := 0
	for dx: int in range(2, 30, 2):
		if dawn.shaded(Vector2(wall[0] - dx, floor_y)):
			west += 1
		if dawn.shaded(Vector2(wall[1] + dx, floor_y)):
			east += 1
	assert_gt(west, 5, "the floor west of the wall is in its shadow")
	assert_eq(east, 0, "and the floor east of it, toward the sun, is lit")


func test_an_ordinary_solve_of_the_same_stone_is_the_other_way_round() -> void:
	# The guard on the guard: the same frame through the solve every chapter
	# gets, unreflected, must find the shade on the other side -- so the
	# test above is reading a mask that has shade in it, and reading it the
	# right way up.
	var level := Level.new()
	level.level_path = DawnFrame.FRAME
	add_child_autofree(level)
	await wait_physics_frames(1)
	var mask := SunShadow.last_mask
	var data := level.data
	var floor_row := data.spawn_point.y + 1
	var cols: Array[int] = []
	for x: int in data.cols:
		if data.is_solid(x, floor_row - 1):
			cols.append(x)
	var y := floor_row * Level.TILE + 1
	var east := 0
	var west := 0
	for dx: int in range(2, 30, 2):
		if mask.get_pixel((cols.max() + 1) * Level.TILE + dx, y).r > 0.5:
			east += 1
		if mask.get_pixel(cols.min() * Level.TILE - dx, y).r > 0.5:
			west += 1
	assert_gt(east, 5, "unreflected, the shadow falls east of the wall")
	assert_eq(west, 0, "and the sun is in the west")


func test_the_sun_is_in_the_east_and_he_faces_it() -> void:
	var dawn := await _dawn()
	assert_true(dawn.sky.east)
	assert_gt(dawn.sky.sun_center(VIEW, Vector2.ZERO).x, VIEW.x * 0.5, "the disc on the right")
	var facing := float(dawn.figure.facing) * dawn.figure.get_global_transform().x.x
	assert_gt(facing, 0.0, "the swordknight faces the sunrise")
	assert_true(dawn.sky.tower_lit, "the great mirror holds the sun")
	assert_lt(dawn.sky.tower_rect(VIEW, Vector2.ZERO).get_center().x, VIEW.x * 0.5,
		"behind him, in the west")


func test_the_words_are_the_endings_and_cast_to_the_left() -> void:
	var dawn := await _dawn()
	assert_true(dawn.card.light_from_east, "the words are lit from the east as well")
	assert_eq(String(Campaign.ENDING["title"]).to_upper(), "DAWN")
	assert_false(dawn.card.leave(), "and are not skipped by a held jump")


func test_the_frame_is_dressed_by_its_author_alone() -> void:
	var level := AsciiLevel.from_file(DawnFrame.FRAME)
	assert_eq(level.problems, PackedStringArray(), "the frame parses clean")
	assert_true(WorldDresser.dressed_by_author(level))
	var dressed := WorldDresser.dress(level)
	assert_eq(dressed["fore"], {}, "no foreground set piece the author did not place")
	assert_eq(dressed["props"], {}, "and no room moods")
	var bare := AsciiLevel.new()
	bare.parse(";! dress everything\n @\n##\n")
	assert_eq(bare.problems.size(), 1, "a dress that is not 'authored' is a problem")
