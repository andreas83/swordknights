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
## --drive hands the prince to a script instead: its static `drive(game)`
## returns the PlayerInput that plays him, so a shot can be taken in the middle
## of a fight a held key could never reach. With --fixed-fps 60 every frame is
## one step of the simulation, so a shot's time is a frame of play.
##
##     ... --fixed-fps 60 --script tools/screenshot.gd -- \
##       --level res://levels/chapter_06_eclipse.txt --time night \
##       --drive res://tests/eclipse_support.gd --out /tmp/eclipse --shots 6.0,30.0
##
## For a scene that plays a level (Game), --level plays another file and
## --time sets the hour it is played at, as `;! time <stop>` would, without
## editing the file: how a level is judged at each stop of the grade.
##
##     ... --script tools/screenshot.gd -- --level res://levels/level_01.txt \
##       --time dusk --out /tmp/dusk --shots 1.0,3.0 --hold move_right
##
## --chapter plays The Last Light from entry N of the catalogue (0 is chapter
## I), as the chapter select would: its card, its sky and its tower, at its
## hour. An entry still being built is stood in for by its draft's static
## stand-in in docs/campaign/drafts/, set at the entry's hour, so every card
## and every sky can be looked at before its level exists. --ending shows the
## dawn after the last entry.
##
##     ... --script tools/screenshot.gd -- --chapter 3 --out /tmp/iv --shots 0.6,1.8

var _scene_path := "res://scenes/game.tscn"
var _out_dir := "user://shots"
var _shot_times: Array[float] = [1.0]
var _hold: Array[String] = []
var _level_path := ""
var _time := ""
var _chapter := -1
var _ending := false
var _drive := ""
var _driving := false

var _elapsed := 0.0
var _taken := 0


func _initialize() -> void:
	_parse_args()

	if _chapter >= 0 or _ending:
		_scene_path = "res://scenes/campaign_game.tscn"
		_stand_in_drafts()
		Campaign.selected = Campaign.count() - 1 if _ending else _chapter
	var packed := load(_scene_path) as PackedScene
	if packed == null:
		push_error("could not load %s" % _scene_path)
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute(_out_dir)

	var instance := packed.instantiate()
	if instance is Game and (_level_path != "" or _time != ""):
		(instance as Game).level_source = _level(instance as Game)
	if instance is CampaignGame:
		(instance as CampaignGame).progress_path = "user://screenshot_campaign.cfg"
	root.add_child(instance)
	root.set_meta("screenshot_target", instance)
	if _ending:
		(instance as CampaignGame).call_deferred("_advance")

	for action: String in _hold:
		Input.action_press(action)

	print("rendering %s -> %s at %s" % [_scene_path, _out_dir, str(_shot_times)])


func _process(delta: float) -> bool:
	_elapsed += delta
	_take_the_prince()

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


## --drive's player, once the scene is in the tree and its prince exists.
func _take_the_prince() -> void:
	if _drive == "" or _driving:
		return
	var game := root.get_meta("screenshot_target") as Game
	if game == null or game.player == null:
		return
	var script := load(_drive) as Script
	var input: Variant = script.call(&"drive", game) if script != null else null
	if input is PlayerInput:
		game.player.input = input
	else:
		push_error("screenshot: %s has no static drive(game) -> PlayerInput" % _drive)
	_driving = true


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


## The catalogue with every entry that has no level yet pointed at its
## draft's stand-in, at the entry's hour. The finale has no draft of its own;
## it stands in on chapter V's.
func _stand_in_drafts() -> void:
	var list: Array[Dictionary] = []
	var chapter := 1
	for index: int in Campaign.count():
		var entry := Campaign.entry(index)
		if String(entry["numeral"]) != "":
			chapter = index + 1
		if not Campaign.is_built(index):
			var draft := "res://docs/campaign/drafts/chapter_%02d_static.txt" % mini(chapter, 5)
			var text := FileAccess.get_file_as_string(draft)
			text += "\n;! time %s\n" % String(entry["time"])
			var path := "user://screenshot_entry_%d.txt" % index
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_string(text)
			file.close()
			entry["file"] = path
		list.append(entry)
	Campaign.use_for_test(list)


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
			"--chapter":
				_chapter = int(value)
				i += 2
			"--ending":
				_ending = true
				i += 1
			"--drive":
				_drive = value
				i += 2
			_:
				i += 1
