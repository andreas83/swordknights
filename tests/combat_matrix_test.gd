extends SceneTree
## The combat matrix: all twelve cells, in both directions.
##
##     godot --headless --script tests/combat_matrix_test.gd
##
## Two layers, because the matrix has two halves that can fail independently:
##
##   1. THE TABLE. DuelCombat.outcome() against the spec's table, transcribed
##      here a second time by hand. If the two copies disagree, one of them was
##      edited without being meant.
##   2. THE SIMULATION. Two fighters on a flat stage, the defender holding a
##      real posture out of real input bytes and the attacker thrusting at a
##      real stance, for every cell and with the sides swapped. This is what
##      proves the geometry agrees with the table — that a 13px duck really is
##      under the HIGH band and that a MID thrust really does find a ducking
##      fighter's head — rather than the table agreeing with itself.

const Support := preload("res://tests/fighter_support.gd")

const HIGH := DuelTuning.Stance.HIGH
const MID := DuelTuning.Stance.MID
const LOW := DuelTuning.Stance.LOW
const DUCKED := DuelTuning.DUCKED

## The spec's table, transcribed from docs/duel-spec.md:
##
##   attacker \ defender | HIGH  | MID   | LOW   | DUCKING
##   HIGH                | clash | kill  | kill  | miss
##   MID                 | kill  | clash | kill  | kill
##   LOW                 | kill  | kill  | clash | kill
const CELLS := [
	[HIGH, HIGH, "clash"], [HIGH, MID, "kill"], [HIGH, LOW, "kill"], [HIGH, DUCKED, "miss"],
	[MID, HIGH, "kill"], [MID, MID, "clash"], [MID, LOW, "kill"], [MID, DUCKED, "kill"],
	[LOW, HIGH, "kill"], [LOW, MID, "kill"], [LOW, LOW, "clash"], [LOW, DUCKED, "kill"],
]

## Body range is a little under 27px and blade range a little under 34px, so
## this gap is "the thrust can reach the body". Every posture is held standing
## still -- LOW included, which is down alone, and the duck, which is down with
## WALK. A LOW guard used to need a direction held, running into the blade,
## because down on the spot was the duck; that is the bug this column guards.
const BODY_GAP := 20.0

var _s := Support.new()
var _warm := 0


func _physics_process(_delta: float) -> bool:
	_warm += 1
	if _warm < 2:
		return false

	_the_table_is_the_spec()
	_every_cell_resolves_as_the_table_says(false)
	_every_cell_resolves_as_the_table_says(true)
	_the_clash_cell_needs_a_blade_that_is_actually_up()
	_a_blade_cannot_parry_what_it_is_turned_away_from()

	quit(_s.report("combat_matrix"))
	return true


## --- the table --------------------------------------------------------------

func _the_table_is_the_spec() -> void:
	for cell: Array in CELLS:
		var expected: String = cell[2]
		var actual := DuelCombat.outcome(cell[0], cell[1])
		_s.equal(
			_name_of(actual), expected,
			"matrix[%s][%s] is %s" % [_stance_name(cell[0]), _stance_name(cell[1]), expected]
		)
	_s.equal(DuelCombat.MATRIX.size(), 3, "the table has one row per stance")
	for row: Array in DuelCombat.MATRIX:
		_s.equal(row.size(), 4, "every row has HIGH, MID, LOW and DUCKING")


## --- the same twelve cells, fought out -------------------------------------

## `mirrored` swaps the seats: the attacker comes from the right instead of the
## left. Nothing in the resolution may depend on which fighter is slot A, and
## the only way to know is to run every cell both ways.
func _every_cell_resolves_as_the_table_says(mirrored: bool) -> void:
	for cell: Array in CELLS:
		_cell(cell[0], cell[1], cell[2], mirrored)


