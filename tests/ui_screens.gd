extends SceneTree
## Renders one frame per interface state, so the layout can be judged as pixels.
##
## tools/screenshot.gd walks a live scene, which cannot reach a pause overlay,
## a settings screen or a finished match on demand. This harness builds each
## screen, pokes it into the state we want to look at, and captures a frame.
##
##     xvfb-run -a godot --path . --rendering-driver opengl3 \
##       --script tests/ui_screens.gd -- --out /tmp/ui --window 1280x720
##
## `--window` matters more than it looks. The viewport is fixed-height with an
## aspect-derived width, so 1280x720 is a 320x180 canvas and 1680x720 is a
## 420x180 one. Any layout that assumes 320 falls apart in the second, which is
## exactly what a wide phone is.
##
## Deliberately not named *_test.gd: the runner collects that suffix and would
## try to run this as an assertion suite. tests/ui_layout_test.gd is the suite.

const SETTLE_FRAMES := 6
## Where the wardrobe shots keep their looks: never the real save, so a shot
## does not change what someone plays as, nor depend on it.
const WARDROBE_STORE := "user://ui_screens_wardrobe.cfg"
## Where the chapter select shots keep their progress, for the same reason.
const PROGRESS_STORE := "user://ui_screens_progress.cfg"

var _out_dir := "user://ui"
var _only := ""

var _shots: Array[Dictionary] = []
var _index := 0
var _settle := 0
var _stage: Node


func _initialize() -> void:
	_parse_args()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_shots = _catalogue()
	print("ui screens -> %s (%d shots), window %s, canvas %s" % [
		_out_dir, _shots.size(), DisplayServer.window_get_size(),
		root.get_visible_rect().size,
	])


func _process(_delta: float) -> bool:
	if _index >= _shots.size():
		return true

	if _stage == null:
		_build(_shots[_index])
		_settle = SETTLE_FRAMES
		return false

	_settle -= 1
	if _settle > 0:
		return false
	# One last poke, now that the scene has had frames to settle.
	_pose(_shots[_index])
	if _settle == 0:
		return false

	_capture(String(_shots[_index]["name"]))
	_stage.queue_free()
	_stage = null
	_index += 1
	return false


func _catalogue() -> Array[Dictionary]:
	var all: Array[Dictionary] = [
		{"name": "menu", "scene": "res://scenes/menu.tscn", "pose": ""},
		{"name": "menu_touch", "scene": "res://scenes/menu.tscn", "pose": "touch"},
		{"name": "menu_update", "scene": "res://scenes/menu.tscn", "pose": "update"},
		{"name": "settings", "scene": "res://scenes/menu.tscn", "pose": "settings"},
		{"name": "hud_title", "scene": "res://scenes/game.tscn", "pose": "title"},
		{"name": "hud_hurt", "scene": "res://scenes/game.tscn", "pose": "hurt"},
		{"name": "hud_pause", "scene": "res://scenes/game.tscn", "pose": "pause"},
		{"name": "match", "scene": "res://scenes/duel_match.tscn", "pose": ""},
		{"name": "match_flash", "scene": "res://scenes/duel_match.tscn", "pose": "flash"},
		{"name": "match_over", "scene": "res://scenes/duel_match.tscn", "pose": "over"},
		{"name": "menu_cpu", "scene": "res://scenes/menu.tscn", "pose": "cpu"},
		{"name": "match_cpu", "scene": "res://scenes/duel_match_cpu.tscn", "pose": "touch",
			"cpu": DuelBrain.Difficulty.HARD},
		{"name": "wardrobe", "scene": "res://scenes/wardrobe.tscn", "pose": "prince"},
		{"name": "wardrobe_heroine", "scene": "res://scenes/wardrobe.tscn",
			"pose": "heroine"},
		{"name": "wardrobe_two", "scene": "res://scenes/wardrobe.tscn", "pose": "two"},
		{"name": "wardrobe_touch", "scene": "res://scenes/wardrobe.tscn", "pose": "touch"},
		{"name": "chapters", "scene": "res://scenes/chapter_select.tscn", "pose": ""},
		{"name": "chapters_touch", "scene": "res://scenes/chapter_select.tscn",
			"pose": "touch", "cleared": true},
	]
	if _only == "":
		return all
	var picked: Array[Dictionary] = []
	for shot: Dictionary in all:
		if String(shot["name"]) == _only:
			picked.append(shot)
	return picked


func _build(shot: Dictionary) -> void:
	var packed := load(String(shot["scene"])) as PackedScene
	if packed == null:
		push_error("ui_screens: cannot load %s" % shot["scene"])
		_index = _shots.size()
		return
	if shot.has("cpu"):
		# What the menu's row would have chosen, read by the scene as it readies.
		ModeRegistry.choose("duel_cpu", int(shot["cpu"]))
	_stage = packed.instantiate()
	if shot.has("cpu") and "wardrobe_path" in _stage:
		_stage.set("wardrobe_path", WARDROBE_STORE)
	if _stage is WardrobeScreen:
		_stock_wardrobe(String(shot["pose"]))
		(_stage as WardrobeScreen).store_path = WARDROBE_STORE
	if _stage is ChapterSelect:
		_stock_progress(bool(shot.get("cleared", false)))
		(_stage as ChapterSelect).store_path = PROGRESS_STORE
	root.add_child(_stage)


