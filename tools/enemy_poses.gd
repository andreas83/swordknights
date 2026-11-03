extends SceneTree
## Renders every state of the palace sentinel as one contact sheet, with the
## prince standing in the first cell for scale and for contrast.
##
## A live level reaches a guard's raise or its death only by playing up to it,
## and the figure is posed from state, so this freezes one guard per beat and
## captures them in a single frame, the way tests/fighter_poses.gd does for the
## duel. The simulation is not stepped: PatrolArt reads `state`, `state_time`
## and `facing`, and those are set directly.
##
##     xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x720 \
##       --script tools/enemy_poses.gd -- --out docs/enemy-poses.png [--silhouette]
##
## `--silhouette` paints every figure flat black. docs/art-direction.md asks
## that a frame read in two tones; this is the check that the guard and the
## prince are told apart by their outline alone.

const COLS := 5
const ROWS := 3
const CELL := Vector2(64.0, 60.0)
const FEET_Y := 44.0
const SETTLE_FRAMES := 20
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")

var _out := "user://enemy-poses.png"
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
		var figure: Node2D = _prince(feet) if pose.has("prince") else _guard(pose, feet)
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
	print("enemy_poses: wrote %s (%dx%d)%s" % [
		_out, image.get_width(), image.get_height(),
		"" if err == OK else " FAILED: %s" % error_string(err)])
	quit(0 if err == OK else 1)
	return true


## Holds every figure on its mark in its state. A node's physics processing is
## switched back on when it becomes ready, which happens after _initialize, so
## a freeze applied once at creation does not hold: the guards walk off and
## the prince falls through the floor. Re-pinning every frame does.
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
			var pose: Dictionary = pin[2]
			guard.state = pose.get("state", Patrol.State.WALK)
			guard.state_time = float(pose.get("t", 0.0))
			guard.velocity = Vector2.ZERO


func _guard(pose: Dictionary, feet: Vector2) -> Node2D:
	var guard := Patrol.new()
	guard.position = feet
	guard.facing = int(pose.get("facing", 1))
	root.add_child(guard)
	return guard


func _prince(feet: Vector2) -> Node2D:
	var player := PLAYER_SCENE.instantiate() as Player
	root.add_child(player)
	player.position = feet
	player.facing = 1
	return player


func _poses() -> Array[Dictionary]:
	var s := Patrol.State
	return [
		{"label": "PRINCE", "prince": true},
		{"label": "WALK", "state": s.WALK, "t": 0.1},
		{"label": "WALK", "state": s.WALK, "t": 0.52, "facing": -1},
		{"label": "LOOK", "state": s.LOOK, "t": 0.1},
		{"label": "LOOK BACK", "state": s.LOOK, "t": 0.4},
		{"label": "RAISE 1/3", "state": s.WINDUP, "t": 0.15},
		{"label": "RAISE 2/3", "state": s.WINDUP, "t": 0.3},
		{"label": "RAISE 3/3", "state": s.WINDUP, "t": 0.4},
		{"label": "CUT", "state": s.STRIKE, "t": 0.06},
		{"label": "CUT END", "state": s.STRIKE, "t": 0.14},
		{"label": "OPENING", "state": s.RECOVER, "t": 0.2},
		{"label": "STAGGER", "state": s.STAGGER, "t": 0.1},
		{"label": "KNEEL", "state": s.DYING, "t": 0.5},
		{"label": "TOPPLE", "state": s.DYING, "t": 0.8},
		{"label": "DOWN", "state": s.DYING, "t": 1.05},
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
