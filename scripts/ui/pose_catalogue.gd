class_name PoseCatalogue
extends RefCounted
## Every pose either figure can be drawn in, as data, and the one way to pin a
## body to one of them: what the pose lab browses and tests/character_poses.gd
## renders.
##
## A pose is a moment of a state, not a drawing. PlayerArt and FighterArt pose
## the figure from the body's state, its clock and its velocity, so a pose here
## is the handful of fields that put a body into that moment -- the state, how
## far into it, which way it is moving -- and the lab or the contact sheet
## draws it with the shipping art. Nothing here draws.
##
## ## Read from the enums, so nothing is missed
##
## Both lists are built from the state enums, not only from the curated rows:
## every `Player.State`, every `Fighter.State`, every `DuelTuning.Stance` and
## every `IdleArt.Bit` gets at least one entry, and a state or stance added
## later -- the duel's guard poses are being redrawn as this is written -- is
## in the lab the day it exists, as a default entry until someone writes it a
## better row. tests/unit/test_pose_lab.gd fails the lab if any is missing.
##
## The curated rows are the moments worth a name: both ends of a thrust, a
## jump going up and coming down, a snatch with the sword still coming.
##
## ## Why the fighter's rows are not the contact sheet's
##
## tests/fighter_poses.gd lays its twenty poses out on one 5x4 frame and is
## the documentation image; it keeps its own table so the picture stays one
## frame. The prince's sheet has no such limit, so its table is the one below
## (`prince_table()`), and a row added here is a row on both.

## The guard's moment: standing, blade at the stance's height. Every stance
## the duel has gets one, read from the enum.
const GUARD_PREFIX := "GUARD "

## Seconds a playing prince pose loops over when its state has no length of
## its own, and frames for a fighter's.
const PRINCE_SPAN := 1.2
const FIGHTER_SPAN := 60


## --- the prince ---------------------------------------------------------------

