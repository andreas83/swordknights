extends SceneTree
## Plays a level under a fixed input program and writes the simulation's whole
## visible state once per physics frame, so two builds of the game can be
## compared frame for frame.
##
##     godot --headless --path . --fixed-fps 60 --script tools/trace_level.gd -- \
##       --program sun_terrace --out /tmp/trace.txt
##
## A refactor of `Game` that claims to change nothing is checked by running
## this before and after and diffing the two files: an empty diff is the
## claim, made on every frame rather than on the handful a test happens to
## assert. The entity registry and the foe contract were proved this way.
##
## ## Why --fixed-fps
##
## The simulation is stepped in `_physics_process` at 60 Hz, but how many steps
## a rendered frame takes depends on the wall clock, and so does everything a
## `_process` does -- a relic's burst, for one, frees its node on that clock.
## `--fixed-fps 60` makes every frame exactly one step, so two runs on two
## machines see the same thing on the same frame.
##
## ## The programs
##
## A program is a list of steps, each `[frames, bits]` held for that many
## frames, or a direction to the run itself: `["warp", x, y]` puts the
## prince's feet there (world units, at rest), `["kill"]` kills him,
## `["face", 1 or -1]` turns him, and `["press", action]` / `["release",
## action]` work the real input map, which is what the game's own screens
## read (JUMP to replay on the complete screen). Warps are part of the
## script, so both builds get the same ones; they let one trace reach every
## interaction the level has without the program having to be a speedrun.
##
## ## What a frame records
##
## The game's phase and counters, the hitstop and the wipe, the prince, every
## entity in tree order, and every sound cued on that frame. The sounds are
## caught by standing a recorder in for the audio director (GameAudio's
## `_director`), so a refactor that moves where a cue is wired -- a guard's
## raise is heard because something connects it to GameAudio.cue -- is
## checked as closely as one that moves a guard.
##
## Only what both sides of a refactor have is read: public fields, and the
## entities by position, state and health through `get()`, which answers null
## for a property a node does not have.

const GAME_SCENE := "res://scenes/game.tscn"

const R := PlayerInput.BIT_RIGHT
const L := PlayerInput.BIT_LEFT
const U := PlayerInput.BIT_UP
const D := PlayerInput.BIT_DOWN
const J := PlayerInput.BIT_JUMP
const A := PlayerInput.BIT_ATTACK

## Each program names its level, so a trace is reproducible from its name.
const PROGRAMS := {
	"sun_terrace": {"level": "res://levels/level_01.txt", "steps": "_sun_terrace"},
	"arena": {"level": "", "steps": "_arena"},
}

## A floor with two guards and room to fight them: every way the prince and a
## guard can meet -- the swing, the air slash, the plunge, the stomp, the
## parry, the backstep, the cut that lands -- in one run.
const ARENA := """; Arena








  @         p              p          D
##########################################
##########################################
"""


class ProgramInput extends PlayerInput:
	var bits := 0

	func poll() -> void:
		apply_bits(bits)


## Stands in for the audio director and writes down what it is asked to play.
## Silent, and it answers the two other questions GameAudio asks of one.
class CueRecorder extends Node:
	var settings := AudioSettings.new()
	var heard := PackedStringArray()

	func play(event: String, opts: Dictionary = {}) -> AudioStreamPlayer:
		heard.append("%s%s" % [event, opts if not opts.is_empty() else ""])
		return null

	func toggle_mute() -> void:
		pass


var _game: Game
var _input := ProgramInput.new()
var _cues := CueRecorder.new()
var _steps: Array = []
var _step := 0
var _left := 0
var _frame := 0
var _lines := PackedStringArray()
var _out := "user://trace.txt"
var _program := "sun_terrace"
var _done := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for i: int in args.size():
		if args[i] == "--out" and i + 1 < args.size():
			_out = args[i + 1]
		elif args[i] == "--program" and i + 1 < args.size():
			_program = args[i + 1]
	if not PROGRAMS.has(_program):
		push_error("trace_level: no program %s" % _program)
		quit(2)
		return
	var spec: Dictionary = PROGRAMS[_program]
	_steps = call(String(spec["steps"]))
	GameAudio._director = _cues

	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Game
	if String(spec["level"]) == "":
		var data := AsciiLevel.new()
		data.parse(ARENA)
		_game.level_source = data
	else:
		_game.level_path = String(spec["level"])
	root.add_child(_game)


