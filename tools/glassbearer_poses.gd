extends SceneTree
## Renders the Glassbearer's states as one contact sheet, with the prince and
## the sentinel standing in the first cells for scale and for contrast: three
## figures that must be told apart by outline alone -- a cowl, a spike, and a
## circle on a stick (docs/campaign.md, "The Glassbearer").
##
##     xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x720 \
##       --script tools/glassbearer_poses.gd -- --out docs/glassbearer-poses.png [--silhouette]
##
## As tools/enemy_poses.gd does for the sentinel: the simulation is not
## stepped; GlassbearerArt reads `state`, `state_time`, `facing` and `glass`,
## and those are set directly and pinned every frame until the capture.
## `--silhouette` paints every figure flat black, which is the two-tone check
## docs/art-direction.md asks for.

const COLS := 5
const ROWS := 3
const CELL := Vector2(64.0, 60.0)
const FEET_Y := 44.0
const SETTLE_FRAMES := 20
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")

var _out := "user://glassbearer-poses.png"
var _silhouette := false
var _frames := 0
var _labels: Array[Dictionary] = []
## [figure, feet, pose] for every cell, re-applied each frame until capture.
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
		var feet := cell + Vector2(CELL.x * 0.5, FEET_Y)
		var pose: Dictionary = poses[i]
		var figure: Node2D
		if pose.has("prince"):
			figure = _prince(feet)
		elif pose.has("sentinel"):
			figure = _sentinel(feet)
		else:
			figure = _bearer(pose, feet)
		if _silhouette:
			figure.modulate = Color.BLACK
		_pins.append([figure, feet, pose])
		_labels.append({"text": String(pose["label"]), "at": cell + Vector2(CELL.x * 0.5, 49.0)})


func _process(_delta: float) -> bool:
	_frames += 1
	_pin()
	if _frames < SETTLE_FRAMES:
		return false
	var image := root.get_texture().get_image()
	var err := image.save_png(_out)
	print("glassbearer_poses: wrote %s (%dx%d)%s" % [
		_out, image.get_width(), image.get_height(),
		"" if err == OK else " FAILED: %s" % error_string(err)])
	quit(0 if err == OK else 1)
	return true


## Holds every figure on its mark in its state, every frame: a node's physics
## is switched back on when it becomes ready, after _initialize.
func _pin() -> void:
	for pin: Array in _pins:
		var figure := pin[0] as Node2D
		figure.set_physics_process(false)
		figure.position = pin[1]
		var prince := figure as Player
		if prince != null:
			prince.state = Player.State.IDLE
			prince.velocity = Vector2.ZERO
		var guard := figure as Patrol
		if guard != null:
			guard.state = Patrol.State.WALK
			guard.state_time = 0.1
			guard.velocity = Vector2.ZERO
		var bearer := figure as Glassbearer
		if bearer != null:
			var pose: Dictionary = pin[2]
			bearer.state = pose.get("state", Glassbearer.State.WALK)
			bearer.state_time = float(pose.get("t", 0.0))
			bearer.glass = bool(pose.get("lit", true))
			bearer.velocity = Vector2(float(pose.get("vx", 0.0)), 0.0)


func _bearer(pose: Dictionary, feet: Vector2) -> Node2D:
	var bearer := Glassbearer.new()
	bearer.position = feet
	bearer.facing = int(pose.get("facing", 1))
	root.add_child(bearer)
	return bearer


func _sentinel(feet: Vector2) -> Node2D:
	var guard := Patrol.new()
	guard.position = feet
	guard.facing = 1
	root.add_child(guard)
	return guard


func _prince(feet: Vector2) -> Node2D:
	var player := PLAYER_SCENE.instantiate() as Player
	root.add_child(player)
	player.position = feet
	player.facing = 1
	return player


func _poses() -> Array[Dictionary]:
	var s := Glassbearer.State
	var aim := Glassbearer.WINDUP_TIME
	return [
		{"label": "PRINCE", "prince": true},
		{"label": "SENTINEL", "sentinel": true},
		{"label": "IN SHADE", "state": s.WALK, "t": 0.2, "lit": false},
		{"label": "IN THE SUN", "state": s.WALK, "t": 0.2},
		{"label": "WALK", "state": s.WALK, "t": 0.5, "facing": -1, "vx": -20.0},
		{"label": "AIM 1/3", "state": s.AIM, "t": aim * 0.15},
		{"label": "AIM 2/3", "state": s.AIM, "t": aim * 0.5},
		{"label": "AIM 3/3", "state": s.AIM, "t": aim * 0.85},
		{"label": "SHOT", "state": s.SPENT, "t": 0.02},
		{"label": "SPENT", "state": s.SPENT, "t": 0.3},
		{"label": "GATHERING", "state": s.SPENT, "t": 0.8},
		{"label": "LOOK", "state": s.LOOK, "t": 0.3, "facing": -1},
		{"label": "SHATTER", "state": s.DYING, "t": 0.2},
		{"label": "FALLING", "state": s.DYING, "t": 0.6},
		{"label": "DOWN", "state": s.DYING, "t": 1.0},
	]


## The backdrop: a wall in the sun, a gold floor line per cell, and the labels.
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
