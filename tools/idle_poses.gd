extends SceneTree
## Renders the prince's idle ladder -- every fidget and every bit, at the
## moments that carry it -- as one contact sheet, at the scale it ships.
##
## A bit only plays after twelve quiet seconds, and which one plays is a roll,
## so the live game is no way to look at them. This pins one prince per cell to
## a bit and a time with IdleArt.pin(), which holds the idle's clock without
## touching the simulation, and captures them all in one frame. Nothing else
## about the prince is posed: he is standing in IDLE, as he would be.
##
##     xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 3072x720 \
##       --script tools/idle_poses.gd -- --out docs/idle-poses.png [--silhouette]
##
## `--silhouette` paints every figure flat black, for the two-tone check in
## docs/art-direction.md: a bit that does not read as a shape does not read.

## Two tall rows rather than three short ones: the high toss goes 22 px over
## the hand, and in a 60 px row it landed in the cell above.
const COLS := 12
const ROWS := 2
const CELL := Vector2(64.0, 90.0)
const FEET_Y := 74.0
const SETTLE_FRAMES := 20
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")

var _out := "user://idle-poses.png"
var _silhouette := false
var _frames := 0
var _labels: Array[Dictionary] = []
## [prince, feet, pose] for every cell, re-pinned each frame until capture.
var _pins: Array[Array] = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--out")
	if at >= 0 and at + 1 < args.size():
		_out = args[at + 1]
	_silhouette = args.has("--silhouette")

	var backdrop := Sheet.new()
	backdrop.labels = _labels
	root.add_child(backdrop)

	var poses := _poses()
	for i: int in poses.size():
		var cell := Vector2(i % COLS, floori(float(i) / COLS)) * CELL
		var feet := cell + Vector2(CELL.x * 0.5 - 4.0, FEET_Y)
		var pose: Dictionary = poses[i]
		var prince := PLAYER_SCENE.instantiate() as Player
		root.add_child(prince)
		prince.position = feet
		prince.facing = 1
		if _silhouette:
			prince.modulate = Color.BLACK
		_pins.append([prince, feet, pose])
		_labels.append({"text": String(pose["label"]), "at": cell + Vector2(CELL.x * 0.5, FEET_Y + 6.0)})


func _process(_delta: float) -> bool:
	_frames += 1
	_pin()
	if _frames < SETTLE_FRAMES:
		return false
	var image := root.get_texture().get_image()
	var err := image.save_png(_out)
	print("idle_poses: wrote %s (%dx%d)%s" % [
		_out, image.get_width(), image.get_height(),
		"" if err == OK else " FAILED: %s" % error_string(err)])
	quit(0 if err == OK else 1)
	return true


## The nodes become ready after _initialize, which switches physics back on
## and is when PlayerArt gives the prince his IdleArt. So the freeze and the
## pin are re-applied every frame, or the princes fall through a floor that is
## only painted on and the idle has nothing to pin.
func _pin() -> void:
	for pin: Array in _pins:
		var prince := pin[0] as Player
		prince.set_physics_process(false)
		prince.position = pin[1]
		prince.state = Player.State.IDLE
		prince.velocity = Vector2.ZERO
		var idle := (prince.get_node("PlayerArt") as PlayerArt).idle_art
		if idle == null:
			continue
		var pose: Dictionary = pin[2]
		idle.pin(pose.get("bit", IdleArt.Bit.NONE) as IdleArt.Bit, float(pose.get("t", 0.0)))


func _poses() -> Array[Dictionary]:
	var b := IdleArt.Bit
	return [
		{"label": "AT REST"},
		{"label": "GLANCE", "bit": b.GLANCE, "t": 0.6},
		{"label": "SASH", "bit": b.SASH, "t": 0.55},
		{"label": "TAP", "bit": b.TAP, "t": 0.53},
		{"label": "SIGH", "bit": b.TAP, "t": 3.0},
		{"label": "SITS", "bit": b.SIT, "t": 0.45},
		{"label": "SEATED", "bit": b.SIT, "t": 1.4},
		{"label": "YAWN", "bit": b.SIT, "t": 2.7},
		{"label": "NODS", "bit": b.SIT, "t": 4.2},
		{"label": "TOSS", "bit": b.JUGGLE, "t": 0.86},
		{"label": "HIGHER", "bit": b.JUGGLE, "t": 2.05},
		{"label": "FUMBLE", "bit": b.JUGGLE, "t": 2.75},
		{"label": "SNATCH", "bit": b.JUGGLE, "t": 3.3},
		{"label": "SHEEPISH", "bit": b.JUGGLE, "t": 4.1},
		{"label": "A FLY", "bit": b.SWAT, "t": 0.8},
		{"label": "SWAT", "bit": b.SWAT, "t": 1.47},
		{"label": "MISSES", "bit": b.SWAT, "t": 2.25},
		{"label": "ON HOOD", "bit": b.SWAT, "t": 3.1},
		{"label": "BONK", "bit": b.SWAT, "t": 3.55},
		{"label": "LEANS", "bit": b.DOZE, "t": 1.0},
		{"label": "DOZES", "bit": b.DOZE, "t": 3.0},
		{"label": "SAGS", "bit": b.DOZE, "t": 4.7},
		{"label": "STARTLE", "bit": b.DOZE, "t": 5.0},
		{"label": "WHO SAW", "bit": b.DOZE, "t": 5.45},
	]


## The backdrop: a lit wall, a gold floor line per cell, and the labels.
class Sheet extends Node2D:
	var labels: Array[Dictionary] = []

	func _ready() -> void:
		z_index = -10

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, Vector2(COLS, ROWS) * CELL), Palette.SHADOW)
		for row: int in ROWS:
			for col: int in COLS:
				var cell := Vector2(col, row) * CELL
				draw_rect(Rect2(cell + Vector2(4.0, FEET_Y), Vector2(CELL.x - 8.0, 1.5)),
					Palette.LIGHT)
				draw_rect(Rect2(cell + Vector2(4.0, FEET_Y + 1.5), Vector2(CELL.x - 8.0, 2.0)),
					Palette.SHADOW_DEEP)
		for label: Dictionary in labels:
			UiFont.draw_text(self, String(label["text"]), label["at"] as Vector2,
				UiFont.Cut.MICRO, Palette.PAPER, UiFont.Align.CENTER, 0.0)