func _cell(att_stance: int, def_posture: int, expected: String, mirrored: bool) -> void:
	var stage := Support.build(root)
	stage.place(BODY_GAP)
	var attacker := stage.b if mirrored else stage.a
	var defender := stage.a if mirrored else stage.b
	var def_bits := Support.stance_bits(def_posture)
	var att_bits := Support.stance_bits(att_stance)

	# Hold the posture for three frames first. A stance that arrives on the
	# frame the blade does is a disarm read, not a parry, and that is a
	# different test (tests/fighter_frames_test.gd).
	_feed(stage, 3, att_bits, def_bits, mirrored)
	_feed(stage, 1, att_bits | Support.ATTACK, def_bits, mirrored)
	_feed(stage, 6, att_bits, def_bits, mirrored)

	var label := "%s into %s%s" % [
		_stance_name(att_stance), _stance_name(def_posture), " mirrored" if mirrored else ""
	]
	match expected:
		"kill":
			_s.check(not defender.is_alive(), "%s kills the defender" % label)
			_s.check(attacker.is_alive(), "%s leaves the attacker standing" % label)
			_s.check(stage.saw("kill"), "%s reports a kill" % label)
		"clash":
			_s.check(defender.is_alive(), "%s kills nobody" % label)
			_s.check(attacker.is_alive(), "%s kills nobody" % label)
			_s.check(stage.saw("clash"), "%s is a clash" % label)
		_:
			_s.check(defender.is_alive(), "%s touches nothing" % label)
			_s.check(not stage.saw("clash"), "%s is not even a clash" % label)
			_s.check(not stage.saw("kill"), "%s is a clean miss" % label)
	stage.dispose()


func _feed(stage: Support.Stage, frames: int, att: int, def: int, mirrored: bool) -> void:
	if mirrored:
		stage.run(frames, def, att)
	else:
		stage.run(frames, att, def)


## --- the two readings the table does not spell out -------------------------

## The table's diagonal says "clash / parry", which assumes there is a blade at
## that height to turn the thrust aside. A fighter in the recovery frames of
## their own thrust has the same stance and no blade up, and the spec is
## explicit that those frames are vulnerable — so the cut lands.
func _the_clash_cell_needs_a_blade_that_is_actually_up() -> void:
	var stage := Support.build(root)
	stage.place(20.0)
	# A thrusts HIGH over a ducking B: the table's one miss, and it leaves A
	# committed to ten frames of recovery at a known stance.
	var duck := Support.stance_bits(DUCKED)
	stage.run(1, Support.UP | Support.ATTACK, duck)
	stage.run(4, Support.UP, duck)
	_s.check(stage.a.is_alive() and stage.b.is_alive(), "the HIGH thrust passed over the duck")
	_s.check(
		stage.a.state == Fighter.State.THRUSTING and not stage.a.is_attacking(),
		"the attacker is now in the recovery of its own thrust"
	)
	# B stands up, then matches the recovering stance and thrusts into it. The
	# stance change lands well outside the disarm window, so this is the
	# matrix's diagonal — and the blade that should parry it is not up.
	stage.run(1, Support.UP, 0)
	stage.run(1, Support.UP, Support.UP | Support.ATTACK)
	stage.run(2, 0, Support.UP)
	_s.check(not stage.a.is_alive(), "a thrust into a recovering blade at the same height kills")
	stage.dispose()

	# And empty-handed there is nothing there at all. B throws its sword away
	# from the fight first, so the throw itself decides nothing.
	stage = Support.build(root)
	stage.place(20.0)
	stage.b.facing = 1
	stage.run(1, 0, Support.THROW)
	stage.b.facing = -1
	_s.check(not stage.b.is_armed(), "the defender threw its sword away")
	stage.run(1, Support.ATTACK, 0)
	stage.run(3, 0, 0)
	_s.check(not stage.b.is_alive(), "the same stance with no sword in it is not a parry")
	stage.dispose()


## Not in the spec's table, which is keyed on heights alone, and added
## deliberately: a blade can only turn aside a thrust it is facing. Without
## this a fighter running away with a matching stance would be immune to being
## stabbed in the back, which no duel should allow. scripts/player/player.gd
## drew the same line for the guard it used to have.
func _a_blade_cannot_parry_what_it_is_turned_away_from() -> void:
	var stage := Support.build(root)
	stage.place(20.0)
	stage.b.facing = 1 # turned away from the sword, same MID stance
	stage.run(1, Support.ATTACK, 0)
	stage.run(3, 0, 0)
	_s.check(not stage.b.is_alive(), "a blade turned away does not parry")
	stage.dispose()


## --- naming -----------------------------------------------------------------

func _name_of(outcome: int) -> String:
	match outcome:
		DuelCombat.Outcome.KILL:
			return "kill"
		DuelCombat.Outcome.CLASH:
			return "clash"
		DuelCombat.Outcome.DISARM_ATTACKER:
			return "disarm"
		_:
			return "miss"


func _stance_name(stance: int) -> String:
	match stance:
		HIGH:
			return "HIGH"
		MID:
			return "MID"
		LOW:
			return "LOW"
		_:
			return "DUCKING"
