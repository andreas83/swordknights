class_name MovePoses
extends RefCounted
## The prince's poses for the duel's moves: the roll, the dive kick and its
## landing, the throw, the sweep, stooping for the blade, and the empty hand.
##
## SwordPoses' rule holds here too: a shape drawn in a pose is a promise about
## a rect in the simulation, so the roll is drawn inside Tuning.ROLL_HEIGHT
## while it is tucked, the heel leads the dive kick where PrinceMoves puts the
## kick's rect, and the sweep's leg is out along the floor exactly in its live
## window. Each returns only the fields it overrides; PlayerArt._pose() fills
## in the rest, so the heroine's costume draws every one of them over the same
## rig without a line of its own.
##
## Two of them borrow the duel's silhouettes (scripts/duel/fighter_art.gd) --
## the roll pitched forward rather than folded, the dive kick heel first --
## because a player who has fought the duel should read them at once. They are
## restated here rather than called: the duel's art reads a Fighter, and its
## files are not this mode's to share.


## The state's pose, for PlayerArt._posture().
static func for_state(state: Player.State, t: float) -> Dictionary:
	match state:
		Player.State.ROLL:
			return roll(t)
		Player.State.DIVE_KICK:
			return dive_kick()
		Player.State.KICK_LAND:
			return kick_land(t)
		Player.State.THROW:
			return throw(t)
		Player.State.SWEEP:
			return sweep(t)
		Player.State.PICKUP:
			return pickup(t)
		Player.State.CRAWL:
			return crawl(t)
	return {}


## On hands and knees, pitched forward over the front hand: the crouch's
## height (Tuning.CROUCH_HEIGHT) -- the body the world and every foe see in
## a crawl -- with the hood low and forward, the hands reaching one after the
## other and the knees drawn up under the hem in counter-time. The sword
## stays in the back hand, laid flat along the floor, out of a one-tile
## ceiling: there is no room to carry it any other way, and the pose should
## say that no swing is coming. Here, not in PlayerArt, so the heroine's
## costume crawls on the same rig without a line of her own.
static func crawl(t: float) -> Dictionary:
	var c := sin(t * 9.0)
	return {
		"sink": Tuning.BODY_HEIGHT - Tuning.CROUCH_HEIGHT + 1.0,
		"squash": 0.92,
		"lean": 3.4,
		"tilt": 0.32,
		"bob": -absf(c) * 0.4,
		"stride": c * 1.6,
		"knee": 1.6 + maxf(0.0, -c) * 1.2,
		"stance": 0.9,
		"hem_lift": 1.8,
		"hem_fwd": -1.0,
		"hem_spread": 1.0,
		"hood_tilt": 0.55,
		"hood_push": 1.0,
		"arm_a": 1.05 - c * 0.35, "arm_a_len": 5.4,
		"arm_b": 1.25 + c * 0.35, "arm_b_len": 5.0,
		"cloak_sweep": 2.0, "cloak_rise": -0.6, "cloak_flare": 0.9,
		"blade": 3.05, "blade_len": 8.0,
	}


## Pitched forward over the knees and folded, hood tucked to the chest, the
## cloak rolling over the back: inside the roll's 9 px while tucked, then the
## rise -- up off a crouch, the hood coming up last. Folding the body down
## without the pitch would sink the hips through the floor, because the hood
## keeps its size (FighterArt._roll() found that out first).
static func roll(t: float) -> Dictionary:
	var tuck := clampf(t / Tuning.ROLL_TUCK, 0.0, 1.0)
	var rise := smoothstep(0.0, 1.0, clampf((t - Tuning.ROLL_TUCK) / Tuning.ROLL_RECOVER,
		0.0, 1.0))
	var spin := sin(tuck * PI)
	var down := 1.0 - rise
	return {
		"sink": lerpf(1.0, 6.0, smoothstep(0.0, 0.2, tuck)) * down,
		"squash": lerpf(1.0, 0.78, down),
		"lean": lerpf(0.6, 1.0, down),
		"tilt": (0.8 + 0.2 * spin) * down,
		"stance": lerpf(1.0, 0.4, down),
		"knee": 3.6 * down,
		"hem_lift": 3.0 * down,
		"hem_spread": 1.2 * down,
		"hood_tilt": lerpf(0.1, 0.85, down),
		"arm_a": lerpf(1.4, 1.9, down), "arm_a_len": lerpf(6.2, 4.4, down),
		"arm_b": lerpf(1.5, 2.2, down), "arm_b_len": lerpf(5.8, 4.0, down),
		"cloak_sweep": lerpf(0.6, 1.2, down), "cloak_rise": 2.0 * down,
		"cloak_flare": lerpf(1.0, 0.8, down),
		"blade": lerpf(2.42, 3.0, down), "blade_len": lerpf(9.0, 7.0, down),
	}


## Heel first and leading, the other knee drawn up, the body laid back behind
## the line of the kick and every piece of cloth streaming up. The sword is
## held back out of the way: this is the one attack the blade takes no part
## in, and the pose has to say so at 22 px.
static func dive_kick() -> Dictionary:
	return {
		"squash": 1.04,
		"lean": -1.6,
		"tilt": 0.5,
		"stride": 4.4,
		"knee": -1.8,
		"stance": 0.3,
		"hem_lift": 5.4,
		"hem_fwd": -2.2,
		"hood_tilt": -0.25,
		"arm_a": 2.6, "arm_a_len": 5.4,
		"arm_b": -0.7, "arm_b_len": 5.6,
		"cloak_sweep": 1.6, "cloak_rise": 1.0, "cloak_flare": 1.0,
		"blade": 3.5, "blade_len": 8.5,
	}


