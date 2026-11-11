extends SceneTree
## Renders every duel fighter state as one contact sheet, at the scale it ships.
##
## A live match cannot reach a roll, a dive kick or a downed fighter on demand,
## and the figure is posed from state, so this freezes twenty-four fighters --
## one per state, the three stances standing, running and thrusting at LOW,
## the duck beside them, both ends of a thrust and of a snatch, the rise out
## of a roll, a LOW parry's spark, and the catch at its two heights -- and
## captures them in a single frame. The simulation is not stepped: FighterArt
## reads state, frame, stance and velocity, and those are set directly.
##
##     xvfb-run -a godot --path . --rendering-driver opengl3 \
##       --resolution 1536x720 \
##       --script tests/fighter_poses.gd -- --out docs/fighter-poses.png [--hitboxes]
##
## `--hitboxes` overlays the hurtbox and blade rect, to check that the figure
## and the sword sit where the simulation says they are. `--figure heroine`
## dresses every fighter as the heroine (CharacterLook), in the seat colours as
## always; that sheet is docs/heroine-fighter-poses.png.

## Six across and four down: the viewport is 180 units tall, which is exactly
## four rows, so the twenty-first pose had to go sideways rather than below,
## and the sheet is rendered 384 units wide (`--resolution 1536x720`, the 4x
## window scale) rather than the usual 320.
const COLS := 6
const ROWS := 4
const CELL := Vector2(64.0, 45.0)
## Feet sit this far down a cell, leaving room for the label under them.
const FEET_Y := 34.0
const SETTLE_FRAMES := 20
const FIGHTER_SCENE: PackedScene = preload("res://scenes/fighter.tscn")

var _out := UserData.at("user://fighter-poses.png")
var _look := CharacterLook.new()
var _frames := 0
var _labels: Array[Dictionary] = []
var _fighters: Array[Fighter] = []
## Fighters whose blades meet a thrust just before the capture: the spark.
var _sparking: Array[Fighter] = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--out")
	if at >= 0 and at + 1 < args.size():
		_out = args[at + 1]
	var figure := args.find("--figure")
	if figure >= 0 and figure + 1 < args.size():
		_look.take_ids({"figure": args[figure + 1]})

	var backdrop := Sheet.new()
	backdrop.labels = _labels
	root.add_child(backdrop)

	var poses := _poses()
	for i: int in poses.size():
		var cell := Vector2(i % COLS, floori(float(i) / COLS)) * CELL
		var feet := cell + Vector2(CELL.x * 0.5, FEET_Y)
		_place(poses[i], feet, i)
		if poses[i].get("spark", false):
			_sparking.append(_fighters[i])
		_labels.append({"text": String(poses[i]["label"]), "at": cell + Vector2(CELL.x * 0.5, 38.0)})


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == SETTLE_FRAMES - 4:
		for fighter: Fighter in _sparking:
			# Struck, then held where it was struck: the sheet's clock is the
			# renderer's, and a spark left to burn out at that clock is there in
			# one run and gone in the next.
			fighter.clashed.emit(fighter.position)
			var art := fighter.get_node(^"FighterArt") as FighterArt
			art.set_process(false)
			art.queue_redraw()
	if _frames < SETTLE_FRAMES:
		return false
	var image := root.get_texture().get_image()
	var err := image.save_png(_out)
	print("fighter_poses: wrote %s (%dx%d)%s" % [
		_out, image.get_width(), image.get_height(),
		"" if err == OK else " FAILED: %s" % error_string(err)])
	quit(0 if err == OK else 1)
	return true


