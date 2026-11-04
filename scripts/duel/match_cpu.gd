extends "res://scripts/duel/match_scene.gd"
## The duel against the computer: the player in the crimson seat, a DuelBrain
## in the sea-green one. Two players do not fit on one phone, so this is the
## only way to duel on one.
##
## Everything the match looks like and every rule in it is the parent scene's,
## and stays so: this file changes where seat two's byte comes from (_step),
## and says who is who. The computer gets nothing a second player would not --
## see scripts/duel/duel_cpu.gd for the order that keeps it so:
##
##     cpu.next_bits()    decided from frames already stepped
##     fight.step(...)    the player's buttons are read here, for the first time
##     cpu.watch(fight)   and the frame is seen, as the screen shows it
##
## HOW HARD comes from the duel page's VS CPU row, as it saved it
## (DuelChoice, read from `choice_path`), or from `--cpu=easy|medium|hard` in
## the user arguments, for a screenshot or a report.
##
## THE SEED is `--seed=N`, or the clock's. It is printed at the start of every
## match, because a match against the computer is the seed and the player's
## inputs, and nothing else: tests/unit/test_duel_cpu_bouts.gd replays one
## frame for frame from exactly those. A rematch takes the next seed.
##
## THE PLAYER uses the shared actions, which the keyboard's single-player keys,
## a gamepad and the touch controls all drive: the stick, JUMP, SWORD and the
## THROW button Duel Online has. Pause and quit are the one-keyboard duel's.
##
## THE LOOKS are the wardrobe's: player one's in the crimson seat, and the
## computer wears player two's, held to sea-green like any second seat.

const CPU_SEAT := 1

var level: DuelBrain.Difficulty = DuelBrain.Difficulty.EASY
var seed_value := 0
var cpu: DuelCpu


func _ready() -> void:
	level = _level_argument()
	seed_value = _seed_argument()
	super._ready()
	if fight.seats.size() < 2:
		return
	cpu = DuelCpu.new(CPU_SEAT, level, seed_value)
	cpu.watch(fight)
	hud.your_slot = 0
	hud.seat_tags.assign([
		PackedStringArray(["YOU"]),
		PackedStringArray(["CPU", DuelBrain.level_name(level)]),
	])
	_announce()


func seat_name(slot: int) -> String:
	return "YOU" if slot != CPU_SEAT else "CPU"


func _step() -> void:
	if cpu == null:
		return
	var theirs := cpu.next_bits()
	fight.step(PlayerInput.bits_from_actions(""), theirs)
	cpu.watch(fight)


func _rematch() -> void:
	super._rematch()
	seed_value += 1
	if cpu != null:
		cpu.reset(seed_value)
		cpu.watch(fight)
	_announce()


func _announce() -> void:
	print("duel vs cpu: %s, seed %d" % [DuelBrain.level_name(level), seed_value])


func _level_argument() -> DuelBrain.Difficulty:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--cpu="):
			var name := arg.trim_prefix("--cpu=").to_upper()
			var at := DuelBrain.LEVEL_NAMES.find(name)
			if at >= 0:
				return at as DuelBrain.Difficulty
	return DuelChoice.open(choice_path).level


func _seed_argument() -> int:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			return arg.trim_prefix("--seed=").to_int()
	return int(Time.get_ticks_usec() + Time.get_unix_time_from_system()) & 0x7fffffff