## The heel met stone: down in a wide crouch on both feet, hands to the
## floor, then up. Long enough to read as planted, which is the kick's price.
static func kick_land(t: float) -> Dictionary:
	var up := smoothstep(0.55, 1.0, clampf(t / Tuning.DIVE_KICK_RECOVER, 0.0, 1.0))
	return {
		"squash": lerpf(0.82, 0.98, up),
		"sink": lerpf(4.4, 0.4, up),
		"lean": lerpf(2.2, 0.6, up),
		"stride": lerpf(2.6, 0.8, up),
		"stance": 2.0,
		"knee": -1.4,
		"hem_lift": -0.6,
		"hem_spread": 2.6,
		"hood_tilt": lerpf(0.55, 0.1, up),
		"arm_a": lerpf(1.7, 1.45, up), "arm_a_len": 6.4,
		"arm_b": lerpf(1.9, 1.5, up), "arm_b_len": 6.0,
		"cloak_sweep": 0.8, "cloak_rise": lerpf(2.6, 0.4, up), "cloak_flare": 1.6,
		"blade": lerpf(2.6, 2.42, up), "blade_len": 9.0,
	}


## Drawn back over the shoulder, then flung forward and down from it, the
## weight going onto the front foot after the arm. The blade is in the hand
## until Tuning.THROW_RELEASE and gone after it -- PlayerArt hides it once the
## hand is empty -- so the release is the frame the blade leaves the drawing.
static func throw(t: float) -> Dictionary:
	var fling := smoothstep(0.0, Tuning.THROW_RELEASE, t)
	var follow := smoothstep(Tuning.THROW_RELEASE, Tuning.THROW_TIME, t)
	return {
		"squash": 0.99,
		"sink": 0.6 + follow * 0.8,
		"lean": lerpf(-1.8, 3.0, fling) - follow * 0.8,
		"twist": lerpf(0.7, 1.0, fling),
		"stride": lerpf(-0.6, 3.6, fling),
		"stance": 1.6,
		"knee": lerpf(0.6, -0.4, fling),
		"hem_lift": 1.6,
		"hem_fwd": lerpf(1.4, -2.0, fling),
		"hem_spread": 0.6,
		"hood_tilt": lerpf(-0.2, 0.25, fling),
		"arm_a": lerpf(-2.4, 0.15, fling) + follow * 0.6, "arm_a_len": 6.8,
		"arm_b": lerpf(0.6, 2.4, fling), "arm_b_len": 5.6,
		"cloak_sweep": lerpf(-1.0, 2.6, fling), "cloak_rise": 1.0, "cloak_flare": 1.3,
		"blade": lerpf(-2.6, -0.2, fling), "blade_len": 10.0,
	}


## The duel's sweep: half down, one leg scything out along the floor in
## front. Out for the live window (Tuning.SWEEP_FROM to SWEEP_TO), drawn
## back after it, so a leg that is seen out is a leg that reaches.
static func sweep(t: float) -> Dictionary:
	var out := smoothstep(0.0, Tuning.SWEEP_FROM, t) \
		* (1.0 - smoothstep(Tuning.SWEEP_TO, Tuning.SWEEP_TIME, t))
	return {
		"sink": lerpf(1.0, 3.2, out),
		"lean": lerpf(0.4, -0.8, out),
		"stride": lerpf(1.0, 9.0, out),
		"knee": lerpf(0.4, -3.0, out),
		"stance": 0.6,
		"hem_lift": lerpf(1.0, 3.2, out),
		"hem_spread": 2.2,
		"hood_tilt": 0.35,
		"arm_a": 2.1, "arm_a_len": 5.0,
		"arm_b": 2.5, "arm_b_len": 5.0,
		"cloak_sweep": lerpf(0.6, 1.8, out), "cloak_flare": 1.3,
	}


## Stooping for the blade: down on the front knee, the hand to the floor where
## the sword lay, and up with it. The blade is drawn from the first frame,
## because it is in the hand from the first frame (PrinceMoves.try_start()).
static func pickup(t: float) -> Dictionary:
	var k := clampf(t / Tuning.PICKUP_TIME, 0.0, 1.0)
	var low := sin(k * PI)
	return {
		"sink": 5.0 * low + 0.6,
		"squash": 1.0 - 0.08 * low,
		"lean": 1.6 * low + 0.4,
		"stride": 1.6,
		"stance": 1.6,
		"knee": -1.2 * low,
		"hem_lift": -0.6,
		"hem_spread": 1.8,
		"hood_tilt": 0.2 + 0.4 * low,
		"arm_a": lerpf(1.2, 0.9, low), "arm_a_len": 6.8,
		"arm_b": 1.7,
		"cloak_sweep": 0.6, "cloak_rise": 0.6 * low, "cloak_flare": 1.4,
		"blade": lerpf(2.42, 0.25, low), "blade_len": 9.0,
	}


## Any pose with an empty hand: no blade, and the sword hand opened a little
## forward of where it held the hilt, so a disarmed prince standing still
## reads as one -- reaching, not holding.
static func unarmed(pose: Dictionary) -> Dictionary:
	var out := pose.duplicate()
	out["blade"] = INF
	out["arm_a"] = float(out.get("arm_a", 1.35)) - 0.25
	out["arm_a_len"] = float(out.get("arm_a_len", 6.2)) + 0.3
	return out
