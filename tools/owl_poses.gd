extends SceneTree
## Renders every state of the owl as one contact sheet, with the prince in the
## first cell for scale, and under them the Well's two blades through their
## cycles: the things Chapter V asks a player to read in the dark.
##
## Posed, not played, like tools/enemy_poses.gd: OwlArt reads the owl's
## `state`, `state_time`, `facing` and `velocity`, and a blade draws from its
## clock `t`, so each figure is frozen on its beat and captured in one frame.
## The backdrop is the night's stone and sky as the night grade leaves them
## (TimeOfDay.NIGHT over the palette), because a figure that reads on a lit
## wall and vanishes in the dark has not passed the test the chapter sets.
##
##     xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1792x720 \
##       --script tools/owl_poses.gd -- --out docs/owl-poses.png [--silhouette]
##
## `--silhouette` paints every figure flat black, the two-tone check from
## docs/art-direction.md: the owl perched, spread and flying must each be
## told from the prince by outline alone.

const COLS := 7
const ROWS := 3
const TILE := 16.0
const CELL := Vector2(64.0, 60.0)
const FEET_Y := 44.0
const SETTLE_FRAMES := 20
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")

var _out := "user://owl-poses.png"
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
		var cell := Vector2(i % COLS, floori(float(i) / COLS))
		var origin := cell * CELL
		var feet := origin + Vector2(CELL.x * 0.5, FEET_Y)
		var pose: Dictionary = poses[i]
		var figure: Node2D
		if pose.has("prince"):
			figure = _prince(feet)
		elif pose.has("blade"):
			figure = _blade(pose, feet)
			if String(pose["blade"]) == "scythe":
				backdrop.doorways.append(feet)
		else:
			figure = _owl(feet)
		if _silhouette:
			figure.modulate = Color.BLACK
		_pins.append([figure, feet, pose])
		_labels.append({"text": String(pose["label"]), "at": origin + Vector2(CELL.x * 0.5, 53.0)})


func _process(_delta: float) -> bool:
	_frames += 1
	_pin()
	if _frames < SETTLE_FRAMES:
		return false
	var image := root.get_texture().get_image()
	var err := image.save_png(_out)
	print("owl_poses: wrote %s (%dx%d)%s" % [
		_out, image.get_width(), image.get_height(),
		"" if err == OK else " FAILED: %s" % error_string(err)])
	quit(0 if err == OK else 1)
	return true


## Holds every figure on its beat. A node's processing comes back on when it
## becomes ready, after _initialize, so the pose is put back every frame.
func _pin() -> void:
	for pin: Array in _pins:
		var figure := pin[0] as Node2D
		figure.set_physics_process(false)
		var pose: Dictionary = pin[2]
		var prince := figure as Player
		if prince != null:
			prince.position = pin[1]
			prince.state = Player.State.IDLE
			prince.velocity = Vector2.ZERO
		var owl := figure as Owl
		if owl != null:
			owl.state = pose.get("state", Owl.State.PERCH)
			owl.state_time = float(pose.get("t", 0.0))
			owl.facing = int(pose.get("facing", -1))
			owl.look = float(pose.get("look", 0.0))
			owl.velocity = pose.get("velocity", Vector2.ZERO)
			var flying: bool = owl.is_flying() or owl.state == Owl.State.DYING
			owl.position = (pin[1] as Vector2) + Vector2(0.0, -14.0 if flying else -6.0)
		var blade := figure as BeatBlade
		if blade != null:
			blade.t = int(pose["t"])
			blade.set(&"_armed", true)
			blade.queue_redraw()


func _owl(feet: Vector2) -> Node2D:
	var owl := Owl.new()
	owl.position = feet + Vector2(0.0, -6.0)
	root.add_child(owl)
	return owl


func _prince(feet: Vector2) -> Node2D:
	var player := PLAYER_SCENE.instantiate() as Player
	root.add_child(player)
	player.position = feet
	player.facing = 1
	return player