## The curated moments, as tests/character_poses.gd has always rendered them:
## `name` (the frame's file name), `state`, `t` (seconds into it) and what else
## the moment needs -- `velocity`, `offset` from the feet, `impact`, the
## signals to `emit` for the dust, `unarmed`, `fell`, `health`.
static func prince_table() -> Array[Dictionary]:
	return [
		{"name": "idle", "state": Player.State.IDLE, "t": 0.45},
		{"name": "walk", "state": Player.State.WALK, "t": 0.26},
		{"name": "run-a", "state": Player.State.RUN, "t": 0.10,
			"velocity": Vector2(Tuning.RUN_SPEED, 0.0)},
		{"name": "run-b", "state": Player.State.RUN, "t": 0.295,
			"velocity": Vector2(Tuning.RUN_SPEED, 0.0)},
		{"name": "turn", "state": Player.State.TURN, "t": 0.045,
			"velocity": Vector2(-40.0, 0.0)},
		{"name": "crouch", "state": Player.State.CROUCH, "t": 0.35},
		{"name": "jump", "state": Player.State.JUMP, "t": 0.09,
			"velocity": Vector2(60.0, -210.0), "offset": Vector2(0.0, -12.0)},
		{"name": "fall", "state": Player.State.FALL, "t": 0.40,
			"velocity": Vector2(50.0, 220.0), "offset": Vector2(0.0, -12.0)},
		{"name": "land-hard", "state": Player.State.LAND, "t": 0.04, "impact": 340.0,
			"emit": [["landed", 340.0]]},
		{"name": "hang", "state": Player.State.HANG, "t": 0.55,
			"emit": [["grabbed_ledge"]]},
		{"name": "mantle", "state": Player.State.CLIMB_UP, "t": 0.17},
		{"name": "ladder", "state": Player.State.LADDER, "t": 0.22},
		{"name": "attack-wind", "state": Player.State.ATTACK, "t": 0.05},
		{"name": "attack-strike", "state": Player.State.ATTACK, "t": 0.15},
		{"name": "air-slash-wind", "state": Player.State.AIR_SLASH, "t": 0.05,
			"velocity": Vector2(60.0, -120.0), "offset": Vector2(0.0, -4.0)},
		{"name": "air-slash-cut", "state": Player.State.AIR_SLASH, "t": 0.15,
			"velocity": Vector2(60.0, 40.0), "offset": Vector2(0.0, -12.0)},
		{"name": "plunge", "state": Player.State.PLUNGE, "t": 0.12,
			"velocity": Vector2(0.0, Tuning.MAX_FALL_SPEED), "offset": Vector2(0.0, -8.0)},
		{"name": "plunge-land", "state": Player.State.PLUNGE_LAND, "t": 0.06,
			"impact": Tuning.MAX_FALL_SPEED, "emit": [["landed", Tuning.MAX_FALL_SPEED]]},
		{"name": "parry", "state": Player.State.PARRY, "t": 0.1},
		{"name": "backstep", "state": Player.State.BACKSTEP, "t": 0.08,
			"velocity": Vector2(-Tuning.backstep_speed(0.08), 0.0),
			"emit": [["backstepped"]]},
		{"name": "backstep-recover", "state": Player.State.BACKSTEP, "t": 0.3},
		{"name": "roll-tuck", "state": Player.State.ROLL, "t": 0.16,
			"velocity": Vector2(Tuning.ROLL_SPEED, 0.0)},
		{"name": "roll-rise", "state": Player.State.ROLL, "t": Tuning.ROLL_TUCK + 0.08},
		{"name": "dive-kick", "state": Player.State.DIVE_KICK, "t": 0.1,
			"velocity": Vector2(Tuning.DIVE_KICK_DRIFT, Tuning.DIVE_KICK_DROP),
			"offset": Vector2(0.0, -12.0)},
		{"name": "kick-land", "state": Player.State.KICK_LAND, "t": 0.06},
		{"name": "throw-draw", "state": Player.State.THROW, "t": 0.02},
		{"name": "throw-release", "state": Player.State.THROW, "t": 0.12, "unarmed": true},
		{"name": "unarmed", "state": Player.State.IDLE, "t": 0.45, "unarmed": true},
		{"name": "sweep", "state": Player.State.SWEEP, "t": 0.09, "unarmed": true},
		{"name": "pickup", "state": Player.State.PICKUP, "t": 0.075},
		{"name": "crawl-reach", "state": Player.State.CRAWL, "t": 0.17,
			"velocity": Vector2(Tuning.CRAWL_SPEED, 0.0)},
		{"name": "crawl-draw", "state": Player.State.CRAWL, "t": 0.52,
			"velocity": Vector2(Tuning.CRAWL_SPEED, 0.0)},
		{"name": "hurt", "state": Player.State.HURT, "t": 0.10,
			"velocity": Vector2(-80.0, -40.0), "health": 2,
			"emit": [["hurt", 2]]},
		{"name": "dead", "state": Player.State.DEAD, "t": 0.70, "health": 0},
		{"name": "dead-fall", "state": Player.State.DEAD, "t": 0.70, "health": 0,
			"fell": true, "impact": Tuning.MAX_FALL_SPEED,
			"emit": [["landed", Tuning.MAX_FALL_SPEED]]},
	]