func _place(pose: Dictionary, feet: Vector2, index: int) -> void:
	var fighter := FIGHTER_SCENE.instantiate() as Fighter
	root.add_child(fighter)
	_fighters.append(fighter)
	fighter.setup(index % 2, null)
	FighterArt.dress(fighter, index % 2, _look)
	fighter.respawn_at(feet, 1)
	fighter.grounded = true
	fighter.state = pose.get("state", Fighter.State.IDLE)
	fighter.state_frame = int(pose.get("frame", 1))
	fighter.stance = int(pose.get("stance", DuelTuning.Stance.MID))
	fighter.velocity = pose.get("velocity", Vector2.ZERO)
	fighter.grounded = bool(pose.get("grounded", true))
	if pose.get("ducked", false):
		fighter.set("_ducked", true)
	if pose.has("incoming"):
		# A sword in the air, a few pixels short of the open hands, flying at
		# them: what the snatch is for, drawn where the simulation would have it.
		fighter.blade.mode = DuelBlade.Mode.FLYING
		fighter.blade.position = feet + (pose["incoming"] as Vector2)
		fighter.blade.velocity = Vector2(-fighter.tuning.throw_speed, 0.0)
	if pose.get("drop_blade", false):
		fighter.blade.drop(
			fighter.tuning.hand_position(feet, 1, fighter.stance), fighter.stance, -1,
			fighter.tuning)
		fighter.blade.mode = DuelBlade.Mode.LOOSE
		fighter.blade.position = feet + Vector2(-14.0, -1.0)
		fighter.blade.velocity = Vector2.ZERO
	# Freeze it: the sheet is a picture of a state, not of a simulation.
	fighter.set_physics_process(false)


func _poses() -> Array[Dictionary]:
	var run := Vector2(120.0, 0.0)
	return [
		{"label": "HIGH", "stance": DuelTuning.Stance.HIGH},
		{"label": "MID", "stance": DuelTuning.Stance.MID},
		{"label": "LOW", "stance": DuelTuning.Stance.LOW},
		{"label": "DUCK", "state": Fighter.State.DUCKING, "ducked": true,
			"stance": DuelTuning.Stance.LOW},
		{"label": "LOW PARRY", "stance": DuelTuning.Stance.LOW, "spark": true},
		{"label": "RUN", "state": Fighter.State.RUNNING, "velocity": run, "frame": 6},
		{"label": "LOW RUN", "state": Fighter.State.RUNNING, "velocity": run, "frame": 6,
			"stance": DuelTuning.Stance.LOW},
		{"label": "JUMP", "state": Fighter.State.JUMPING,
			"velocity": Vector2(60.0, -300.0), "grounded": false},
		{"label": "FALL", "state": Fighter.State.JUMPING,
			"velocity": Vector2(60.0, 220.0), "grounded": false},
		{"label": "THRUST", "state": Fighter.State.THRUSTING, "frame": 2},
		{"label": "LOW THRUST", "state": Fighter.State.THRUSTING, "frame": 2,
			"stance": DuelTuning.Stance.LOW},
		{"label": "RECOVER", "state": Fighter.State.THRUSTING, "frame": 10},
		{"label": "ROLL", "state": Fighter.State.ROLLING, "frame": 8, "velocity": run},
		{"label": "RISING", "state": Fighter.State.RISING, "frame": 4, "velocity": run},
		{"label": "DIVE KICK", "state": Fighter.State.DIVEKICK,
			"velocity": Vector2(180.0, 420.0), "grounded": false},
		{"label": "DISARMED", "state": Fighter.State.DISARMED, "frame": 4,
			"drop_blade": true},
		{"label": "SWEEP", "state": Fighter.State.SWEEP, "frame": 5, "drop_blade": true},
		{"label": "POUND", "state": Fighter.State.POUND, "grounded": false,
			"drop_blade": true},
		{"label": "DOWNED", "state": Fighter.State.DOWNED, "frame": 20},
		{"label": "DEAD", "state": Fighter.State.DEAD, "frame": 40},
		{"label": "SNATCH", "state": Fighter.State.SNATCH, "frame": 3,
			"incoming": Vector2(24.0, -14.0)},
		{"label": "MISSED", "state": Fighter.State.SNATCH, "frame": 14,
			"drop_blade": true},
		{"label": "CAUGHT", "state": Fighter.State.CATCH, "frame": 2},
		{"label": "CATCH HI", "state": Fighter.State.CATCH, "frame": 4,
			"stance": DuelTuning.Stance.HIGH},
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
