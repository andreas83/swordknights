extends SceneTree
## Renders a scene off-screen and writes PNGs, so visual changes can be checked
## without a human at a screen — locally and in CI.
##
##     xvfb-run -a godot --path . --rendering-driver opengl3 \
##       --script tools/screenshot.gd -- --scene res://scenes/game.tscn \
##       --out /tmp/shots --shots 0.5,2.0,4.0 --hold move_right
##
## --hold holds an input action for the whole run, which is enough to walk the
## character into the first few beats of a level.
##
## For a scene that plays a level (Game), --level plays another file and
## --time sets the hour it is played at, as `;! time <stop>` would, without
## editing the file: how a level is judged at each stop of the grade.
##
##     ... --script tools/screenshot.gd -- --level res://levels/level_01.txt \
##       --time dusk --out /tmp/dusk --shots 1.0,3.0 --hold move_right

var _scene_path := "res://scenes/game.tscn"
var _out_dir := "user://shots"
var _shot_times: Array[float] = [1.0]
var _hold: Array[String] = []
var _level_path := ""
var _time := ""

var _elapsed := 0.0
var _taken := 0


func _initialize() -> void:
	_parse_args()

	var packed := load(_scene_path) as PackedScene
	if packed == null:
		push_error("could not load %s" % _scene_path)
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute(_out_dir)

	var instance := packed.instantiate()
	if instance is Game and (_level_path != "" or _time != ""):
		(instance as Game).level_source = _level(instance as Game)
	root.add_child(instance)
	root.set_meta("screenshot_target", instance)

	for action: String in _hold:
		Input.action_press(action)

	print("rendering %s -> %s at %s" % [_scene_path, _out_dir, str(_shot_times)])


func _process(delta: float) -> bool:
	_elapsed += delta

	while _taken < _shot_times.size() and _elapsed >= _shot_times[_taken]:
		_capture(_taken)
		_taken += 1

	if _taken >= _shot_times.size():
		for action: String in _hold:
			Input.action_release(action)
		return true
	return false


func _capture(index: int) -> void:
	var texture := root.get_texture()
	if texture == null:
		push_warning("no viewport texture yet")
		return
	var image := texture.get_image()
	var path := "%s/%02d.png" % [_out_dir, index]
	var err := image.save_png(path)
	if err != OK:
		push_error("could not write %s: %d" % [path, err])
		return
	print("wrote %s (%dx%d) at t=%.2f" % [path, image.get_width(), image.get_height(), _elapsed])


## The level to play: the scene's own file, or --level's, at --time's hour.
## The line goes last, because the last `;! time` in a file is the one read.
func _level(game: Game) -> AsciiLevel:
	var path := _level_path if _level_path != "" else game.level_path
	var text := FileAccess.get_file_as_string(path)
	if _time != "":
		text += "\n;! time %s\n" % _time
	var data := AsciiLevel.new()
	data.parse(text)
	return data


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var key: String = args[i]
		var value: String = args[i + 1] if i + 1 < args.size() else ""
		match key:
			"--scene":
				_scene_path = value
				i += 2
			"--out":
				_out_dir = value
				i += 2
			"--shots":
				_shot_times.clear()
				for part: String in value.split(",", false):
					_shot_times.append(float(part))
				i += 2
			"--hold":
				for part: String in value.split(",", false):
					_hold.append(part)
				i += 2
			"--level":
				_level_path = value
				i += 2
			"--time":
				_time = value
				i += 2
			_:
				i += 1
