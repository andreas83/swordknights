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
## table -- a pose added here is a pose checked on both. Those two runs side by
## side are docs/heroine-poses.png.

const FEET := Vector2(160.0, 124.0)
## Long enough for the cloth lag and the squash spring to settle on the pose.
const SETTLE_FRAMES := 14
## Effects are fired this many frames before the shutter, so the dust is still
## in the air when the frame is taken.
const EFFECT_LEAD := 3

var _out_dir := "user://poses"
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
	_player.state = pose["state"]
	_player.state_time = pose["t"]
	_player.facing = pose.get("facing", 1)
	_player.invulnerable = pose.get("invulnerable", 0.0)
	_player.last_impact = pose.get("impact", 0.0)
	_player.velocity = pose.get("velocity", Vector2.ZERO)
	_player.health = pose.get("health", Tuning.MAX_HEALTH)
	_player.position = FEET + pose.get("offset", Vector2.ZERO)
	# An empty hand is the blade out of it: thrown, and lying out of frame.
	if pose.get("unarmed", false):
		if _player.moves.armed():
			_player.moves.blade.launch(Vector2(-200.0, -200.0), 1)
		_player.moves.blade.mode = PrinceBlade.Mode.LOOSE
	else:
		_player.moves.rearm()
	# A death from a fall is DEAD with the fall's flag up, which nothing
	# public sets but the landing itself. Read back: Object.set() on a name
	# the script does not have drops the value in silence (CLAUDE.md).
	_player.set("_fell", pose.get("fell", false))
	if _player.is_fallen() != (pose.get("fell", false) and _player.state == Player.State.DEAD):
		push_error("could not pose %s: the fall flag did not take" % String(pose["name"]))


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


func _pose_table() -> Array[Dictionary]:
	return [
		{"name": "idle", "state": Player.State.IDLE, "t": 0.45},
		{"name": "walk", "state": Player.State.WALK, "t": 0.26},
		{"name": "run-a", "state": Player.State.RUN, "t": 0.10,
			"velocity": Vector2(Tuning.RUN_SPEED, 0.0)},
		{"name": "run-b", "state": Player.State.RUN, "t": 0.295,
			"velocity": Vector2(Tuning.RUN_SPEED, 0.0)},
		{"name": "turn", "state": Player.State.TURN, "t": 0.045,
			"velocity": Vector2(-40.0, 0.0)},
		{"name": "crouch", "state": Player.State.CROUCH, "t": 0.35},
		{"name": "jump", "state": Player.State.JUMP, "t": 0.09,
			"velocity": Vector2(60.0, -210.0), "offset": Vector2(0.0, -12.0)},
		{"name": "fall", "state": Player.State.FALL, "t": 0.40,
			"velocity": Vector2(50.0, 220.0), "offset": Vector2(0.0, -12.0)},
		{"name": "land-hard", "state": Player.State.LAND, "t": 0.04, "impact": 340.0,
			"emit": [["landed", 340.0]]},
		{"name": "hang", "state": Player.State.HANG, "t": 0.55,
			"emit": [["grabbed_ledge"]]},
		{"name": "mantle", "state": Player.State.CLIMB_UP, "t": 0.17},
		{"name": "ladder", "state": Player.State.LADDER, "t": 0.22},
		{"name": "attack-wind", "state": Player.State.ATTACK, "t": 0.05},
		{"name": "attack-strike", "state": Player.State.ATTACK, "t": 0.15},
		{"name": "air-slash-wind", "state": Player.State.AIR_SLASH, "t": 0.05,
			"velocity": Vector2(60.0, -120.0), "offset": Vector2(0.0, -4.0)},
		{"name": "air-slash-cut", "state": Player.State.AIR_SLASH, "t": 0.15,
			"velocity": Vector2(60.0, 40.0), "offset": Vector2(0.0, -12.0)},
		{"name": "plunge", "state": Player.State.PLUNGE, "t": 0.12,
			"velocity": Vector2(0.0, Tuning.MAX_FALL_SPEED), "offset": Vector2(0.0, -8.0)},
		{"name": "plunge-land", "state": Player.State.PLUNGE_LAND, "t": 0.06,
			"impact": Tuning.MAX_FALL_SPEED, "emit": [["landed", Tuning.MAX_FALL_SPEED]]},
		{"name": "parry", "state": Player.State.PARRY, "t": 0.1},
		{"name": "backstep", "state": Player.State.BACKSTEP, "t": 0.08,
			"velocity": Vector2(-Tuning.backstep_speed(0.08), 0.0),
			"emit": [["backstepped"]]},
		{"name": "backstep-recover", "state": Player.State.BACKSTEP, "t": 0.3},
		{"name": "roll-tuck", "state": Player.State.ROLL, "t": 0.16,
			"velocity": Vector2(Tuning.ROLL_SPEED, 0.0)},
		{"name": "roll-rise", "state": Player.State.ROLL, "t": Tuning.ROLL_TUCK + 0.08},
		{"name": "dive-kick", "state": Player.State.DIVE_KICK, "t": 0.1,
			"velocity": Vector2(Tuning.DIVE_KICK_DRIFT, Tuning.DIVE_KICK_DROP),
			"offset": Vector2(0.0, -12.0)},
		{"name": "kick-land", "state": Player.State.KICK_LAND, "t": 0.06},
		{"name": "throw-draw", "state": Player.State.THROW, "t": 0.02},
		{"name": "throw-release", "state": Player.State.THROW, "t": 0.12, "unarmed": true},
		{"name": "unarmed", "state": Player.State.IDLE, "t": 0.45, "unarmed": true},
		{"name": "sweep", "state": Player.State.SWEEP, "t": 0.09, "unarmed": true},
		{"name": "pickup", "state": Player.State.PICKUP, "t": 0.075},
		{"name": "crawl-reach", "state": Player.State.CRAWL, "t": 0.17,
			"velocity": Vector2(Tuning.CRAWL_SPEED, 0.0)},
		{"name": "crawl-draw", "state": Player.State.CRAWL, "t": 0.52,
			"velocity": Vector2(Tuning.CRAWL_SPEED, 0.0)},
		{"name": "hurt", "state": Player.State.HURT, "t": 0.10,
			"velocity": Vector2(-80.0, -40.0), "health": 2,
			"emit": [["hurt", 2]]},
		{"name": "dead", "state": Player.State.DEAD, "t": 0.70, "health": 0},
		{"name": "dead-fall", "state": Player.State.DEAD, "t": 0.70, "health": 0,
			"fell": true, "impact": Tuning.MAX_FALL_SPEED,
			"emit": [["landed", Tuning.MAX_FALL_SPEED]]},
	]


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