## Everything the lab shows of the prince: the curated table, a default moment
## for any Player.State it does not cover, and every idle bit (IdleArt.Bit) at a
## point where it reads. Each entry carries a `label` to show and a `span`, the
## seconds a playing pose loops over.
static func prince() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var covered := {}
	for pose: Dictionary in prince_table():
		var entry := pose.duplicate()
		entry["label"] = String(pose["name"]).replace("-", " ").to_upper()
		entry["span"] = prince_span(int(pose["state"]))
		out.append(entry)
		covered[int(pose["state"])] = true
	for state: int in Player.State.values():
		if covered.has(state):
			continue
		out.append({
			"name": String(Player.State.keys()[state]).to_lower(),
			"label": String(Player.State.keys()[state]).replace("_", " "),
			"state": state, "t": 0.2, "span": prince_span(state),
		})
	for bit: int in IdleArt.Bit.values():
		if bit == IdleArt.Bit.NONE:
			continue
		var length := float(IdleArt.LENGTH.get(bit, PRINCE_SPAN))
		out.append({
			"name": "idle-" + String(IdleArt.Bit.keys()[bit]).to_lower(),
			"label": "IDLE · " + String(IdleArt.Bit.keys()[bit]),
			"state": Player.State.IDLE, "t": 0.45, "bit": bit,
			"bit_t": length * 0.4, "span": length,
		})
	return out


## How long a playing prince pose loops: the state's own length where Tuning
## gives one, so a swing is seen whole and then again.
static func prince_span(state: int) -> float:
	match state:
		Player.State.ATTACK, Player.State.AIR_SLASH:
			return Tuning.ATTACK_TIME + 0.3
		Player.State.PARRY:
			return Tuning.PARRY_TIME + 0.2
		Player.State.BACKSTEP:
			return Tuning.BACKSTEP_TIME + 0.2
		Player.State.ROLL:
			return Tuning.ROLL_TIME + 0.2
		Player.State.THROW:
			return Tuning.THROW_TIME + 0.3
		Player.State.PICKUP:
			return Tuning.PICKUP_TIME + 0.3
		Player.State.SWEEP:
			return Tuning.SWEEP_TIME + 0.3
		Player.State.TURN:
			return Tuning.TURN_TIME + 0.3
		Player.State.DEAD:
			return 1.6
	return PRINCE_SPAN


## Puts `player` into `pose` with its feet at `feet`, `t` seconds into the
## state. The state machine is not stepped -- physics is off -- so this is the
## whole of what the art reads. False, with an error, if a field did not take.
static func pin_player(player: Player, pose: Dictionary, feet: Vector2, t: float) -> bool:
	player.state = pose["state"]
	player.state_time = t
	player.facing = pose.get("facing", 1)
	player.invulnerable = pose.get("invulnerable", 0.0)
	player.last_impact = pose.get("impact", 0.0)
	player.velocity = pose.get("velocity", Vector2.ZERO)
	player.health = pose.get("health", Tuning.MAX_HEALTH)
	player.position = feet + pose.get("offset", Vector2.ZERO)
	# An empty hand is the blade out of it: thrown, and lying out of frame.
	if pose.get("unarmed", false):
		if player.moves.armed():
			player.moves.blade.launch(Vector2(-200.0, -200.0), 1)
		player.moves.blade.mode = PrinceBlade.Mode.LOOSE
	else:
		player.moves.rearm()
	# A death from a fall is DEAD with the fall's flag up, which nothing
	# public sets but the landing itself. Read back: Object.set() on a name
	# the script does not have drops the value in silence (CLAUDE.md).
	var fell := bool(pose.get("fell", false))
	player.set("_fell", fell)
	if player.is_fallen() != (fell and player.state == Player.State.DEAD):
		push_error("could not pose %s: the fall flag did not take" % String(pose["name"]))
		return false
	return true


## --- the duel fighter -----------------------------------------------------------

