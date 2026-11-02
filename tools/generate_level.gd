extends SceneTree
## Generates a level from the command line, so a seed can be inspected, kept
## and committed as a file without opening the editor.
##
##     godot --headless --path . --script tools/generate_level.gd -- \
##       --seed 1234 --length 160 --difficulty 0.6
##
##     godot --headless --path . --script tools/generate_level.gd -- \
##       --seed 1234 --out levels/level_gen_1234.txt
##
## With no --out the ASCII goes to stdout, which makes the generator diffable
## from a shell: generate the same seed twice and the output is byte-identical.
##
## Exits non-zero when generation fails, so CI can treat an unsolvable seed as
## a build failure rather than silently shipping a broken level.

const DEFAULT_LENGTH := 160
const DEFAULT_DIFFICULTY := 0.5

var _seed := 0
var _length := DEFAULT_LENGTH
var _difficulty := DEFAULT_DIFFICULTY
var _out := ""
var _quiet := false
var _show_envelope := false
var _seed_given := false


func _initialize() -> void:
	if not _parse_args():
		quit(2)
		return

	if not _seed_given:
		# An unseeded run still has to report the seed it used, or the level it
		# just printed can never be reproduced.
		_seed = abs(int(Time.get_unix_time_from_system() * 1000.0)) % 0x7FFFFFFF

	if _show_envelope:
		_print_envelope()

	var result := LevelGenerator.build(_seed, _length, _difficulty)
	if not bool(result["ok"]):
		printerr(String(result["reason"]))
		quit(1)
		return

	var text := String(result["text"])
	if _out.is_empty():
		print(text)
		_log("generated seed %d — %d attempt(s), %s" % [
			_seed, int(result["attempts"]), _verdict(result)])
		quit(0)
		return

	var file := FileAccess.open(_out, FileAccess.WRITE)
	if file == null:
		printerr("could not write %s (%d)" % [_out, FileAccess.get_open_error()])
		quit(1)
		return
	file.store_string(text)
	file.close()
	print("wrote %s — seed %d, %d attempt(s), %s" % [
		_out, _seed, int(result["attempts"]), _verdict(result)])
	quit(0)


func _verdict(result: Dictionary) -> String:
	var report: Dictionary = result["report"]
	return "verified solvable (%d states explored)" % int(report.get("explored", 0))


func _print_envelope() -> void:
	var envelope := LevelReachability.envelope()
	var measured := LevelReachability.measure_reach()
	_log("reach envelope derived from scripts/core/tuning.gd:")
	_log("  hop %d / platform step %d / ledge grab %d tiles" % [
		int(envelope["hop_tiles"]), int(envelope["platform_step_tiles"]),
		int(envelope["grab_tiles"])])
	_log("  jump rise %.2f px over %.3f s, gap %d tiles (authored %d)" % [
		float(envelope["max_jump_rise_px"]), float(envelope["jump_airtime_s"]),
		int(envelope["max_gap_tiles"]), int(envelope["authored_gap_tiles"])])
	_log("  simulated: hop %d, grab %d, gap %d tiles" % [
		int(measured["hop"]), int(measured["grab"]), int(measured["gap"])])


## Progress goes to stderr so `--out`-less runs can be piped straight into a
## file without the commentary ending up in the level.
func _log(message: String) -> void:
	if not _quiet:
		printerr(message)


func _parse_args() -> bool:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var key: String = args[i]
		var value: String = args[i + 1] if i + 1 < args.size() else ""
		match key:
			"--seed":
				_seed = int(value)
				_seed_given = true
				i += 2
			"--length":
				_length = int(value)
				i += 2
			"--difficulty":
				_difficulty = clampf(float(value), 0.0, 1.0)
				i += 2
			"--out":
				_out = value
				i += 2
			"--envelope":
				_show_envelope = true
				i += 1
			"--quiet":
				_quiet = true
				i += 1
			"--help", "-h":
				print(_usage())
				return false
			_:
				printerr("unknown argument '%s'\n%s" % [key, _usage()])
				return false
	return true


func _usage() -> String:
	return """usage: godot --headless --path . --script tools/generate_level.gd -- [options]

  --seed <int>          seed to generate from (default: derived from the clock)
  --length <tiles>      target level width, minimum %d (default: %d)
  --difficulty <0..1>   how hard the beats are allowed to be (default: %.1f)
  --out <path>          write a .txt instead of printing to stdout
  --envelope            also report the reach envelope read out of Tuning
  --quiet               suppress the progress notes on stderr
  --help                this text""" % [
		LevelGenerator.MIN_LENGTH, DEFAULT_LENGTH, DEFAULT_DIFFICULTY]
