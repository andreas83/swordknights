extends SceneTree
## Renders one frame per character pose so the art can be judged as pixels.
##
## The screenshot tool walks a live scene, which cannot reach HANG, CLIMB_UP,
## ATTACK or DEAD on demand. This harness instead freezes a player (physics off)
## into each pose in turn and captures a frame, so every state in the vocabulary
## gets a deterministic picture at the resolution it actually ships at.
##
##     xvfb-run -a godot --path . --rendering-driver opengl3 \
##       --script tests/character_poses.gd -- --out /tmp/poses
##
## The frames are 1280x720 (the 320x180 viewport at the 4x window scale), with
## the character's feet pinned to FEET so a fixed crop lands on it every time.
## tests/character_contact_sheet.py turns the frames into docs/character-states.png.
##
## `--figure heroine` dresses the player as the heroine (CharacterLook) instead
## of the prince, so both figures are rendered through every pose in this one
## table -- a pose added to it is a pose checked on both. Those two runs side by
## side are docs/heroine-poses.png. The table is PoseCatalogue.prince_table()
## (scripts/ui/pose_catalogue.gd), which the pose lab browses on the phone, and
## the pinning is PoseCatalogue.pin_player(), so the sheet and the lab cannot
## pose a moment two different ways.

const FEET := Vector2(160.0, 124.0)
## Long enough for the cloth lag and the squash spring to settle on the pose.
const SETTLE_FRAMES := 14
## Effects are fired this many frames before the shutter, so the dust is still
## in the air when the frame is taken.
const EFFECT_LEAD := 3

var _out_dir := UserData.at("user://poses")
var _figure := "prince"
var _poses: Array[Dictionary] = []
var _index := 0
var _settle := 0
var _player: Player
var _fx: Node


func _initialize() -> void:
	_parse_args()
	DirAccess.make_dir_recursive_absolute(_out_dir)

	var stage := Backdrop.new()
	stage.ground_y = FEET.y
	root.add_child(stage)

	var packed := load("res://scenes/player.tscn") as PackedScene
	if packed == null:
		push_error("could not load player.tscn")
		quit(1)
		return
	_player = packed.instantiate() as Player
	root.add_child(_player)
	_player.set_physics_process(false)
	_player.position = FEET
	_dress()

	_poses = _pose_table()
	_enter(_poses[0])
	print("posing %d states -> %s" % [_poses.size(), _out_dir])


func _process(_delta: float) -> bool:
	# The state machine keeps running in _physics_process, so the pose is
	# re-pinned every idle frame — after physics, before the frame is drawn.
	_pin(_poses[_index])

	if _settle > 0:
		_settle -= 1
		if _settle == EFFECT_LEAD:
			_fire(_poses[_index])
		return false

	_capture(_poses[_index])
	_index += 1
	if _index >= _poses.size():
		print("done: %d frames" % _poses.size())
		return true
	_enter(_poses[_index])
	return false


## --- posing ----------------------------------------------------------------

func _pin(pose: Dictionary) -> void:
	PoseCatalogue.pin_player(_player, pose, FEET, float(pose["t"]))


func _enter(pose: Dictionary) -> void:
	_pin(pose)
	_fx = _player.get_node_or_null("PlayerFx")
	if _fx != null and _fx.has_method("reset"):
		_fx.call("reset")
	_settle = SETTLE_FRAMES


## Fires the signals a pose wants, so the effects node shows what that moment
## actually looks like in play.
func _fire(pose: Dictionary) -> void:
	_fx = _player.get_node_or_null("PlayerFx")
	for spec: Array in pose.get("emit", [] as Array):
		_player.callv("emit_signal", spec)


func _capture(pose: Dictionary) -> void:
	var texture := root.get_texture()
	if texture == null:
		push_warning("no viewport texture yet")
		return
	var image := texture.get_image()
	var path := "%s/%02d_%s.png" % [_out_dir, _index, String(pose["name"])]
	var err := image.save_png(path)
	if err != OK:
		push_error("could not write %s: %d" % [path, err])
		return
	print("wrote %s" % path)


## The table is the pose lab's too (scripts/ui/pose_catalogue.gd), so a row
## added there is a frame here and a pose on the phone.
func _pose_table() -> Array[Dictionary]:
	return PoseCatalogue.prince_table()


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		if args[i] == "--out" and i + 1 < args.size():
			_out_dir = args[i + 1]
			i += 2
		elif args[i] == "--figure" and i + 1 < args.size():
			_figure = args[i + 1]
			i += 2
		else:
			i += 1


## The default look of the named figure. The saved wardrobe is never read here:
## a contact sheet must not depend on what someone last chose in the editor.
func _dress() -> void:
	var look := CharacterLook.new()
	look.take_ids({"figure": _figure})
	look.dress(_player.get_node(^"PlayerArt") as PlayerArt)


## A stand-in for terrain: flat bands in the game's palette plus a few niches,
## so the silhouette is judged against busy ground rather than a void.
class Backdrop:
	extends Node2D

	var ground_y: float = 124.0

	func _draw() -> void:
		draw_rect(Rect2(0.0, 0.0, 320.0, 180.0), Palette.SHADOW)
		draw_rect(Rect2(0.0, 0.0, 320.0, 64.0), Palette.SHADOW_DEEP)
		draw_rect(Rect2(0.0, 64.0, 320.0, ground_y - 64.0), Palette.MID)
		for i: int in 9:
			var x := 8.0 + i * 36.0
			draw_rect(Rect2(x, 72.0, 14.0, 30.0), Palette.SHADOW_DEEP)
		draw_rect(Rect2(0.0, ground_y, 320.0, 4.0), Palette.SURFACE_LIT)
		draw_rect(Rect2(0.0, ground_y + 4.0, 320.0, 56.0), Palette.SURFACE_SHADE_DEEP)