## Everything the lab shows of the duel fighter: a guard at every stance, the
## duck, the moments worth a name, and a default moment for any Fighter.State
## none of those covers. Fields are the fighter's: `state`, `frame` (1 on the
## frame a state is entered), `stance`, `velocity` in the facing's terms,
## `grounded`, `ducked`, and what its sword is doing -- `drop_blade` (lying
## behind), `incoming` (flying at open hands, from the feet), `thrown` (just
## left the hand). `span` is the frames a playing pose loops over.
static func fighter() -> Array[Dictionary]:
	var tuning := DuelTuning.default()
	var run := Vector2(tuning.run_speed, 0.0)
	var walk := Vector2(tuning.walk_speed, 0.0)
	var out: Array[Dictionary] = []
	for stance: int in DuelTuning.Stance.values():
		out.append({"label": GUARD_PREFIX + _stance_name(stance),
			"state": Fighter.State.IDLE, "stance": stance})
	out.append_array([
		# Down is held through a duck, and down is LOW: in play a duck's stance
		# is LOW, whatever it was before (Fighter._update_stance).
		{"label": "DUCK", "state": Fighter.State.DUCKING, "ducked": true,
			"stance": DuelTuning.Stance.LOW},
		{"label": "WALK", "state": Fighter.State.RUNNING, "velocity": walk, "frame": 6,
			"span": 120},
		{"label": "WALK BACK", "state": Fighter.State.RUNNING, "velocity": -walk, "frame": 6,
			"span": 120},
	])
	for stance: int in DuelTuning.Stance.values():
		out.append({"label": "RUN " + _stance_name(stance), "state": Fighter.State.RUNNING,
			"stance": stance, "velocity": run, "frame": 6, "span": 120})
	out.append_array([
		{"label": "JUMP", "state": Fighter.State.JUMPING,
			"velocity": Vector2(60.0, -300.0), "grounded": false, "offset": Vector2(0.0, -14.0)},
		{"label": "FALL", "state": Fighter.State.JUMPING,
			"velocity": Vector2(60.0, 220.0), "grounded": false, "offset": Vector2(0.0, -10.0)},
	])
	for stance: int in DuelTuning.Stance.values():
		out.append({"label": "THRUST " + _stance_name(stance),
			"state": Fighter.State.THRUSTING, "stance": stance, "frame": 2,
			"span": tuning.thrust_frames + 10})
	for stance: int in DuelTuning.Stance.values():
		out.append({"label": "RECOVER " + _stance_name(stance),
			"state": Fighter.State.THRUSTING, "stance": stance, "frame": 10,
			"span": tuning.thrust_frames + 10})
	out.append_array([
		{"label": "ROLL", "state": Fighter.State.ROLLING, "frame": 8, "velocity": run,
			"span": tuning.roll_frames},
		{"label": "RISING", "state": Fighter.State.RISING, "frame": 3,
			"velocity": Vector2(tuning.roll_speed, 0.0), "span": tuning.roll_recover + 6},
		{"label": "DIVE KICK", "state": Fighter.State.DIVEKICK,
			"velocity": Vector2(tuning.divekick_speed_x, tuning.divekick_speed_y),
			"grounded": false, "offset": Vector2(0.0, -10.0)},
		{"label": "THROW", "state": Fighter.State.IDLE, "thrown": Vector2(16.0, -12.0)},
		{"label": "SNATCH", "state": Fighter.State.SNATCH, "frame": 3,
			"incoming": Vector2(24.0, -14.0), "span": tuning.snatch_frames + 6},
		{"label": "MISSED SNATCH", "state": Fighter.State.SNATCH, "frame": 14,
			"drop_blade": true, "span": tuning.snatch_frames + 6},
		{"label": "CATCH", "state": Fighter.State.CATCH, "frame": 2,
			"span": tuning.catch_settle + 10},
		{"label": "CATCH HIGH", "state": Fighter.State.CATCH, "frame": 4,
			"stance": DuelTuning.Stance.HIGH, "span": tuning.catch_settle + 10},
		{"label": "DISARMED", "state": Fighter.State.DISARMED, "frame": 4, "drop_blade": true,
			"span": tuning.disarmed_frames + 10},
		{"label": "UNARMED", "state": Fighter.State.IDLE, "drop_blade": true},
		{"label": "UNARMED DUCK", "state": Fighter.State.DUCKING, "ducked": true,
			"drop_blade": true},
		{"label": "SWEEP", "state": Fighter.State.SWEEP, "frame": 5, "drop_blade": true,
			"span": tuning.sweep_frames + 8},
		{"label": "POUND", "state": Fighter.State.POUND, "grounded": false,
			"drop_blade": true, "offset": Vector2(0.0, -10.0)},
		{"label": "DOWNED", "state": Fighter.State.DOWNED, "frame": 20,
			"span": tuning.downed_frames},
		{"label": "DEAD", "state": Fighter.State.DEAD, "frame": 40, "span": 90},
	])
	var covered := {}
	for entry: Dictionary in out:
		covered[int(entry["state"])] = true
	for state: int in Fighter.State.values():
		if not covered.has(state):
			out.append({"label": String(Fighter.State.keys()[state]).replace("_", " "),
				"state": state, "frame": 6})
	for entry: Dictionary in out:
		if not entry.has("span"):
			entry["span"] = FIGHTER_SPAN
	return out


