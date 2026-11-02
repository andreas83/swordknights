extends SceneTree
## Pins the feel relationships that the grammar test does not cover.
##
## The grammar test guards what the levels are built on. This one guards what
## the character is built on: the landing thresholds must stay above a flat
## jump, the ground must accelerate faster than the air, and the forgiveness
## windows must stay long enough to survive a touchscreen.
##
##     godot --headless --script tests/tuning_feel_test.gd

var _failures := 0


func _initialize() -> void:
	_check_landing_thresholds()
	_check_acceleration()
	_check_forgiveness()
	_check_timings()

	if _failures > 0:
		printerr("tuning_feel_test: %d failure(s)" % _failures)
		quit(1)
		return
	print("tuning_feel_test: ok")
	quit(0)


## The rule the retune is built on: a plain jump must cost no recovery, one
## extra tile of drop must cost a soft one, and two must thump.
func _check_landing_thresholds() -> void:
	var flat := Tuning.flat_jump_land_speed()
	_true(flat < Tuning.SOFT_LAND_SPEED,
		"a jump from flat ground (%.1f) lands below SOFT_LAND_SPEED (%.1f)"
			% [flat, Tuning.SOFT_LAND_SPEED])

	var one := Tuning.land_speed_after_drop(1.0)
	_true(one >= Tuning.SOFT_LAND_SPEED and one < Tuning.HARD_LAND_SPEED,
		"a 1-tile drop (%.1f) is a soft landing" % one)

	var two := Tuning.land_speed_after_drop(2.0)
	_true(two >= Tuning.HARD_LAND_SPEED, "a 2-tile drop (%.1f) is a hard landing" % two)

	_true(Tuning.HARD_LAND_SPEED < Tuning.MAX_FALL_SPEED,
		"terminal velocity still counts as a hard landing")
	_true(Tuning.SOFT_LAND_SPEED < Tuning.HARD_LAND_SPEED, "the two thresholds are ordered")

	# The art and the dust both scale off impact_weight, so it has to span 0..1
	# across the range of landings the game can actually produce.
	_true(Tuning.impact_weight(0.0) == 0.0, "impact_weight bottoms out at 0")
	_true(is_equal_approx(Tuning.impact_weight(Tuning.MAX_FALL_SPEED), 1.0),
		"impact_weight tops out at 1")
	_true(Tuning.impact_weight(Tuning.HARD_LAND_SPEED) > Tuning.impact_weight(flat),
		"a hard landing weighs more than a flat one")


## Ground beats air, and stopping beats starting — otherwise the character
## skates.
func _check_acceleration() -> void:
	_true(Tuning.GROUND_ACCEL > Tuning.AIR_ACCEL, "the ground has more grip than the air")
	_true(Tuning.GROUND_FRICTION > Tuning.GROUND_ACCEL, "stopping is faster than starting")
	_true(Tuning.AIR_FRICTION < Tuning.AIR_ACCEL, "air momentum is preserved")

	var to_top := Tuning.RUN_SPEED / Tuning.GROUND_ACCEL
	_true(to_top <= 0.12, "0 -> run speed in %.0f frames (<= 7)" % (to_top * 60.0))
	var to_stop := Tuning.RUN_SPEED / Tuning.GROUND_FRICTION
	_true(to_stop <= 0.1, "run speed -> 0 in %.0f frames (<= 6)" % (to_stop * 60.0))


## A touchscreen player taps late and early; these windows are what forgive it.
func _check_forgiveness() -> void:
	# The feel lab's long-gap station is three tiles wide; it has to stay
	# crossable, or the bench stops being a bench.
	_true(Tuning.gap_tiles() >= 3, "a running jump crosses %d tiles" % Tuning.gap_tiles())
	_true(Tuning.COYOTE_TIME >= 0.08, "coyote time survives a late tap")
	_true(Tuning.JUMP_BUFFER >= 0.12, "jump buffering survives an early tap")
	_true(Tuning.MAX_GRAB_FALL_SPEED >= Tuning.flat_jump_land_speed(),
		"a ledge is still grabbable at the speed a jump falls past it")


## Nothing takes control away for long enough to feel like a cutscene.
func _check_timings() -> void:
	var hard_recovery := Tuning.LAND_RECOVER_TIME * 1.6 # player.gd's hard-land factor
	_true(hard_recovery <= 0.2, "the hardest landing locks out %.0f frames (<= 12)"
		% (hard_recovery * 60.0))
	_true(Tuning.TURN_TIME <= 0.12, "turning around costs %.0f frames (<= 7)"
		% (Tuning.TURN_TIME * 60.0))
	_true(Tuning.CLIMB_UP_TIME <= 0.3, "the mantle takes %.0f frames (<= 18)"
		% (Tuning.CLIMB_UP_TIME * 60.0))
	_true(Tuning.ATTACK_TIME <= 0.26, "the sword swing takes %.0f frames (<= 16)"
		% (Tuning.ATTACK_TIME * 60.0))


func _true(condition: bool, what: String) -> void:
	if not condition:
		_fail(what)


func _fail(message: String) -> void:
	_failures += 1
	printerr("  FAIL  " + message)
