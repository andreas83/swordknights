extends SceneTree
## Renders a 3D figure's portrait -- from the front, lit as a character sheet
## -- so the model can be compared with its concept art side by side.
##
##     xvfb-run -a godot --path . --rendering-driver opengl3 \
##       --resolution 3840x2160 --script tools/model_portrait.gd -- \
##       --figure princess --out /tmp/princess.png [--yaw 1.15]
##
## The game never draws a model this way. In play a model is sheared onto the
## 2D rig so every joint lands on its rig point (ModelCostume._lift()); a
## portrait sets ModelCostume.view_yaw, which places the body as it really
## stands and turns the camera round to it. The figure stands in its idle pose
## with its feet at FEET, so a fixed crop lands on it every time. The 2D sword
## is still drawn where the side view puts it, and is not part of the portrait.

const FEET := Vector2(160.0, 150.0)
const SETTLE_FRAMES := 20

var _out := "user://portrait.png"
var _figure := "princess"
var _yaw := 1.15
var _player: Player
var _pose := {}
var _settle := SETTLE_FRAMES


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for i: int in args.size() - 1:
		match args[i]:
			"--out":
				_out = args[i + 1]
			"--figure":
				_figure = args[i + 1]
			"--yaw":
				_yaw = float(args[i + 1])
	var backdrop := ColorRect.new()
	backdrop.color = Palette.PAPER
	backdrop.size = Vector2(320.0, 180.0)
	root.add_child(backdrop)
	_player = (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	root.add_child(_player)
	_player.set_physics_process(false)
	_player.position = FEET
	var art := _player.get_node(^"PlayerArt") as PlayerArt
	CharacterLook.from_ids({"figure": _figure}).dress(art)
	var model := art.costume as ModelCostume
	if model == null:
		push_error("%s is not a 3D figure" % _figure)
		quit(1)
		return
	model.view_yaw = _yaw
	for entry: Dictionary in PoseCatalogue.prince_table():
		if String(entry["name"]) == "idle":
			_pose = entry


func _process(_delta: float) -> bool:
	if _pose.is_empty():
		return true
	PoseCatalogue.pin_player(_player, _pose, FEET, float(_pose["t"]))
	_settle -= 1
	if _settle > 0:
		return false
	var err := root.get_texture().get_image().save_png(_out)
	if err != OK:
		push_error("could not write %s: %d" % [_out, err])
	else:
		print("wrote %s" % _out)
	return true
