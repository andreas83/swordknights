extends GutTest
## The Adventure's frame looks where the jump goes (scripts/render/game_camera.gd,
## "Looking where the jump goes"), in a real Game on a real level: from the lip
## of a five-tile drop, the deepest a level may ask for, the floor it lands on
## is in shot before the jump; from under a ledge a jump can grab, its lip is;
## and on open floor the frame stays where it always rested. This is the
## campaign's "No blind jumps" (docs/campaign.md) held at the 1.5x the camera
## stands at.
##
## The static rules are pinned in tests/feel_camera_test.gd; this is the half
## that proves the camera reads the level it is in.

## Each level stands in open air with deep rock under it, so the frame is
## never held by the world's edge (Camera2D limits): a frame pinned to the
## bottom of a short level showed the drop whether or not it looked, and the
## first draft of this test passed for that reason alone.
func _sky() -> String:
	return "\n".repeat(12)


func _rock() -> String:
	return "####################\n".repeat(10)


func _lip() -> String:
	return "; Camera Lip\n" + _sky() + "   @\n" + "#####\n".repeat(5) + _rock()


func _ledge() -> String:
	return "; Camera Ledge\n" + _sky() + "     ##########\n".repeat(3) \
		+ "   @ ##########\n" + _rock()


func _flat() -> String:
	return "; Camera Flat\n" + _sky() + "   @\n" + _rock()


func _game(source: String) -> Game:
	var data := AsciiLevel.new()
	data.parse(source)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Game
	game.level_source = data
	add_child_autofree(game)
	return game


## How much of the world the frame shows below and above the feet, once it
## has had time to settle on the prince standing still.
func _shown(game: Game) -> Vector2:
	await wait_physics_frames(150)
	var centre := game.camera.frame_centre()
	var feet := game.player.position.y
	var half := GameCamera.half_shown()
	return Vector2(centre.y + half - feet, feet - (centre.y - half))


func test_from_the_lip_of_a_five_tile_drop_its_floor_is_in_shot() -> void:
	var game := _game(_lip())
	game.player.facing = 1
	var shown := await _shown(game)
	assert_gte(shown.x, 5.0 * Tuning.TILE, "below the feet: %.1f" % shown.x)
	assert_gte(shown.y, Tuning.BODY_HEIGHT, "and the head still in shot: %.1f" % shown.y)


func test_under_a_ledge_its_lip_is_in_shot() -> void:
	var game := _game(_ledge())
	game.player.facing = 1
	var shown := await _shown(game)
	assert_gte(shown.y, 4.0 * Tuning.TILE, "above the feet: %.1f" % shown.y)


func test_on_open_floor_the_frame_rests_on_the_feet() -> void:
	var game := _game(_flat())
	game.player.facing = 1
	var shown := await _shown(game)
	assert_almost_eq(shown.x, GameCamera.half_shown(), 1.0, "centred: %.1f below" % shown.x)