## Puts `fighter` into `pose` with its feet at `feet`, `frame` frames into the
## state. The fighter is never simulated here, so these fields are everything
## FighterArt reads. False, with an error, if the duck did not take: it is a
## private field set by name (CLAUDE.md, on Object.set()), so it is read back
## through the posture the matrix sees.
static func pin_fighter(fighter: Fighter, pose: Dictionary, feet: Vector2, frame: int) -> bool:
	fighter.position = feet
	fighter.facing = int(pose.get("facing", 1))
	fighter.state = pose.get("state", Fighter.State.IDLE)
	fighter.state_frame = frame
	fighter.stance = int(pose.get("stance", DuelTuning.Stance.MID))
	var velocity: Vector2 = pose.get("velocity", Vector2.ZERO)
	fighter.velocity = Vector2(velocity.x * fighter.facing, velocity.y)
	fighter.grounded = bool(pose.get("grounded", true))
	var ducked := bool(pose.get("ducked", false))
	fighter.set("_ducked", ducked)
	_pin_blade(fighter, pose, feet)
	var folded := fighter.state == Fighter.State.ROLLING or fighter.state == Fighter.State.DOWNED
	if not folded and (fighter.posture() == DuelTuning.DUCKED) != ducked:
		push_error("could not pose %s: the duck did not take" % String(pose["label"]))
		return false
	return true


static func _pin_blade(fighter: Fighter, pose: Dictionary, feet: Vector2) -> void:
	var tuning := fighter.tuning
	var blade := fighter.blade
	var facing := fighter.facing
	if pose.has("incoming"):
		# A sword in the air a few pixels short of the open hands, flying at
		# them: what the snatch is for, drawn where the simulation would have it.
		var at: Vector2 = pose["incoming"]
		blade.mode = DuelBlade.Mode.FLYING
		blade.position = feet + Vector2(at.x * facing, at.y)
		blade.velocity = Vector2(-facing * tuning.throw_speed, 0.0)
	elif pose.has("thrown"):
		var ahead: Vector2 = pose["thrown"]
		blade.mode = DuelBlade.Mode.FLYING
		blade.position = feet + Vector2(ahead.x * facing, ahead.y)
		blade.velocity = Vector2(facing * tuning.throw_speed, 0.0)
		blade.thrown_by = fighter.id
	elif pose.get("drop_blade", false):
		blade.mode = DuelBlade.Mode.LOOSE
		blade.position = feet + Vector2(-14.0 * facing, -1.0)
		blade.velocity = Vector2.ZERO
	else:
		blade.hold()


## A stance's name as the lab and the readout print it: the enum's own key, so
## a stance added to DuelTuning is named without a list here.
static func stance_name(stance: int) -> String:
	if stance == DuelTuning.DUCKED:
		return "DUCKED"
	return _stance_name(stance)


static func _stance_name(stance: int) -> String:
	var keys := DuelTuning.Stance.keys()
	for i: int in keys.size():
		if int(DuelTuning.Stance.values()[i]) == stance:
			return String(keys[i])
	return str(stance)
