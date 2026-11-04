extends SceneTree
## Renders a whole level as it is played -- the grade, the firelight, every
## foe, blade and torch at its post -- as a grid of frames that
## tools/level_tour.py stitches into one image: the tour of a chapter, judged
## on rendered pixels rather than on its ASCII.
##
##     xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x720 \
##       --script tools/level_tour.gd -- --level res://levels/chapter_05.txt \
##       --out /tmp/tour
##     python3 tools/level_tour.py /tmp/tour /tmp/chapter_05_tour.png
##
## `--face x,y,DIR` turns the sun mirror in cell (x, y) to face UP, RIGHT,
## DOWN or LEFT before the first shot, so a set piece can be toured with its
## light where the player sends it: Chapter IV's tour is the great mirror at
## (5, 6) turned DOWN, the last ray falling the tower's whole height.
##
##     ... --script tools/level_tour.gd -- --level res://levels/chapter_04.txt \
##       --face 5,6,DOWN --out /tmp/tour
##
## The view is always 180 units tall (CLAUDE.md), so a level is shot a frame
## at a time: the camera is taken off the prince and put at each frame's
## centre, the prince is parked out of the way, and the frames are written
## with their grid position in the name. Nothing is stepped but the clock, so
## the blades and the owls are at rest as the level was authored.

const GAME_SCENE := "res://scenes/game.tscn"
## Frames to let the wipe lift and the title card pass before the first shot.
const SETTLE := 330
## Frames between shots, for the camera's move to be drawn.
const BETWEEN := 8

var _level_path := ""
var _out := "user://tour"
var _game: Game
var _frames := 0
var _shots: Array[Vector2] = []
var _view := Vector2(320.0, 180.0)
## --face: [cell, face] for each mirror to turn before the tour.
var _faces: Array[Array] = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for i: int in args.size():
		if args[i] == "--level" and i + 1 < args.size():
			_level_path = args[i + 1]
		elif args[i] == "--out" and i + 1 < args.size():
			_out = args[i + 1]
		elif args[i] == "--face" and i + 1 < args.size():
			var parts := args[i + 1].split(",")
			_faces.append([Vector2i(int(parts[0]), int(parts[1])),
				int(SunLight.Face.get(parts[2].to_upper(), SunLight.Face.UP))])
	DirAccess.make_dir_recursive_absolute(_out)
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Game
	if _level_path != "":
		_game.level_path = _level_path
	root.add_child(_game)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_plan()
		_turn_mirrors()
	if _frames < SETTLE:
		return false
	var index := (_frames - SETTLE) / BETWEEN
	var phase := (_frames - SETTLE) % BETWEEN
	if index >= _shots.size():
		print("level_tour: %d frames of %s -> %s" % [_shots.size(), _level_path, _out])
		quit(0)
		return true
	if phase == 0:
		_game.camera.global_position = _shots[index]
	elif phase == BETWEEN - 1:
		_capture(index)
	return false


## The frame centres, row by row, covering the level, and the prince parked
## where he draws nothing: a cell of solid stone.
func _plan() -> void:
	_view = root.get_visible_rect().size
	_game.camera.set_physics_process(false)
	_game.camera.position_smoothing_enabled = false
	_game.player.set_physics_process(false)
	_game.player.visible = false
	_game.get_node("HudLayer").visible = false
	# Half a view apart: the camera's drag keeps it short of where it is put,
	# and frames that overlap by half leave nothing between them uncovered.
	var size := _game.level.world_size()
	var cols := ceili(size.x / (_view.x * 0.5))
	var rows := ceili(size.y / (_view.y * 0.5))
	for row: int in rows:
		for col: int in cols:
			_shots.append(_view * 0.5 + Vector2(col, row) * _view * 0.5)
	var file := FileAccess.open("%s/grid.txt" % _out, FileAccess.WRITE)
	file.store_line("%d %d %d %d %d %d" % [cols, rows, roundi(_view.x), roundi(_view.y),
		roundi(size.x), roundi(size.y)])
	file.close()


## --face: each named mirror set to its face, and the light told it moved.
func _turn_mirrors() -> void:
	for turn: Array in _faces:
		var mirror := SunField.mirror_at(_game.level, turn[0] as Vector2i)
		if mirror == null:
			push_error("level_tour: no sun mirror at %s" % turn[0])
			continue
		mirror.face = int(turn[1])
		# The tour takes longer than the great mirror's sunset count, and the
		# sun going under halfway down the tower would leave half the frames
		# without the ray they are for: a toured mirror holds the hour.
		mirror.set(&"_sunset_wire", &"")
	SunField.touch()


## The frame, and where the camera really was: its limits, drag and offset
## all have a say, so the stitcher places each frame by this, not by the plan.
func _capture(index: int) -> void:
	var cols := ceili(_game.level.world_size().x / (_view.x * 0.5))
	var name := "%02d_%02d" % [index / cols, index % cols]
	root.get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	var centre := _game.camera.get_screen_center_position()
	var file := FileAccess.open("%s/%s.txt" % [_out, name], FileAccess.WRITE)
	file.store_line("%f %f" % [centre.x, centre.y])
	file.close()
