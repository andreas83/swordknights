extends GutTest
## The duel's sky is the adventure's ParallaxSky, and nothing the campaign's
## story added to that sky reaches it: no Mirror Tower, no sun in the east,
## no windows lit (docs/campaign.md: the duel shares the sky, and only the
## sun's side was ever decided for both). Checked on the duel's own scene as
## it builds itself, and on every scene in the game that is not the
## campaign, so a default changed in ParallaxSky shows up here and not in a
## match.

const SCENES: Array[String] = [
	"res://scenes/duel_match.tscn",
	"res://scenes/menu.tscn",
	"res://scenes/game.tscn",
	"res://scenes/generated_game.tscn",
]


func test_the_duels_sky_has_none_of_the_campaigns_story() -> void:
	var scene := (load(SCENES[0]) as PackedScene).instantiate()
	add_child_autofree(scene)
	await wait_physics_frames(3)
	var sky := scene.get_node(^"Sky/ParallaxSky") as ParallaxSky
	assert_not_null(sky, "the duel has its sky")
	_assert_plain(sky, "the duel")
	var view := Vector2(320, 180)
	assert_lt(sky.sun_center(view, Vector2(view.x * 0.5, 90.0)).x, view.x * 0.5,
		"and its sun is in the west, where the light comes from")


func test_no_scene_but_the_campaign_puts_the_tower_up() -> void:
	var checked := 0
	for path: String in SCENES.slice(1):
		var scene := (load(path) as PackedScene).instantiate()
		add_child_autofree(scene)
		await wait_physics_frames(2)
		var sky := scene.get_node_or_null(^"Sky/ParallaxSky") as ParallaxSky
		if sky == null:
			for child: Node in scene.get_children():
				sky = child.get_node_or_null(^"Sky/ParallaxSky") as ParallaxSky
				if sky != null:
					break
		assert_not_null(sky, "%s has a sky" % path)
		if sky != null:
			_assert_plain(sky, path)
			checked += 1
	assert_eq(checked, SCENES.size() - 1, "checked every scene")


func _assert_plain(sky: ParallaxSky, what: String) -> void:
	assert_eq(sky.tower, 0.0, "%s: no Mirror Tower" % what)
	assert_eq(sky.tower_rect(Vector2(320, 180), Vector2(160, 90)), Rect2(),
		"%s: nothing drawn for it" % what)
	assert_false(sky.tower_lit, "%s: no mirror lit" % what)
	assert_false(sky.east, "%s: the sun in the west" % what)
	assert_false(sky.windows_lit, "%s: the windows dark" % what)
