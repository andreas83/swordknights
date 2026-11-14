extends GutTest
## The Adventure's camera stands at 1.5x and nothing else does
## (scripts/render/game_camera.gd, "A fixed 1.5x").
##
## The owner's call: the 22-unit figure fills nearly a fifth of the screen's
## height in every scene that plays a level, instead of an eighth. It is made
## by the camera and only by the camera, so it is pinned at each of the three
## places it could leak from or into:
##
## - every scene that plays a level is GameCamera at GameCamera.ZOOM --
##   game.tscn, which the Adventure, the campaign and Endless all instantiate,
##   and the feel lab, which is its own scene;
## - the frame a foe asks about (CameraView) is the world the zoomed camera
##   shows, not the viewport's 180 units: a foe acting on a stretch of world
##   off the screen is a death nobody could read;
## - what is not the world does not move: the viewport is still 180 units
##   tall, the HUD draws at the viewport's own scale, and the duel's camera
##   keeps its own whole-pixel framing (MatchFraming), never multiplied by the
##   Adventure's zoom.

const GAME_SCENE := "res://scenes/game.tscn"
const FEEL_LAB := "res://scenes/feel_lab.tscn"
const Support := preload("res://tests/duel_support.gd")
const ROOM := """; Zoom Room



  @                       D
############################
############################
"""


func _play(path: String, source: AsciiLevel = null) -> Game:
	var game := (load(path) as PackedScene).instantiate() as Game
	if source != null:
		game.level_source = source
	add_child_autofree(game)
	await wait_physics_frames(4)
	return game


func _room() -> AsciiLevel:
	var data := AsciiLevel.new()
	data.parse(ROOM)
	return data


func test_the_adventure_s_scale_is_one_and_a_half() -> void:
	assert_eq(GameCamera.ZOOM, 1.5, "the owner's 1.5x")
	assert_eq(ProjectSettings.get_setting("display/window/size/viewport_height"), 180,
		"made by the camera, not by a shorter viewport")


func test_the_game_scene_stands_at_it() -> void:
	_assert_zoomed(await _play(GAME_SCENE, _room()), GAME_SCENE)


func test_the_feel_lab_stands_at_it() -> void:
	_assert_zoomed(await _play(FEEL_LAB), FEEL_LAB)


func _assert_zoomed(game: Game, path: String) -> void:
	var drawing := game.get_viewport().get_camera_2d()
	assert_true(drawing is GameCamera, "%s draws through GameCamera" % path)
	assert_eq(drawing, game.camera as Camera2D, "%s: its own camera" % path)
	assert_eq(drawing.zoom, Vector2.ONE * GameCamera.ZOOM,
		"%s stands at GameCamera.ZOOM" % path)


func test_a_foe_asks_about_the_world_the_screen_shows() -> void:
	var game := await _play(GAME_SCENE, _room())
	var view := game.get_viewport().get_visible_rect().size
	var frame := CameraView.rect_for(game.player)
	assert_eq(frame.size, view / GameCamera.ZOOM,
		"the frame is the viewport's size over the zoom")
	# The drawn rectangle, from the canvas transform the renderer uses: the
	# frame play reads and the picture must be the same size, or a foe acts
	# off the edge of the screen.
	var drawn := game.get_viewport().get_canvas_transform().affine_inverse() \
		* game.get_viewport().get_visible_rect()
	assert_almost_eq(frame.size.x, drawn.size.x, 0.01, "as wide as what is drawn")
	assert_almost_eq(frame.size.y, drawn.size.y, 0.01, "as tall as what is drawn")


func test_the_hud_is_not_zoomed() -> void:
	var game := await _play(GAME_SCENE, _room())
	var hud := game.get_node("HudLayer/Hud") as Control
	assert_not_null(hud, "the HUD is where game.tscn puts it")
	var layer := game.get_node("HudLayer") as CanvasLayer
	assert_false(layer.follow_viewport_enabled, "the HUD's layer does not follow the camera")
	assert_eq(hud.get_global_transform_with_canvas().get_scale(), Vector2.ONE,
		"the HUD draws at the viewport's own scale")
	assert_eq(hud.get_viewport_rect().size, game.get_viewport().get_visible_rect().size,
		"and over the whole viewport")


func test_the_duel_keeps_its_own_framing() -> void:
	var fight := DuelMatch.new()
	add_child_autofree(fight)
	assert_true(fight.build(Support.load_strip()), "the match builds")
	var camera := MatchCamera.new()
	camera.screen_pixels = Vector2(2400.0, 1080.0)
	camera.pixels_per_unit = 6.0
	add_child_autofree(camera)
	camera.setup(fight)
	for _frame: int in 30:
		fight.step(0, 0)
		camera._process(1.0 / 60.0)
	var framing: Node = camera
	assert_false(framing is GameCamera, "the duel does not frame with the Adventure's camera")
	assert_eq(camera.zoom, Vector2.ONE * camera.framing.zoom(),
		"its zoom is its own framing's answer")
	# At rest the duel stands at a whole number of screen pixels per texel; the
	# Adventure's 1.5 laid over it would put it at a half.
	assert_true(camera.framing.at_rest(), "the framing has come to rest")
	var per_texel := camera.zoom.x * 6.0
	assert_almost_eq(per_texel, roundf(per_texel), 0.001,
		"%.2f screen pixels a texel: a whole number" % per_texel)
	assert_eq(roundi(per_texel), camera.framing.level, "and the level its framing chose")
