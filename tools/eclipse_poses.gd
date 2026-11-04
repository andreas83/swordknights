extends SceneTree
## Renders the Eclipse's poses, phase by phase, as one sheet: the figure
## frozen on each beat of the fight, with the prince in the first cell for
## scale. docs/eclipse-phases.png is this.
##
## The King is posed from his phase and state (scripts/entities/eclipse_art.gd),
## so each cell is a King set to one beat and never stepped, the way
## tools/enemy_poses.gd sheets the sentinel. Cells from the third phase are
## drawn on a near-black ground, because that is the dark they are fought in:
## the sheet is how the silhouette is judged where it has to read.
##
##     xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 2880x540 \
##       --script tools/eclipse_poses.gd -- --out docs/eclipse-phases.png [--silhouette]
##
## `--silhouette` paints every figure flat black, the two-tone check.

## Two rows of twelve: the King is drawn at EclipseArt.SCALE, and a 60-unit
## cell clipped his crown and his disc into the cells around him.
const COLS := 12
const ROWS := 2
const CELL := Vector2(80.0, 90.0)
const FEET_Y := 76.0
const SETTLE_FRAMES := 20
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")

var _out := "user://eclipse-phases.png"
var _silhouette := false
var _frames := 0
var _labels: Array[Dictionary] = []
var _darks: Array[Rect2] = []
## [figure, feet, pose] for every cell, re-applied each frame until capture.
var _pins: Array[Array] = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--out")
	if at >= 0 and at + 1 < args.size():
		_out = args[at + 1]
	_silhouette = args.has("--silhouette")

	var sheet := Sheet.new()
	sheet.labels = _labels
	sheet.darks = _darks
	root.add_child(sheet)

	var poses := _poses()
	for i: int in poses.size():
		var cell := Vector2(i % COLS, floori(float(i) / COLS)) * CELL
		var feet := cell + Vector2(CELL.x * 0.5, FEET_Y)
		var pose: Dictionary = poses[i]
		var figure: Node2D = _prince(feet) if pose.has("prince") else _king(pose, feet)
		if _silhouette:
			figure.modulate = Color.BLACK
		if int(pose.get("phase", 0)) == Eclipse.Phase.ECLIPSE:
			_darks.append(Rect2(cell, CELL))
		_pins.append([figure, feet, pose])
		_labels.append({"text": String(pose["label"]), "at": cell + Vector2(CELL.x * 0.5, FEET_Y + 5.0)})


func _process(_delta: float) -> bool:
	_frames += 1
	_pin()
	if _frames < SETTLE_FRAMES:
		return false
	var image := root.get_texture().get_image()
	var err := image.save_png(_out)
	print("eclipse_poses: wrote %s (%dx%d)%s" % [
		_out, image.get_width(), image.get_height(),
		"" if err == OK else " FAILED: %s" % error_string(err)])
	quit(0 if err == OK else 1)
	return true


## Holds every figure on its mark in its beat. Physics comes back on when a
## node is ready, after _initialize, so the pin is re-applied every frame.
func _pin() -> void:
	for pin: Array in _pins:
		var figure := pin[0] as Node2D
		figure.set_physics_process(false)
		figure.position = pin[1]
		var prince := figure as Player
		if prince != null:
			prince.state = Player.State.IDLE
			prince.velocity = Vector2.ZERO
		var king := figure as Eclipse
		if king != null:
			var pose: Dictionary = pin[2]
			king.phase = int(pose.get("phase", 0)) as Eclipse.Phase
			king.state = pose.get("state", Eclipse.State.WALK)
			king.state_time = float(pose.get("t", 0.0))
			king.wounds = int(pose.get("wounds", 0))
			king.crown_guard = bool(pose.get("guard", false))
			king.velocity = Vector2(float(pose.get("vx", 0.0)), 0.0)
			king.floor_y = (pin[1] as Vector2).y
			king.sun_x = (pin[1] as Vector2).x - 40.0


func _king(pose: Dictionary, feet: Vector2) -> Node2D:
	var king := Eclipse.new()
	king.position = feet
	king.facing = int(pose.get("facing", 1))
	root.add_child(king)
	# A King on a sheet holds no door.
	king.remove_from_group(ExitDoor.HELD_SHUT)
	return king


