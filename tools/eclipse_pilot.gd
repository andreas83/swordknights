extends SceneTree
## Plays the Eclipse with the pilot in tests/eclipse_support.gd, which reads
## the fight and answers each phase with its lesson, and writes down what it
## pressed as a program in tools/trace_level.gd's format.
##
##     godot --headless --path . --fixed-fps 60 --script tools/eclipse_pilot.gd -- \
##       [--out /tmp/eclipse_program.txt] [--steady] [--assist] [--every-bolt]
##       [--verbose [--every FRAMES] [--from SECONDS]]
##
## The program it writes with `--steady` is the clear run's (CLEAR_RUN in
## tests/eclipse_support.gd): after a deliberate change to the fight,
## re-record it with this and paste it there. `--steady` plunges once a pass
## where the expert line chains the rebound into a second.
## `--assist` plays under LONGER WARNINGS, `--every-bolt` parries every bolt
## of phase 2 instead of the first of each volley, and `--verbose` prints the
## King, the prince and every shot in the air twice a second, or every FRAMES
## frames from SECONDS on.
##
## It stops at the complete screen, at the first death, or after LIMIT
## seconds, and prints the beats and how long the fight took.

const EclipseSupport := preload("res://tests/eclipse_support.gd")
const GAME_SCENE := "res://scenes/game.tscn"
const LIMIT := 240.0

var _game: Game
var _pilot: EclipseSupport.Pilot
var _out := "user://eclipse_program.txt"
var _frames := 0
var _done := false
var _verbose := false
var _every := 30
var _from := 0.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--out")
	if at >= 0 and at + 1 < args.size():
		_out = args[at + 1]
	_verbose = args.has("--verbose")
	var every := args.find("--every")
	if every >= 0 and every + 1 < args.size():
		_every = maxi(1, int(args[every + 1]))
	var from := args.find("--from")
	if from >= 0 and from + 1 < args.size():
		_from = float(args[from + 1])
	if args.has("--assist"):
		Assist._longer_warnings = true
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Game
	_game.level_path = EclipseSupport.LEVEL
	root.add_child(_game)
	_pilot = EclipseSupport.Pilot.new(_game)
	_pilot.parry_every_bolt = args.has("--every-bolt")
	_pilot.chain_plunges = not args.has("--steady")


func _physics_process(_delta: float) -> bool:
	if _done:
		return true
	# The scene is ready by the first step, not during _initialize: the root
	# only enters the tree once this script has handed it back.
	if _frames == 0:
		_game.player.input = _pilot
	_frames += 1
	if _verbose and _frames % _every == 0 and float(_frames) / 60.0 >= _from:
		_status()
	if _game.phase == Game.Phase.COMPLETE:
		_finish("escaped")
	elif _game.deaths > 0:
		_finish("died")
	elif float(_frames) / 60.0 > LIMIT:
		_finish("timed out")
	return _done


func _finish(how: String) -> void:
	_done = true
	for beat: Dictionary in _pilot.beats:
		print("  poll %5d  %6.2f s  %s" % [beat["poll"], float(beat["poll"]) / 60.0, beat["what"]])
	var steps := _pilot.program()
	var lines := PackedStringArray()
	for step: Array in steps:
		lines.append("\t[%d, %d]," % [step[0], step[1]])
	var file := FileAccess.open(_out, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(lines) + "\n")
		file.close()
	print("eclipse_pilot: %s after %d frames (%.2f s of play, game clock %.2f s), %d polls, "
		% [how, _frames, float(_frames) / 60.0, _game.elapsed, _pilot.recorded.size()]
		+ "%d steps -> %s; deaths %d, relics %d/%d"
		% [steps.size(), _out, _game.deaths, _game.relics, _game.relics_total])
	quit(0 if how == "escaped" else 1)


func _status() -> void:
	var king := _pilot.king()
	var prince := _game.player
	var line := "%6.2f s  prince (%.1f, %.1f) %s hp %d" % [float(_frames) / 60.0,
		prince.position.x, prince.position.y, Player.State.keys()[prince.state], prince.health]
	if king != null:
		line += "  | king %s %s (%.1f, %.1f) f %d wounds %d pass %d" % [
			Eclipse.Phase.keys()[king.phase], Eclipse.State.keys()[king.state],
			king.position.x, king.position.y, king.facing, king.wounds, king.pass_wounds]
	for node: Node in _game.get_node(^"Entities").get_children():
		var shot := node as FoeProjectile
		if shot != null and not shot.is_spent():
			line += "  | shot %.1f,%.1f v%.0f%s" % [shot.global_position.x,
				shot.global_position.y, shot.velocity.x, " R" if shot.reflected else ""]
	print(line)