## A blade standing on `feet`: a scythe in a doorway two cells tall, or two
## slots in the floor. Its cells are its own, round the origin, and a holder
## puts them on the sheet: a mechanism draws on the tile grid.
func _blade(pose: Dictionary, feet: Vector2) -> Node2D:
	var holder := Node2D.new()
	holder.position = feet - Vector2(TILE * 0.5, 2.0 * TILE)
	var blade: BeatBlade
	var cells: Array[Vector2i] = []
	if String(pose["blade"]) == "scythe":
		blade = Scythe.new()
		cells = [Vector2i(0, 0), Vector2i(0, 1)]
		(blade as Scythe).mount = Scythe.Mount.LINTEL
	else:
		blade = SpikeSlot.new()
		holder.position.x -= TILE * 0.5
		cells = [Vector2i(0, 1), Vector2i(1, 1)]
	blade.cells = cells
	blade.position = Vector2(cells[0].x, cells[cells.size() - 1].y) * TILE \
		+ Vector2(TILE * 0.5, TILE)
	holder.add_child(blade)
	root.add_child(holder)
	return blade


func _poses() -> Array[Dictionary]:
	var s := Owl.State
	var spread := Owl.SPREAD_TIME
	return [
		{"label": "PRINCE", "prince": true},
		{"label": "PERCH", "state": s.PERCH, "look": 0.0},
		{"label": "WATCHING", "state": s.PERCH, "look": -1.0},
		{"label": "SPREAD 1", "state": s.SPREAD, "t": spread * 0.1},
		{"label": "SPREAD 2", "state": s.SPREAD, "t": spread * 0.45},
		{"label": "SPREAD 3", "state": s.SPREAD, "t": spread * 0.9},
		{"label": "STOOP", "state": s.STOOP, "velocity": Vector2(-150.0, 147.0)},
		{"label": "PULL-UP", "state": s.PULL_UP, "t": 0.0, "velocity": Vector2(60.0, -40.0)},
		{"label": "PULL-UP", "state": s.PULL_UP, "t": 0.05, "velocity": Vector2(60.0, -40.0)},
		{"label": "FOLD", "state": s.FOLD, "t": 0.04},
		{"label": "STRUCK", "state": s.DYING, "t": 0.15, "velocity": Vector2(40.0, 20.0)},
		{"label": "DOWN", "state": s.DYING, "t": 0.5, "velocity": Vector2(10.0, 80.0)},
		{"label": "SCYTHE", "blade": "scythe", "t": 50},
		{"label": "RATCHET 1", "blade": "scythe", "t": 74},
		{"label": "RATCHET 3", "blade": "scythe", "t": 95},
		{"label": "CUT", "blade": "scythe", "t": 4},
		{"label": "RETURN", "blade": "scythe", "t": 16},
		{"label": "SLOTS", "blade": "slot", "t": 50},
		{"label": "RATTLE", "blade": "slot", "t": 85},
		{"label": "UP", "blade": "slot", "t": 6},
	]


## The night's stone and sky, a floor line per cell, a lintel over each
## doorway, and the labels.
class Sheet extends Node2D:
	var labels: Array[Dictionary] = []
	var doorways: Array[Vector2] = []

	func _ready() -> void:
		z_index = -10

	func _draw() -> void:
		var night := TimeOfDay.NIGHT
		draw_rect(Rect2(Vector2.ZERO, Vector2(COLS, ROWS) * CELL), Palette.INK)
		for row: int in ROWS:
			for col: int in COLS:
				var cell := Vector2(col, row) * CELL
				# The lower half of each cell is stone under the night grade.
				draw_rect(Rect2(cell + Vector2(0.0, FEET_Y), Vector2(CELL.x, CELL.y - FEET_Y)),
					Palette.SHADOW * night)
				draw_rect(Rect2(cell + Vector2(0.0, FEET_Y), Vector2(CELL.x, 1.0)),
					Palette.SHADOW_WARM * night)
		# A lintel over each doorway, down to the top of its two cells.
		for feet: Vector2 in doorways:
			var top := feet.y - 2.0 * TILE
			var cell_top := floorf(feet.y / CELL.y) * CELL.y
			draw_rect(Rect2(feet.x - TILE * 0.5, cell_top, TILE, top - cell_top),
				Palette.SHADOW * night)
		for label: Dictionary in labels:
			UiFont.draw_text(self, String(label["text"]), label["at"] as Vector2,
				UiFont.Cut.MICRO, Palette.PAPER, UiFont.Align.CENTER, 0.0)