## Each screen state, reached through the public API of the thing being shot.
func _pose(shot: Dictionary) -> void:
	var hud := _stage.get_node_or_null(^"HudLayer/Hud")
	match String(shot["pose"]):
		"touch":
			var surface := _stage.get_node_or_null(^"TouchControls/Surface")
			if surface != null:
				surface.visible = true
			# The duel's THROW button shows itself only on a phone.
			var throw := _stage.get_node_or_null(^"ThrowLayer/ThrowButton")
			if throw != null:
				throw.visible = true
		"cpu":
			# DUEL VS CPU chosen, at HARD, with the thumbs up beside it.
			var thumbs := _stage.get_node_or_null(^"TouchControls/Surface")
			if thumbs != null:
				thumbs.visible = true
			var menu := _stage as MenuScene
			if menu != null:
				for _row: int in menu.rows().size():
					if String(menu.rows()[menu.index()]["id"]) == "duel_cpu":
						break
					menu.move(1)
				menu.shift_choice(2)
		"update":
			# A dev build that has been superseded, with the thumbs up so the
			# plaque is seen next to the pause and mute buttons it must clear.
			var thumbs := _stage.get_node_or_null(^"TouchControls/Surface")
			if thumbs != null:
				thumbs.visible = true
			if _stage.has_method("offer_update"):
				_stage.offer_update({
					"code": 158, "name": "0.1.0-dev+4f2c9e1", "sha": "4f2c9e1",
					"date": "", "apk_url": "https://example.invalid/swordknights-dev.apk",
				})
		"heroine":
			var screen := _stage as WardrobeScreen
			if screen != null and screen.index() == 0:
				screen.move(1)
				screen.move(1)
		"two":
			var screen := _stage as WardrobeScreen
			if screen != null and screen.player() == Wardrobe.PLAYER_ONE:
				screen.adjust(1)
		"settings":
			var panel := _stage.get_node_or_null(^"SettingsPanel")
			if panel != null:
				panel.visible = true
				panel.queue_redraw()
		"title":
			if hud != null:
				hud.update_model(3, 3, 0, 3)
		"hurt":
			if hud != null:
				hud.update_model(1, 3, 2, 3)
				hud.set_overlay("", "")
				# Clear the level card so the corner is the only thing on
				# screen; the card gets its own shot.
				hud.show_title("")
		"pause":
			if hud != null:
				hud.update_model(2, 3, 1, 3)
				hud.set_overlay("PAUSED", "PAUSE TO RESUME  ·  SWORD TO QUIT")
		"flash":
			if hud != null:
				hud.flash("ONE HAS THE INITIATIVE", "ONE LEADS")
		"over":
			if hud != null and hud.fight != null:
				hud.fight.phase = DuelMatch.Phase.MATCH_OVER
				hud.fight.winner = 0
				hud.footer = "JUMP FOR A REMATCH  ·  SWORD FOR THE MENU"
				hud.queue_redraw()
		_:
			pass


## Writes the looks a wardrobe shot opens on: the heroine in a non-default dress
## for player one, and the heroine for player two in the sea-green seat.
func _stock_wardrobe(pose: String) -> void:
	var wardrobe := Wardrobe.open(WARDROBE_STORE)
	var one := CharacterLook.new()
	if pose != "prince":
		one.take_ids({"figure": "heroine", "accent": "gold", "hair": "raven", "skin": "amber"})
	wardrobe.set_look(Wardrobe.PLAYER_ONE, one)
	var two := CharacterLook.new()
	two.take_ids({"figure": "heroine", "accent": "pale", "hair": "henna", "skin": "copper"})
	wardrobe.set_look(Wardrobe.PLAYER_TWO, two)
	wardrobe.save()


## A first launch, or chapter I cleared with something left to find in it.
func _stock_progress(cleared: bool) -> void:
	var progress := CampaignProgress.new()
	progress.path = PROGRESS_STORE
	if cleared:
		progress.record_clear(0, 74.6, 5, 6, 2, 3)
	progress.save()


func _capture(name: String) -> void:
	var texture := root.get_texture()
	if texture == null:
		push_warning("no viewport texture yet")
		return
	var image := texture.get_image()
	var path := "%s/%s.png" % [_out_dir, name]
	if image.save_png(path) != OK:
		push_error("could not write %s" % path)
		return
	print("wrote %s (%dx%d)" % [path, image.get_width(), image.get_height()])


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var key: String = args[i]
		var value: String = args[i + 1] if i + 1 < args.size() else ""
		match key:
			"--out":
				_out_dir = value
				i += 2
			"--only":
				_only = value
				i += 2
			"--window":
				var parts := value.split("x", false)
				if parts.size() == 2:
					DisplayServer.window_set_size(
						Vector2i(int(parts[0]), int(parts[1]))
					)
				i += 2
			_:
				i += 1
