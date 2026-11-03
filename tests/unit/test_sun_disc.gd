extends GutTest
## The sun disc stands where the light comes from (ParallaxSky.sun_center()).
##
## Every shadow in the world falls along SunShadow's lane, RUN across for RISE
## down, away from the sun; for years the disc was drawn on the right of the
## sky, behind the shadows it cast. The owner moved it to the left, in every
## sky -- the adventure's and the duel's are the same ParallaxSky -- and these
## hold it there: at noon and at dusk, on the narrowest and widest screens,
## and however far the camera has run, since the disc drifts with it.

const VIEWS: Array[Vector2] = [Vector2(240, 180), Vector2(320, 180), Vector2(440, 180)]
## The disc's core at noon, in view units: what must stay on the screen.
const NOON_CORE := 17.0


func _sky() -> ParallaxSky:
	var sky := ParallaxSky.new()
	add_child_autofree(sky)
	return sky


func test_the_disc_is_on_the_side_the_light_comes_from() -> void:
	assert_gt(SunShadow.RUN, 0, "shadows fall to the right, so the light is on the left")
	var sky := _sky()
	for view: Vector2 in VIEWS:
		for dusk: float in [0.0, 0.5, 1.0]:
			sky.dusk = dusk
			var at := sky.sun_center(view, Vector2(view.x * 0.5, view.y * 0.5))
			assert_lt(at.x, view.x * 0.5, "left of centre on %s at dusk %.1f" % [view, dusk])


func test_dusk_draws_it_in_toward_the_middle_as_it_sinks() -> void:
	var sky := _sky()
	var view := VIEWS[1]
	var noon := sky.sun_center(view, Vector2.ZERO)
	sky.dusk = 1.0
	var dusk := sky.sun_center(view, Vector2.ZERO)
	assert_gt(dusk.x, noon.x, "the setting sun moves in, mirrored from where it was")
	assert_gt(dusk.y, noon.y, "and down")


func test_a_long_run_does_not_carry_it_off_the_sky() -> void:
	var sky := _sky()
	for view: Vector2 in VIEWS:
		var start := sky.sun_center(view, Vector2(view.x * 0.5, 90.0))
		var far := sky.sun_center(view, Vector2(170.0 * 16.0, 90.0))
		assert_lt(far.x, start.x, "it drifts left as the camera runs right")
		assert_gt(far.x - NOON_CORE, 0.0, "but its core is still on %s at the end of a ruin" % view)