func _physics_process(_delta: float) -> bool:
	if _done:
		return true
	# The scene is ready by the first step, not during _initialize: the root
	# only enters the tree once this script has handed it back.
	if _frame == 0:
		_game.player.input = _input
	else:
		_lines.append(_record())
	if not _advance():
		_finish()
		return true
	_frame += 1
	return false


## Applies this frame's step: sets the held bits, or runs a direction. False
## once the program has run out.
func _advance() -> bool:
	while _left <= 0:
		if _step >= _steps.size():
			return false
		var step: Array = _steps[_step]
		_step += 1
		if not step[0] is String:
			_left = int(step[0])
			_input.bits = int(step[1])
			continue
		match String(step[0]):
			"warp":
				_game.player.position = Vector2(float(step[1]), float(step[2]))
				_game.player.velocity = Vector2.ZERO
			"kill":
				_game.player.kill()
			"face":
				_game.player.facing = int(step[1])
			"press":
				Input.action_press(StringName(step[1]))
			"release":
				Input.action_release(StringName(step[1]))
	_left -= 1
	return true


func _finish() -> void:
	_done = true
	var file := FileAccess.open(_out, FileAccess.WRITE)
	if file == null:
		push_error("trace_level: cannot write %s" % _out)
		quit(1)
		return
	file.store_string("\n".join(_lines) + "\n")
	file.close()
	GameAudio._director = null
	_cues.free()
	var player := _game.player
	print("trace_level: %s, %d frames -> %s; prince at (%.1f, %.1f), phase %d, deaths %d, "
		% [_program, _lines.size(), _out, player.position.x, player.position.y,
			_game.phase, _game.deaths]
		+ "relics %d/%d" % [_game.relics, _game.relics_total])
	quit(0)


## One frame: the game, the prince, then every entity in tree order.
func _record() -> String:
	var player := _game.player
	var parts := PackedStringArray([
		"%d" % _frame,
		"ph=%d el=%.6f rel=%d/%d d=%d cp=%s sec=%d" % [_game.phase, _game.elapsed, _game.relics,
			_game.relics_total, _game.deaths, _v(_game.checkpoint), _game.secrets.count],
		"hs=%s busy=%s" % [Flow.is_hitstopped(), Flow.busy()],
		"P %s %s st=%d t=%.6f hp=%d inv=%.6f f=%d" % [_v(player.position), _v(player.velocity),
			player.state, player.state_time, player.health, player.invulnerable, player.facing],
	])
	var entities := _game.get_node_or_null(^"Entities")
	if entities != null:
		for node: Node in entities.get_children():
			parts.append(_entity(node))
	if not _cues.heard.is_empty():
		parts.append("cues " + ", ".join(_cues.heard))
		_cues.heard.clear()
	return " | ".join(parts)


func _entity(node: Node) -> String:
	var script := node.get_script() as Script
	var name: String = node.get_class() if script == null else String(script.get_global_name())
	var at: String = _v((node as Node2D).position) if node is Node2D else "-"
	var text := "%s %s" % [name, at]
	for field: String in ["state", "health", "facing", "velocity", "state_time", "claimed"]:
		var value: Variant = node.get(field)
		if value != null:
			text += " %s=%s" % [field, _v(value) if value is Vector2 else str(value)]
	if node.has_method(&"is_taken"):
		text += " taken=%s" % node.call(&"is_taken")
	if node is CanvasItem and not (node as CanvasItem).visible:
		text += " hidden"
	return text


static func _v(value: Variant) -> String:
	if value is Vector2:
		return "(%.5f,%.5f)" % [(value as Vector2).x, (value as Vector2).y]
	return str(value)


