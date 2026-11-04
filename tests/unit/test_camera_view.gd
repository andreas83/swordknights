extends GutTest
## What the camera shows, as play reads it (scripts/entities/camera_view.gd),
## is a fact of the simulation: the same on every run and at any frame rate.
##
## A foe acts only while the camera shows it, so the frame is a rule of play.
## It used to be read off the rendered camera: smoothed on the display's
## clock and shaken by randf(). The campaign's end-to-end run, played ten
## times faster than the wall clock with every step still 1/60 s, found it --
## Chapter III's frozen clear run took a scratch from a cat that saw the
## prince a frame early, and finished half a second later than in its own
## test. Held here: the camera smooths on the physics step, and the frame a
## foe asks about leaves the shake and the settle out.

const GAME_SCENE := "res://scenes/game.tscn"
const ROOM := """; Camera Room



  @                       D
############################
############################
"""

var _game: Game


func _play() -> void:
	var data := AsciiLevel.new()
	data.parse(ROOM)
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Game
	_game.level_source = data
	add_child_autofree(_game)
	await wait_physics_frames(4)


func test_the_camera_follows_on_the_simulation_s_clock() -> void:
	await _play()
	assert_eq(_game.camera.process_callback, Camera2D.CAMERA2D_PROCESS_PHYSICS,
		"smoothed per physics step, not per rendered frame")


func test_a_shake_does_not_move_the_frame_play_reads() -> void:
	await _play()
	var still := CameraView.rect_for(_game.player)
	_game.camera.shake(6.0, 1.0)
	await wait_physics_frames(2)
	assert_ne(_game.camera.offset, Vector2.ZERO, "the image shakes")
	assert_eq(CameraView.rect_for(_game.player), still, "the frame a foe asks about does not")
