extends SceneTree
## Renders the three moments the feel work is about, one frame at a time, so
## they can be looked at as a filmstrip rather than described.
##
## `tools/screenshot.gd` takes shots at wall-clock times and holds one input,
## which is the right tool for "what does this level look like". It cannot
## stage a sword landing on a guard on a known frame, and a hitstop or a wipe
## is a *timing* thing: what matters is the frame before, the frames held, and
## the frame after. So this drives the real `Game` scene on a fixed clock and
## captures every frame of each beat.
##
## Not a test — it is named without the `_test.gd` suffix on purpose, so the
## runner does not collect it. `tests/character_poses.gd` is the same shape.
##
## Naming `Game` as a type here is only possible because gameplay code goes
## through `GameAudio` rather than calling the `AudioDirector` autoload by
## name. A bare `--script` main loop resolves a script's dependencies before
## the autoloads exist, so the typed reference used to take the whole harness
## down with a compile error — and a harness that fails to compile still
## *runs*, producing a hundred screenshots of a scene with no script on it.
## If a dependency of game.gd ever reaches for an autoload again, this is the
## first thing that will fall over; `scripts/audio/game_audio.gd` explains the
## shape of it.
##
##     xvfb-run -a godot --path . --rendering-driver opengl3 --fixed-fps 60 \
##       --script tests/feel_frames.gd -- --out /tmp/feel
##
## Then tests/feel_frames.py assembles docs/feel-frames.png from the result.

const GAME_SCENE := "res://scenes/game.tscn"
## The spawn drops the character in, and an attack is a grounded move, so the
## impact beat waits for the feet rather than counting frames at it.
const ARM_TIMEOUT := 240
## Where the guard is put, relative to the character: outside the two bodies'
## combined half-widths, inside ATTACK_REACH.
const GUARD_REACH := 18.0

var _out_dir := UserData.at("user://feel")
var _game: Game
var _guard: Patrol
var _frame := 0
var _written := 0
var _beat := 0
var _beat_frame := 0
## Frame the guard was put in reach on; -1 until the character is ready.
var _armed := -1


func _initialize() -> void:
	_parse_args()
	DirAccess.make_dir_recursive_absolute(_out_dir)

	var packed := load(GAME_SCENE) as PackedScene
	if packed == null:
		push_error("could not load %s" % GAME_SCENE)
		quit(1)
		return
	_game = packed.instantiate() as Game
	root.add_child(_game)
	print("feel_frames -> %s" % _out_dir)


func _process(_delta: float) -> bool:
	_frame += 1
	# One frame of grace: the first viewport texture is not there yet.
	if _frame < 2:
		return false

	match _beat:
		0:
			return _beat_reveal()
		1:
			return _beat_impact()
		2:
			return _beat_retry()
	print("feel_frames: wrote %d frame(s)" % _written)
	quit(0)
	return true


## --- the beats --------------------------------------------------------------

## The shadow lifting off a scene that has just loaded. Every frame of it: the
## wipe is short enough that a sampled one would miss the shape of the edge.
func _beat_reveal() -> bool:
	_capture("reveal")
	_beat_frame += 1
	if _beat_frame >= 22:
		_advance()
	return false


## A sword landing on a guard: the frame it connects on, the frames held, and
## the frames after the simulation lets go again.
func _beat_impact() -> bool:
	_beat_frame += 1
	if _armed < 0:
		if _beat_frame > 10 and _game.player.is_grounded():
			_stage_guard()
			_armed = _beat_frame
		elif _beat_frame > ARM_TIMEOUT:
			push_warning("impact beat: the character never settled")
			_advance()
		return false

	var since := _beat_frame - _armed
	if since == 1:
		Input.action_press("attack")
	elif since == 4:
		Input.action_release("attack")
	_capture("impact")
	if since >= 24:
		_advance()
	return false


## Death, the beat that makes it readable, and the respawn happening behind the
## wipe so the player never sees the teleport.
func _beat_retry() -> bool:
	if _beat_frame == 2:
		_game.player.kill()
	_capture("retry")
	_beat_frame += 1
	if _beat_frame >= 56:
		_advance()
	return false


## --- staging ----------------------------------------------------------------

## A guard put at sword range, rather than walking the character across the
## level to find one: this harness is about the frames around the hit, and a
## patrol put down any earlier would have walked off before the swing.
##
## GUARD_REACH is the gap that matters. It is inside the guard's engage gap
## (scripts/entities/patrol.gd), so the guard has begun its raise when the
## sword lands, and the strip shows the answer the raise is there to invite:
## cut first, and the raise is staggered out of its cut.
func _stage_guard() -> void:
	var entities := _game.get_node_or_null("Entities") as Node2D
	if entities == null:
		push_error("no Entities node")
		return
	_guard = Patrol.new()
	_guard.level = _game.level
	_guard.position = _game.player.position + Vector2(
		_game.player.facing * GUARD_REACH, 0.0
	)
	entities.add_child(_guard)


func _advance() -> void:
	_beat += 1
	_beat_frame = 0


func _capture(label: String) -> void:
	var texture := root.get_texture()
	if texture == null:
		return
	var image := texture.get_image()
	var path := "%s/%s-%03d.png" % [_out_dir, label, _beat_frame]
	if image.save_png(path) != OK:
		push_error("could not write %s" % path)
		return
	_written += 1


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		if args[i] == "--out" and i + 1 < args.size():
			_out_dir = args[i + 1]
			i += 2
		else:
			i += 1