## --- programs ---------------------------------------------------------------

## The Sun Terrace end to end: the torch, the cistern and its ladder, the
## spike pit and the grab wall, the upper terrace's guard, a death in the
## basin and the respawn at the torch, the lower guard, the platform stair
## and the door. Warps carry it past the beats a program cannot see.
func _sun_terrace() -> Array:
	return [
		[20, 0],
		# Past the first torch and down into the cistern, then on through its
		# far wall, which is the false one: secret A and its relic.
		[215, R],
		# Up the ladder and off the top with a leap.
		["warp", 232.0, 320.0],
		[50, U],
		[1, U | R | J],
		[40, R],
		# A hop onto the one-way platform for its relic, and off the end.
		["warp", 344.0, 256.0],
		[14, R | J],
		[40, R],
		# The spike pit and the four-tile wall: a running jump into the grab.
		["warp", 420.0, 256.0],
		[32, R],
		[22, R | J],
		[20, R],
		[30, U],
		# The upper terrace: its torch, and its guard, cut down from behind.
		[40, R],
		[26, R],
		[1, A],
		[30, 0],
		[20, R],
		[1, A],
		[60, 0],
		# Its relic, the drop off the terrace's end, and a run on into the
		# basin: a death, and the respawn at the terrace's torch with the
		# guard still down.
		[150, R],
		[70, 0],
		# Over the basin this time, to the lower guard.
		["warp", 760.0, 240.0],
		[20, R],
		[20, R | J],
		[20, R],
		# Standing in front of him: his cut lands, then the answer to it.
		[60, 0],
		[12, 0],
		[1, A],
		[30, 0],
		[10, R],
		[1, A],
		[60, 0],
		# His relic gives back the heart he took. Then a jump, and the plunge
		# down onto the cracked floor beyond: secret C and its cellar.
		[16, R],
		[10, R | J],
		[19, R],
		[1, D | A],
		[60, 0],
		# The cellar's relic, then out the way the floor came in: straight up
		# into a grab on the lip of the hole.
		[40, R],
		[10, 0],
		["warp", 938.0, 304.0],
		["face", 1],
		[5, 0],
		[20, J],
		[10, 0],
		[20, U],
		[30, 0],
		# Secret B: a cut at the cracked doorway in the high block's face,
		# and in for its relic.
		["warp", 736.0, 240.0],
		["face", -1],
		[5, 0],
		[1, A],
		[30, 0],
		[80, L],
		[20, 0],
		# The platform stair, the last grab, the last torch and the door.
		["warp", 944.0, 240.0],
		[10, 0],
		[16, J],
		[30, 0],
		[12, R | J],
		[6, 0],
		[40, 0],
		[8, R],
		[22, R | J],
		[20, R],
		[30, U],
		[130, R],
		# Escaped: then JUMP to replay, which restarts the whole level, and a
		# few steps into the new attempt.
		[40, 0],
		["press", "jump"],
		[1, 0],
		["release", "jump"],
		[90, 0],
		[60, R],
	]


func _arena() -> Array:
	return [
		[20, 0],
		[40, R],
		# The first guard comes on and raises: a late parry turns the cut,
		# and the riposte comes out at once.
		[141, 0],
		[1, U | A],
		[15, 0],
		[2, A],
		[40, 0],
		[8, R],
		[1, A],
		[60, 0],
		# The second guard: out from under his cut with a backstep.
		["warp", 250.0, 144.0],
		["face", 1],
		[87, 0],
		[1, L | A],
		[60, 0],
		# Then down on his helm from above: a stomp, and off the bounce a
		# plunge into him.
		["warp", 262.0, 98.0],
		[40, 0],
		["warp", 244.0, 90.0],
		[4, 0],
		[1, D | A],
		[60, 0],
		# A slash in the air over the fallen, a death, and the respawn with
		# both guards still down; then out of the door.
		[1, J],
		[8, J],
		[1, J | A],
		[40, 0],
		["kill"],
		[60, 0],
		[420, R],
		[20, 0],
	]