func _prince(feet: Vector2) -> Node2D:
	var player := PLAYER_SCENE.instantiate() as Player
	root.add_child(player)
	player.position = feet
	player.facing = 1
	return player


func _poses() -> Array[Dictionary]:
	var s := Eclipse.State
	var p := Eclipse.Phase
	return [
		{"label": "PRINCE", "prince": true},
		{"label": "AWAIT", "state": s.AWAIT, "phase": p.SHIELD},
		{"label": "1 WALK", "state": s.WALK, "t": 0.3, "phase": p.SHIELD, "vx": 30.0},
		{"label": "1 PAUSE", "state": s.PAUSE, "t": 0.4, "phase": p.SHIELD},
		{"label": "1 DRAW", "state": s.DRAW, "t": 0.3, "phase": p.SHIELD},
		{"label": "1 SHOVE", "state": s.SHOVE, "t": 0.12, "phase": p.SHIELD},
		{"label": "1 HIT", "state": s.STAGGER, "t": 0.05, "phase": p.SHIELD, "wounds": 1},
		{"label": "1 GUARD", "state": s.WALK, "t": 0.6, "phase": p.SHIELD, "wounds": 2,
			"guard": true, "vx": 30.0},
		{"label": "2 REST", "state": s.REST, "t": 0.3, "phase": p.BURNING},
		{"label": "2 TELL", "state": s.CHARGE, "t": 0.22, "phase": p.BURNING},
		{"label": "2 THROW", "state": s.CHARGE, "t": 0.44, "phase": p.BURNING, "wounds": 1},
		{"label": "2 HIT", "state": s.STAGGER, "t": 0.05, "phase": p.BURNING, "wounds": 2},
		{"label": "3 STALK", "state": s.STALK, "t": 0.2, "phase": p.ECLIPSE},
		{"label": "3 TELL", "state": s.CROUCH, "t": 0.36, "phase": p.ECLIPSE},
		{"label": "3 LEAP", "state": s.LEAP, "t": 0.2, "phase": p.ECLIPSE},
		{"label": "3 SKID", "state": s.SKID, "t": 0.15, "phase": p.ECLIPSE},
		{"label": "3 CUT", "state": s.STAGGER, "t": 0.05, "phase": p.ECLIPSE, "wounds": 1},
		{"label": "3 WON", "state": s.WON, "t": 0.6, "phase": p.ECLIPSE, "wounds": 2},
		{"label": "4 TELL", "state": s.GATHER, "t": 0.3, "phase": p.FINALE},
		{"label": "4 POINT", "state": s.GATHER, "t": 0.86, "phase": p.FINALE},
		{"label": "4 POUR", "state": s.POUR, "t": 0.2, "phase": p.FINALE},
		{"label": "4 SPENT", "state": s.SPENT, "t": 0.4, "phase": p.FINALE},
		{"label": "CRACK", "state": s.FALL, "t": 0.6, "phase": p.FINALE},
		{"label": "DOWN", "state": s.FALL, "t": 3.2, "phase": p.FINALE},
	]


## The ground: the Vault's night wall per cell, near-black for the dark, a lit
## floor line, and the labels.
class Sheet extends Node2D:
	var labels: Array[Dictionary] = []
	var darks: Array[Rect2] = []

	func _ready() -> void:
		z_index = -10

	func _draw() -> void:
		var night := Palette.SHADOW_PIT * TimeOfDay.NIGHT
		draw_rect(Rect2(Vector2.ZERO, Vector2(COLS, ROWS) * CELL), Color(night, 1.0))
		for dark: Rect2 in darks:
			var black := night * WorldGrade.DARK
			draw_rect(dark, Color(black, 1.0))
		for row: int in ROWS:
			for col: int in COLS:
				var cell := Vector2(col, row) * CELL
				draw_rect(Rect2(cell + Vector2(4.0, FEET_Y), Vector2(CELL.x - 8.0, 1.0)),
					Palette.LIGHT_WARM)
				draw_rect(Rect2(cell + Vector2(4.0, FEET_Y + 1.0), Vector2(CELL.x - 8.0, 2.0)),
					Palette.SHADOW_DEEP)
		for label: Dictionary in labels:
			UiFont.draw_text(self, String(label["text"]), label["at"] as Vector2,
				UiFont.Cut.MICRO, Palette.PAPER, UiFont.Align.CENTER, 0.0)
