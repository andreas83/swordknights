class_name FigurePreview
extends PlayerArt
## A mannequin for the wardrobe: the real figure, posed by a clock instead of a
## character.
##
## It is PlayerArt itself -- the same rig, the same costume layers, the same
## pose functions -- so what the editor shows is exactly what the game draws,
## not a picture of it. What it replaces is the body: PlayerArt reads the
## character it dresses through a handful of overridable methods (the seam
## FighterArt uses to dress a duel Fighter), and here they answer from a short
## loop of poses rather than from a Player. A real Player would have brought
## its physics, its footstep audio and its dust along, and a menu should not
## play footsteps.
##
## The loop shows what the costume layers have to answer for: standing, the
## run (what trails), a jump and a fall (what streams), a landing (what the
## spring does), the swing and a hang.

## (pose, seconds)
const LOOP: Array[Array] = [
	[&"idle", 1.6],
	[&"run", 1.6],
	[&"jump", 0.4],
	[&"fall", 0.5],
	[&"land", 0.35],
	[&"attack", 0.75],
	[&"hang", 1.4],
]

## Which way the mannequin faces. The wardrobe turns it toward the list, which
## also turns the lit side of the figure toward the viewer.
var facing := 1
var pose_name: StringName = &"idle"
var pose_time := 0.0

var _step := 0


func _bind() -> bool:
	return true


func _process(delta: float) -> void:
	_advance(delta)
	super._process(delta)


## Moves the loop on. Public through `show_pose()` for a test or a screenshot
## that wants one pose held.
func _advance(delta: float) -> void:
	pose_time += delta
	var length := float(LOOP[_step][1])
	if pose_time < length:
		return
	_step = (_step + 1) % LOOP.size()
	_enter(LOOP[_step][0] as StringName)


func show_pose(which: StringName) -> void:
	for i: int in LOOP.size():
		if LOOP[i][0] == which:
			_step = i
	_enter(which)


func _enter(which: StringName) -> void:
	pose_name = which
	pose_time = 0.0
	match which:
		&"jump":
			_on_jumped()
		&"land":
			_on_landed(Tuning.MAX_FALL_SPEED)


## --- the body ---------------------------------------------------------------

func _has_body() -> bool:
	return true


func _body_facing() -> int:
	return facing


func _body_motion() -> Vector2:
	match pose_name:
		&"run":
			return Vector2(1.0, 0.0)
		&"jump":
			return Vector2(0.5, -0.9)
		&"fall":
			return Vector2(0.5, 0.9)
	return Vector2.ZERO


func _speed_share() -> float:
	return 1.0 if pose_name == &"run" else 0.0


func _skip_frame() -> bool:
	return false


func _blade_in_front() -> bool:
	return pose_name == &"attack"


func _show_grip() -> bool:
	return pose_name == &"hang"


func _grounded() -> bool:
	return pose_name in [&"idle", &"run", &"land", &"attack"]


func _posture() -> Dictionary:
	match pose_name:
		&"run":
			return _run(pose_time)
		&"jump":
			return _jump()
		&"fall":
			return _fall()
		&"land":
			return _land()
		&"attack":
			return _pose(SwordPoses.attack(fmod(pose_time, Tuning.ATTACK_TIME * 2.5)))
		&"hang":
			return _hang()
	return _idle()
