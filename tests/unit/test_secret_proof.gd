extends GutTest
## Never required, never a trap: LevelReachability.audit_secrets() on the
## shipping level, and on one broken level per clause, so each clause is seen
## to refuse the thing it exists to refuse.
##
## The broken levels are each one mistake away from sound. A proof that only
## ever says yes is worth nothing, and this one is what stands between the
## generator and a ruin with a hole in it.

## Sound: the exit is behind the spawn and the room is a dead end that walks
## back out.
const SOUND := """; Sound


     #####
     #####
     %:::#
 D @ %::*#
##########
##########
"""

## The exit is in the room: with the seal shut there is no way to finish.
const REQUIRED := """; Required


     ######
     ######
     %::::#
   @ %::D:#
###########
###########
"""

## The room's far side is open air: the main line walks straight into it.
const NOT_HIDDEN := """; Not Hidden


     ####
     ####
     %:::
 D @ %::*
############
############
"""

## The room's floor has a shaft six deep in it, past any ledge grab, with the
## prize at the bottom: open the seal and the room is a hole.
const TRAP := """; Trap


     ######
     ######
     %::::#
 D @ %::::#
#########:#
#########:#
#########:#
#########:#
#########:#
#########*#
###########
"""

## A room one course tall: nobody can stand in it, so its prize is a lie.
const UNREACHABLE := """; Unreachable



     ######
 D @ %:::*#
###########
###########
"""


## SOUND with a pit past the block, six deep: climb the block, walk off the
## far side, and that is the end of the attempt. Nothing to do with the room.
const OLD_PIT := """; Old Pit


     #####
     #####
     %:::#
 D @ %::*#
##########  #
##########  #
##########  #
##########  #
##########  #
##########  #
#############
"""


func _audit(text: String) -> Dictionary:
	var level := AsciiLevel.new()
	level.parse(text)
	assert_eq(level.secrets.size(), 1, "the fixture has its one secret")
	return LevelReachability.audit_secrets(level)


func test_the_sun_terrace_secrets_are_never_required_and_never_a_trap() -> void:
	var level := AsciiLevel.from_file("res://levels/level_01.txt")
	assert_eq(level.secrets.size(), 3, "the Sun Terrace has three secrets")
	var kinds: Array[String] = []
	for secret: Dictionary in level.secrets:
		kinds.append(String(secret["kind"]))
	assert_eq(kinds, ["false", "cracked", "cracked"] as Array[String],
		"one walked through, then two cut open")
	var report := LevelReachability.audit_secrets(level)
	assert_true(bool(report["ok"]), String(report["reason"]))


func test_a_sound_secret_passes() -> void:
	var report := _audit(SOUND)
	assert_true(bool(report["ok"]), String(report["reason"]))


func test_a_secret_that_is_the_way_is_refused() -> void:
	var report := _audit(REQUIRED)
	assert_false(bool(report["ok"]), "the exit is behind the seal")
	assert_string_contains(String(report["reason"]), "never be the way", false)


func test_a_room_open_to_the_level_is_refused() -> void:
	var report := _audit(NOT_HIDDEN)
	assert_false(bool(report["ok"]), "the room is open on its far side")
	assert_string_contains(String(report["reason"]), "not hidden", false)


func test_a_room_that_strands_the_player_is_refused() -> void:
	var report := _audit(TRAP)
	assert_false(bool(report["ok"]), "the shaft in the room is a dead end")
	assert_string_contains(String(report["reason"]), "the exit is gone", false)


func test_a_room_nobody_can_stand_in_is_refused() -> void:
	var report := _audit(UNREACHABLE)
	assert_false(bool(report["ok"]), "the room is one course tall")
	assert_string_contains(String(report["reason"]), "cannot be stood in", false)


func test_a_dead_end_the_level_already_had_is_not_blamed_on_a_secret() -> void:
	var level := AsciiLevel.new()
	level.parse(OLD_PIT)
	var survey := LevelReachability.survey(level)
	assert_true(bool(survey["ok"]), "the level is solvable")
	assert_gt((survey["stranded"] as Dictionary).size(), 0,
		"and the pit past the block is a dead end the survey sees")
	var report := LevelReachability.audit_secrets(level)
	assert_true(bool(report["ok"]),
		"a dead end that was there with the seal shut is not the secret's: %s"
			% String(report["reason"]))
