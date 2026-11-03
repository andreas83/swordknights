extends SceneTree
## Renders every state of the Bastion as one contact sheet, with the prince
## and the sentinel in the first cells for scale and for contrast: the sheet
## is how a change to the figure is judged on pixels, the way
## tools/enemy_poses.gd does it for the sentinel.
##
##     xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x720 \
##       --script tools/bastion_poses.gd -- --out docs/bastion-poses.png [--silhouette]
##
## `--silhouette` paints every figure flat black: docs/art-direction.md asks
## that a frame read in two tones, and this is the check that the Bastion is
## told from the prince and the sentinel by its outline alone -- the flat brim
## and the board taller than the man.
##
## The simulation is not stepped. BastionArt reads `state`, `state_time` and
## `facing`, and those are pinned every frame.

const COLS := 5
const ROWS := 3
const CELL := Vector2(64.0, 60.0)
const FEET_Y := 44.0
const SETTLE_FRAMES := 20
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")

var _out := "user://bastion-poses.png"
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
			figure = _bastion(pose, feet)
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
	print("bastion_poses: wrote %s (%dx%d)%s" % [
		_out, image.get_width(), image.get_height(),
		"" if err == OK else " FAILED: %s" % error_string(err)])
	quit(0 if err == OK else 1)
	return true


## Holds every figure on its mark in its state, every frame: physics comes
## back on when a node becomes ready, after _initialize (tools/enemy_poses.gd).
func _pin() -> void:
	for pin: Array in _pins:
		var figure := pin[0] as Node2D
		figure.set_physics_process(false)
		figure.position = pin[1]
		var pose: Dictionary = pin[2]
		var prince := figure as Player
		if prince != null:
			prince.state = Player.State.IDLE
			prince.velocity = Vector2.ZERO
		var sentinel := figure as Patrol
		if sentinel != null:
			sentinel.state = Patrol.State.WALK
			sentinel.state_time = 0.1
			sentinel.velocity = Vector2.ZERO
		var bastion := figure as Bastion
		if bastion != null:
			bastion.state = pose.get("state", Bastion.State.STAND)
			bastion.state_time = float(pose.get("t", 0.0))
			bastion.velocity = Vector2.ZERO


func _bastion(pose: Dictionary, feet: Vector2) -> Node2D:
	var bastion := Bastion.new()
	bastion.position = feet
	bastion.facing = int(pose.get("facing", 1))
	root.add_child(bastion)
	return bastion


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
	var s := Bastion.State
	var windup := Bastion.WINDUP_TIME
	return [
		{"label": "PRINCE", "prince": true},
		{"label": "SENTINEL", "sentinel": true},
		{"label": "STAND", "state": s.STAND, "t": 0.2, "facing": -1},
		{"label": "STAND", "state": s.STAND, "t": 0.2},
		{"label": "BRACE", "state": s.BRACE, "t": 0.2, "facing": -1},
		{"label": "WINDUP 1/3", "state": s.WINDUP, "t": windup * 0.3, "facing": -1},
		{"label": "WINDUP 2/3", "state": s.WINDUP, "t": windup * 0.6, "facing": -1},
		{"label": "WINDUP 3/3", "state": s.WINDUP, "t": windup * 0.9, "facing": -1},
		{"label": "SHOVE", "state": s.SHOVE, "t": Bastion.SHOVE_TIME * 0.8, "facing": -1},
		{"label": "RECOVER", "state": s.RECOVER, "t": 0.15, "facing": -1},
		{"label": "TURN", "state": s.TURN, "t": Bastion.TURN_TIME * 0.25, "facing": -1},
		{"label": "BACK OPEN", "state": s.TURN, "t": Bastion.TURN_TIME * 0.45, "facing": -1},
		{"label": "STAGGER", "state": s.STAGGER, "t": 0.04, "facing": -1},
		{"label": "KNEEL", "state": s.DYING, "t": Bastion.DEATH_TIME * 0.4, "facing": -1},
		{"label": "DOWN", "state": s.DYING, "t": Bastion.DEATH_TIME * 0.8, "facing": -1},
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
