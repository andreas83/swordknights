class_name SwordPoses
extends RefCounted
## The prince's poses with the sword in play: the swing, the air slash, the
## plunge and its landing, and the parry.
##
## They live apart from PlayerArt because they are the part of the vocabulary
## that grows -- four of these five arrived together -- and because they share
## one rule the rest of the poses do not: a blade drawn in a pose here is a
## promise about a hitbox in Player, so a curve here and a window there change
## together. Each returns only the fields it overrides; PlayerArt._pose()
## fills in the rest, exactly as it does for a pose written in PlayerArt.
##
## Pure functions of the state's clock and Tuning, like every pose, so a
## replay draws the same frames.


## Wind up back, lunge through, recover. The blade angle is the same curve as
## player.gd's attack_rect window, so what you see is what connects.
static func attack(t: float) -> Dictionary:
	var phase := clampf(t / Tuning.ATTACK_TIME, 0.0, 1.0)
	var drive := smoothstep(0.18, 0.5, phase)
	var settle := smoothstep(0.72, 1.0, phase)
	var out := drive - settle
	return {
		"squash": lerpf(0.98, 1.0, out),
		"sink": lerpf(0.8, 2.4, out),
		"lean": lerpf(-2.2, 4.4, out),
		"twist": lerpf(0.72, 1.0, out),
		"stride": lerpf(-1.4, 4.4, out),
		"stance": lerpf(1.2, 1.9, out),
		"knee": lerpf(0.4, -0.6, out),
		"hem_lift": lerpf(0.8, 2.4, out),
		"hem_fwd": lerpf(1.8, -2.6, out),
		"hem_spread": lerpf(0.4, 1.0, out),
		"hood_tilt": lerpf(-0.1, 0.3, out),
		"arm_a": lerpf(-2.5, 0.55, drive) - settle * 0.8, "arm_a_len": 6.6,
		"arm_b": 2.1 - out * 0.6,
		"cloak_sweep": lerpf(-1.6, 3.4, out), "cloak_rise": 1.2, "cloak_flare": 1.5,
		"blade": lerpf(-2.6, 0.75, drive) - settle * 0.9,
		"blade_len": 11.0,
		"blade_hot": 1.0 if phase > 0.22 and phase < 0.82 else 0.0,
	}


## A cleave from overhead down past the feet, legs tucked under it. It has to
## read as a different swing from ATTACK at 22 px: the ground swing is a lunge
## along the floor with the feet planted wide, so this one is the opposite on
## both counts -- knees drawn up off the ground and the blade travelling down
## rather than across, ending point-low in front. The blade curve is the same
## shape as Player.attack_rect()'s window, so what you see is what connects.
static func air_slash(t: float) -> Dictionary:
	var phase := clampf(t / Tuning.ATTACK_TIME, 0.0, 1.0)
	var drive := smoothstep(0.15, 0.5, phase)
	var settle := smoothstep(0.75, 1.0, phase)
	var out := drive - settle
	return {
		"squash": lerpf(1.06, 0.98, out),
		"lean": lerpf(-0.8, 3.2, out),
		"twist": lerpf(0.78, 1.0, out),
		"dangle": lerpf(-1.6, -2.8, out),
		"stride": lerpf(1.6, 3.0, out),
		"stance": 0.6,
		"knee": lerpf(4.4, 3.6, out),
		"hem_lift": 5.2,
		"hem_fwd": lerpf(-0.4, -2.6, out),
		"hood_tilt": lerpf(-0.3, 0.38, out),
		"arm_a": lerpf(-2.3, 1.2, drive) - settle * 0.7, "arm_a_len": 6.8,
		"arm_b": lerpf(-0.6, 2.2, out), "arm_b_len": 5.8,
		"cloak_sweep": lerpf(0.6, 3.0, out), "cloak_rise": lerpf(-1.4, 3.2, out),
		"cloak_flare": 1.4,
		"blade": lerpf(-2.5, 1.2, drive) - settle * 0.9,
		"blade_len": 12.0,
		"blade_hot": 1.0 if phase > 0.22 and phase < 0.82 else 0.0,
	}


## Both hands on the hilt at the hip, point straight down past the feet, knees
## drawn up out of its way and every piece of cloth streaming up. The only pose
## in the game that is a vertical line: at 22 px a plunge has to read as
## "coming down" before it reads as anything else.
static func plunge() -> Dictionary:
	return {
		"squash": 1.1,
		"lean": 0.8,
		"dangle": -2.0,
		"stride": 0.6,
		"stance": 0.5,
		"knee": 4.6,
		"hem_lift": 4.4,
		"hem_fwd": -0.6,
		"hood_tilt": 0.55,
		"arm_a": 1.15, "arm_a_len": 6.0,
		"arm_b": 1.3, "arm_b_len": 5.4,
		# The fall's own lag lifts the cloak a further 4 px at this speed, so
		# the pose asks for little rise and more sweep: past that the tail
		# climbs above its own middle and the polygon folds over itself.
		"cloak_sweep": 2.2, "cloak_rise": 1.2, "cloak_flare": 0.9,
		"blade": 1.48, "blade_len": 12.0,
		"blade_hot": 1.0,
	}


## Down on one knee over the blade, point bitten into the floor, then dragging
## it free and standing. The blade is drawn short while it is buried, because
## the part in the stone is not there to see. Long enough to read as stuck:
## this is the price of a plunge that met stone.
static func plunge_land(t: float) -> Dictionary:
	var phase := clampf(t / Tuning.PLUNGE_RECOVER, 0.0, 1.0)
	var free := smoothstep(0.6, 1.0, phase)
	return {
		"squash": lerpf(0.84, 0.98, free),
		"sink": lerpf(4.6, 0.6, free),
		"lean": lerpf(3.2, 1.2, free),
		"stride": 1.4,
		"stance": 1.8,
		"knee": -1.2,
		"hem_lift": -0.6,
		"hem_spread": 2.4,
		"hood_tilt": lerpf(0.6, 0.2, free),
		"arm_a": lerpf(1.25, 1.45, free), "arm_a_len": 5.6,
		"arm_b": 1.35, "arm_b_len": 5.0,
		"cloak_sweep": 0.6, "cloak_rise": lerpf(3.0, 0.4, free), "cloak_flare": 1.7,
		"blade": lerpf(1.42, 2.3, free), "blade_len": lerpf(7.0, 9.0, free),
	}


## The high guard: weight back on the rear foot, both hands up over the hood
## and the blade held across above it, edge up, where the sentinel's overhead
## cut comes down. The edge gleams only while the parry can turn a cut, so the
## player can see the window close.
static func parry(t: float) -> Dictionary:
	var up := smoothstep(0.0, 0.05, t)
	return {
		"squash": 0.97,
		"sink": 1.0,
		"lean": lerpf(0.4, -1.0, up),
		"twist": 0.86,
		"stride": -1.2,
		"stance": 1.7,
		"knee": 0.4,
		"hem_lift": 1.0,
		"hem_fwd": 1.4,
		"hem_spread": 0.8,
		"hood_tilt": -0.25,
		"arm_a": lerpf(0.6, -1.3, up), "arm_a_len": 6.6,
		"arm_b": lerpf(1.6, -1.75, up), "arm_b_len": 6.2,
		"cloak_sweep": 0.2, "cloak_rise": 0.6, "cloak_flare": 1.2,
		"blade": lerpf(0.4, -0.22, up), "blade_len": 10.0,
		"blade_hot": 1.0 if t < Tuning.PARRY_ACTIVE else 0.0,
	}
