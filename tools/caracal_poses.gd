extends SceneTree
## Renders every beat of the Caracal as one contact sheet, with the prince and
## the sentinel standing in the first cells for scale and for contrast, and a
## flock of doves pecking in the last.
##
## The cat is posed from state (scripts/entities/caracal_art.gd), so this
## freezes one cat per beat and captures them in a single frame, the way
## tools/enemy_poses.gd does for the sentinel. The simulation is not stepped.
##
##     xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x720 \
##       --script tools/caracal_poses.gd -- --out docs/caracal-poses.png [--silhouette]
##
## `--silhouette` paints every figure flat black: docs/art-direction.md asks
## that a frame read in two tones, and this is the check that the cat is told
## from both people by its outline alone -- the ear-tufts, the four legs.

const COLS := 5
const ROWS := 3
const CELL := Vector2(64.0, 60.0)
const FEET_Y := 44.0
const SETTLE_FRAMES := 20
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")

var _out := "user://caracal-poses.png"
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
		elif pose.has("guard"):
			figure = _guard(feet)
		elif pose.has("doves"):
			figure = _doves(feet)
		else:
			figure = _cat(pose, feet)
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
	print("caracal_poses: wrote %s (%dx%d)%s" % [
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
		var cat := figure as Caracal
		if cat != null:
			var pose: Dictionary = pin[2]
			cat.state = pose.get("state", Caracal.State.PROWL)
			cat.state_time = float(pose.get("t", 0.0))
			cat.velocity = pose.get("v", Vector2.ZERO)


func _cat(pose: Dictionary, feet: Vector2) -> Node2D:
	var cat := Caracal.new()
	cat.position = feet
	cat.facing = int(pose.get("facing", 1))
	root.add_child(cat)
	return cat


func _guard(feet: Vector2) -> Node2D:
	var guard := Patrol.new()
	guard.position = feet
	guard.facing = -1
	root.add_child(guard)
	return guard


func _doves(feet: Vector2) -> Node2D:
	var flock := DoveFlock.new()
	var site := EntitySite.new()
	site.at = feet
	site.post = "doves@sheet"
	site.params = {"count": "4"}
	flock.place(site)
	root.add_child(flock)
	return flock


func _prince(feet: Vector2) -> Node2D:
	var player := PLAYER_SCENE.instantiate() as Player
	root.add_child(player)
	player.position = feet
	player.facing = 1
	return player


func _poses() -> Array[Dictionary]:
	var s := Caracal.State
	return [
		{"label": "PRINCE", "prince": true},
		{"label": "SENTINEL", "guard": true},
		{"label": "PROWL", "state": s.PROWL, "t": 0.05},
		{"label": "PROWL", "state": s.PROWL, "t": 0.2, "facing": -1},
		{"label": "LOOK", "state": s.LOOK, "t": 0.3},
		{"label": "STALK", "state": s.STALK, "t": 0.3, "v": Vector2(40.0, 0.0)},
		{"label": "CROUCH", "state": s.CROUCH, "t": 0.08},
		{"label": "WIGGLE", "state": s.CROUCH, "t": 0.24},
		{"label": "GLINT", "state": s.CROUCH, "t": 0.42},
		{"label": "POUNCE", "state": s.POUNCE, "t": 0.2},
		{"label": "SKID", "state": s.SKID, "t": 0.06},
		{"label": "SHAKE", "state": s.SKID, "t": 0.42},
		{"label": "FALL", "state": s.FALL, "t": 0.2},
		{"label": "DOWN", "state": s.DYING, "t": 0.5},
		{"label": "DOVES", "doves": true},
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
