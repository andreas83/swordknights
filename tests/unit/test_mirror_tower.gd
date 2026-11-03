extends GutTest
## The Mirror Tower in the campaign's sky (ParallaxSky.tower, Campaign.TOWER).
##
## The bible: it "stands in the parallax skyline from Chapter I, its great
## mirror dark and turned away, and grows nearer each chapter until you are
## on it" (docs/campaign.md, "Story without words"). Held here: every entry
## says how far away it is; Chapter I has it; it only ever comes nearer, and
## strictly while it is still in the sky; it is reached -- 0, no tower in
## the sky -- at the chapter that is the tower; CampaignGame puts each
## entry's distance on that chapter's sky; and the tower sits right in the
## sky at every hour a level can be set at, at every distance a chapter puts
## it, on the narrowest and widest screens -- on the screen, standing clear
## above the near skyline's baseline, and a tone apart from the sky behind
## its top, which is the bug a far tower in the far plane's own colour had:
## its windows and nothing else.

const VIEWS: Array[Vector2] = [Vector2(320, 180), Vector2(440, 180)]
## How far apart, in luminance, the tower's top and the sky band behind it
## must be for the outline to read at 1:1.
const CONTRAST := 0.03


func after_each() -> void:
	Campaign.reset()


func test_every_entry_says_how_far_away_it_is() -> void:
	for index: int in Campaign.count():
		var entry := Campaign.entry(index)
		assert_true(entry.has("tower"), "%s has a tower distance" % entry["id"])
		var far := float(entry["tower"])
		assert_between(far, 0.0, 1.0, "%s's is between here and the horizon" % entry["id"])
	assert_gt(float(Campaign.entry(0)["tower"]), 0.0, "Chapter I has it in its sky")


func test_it_only_ever_comes_nearer() -> void:
	var last := INF
	for index: int in Campaign.count():
		var entry := Campaign.entry(index)
		var far := float(entry["tower"])
		assert_true(far <= last, "%s: never further than the chapter before" % entry["id"])
		if last > 0.0 and last != INF and not bool(entry["finale"]):
			assert_lt(far, last, "%s: nearer than the chapter before, until reached"
				% entry["id"])
		last = far


func test_it_is_reached_at_the_chapter_that_is_the_tower() -> void:
	var at := -1
	for index: int in Campaign.count():
		if String(Campaign.entry(index)["title"]) == "The Mirror Tower":
			at = index
	assert_gt(at, 0, "the Mirror Tower is a chapter")
	assert_eq(float(Campaign.entry(at)["tower"]), 0.0, "on it: not in its sky")
	assert_gt(float(Campaign.entry(at - 1)["tower"]), 0.0, "and in the sky right up to it")


func test_a_sky_without_a_distance_has_no_tower() -> void:
	var sky := ParallaxSky.new()
	add_child_autofree(sky)
	assert_eq(sky.tower, 0.0)
	assert_eq(sky.tower_rect(VIEWS[0], Vector2(160, 90)), Rect2(), "and draws none")


func test_it_sits_right_at_every_hour_and_every_distance() -> void:
	var checked := 0
	for stop: String in TimeOfDay.STOPS:
		var level := AsciiLevel.new()
		level.parse(";! time %s\n @\n##\n" % stop)
		var grade := TimeOfDay.grade_of(level)
		for index: int in Campaign.count():
			var far := float(Campaign.entry(index)["tower"])
			if far <= 0.0:
				continue
			for view: Vector2 in VIEWS:
				for cam: Vector2 in [Vector2(view.x * 0.5, 90.0), Vector2(2000.0, 320.0)]:
					_check(far, float(grade["sky"]), float(grade["night"]), view, cam,
						"%s at %.2f on %s, camera %s" % [stop, far, view, cam])
					checked += 1
	assert_gt(checked, 40, "checked every hour at every distance")


func _check(far: float, dusk: float, night: float, view: Vector2, cam: Vector2,
		what: String) -> void:
	var sky := ParallaxSky.new()
	add_child_autofree(sky)
	sky.tower = far
	sky.dusk = dusk
	sky.night = night
	var shaft := sky.tower_rect(view, cam)
	assert_gt(shaft.size.x, 0.0, "%s: drawn" % what)
	assert_gt(shaft.position.x, 0.0, "%s: on the screen" % what)
	assert_lt(shaft.end.x, view.x, "%s: on the screen" % what)
	assert_gt(shaft.position.y, 0.0, "%s: its top in the frame" % what)
	assert_lt(shaft.position.y, view.y * 0.25, "%s: high over the city" % what)
	var behind := sky.sky_at(shaft.position.y + 1.0, view)
	var tone := sky.tower_colour(view, shaft.position.y)
	var seen := behind.lerp(Color(tone.r, tone.g, tone.b), tone.a)
	assert_gt(absf(seen.get_luminance() - behind.get_luminance()), CONTRAST,
		"%s: a tone apart from the sky behind it" % what)


func test_each_chapter_has_its_own_distance_in_its_sky() -> void:
	var dir := "user://test_mirror_tower"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := dir.path_join("alpha.txt")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("; Alpha\n\n @    D\n########\n")
	file.close()
	Campaign.use_for_test([{"id": "alpha", "numeral": "II", "title": "Alpha",
		"epigraph": "", "time": "afternoon", "file": path, "finale": false, "tower": 0.6}])
	var campaign := (load("res://scenes/campaign_game.tscn") as PackedScene).instantiate() \
		as CampaignGame
	campaign.progress_path = "user://test_mirror_tower.cfg"
	campaign.leave = func() -> void: pass
	add_child_autofree(campaign)
	await wait_physics_frames(2)
	assert_eq(campaign.game().sky.tower, 0.6, "the entry's distance, on its sky")
	assert_false(campaign.game().sky.east, "with the sun where it always is")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
