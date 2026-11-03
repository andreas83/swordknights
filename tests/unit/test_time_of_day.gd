extends GutTest
## A level's hour (scripts/render/time_of_day.gd, world_grade.gd): the grade
## each stop lays over the world and the sky, the light the shadow solve
## works in, and what is lifted back out of it.
##
## Held here: each stop's multiply and sky are the table's (docs/campaign.md,
## "Time of day"), along MatchDusk.DUSK and on to NIGHT; an afternoon level --
## every level so far -- gets no grade node at all, so it is the game as it
## was; a lower sun throws longer shadows, a horizon leaves no lit pixel below
## it, and night is all shade with no solve; the sky has no sun at night; and
## everything that must be read -- the prince, a foe, a relic, a torch -- is
## lifted back to its own light, which is what keeps a tell readable at dusk.

const TILE := 16
const GAME_SCENE := "res://scenes/game.tscn"

## A wall on a terrace, with a guard, a relic and a torch to lift.
const TERRACE := """; Terrace
%s



 @  #   p  *  t     D
####################
####################
####################
"""

var _atlas: Image


func before_all() -> void:
	_atlas = (load("res://assets/tiles.png") as Texture2D).get_image()


func _level(time: String, extra: String = "") -> AsciiLevel:
	var level := AsciiLevel.new()
	var header := (";! time %s" % time) if time != "" else ""
	level.parse(TERRACE % (header + extra))
	assert_eq(level.problems, PackedStringArray(), "the terrace parses clean at %s" % time)
	return level


func _shaded(time: String, extra: String = "") -> PackedByteArray:
	var image := SunShadow.build(_level(time, extra), {}, TILE, _atlas).get_image()
	return image.get_data()


func _count(mask: PackedByteArray) -> int:
	var shaded := 0
	for value: int in mask:
		if value == SunShadow.SHADOW_BIT:
			shaded += 1
	return shaded


## --- the table ------------------------------------------------------------------

func test_each_stop_is_its_row_of_the_table() -> void:
	var afternoon := TimeOfDay.grade_of(_level(""))
	assert_true(TimeOfDay.is_plain(afternoon), "no directive is the afternoon: no grade")
	assert_true(TimeOfDay.is_plain(TimeOfDay.grade_of(_level("afternoon"))))
	var rows := {
		"golden": [Color.WHITE.lerp(MatchDusk.DUSK, 0.25), 0.25, 0.0],
		"sunset": [Color.WHITE.lerp(MatchDusk.DUSK, 0.55), 0.6, 0.0],
		"dusk": [MatchDusk.DUSK, 1.0, 0.0],
		"night": [TimeOfDay.NIGHT, 1.0, 1.0],
		"0.4": [Color.WHITE.lerp(MatchDusk.DUSK, 0.4), 0.4, 0.0],
	}
	for stop: String in rows:
		var grade := TimeOfDay.grade_of(_level(stop))
		var want: Array = rows[stop]
		assert_true((grade["world"] as Color).is_equal_approx(want[0]), "%s's multiply" % stop)
		assert_almost_eq(float(grade["sky"]), float(want[1]), 0.001, "%s's sky" % stop)
		assert_almost_eq(float(grade["night"]), float(want[2]), 0.001, "%s's night" % stop)
	assert_eq(TimeOfDay.label("golden"), "Golden hour")


## --- the shadow ---------------------------------------------------------------

func test_a_lower_sun_throws_longer_shadows() -> void:
	var afternoon := _count(_shaded(""))
	var sunset := _count(_shaded("sunset"))
	var dusk := _count(_shaded("dusk"))
	assert_gt(sunset, afternoon, "sunset's reach is longer than the afternoon's")
	assert_gt(dusk, sunset, "and dusk's longer still")
	assert_eq(_count(_shaded("afternoon")), afternoon, "the afternoon is the light as it was")


func test_below_the_horizon_nothing_is_lit() -> void:
	var image := SunShadow.build(_level("dusk", "\n;! horizon 4"), {}, TILE, _atlas).get_image()
	var lit_below := 0
	for y: int in range(4 * TILE, image.get_height()):
		for x: int in image.get_width():
			if image.get_pixel(x, y).r < 0.5:
				lit_below += 1
	assert_eq(lit_below, 0, "every pixel from row 4 down is in the far city's shadow")
	assert_lt(_count(image.get_data()), image.get_width() * image.get_height(),
		"and above it the sun still shines")


func test_night_is_all_shade_and_solves_nothing() -> void:
	var mask := _shaded("night")
	assert_eq(_count(mask), mask.size(), "every pixel in shade")
	assert_true(bool(SunShadow.timings.get("sunless", false)), "and no solve was run")


## --- the sky ------------------------------------------------------------------------

func test_the_night_sky_has_no_sun() -> void:
	var sky := ParallaxSky.new()
	add_child_autofree(sky)
	assert_true(sky.shows_sun(), "by day there is a sun")
	sky.night = 1.0
	assert_false(sky.shows_sun(), "at night there is none")


## --- in play ---------------------------------------------------------------------------

func _play(time: String) -> Game:
	var game := (load(GAME_SCENE) as PackedScene).instantiate() as Game
	game.level_source = _level(time)
	add_child_autofree(game)
	await wait_physics_frames(3)
	await wait_process_frames(2)
	return game


func test_an_afternoon_level_gets_no_grade_at_all() -> void:
	var game := await _play("")
	assert_null(game.get_node_or_null(^"WorldGrade"), "no node: the game as it always was")
	assert_eq(game.sky.dusk, 0.0)
	assert_eq(game.sky.night, 0.0)


func test_at_dusk_the_world_is_graded_and_what_must_be_read_is_not() -> void:
	var game := await _play("dusk")
	var grade := game.get_node_or_null(^"WorldGrade") as WorldGrade
	assert_not_null(grade, "dusk is a grade")
	if grade == null:
		return
	assert_true(grade.color.is_equal_approx(MatchDusk.DUSK), "the world goes to MatchDusk's dusk")
	assert_eq(game.sky.dusk, 1.0, "and the sky paints its own")
	var lifted: Array[Node] = [game.player]
	for node: Node in game.get_node(^"Entities").get_children():
		if node is Patrol or node is Relic or node is Torch:
			lifted.append(node)
	assert_eq(lifted.size(), 4, "the prince, the guard, the relic and the torch")
	for node: Node in lifted:
		var seen := (node as CanvasItem).modulate * grade.color
		assert_true(seen.is_equal_approx(Color.WHITE),
			"%s is at its own light under the grade" % node.name)
