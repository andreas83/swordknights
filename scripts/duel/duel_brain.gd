class_name DuelBrain
extends RefCounted
## The computer opponent: one byte of input per frame, from what it can see.
##
## It drives a seat the way a player does, through the same eight bits
## (PlayerInput), and its only window on the match is a DuelView: its own
## fighter as of the last frame, everything else as of `reaction` frames
## before that. It never holds the match, a fighter or an input, so it cannot
## cheat on the simulation or read the human's buttons; scripts/duel/duel_view.gd
## argues that, and tests/unit/test_duel_cpu_seat.gd holds it.
##
## HOW IT PLAYS. Nidhogg as good players play it, which is mostly about range.
## A thrust reaches a body at `body_width + blade_reach` (27 px between feet)
## and a resting blade a little further, so between those two distances -- the
## edge -- a thrust can be parried or read but cannot kill. The brain fences
## from the edge:
##
## - It holds a stance, usually the other fighter's (a block), sometimes not.
## - From the edge it flicks its blade into their height and out again: a
##   thrust from there that meets the flick on its way in is the disarm read
##   (docs/duel-combat.md, "The disarm window"), and one that does not meets a
##   blade or air.
## - It attacks by choosing an open line -- a height they are not holding, and
##   the one they hold least, from a running count of their stances -- showing
##   that stance for a `tell`, then stepping in and thrusting. A `feint`
##   switches to the other open line on the thrust frame.
## - A thrust that missed, a snatch at nothing, a fighter on the floor: those
##   are punished at once, with no tell.
## - It throws at a back that is running away from it, and at range now and
##   then, low by preference so the throw cannot be caught. Empty-handed it
##   snatches a throw out of the air, fetches a sword, or sweeps and stamps.
## - With the initiative it runs for its gate and does not fight: a respawn in
##   its path is vaulted (a jump against a low blade, mostly a roll under a
##   high or middle one), a chaser left inside its reach is out-rolled, and it
##   stops short of a respawn about to appear in front of the gate. Without
##   it, it stands between the runner and their gate and waits for them on the
##   open ground a respawn puts it on, thrusts low at a roller, chases and
##   throws at a runner who got past, and goes and gets one who stops coming.
## - Every step goes through DuelFeet, which knows the moat and the spikes.
##
## Fun rather than perfect: the levels differ in how late it sees, how much it
## telegraphs, how often it guards and reads, how often it blunders, and how
## readily it attacks -- not in how much it is allowed to know.
##
## DETERMINISM. All chance is drawn from one RandomNumberGenerator seeded in
## reset(), and only inside decide(). Given the same seed and the same views,
## it answers the same bits, so a match against it replays from its seed and
## the human's inputs (tests/unit/test_duel_cpu_bouts.gd).

enum Difficulty { EASY, MEDIUM, HARD }

const LEVEL_NAMES: Array[String] = ["EASY", "MEDIUM", "HARD"]

## The knobs, one dictionary per level. Every one is a number a player can feel:
##   reaction    frames between something happening and the brain seeing it
##   anticipate  how far it leads a moving fighter, 0 (not at all) to 1 (fully)
##   tell        frames it shows the stance it is about to thrust from
##   feint       chance to switch to the other open line on the thrust frame
##   guard       chance, each time it reconsiders, to hold the other's stance
##   flick       chance, each time it reconsiders at the edge, to fish for a disarm
##   blunder     chance that a thrust, a vault or a dodge goes wrong
##   aggression  attacks started per second of standing at the edge
##   throw       chance per second of throwing at a back running away
##   contest     chance, per approach, that a runner fights a fighter in its way
##               rather than vaulting them (twice it against a LOW blade)
##   slop        frames late it jumps a hazard (never past the lip; DuelFeet)
const PROFILES: Array[Dictionary] = [
	{
		"reaction": 20, "anticipate": 0.4, "tell": 22, "feint": 0.0, "guard": 0.3,
		"flick": 0.0, "blunder": 0.35, "aggression": 0.45, "throw": 0.2, "slop": 2,
		"contest": 0.1,
	},
	{
		"reaction": 13, "anticipate": 0.8, "tell": 7, "feint": 0.15, "guard": 0.75,
		"flick": 0.35, "blunder": 0.12, "aggression": 1.0, "throw": 0.5, "slop": 1,
		"contest": 0.25,
	},
	{
		"reaction": 8, "anticipate": 1.0, "tell": 4, "feint": 0.4, "guard": 0.9,
		"flick": 0.5, "blunder": 0.04, "aggression": 1.2, "throw": 0.9, "slop": 0,
		"contest": 0.35,
	},
]

const DT := DuelRules.DT
const HIGH := DuelTuning.Stance.HIGH
const MID := DuelTuning.Stance.MID
const LOW := DuelTuning.Stance.LOW

## Frames an attack may take, tell and approach together, before it is dropped.
const ATTACK_PATIENCE := 70
## Frames after a thrust before it will start another attack.
const COOLDOWN := 10
## Beyond this, in px, it does not fence: it closes.
const ENGAGE := 120.0
## A runner who got past is thrown at between these distances, in px.
const THROW_NEAR := 36.0
const THROW_FAR := 240.0
## How far ahead of a vault the decision to vault is taken, in px.
const VAULT_LOOK := 80.0
## Seconds before a respawn just ahead that the runner stops to let it happen.
const RESPAWN_CAUTION := 0.6
## The flick's rhythm: into their height one frame in this many. Four is inside
## the five-frame disarm window, so a thrust from the edge always meets one.
const FLICK_PERIOD := 4
## How long it waits on its ground for a runner who has stopped running, in
## frames, before it goes to them.
const WAIT := 150
## A sword in flight is worth reacting to this many frames before it arrives.
const DODGE_LOOK := 16.0
## How far ahead it checks that the place it stands will not cut it: a little
## over the blades' tell, so it moves while the ratchet is still ticking.
const DOOM_LOOK := 34
## The same in a basin, where the way out may be six tiles and a hop.
const FLOOD_LOOK := 120

## Which seat this brain plays.
var seat := 1
var level: Difficulty = Difficulty.MEDIUM

var _p: Dictionary = PROFILES[Difficulty.MEDIUM]
var _rng := RandomNumberGenerator.new()

## The bits emitted last frame: a press has to be an edge.
var _last := 0
## Frames of jump still to hold.
var _hold := 0
## The attack in progress: frames left, frames of tell left, the line chosen.
var _attack := -1
var _tell := 0
var _line := MID
var _cool := 0
## The stance held while fencing, and frames until it is reconsidered.
var _guard := MID
var _guard_left := 0
## Frames left fishing for a disarm, and the stance it flicks out to.
var _flick := 0
var _flick_base := HIGH
## How the next vault goes over or under: 0 undecided, 1 jump, 2 roll, and 4
## not at all -- the fighter in the way is fought instead.
var _vault := 0
## Whether the sword now in flight is being reacted to, decided once per throw.
var _dodging := 0
var _sword_seen := false
## How often each of their heights has been seen: the least used is the open
## line most likely to stay open.
var _seen := PackedInt32Array([1, 1, 1])
## How often they have been seen to thrust at each height. A fighter who holds
## MID while walking and thrusts LOW every time is a LOW thrust coming, whatever
## the blade shows: this is what the guard is cut to at the edge of reach.
var _thrusts := PackedInt32Array([0, 0, 0])
## Whether they were inside the edge of reach last frame: the guard is chosen
## again the frame they step into it.
var _was_close := false
## Frames spent waiting for a runner who is not coming, and the furthest toward
## their gate they have been seen since it started counting.
var _waited := 0
var _their_best := -INF
## Frames spent within ENGAGE of a living opponent without anyone dying.
## Patience running out is what ends a standoff between two careful fighters.
var _standoff := 0


func _init(at_seat: int = 1, at_level: Difficulty = Difficulty.MEDIUM,
		seed_value: int = 0) -> void:
	seat = at_seat
	level = at_level
	_p = PROFILES[clampi(int(at_level), 0, PROFILES.size() - 1)]
	reset(seed_value)


## Back to a fresh mind: forget everything learned, reseed the dice.
func reset(seed_value: int) -> void:
	_rng.seed = seed_value
	_last = 0
	_hold = 0
	_attack = -1
	_tell = 0
	_cool = 0
	_guard = MID
	_guard_left = 0
	_flick = 0
	_vault = 0
	_dodging = 0
	_sword_seen = false
	_seen = PackedInt32Array([1, 1, 1])
	_thrusts = PackedInt32Array([0, 0, 0])
	_was_close = false
	_waited = 0
	_their_best = -INF
	_standoff = 0


## Frames between a thing happening and this brain seeing it.
func reaction() -> int:
	return int(_p["reaction"])


static func level_name(which: Difficulty) -> String:
	return LEVEL_NAMES[clampi(int(which), 0, LEVEL_NAMES.size() - 1)]


## One frame of input, from one view. The only way anything gets out of here.
func decide(view: DuelView) -> int:
	if view == null or view.me == null or view.them == null:
		return _emit(0)
	DuelFeet.look(view)
	_cool = maxi(0, _cool - 1)
	if not view.is_fighting() or not view.me.alive:
		_calm()
		return _emit(0)
	_learn(view)
	var want := Want.new()
	want.stance = view.me.stance
	if not view.me.is_free():
		# A commitment ignores input. Let go of everything, so the first free
		# frame can press anything as a fresh edge.
		_hold = 0
		return _emit(0)
	if _mind_the_ground(view, want):
		pass
	elif not _dodge(view, want):
		if not view.me.armed:
			_fetch(view, want)
		elif view.leader == seat:
			_run_home(view, want)
		elif view.leader == 1 - seat:
			_intercept(view, want)
		else:
			_fence(view, want)
	return _emit(_compose(view, want))


## What one frame of the brain wants, before the feet and the press edges have
## had their say.
class Want:
	extends RefCounted

	var dir := 0
	var stance := DuelTuning.Stance.MID
	## Frames to hold a jump starting this frame; 0 for none.
	var jump := 0
	var roll := false
	var attack := false
	var throw := false
	## Down, whatever the stance: a hand reaching for a sword. Standing, down
	## is the LOW guard; this only says the stance does not matter.
	var down := false
	## The duck: down with WALK, planted, under a HIGH blade or a scythe.
	var duck := false
	## WALK: move without turning round, blade still toward the other.
	var walk := false
	## Getting off ground that is about to kill: the direction is the way out,
	## taken as it is. Steering would see the slab going under the feet as a
	## lip, and stop on it.
	var flee := false


## --- the ground ------------------------------------------------------------

## When the place it stands is about to kill it -- a blade's beat coming, the
## water coming, the slab under it going -- getting out comes before any
## fencing: ducking under a scythe if a duck is enough, otherwise to the
## nearer safe footing (DuelFeet.refuge). Returns true when the frame was
## spent on that. The clock and the stones are on the screen, so this is what
## a player who has learned the strip does without thinking; the blunder knob
## does not reach it, because a computer that stood in a slot on purpose would
## not be making a mistake a person makes.
func _mind_the_ground(view: DuelView, want: Want) -> bool:
	var me := view.me
	var strip := view.strip
	if strip.hazards.is_empty() or not me.grounded:
		return false
	var half := view.tuning.body_width * 0.5
	var body := Rect2(me.position.x - half, me.position.y - view.tuning.body_height,
		half * 2.0, view.tuning.body_height)
	var within := FLOOD_LOOK if strip.hazards.in_a_basin(body.grow(2.0)) else DOOM_LOOK
	if not DuelFeet.doomed(strip, view.tuning, me, within):
		return false
	want.stance = _guard
	if DuelFeet.duck_saves(strip, view.tuning, me, within):
		want.duck = true
		return true
	want.dir = DuelFeet.refuge(strip, view.tuning, me)
	want.flee = want.dir != 0
	return want.flee


## --- reading the other fighter ---------------------------------------------

func _learn(view: DuelView) -> void:
	var them := view.them
	if them.alive and them.armed and them.is_free():
		_seen[clampi(them.stance, 0, 2)] += 1
		if _seen[them.stance] > 4000:
			for i: int in 3:
				_seen[i] = maxi(1, _seen[i] / 2)
	if them.alive and them.state == Fighter.State.THRUSTING and them.state_frame == 1:
		_thrusts[clampi(them.stance, 0, 2)] += 1
		if _thrusts[them.stance] > 60:
			for i: int in 3:
				_thrusts[i] /= 2
	if them.alive and view.me.alive and absf(_their_x(view) - view.me.position.x) < ENGAGE:
		_standoff += 1
	if not them.alive:
		_standoff = 0


## Where they probably are now: seen `age` frames ago, led by their speed as
## far as this level anticipates.
func _their_x(view: DuelView) -> float:
	var lead := float(view.age - 1) * DT * float(_p["anticipate"])
	return view.them.position.x + view.them.velocity.x * lead


## How many frames they will be unable to do anything, now, or 0.
func _helpless(view: DuelView) -> int:
	var them := view.them
	var tuning := view.tuning
	var now := them.state_frame + view.age - 1
	var left := 0
	match them.state:
		Fighter.State.THRUSTING:
			if now > tuning.thrust_active:
				left = tuning.thrust_frames - now
		Fighter.State.SNATCH:
			if now > tuning.catch_window:
				left = tuning.snatch_frames - now
		Fighter.State.DISARMED:
			left = tuning.disarmed_frames - now
		Fighter.State.SWEEP:
			left = tuning.sweep_frames - now
		Fighter.State.DOWNED:
			left = tuning.downed_frames - now
		Fighter.State.CATCH:
			left = tuning.catch_settle - now
		Fighter.State.RISING:
			left = tuning.roll_recover - now
		_:
			left = 0
	return maxi(0, left)


## The heights a thrust can kill through right now: anything they are not
## holding, and never over a ducking head.
func _open_lines(view: DuelView) -> Array[int]:
	var them := view.them
	var lines: Array[int] = []
	var helpless := _helpless(view) > 0 or not them.armed
	for line: int in [HIGH, MID, LOW]:
		if them.posture == DuelTuning.DUCKED and line == HIGH:
			continue
		if line == them.posture and not helpless:
			continue
		lines.append(line)
	if lines.is_empty():
		lines.append(MID)
	return lines


## Of the open lines, the one they go to least: the likeliest to stay open
## through a tell. A blunder picks any height at all, open or not.
func _choose_line(view: DuelView) -> int:
	if _chance(float(_p["blunder"])):
		return _rng.randi_range(HIGH, LOW)
	var lines := _open_lines(view)
	var weights := PackedFloat32Array()
	var total := 0.0
	var sum := float(_seen[0] + _seen[1] + _seen[2])
	for line: int in lines:
		var weight := 1.0 - float(_seen[line]) / sum + 0.15
		weights.append(weight)
		total += weight
	var roll := _rng.randf() * total
	for i: int in lines.size():
		roll -= weights[i]
		if roll <= 0.0:
			return lines[i]
	return lines[lines.size() - 1]


## --- fencing -----------------------------------------------------------------

## `hold` keeps it on its ground: a runner coming at it is met where it stands,
## not run at, because two fighters closing at once close faster than either
## can see.
func _fence(view: DuelView, want: Want, hold: bool = false) -> void:
	var me := view.me
	var them := view.them
	var tuning := view.tuning
	var reach := tuning.body_width + tuning.blade_reach
	var edge := reach + tuning.blade_rest
	var dx := _their_x(view) - me.position.x
	var d := absf(dx)
	var toward := _sign(dx, me.facing)
	if not them.alive:
		_attack = -1
		want.stance = _guard
		return

	want.stance = _guard_stance(view, d, reach, edge)
	if _attack < 0 and _cool == 0:
		var helpless := _helpless(view)
		if helpless > 0 and d < edge + 2.0 * float(helpless):
			_begin_attack(view, 0)
		elif not them.armed and d < ENGAGE:
			_begin_attack(view, int(_p["tell"]) / 2)
	if _attack >= 0:
		_attacking(view, want, d, toward, reach)
		return
	if _wants_to_throw(view, d, false):
		_throw(want, view, toward)
		return

	if d > edge + 2.0:
		# Close the distance -- unless the moat or the pit is between them and
		# they are near it, in which case the other one can do the crossing,
		# and land in reach. Far off, it is only ground to cover.
		# Not for ever: two fighters each waiting for the other to cross -- the
		# Aqueduct worn through between them after a double kill put both back
		# on their marks -- would wait out the match. After WAIT, it crosses.
		var near_gap := d < ENGAGE and DuelFeet.gap_between(view.strip, me, _their_x(view)) \
			and _standoff < WAIT
		if hold or near_gap:
			_face(want, me, toward)
		else:
			want.dir = toward
	elif d >= reach + 1.0:
		_face(want, me, toward)
		var urge := float(_p["aggression"]) * DT * (1.0 + float(_standoff) / 240.0)
		if _cool == 0 and _chance(urge):
			_begin_attack(view, int(_p["tell"]))
	else:
		# Inside their reach. Whoever thrusts first wins this, and a careful
		# fighter does not stand here: strike now, or step back out.
		_face(want, me, toward)
		if _cool == 0 and _chance(0.35 + float(_p["aggression"]) * 0.2):
			_begin_attack(view, mini(int(_p["tell"]), 2))
			_attacking(view, want, d, toward, reach)
		elif d < reach - 4.0 and DuelFeet.safe_step(view.strip, tuning, me, -toward):
			# Back out of it facing them: a walk, not a run that turns round.
			want.dir = -toward
			want.walk = true


## The stance held while not attacking: their height, as often as this level
## guards, reconsidered every few frames rather than every frame. At the edge,
## sometimes a flick: out of their height and back into it, on a rhythm that a
## thrust's disarm window cannot fall between.
func _guard_stance(view: DuelView, d: float, reach: float, edge: float) -> int:
	var them := view.them
	var theirs := _expected_thrust(view)
	# Stepping into the edge of reach is when a guard matters: choose it again
	# then, rather than up to two dozen frames later.
	var close := d <= edge + 4.0
	if close and not _was_close:
		_guard_left = 0
	_was_close = close
	_guard_left -= 1
	if _guard_left <= 0:
		_guard_left = _rng.randi_range(8, 24)
		_guard = theirs if _chance(float(_p["guard"])) else _rng.randi_range(HIGH, LOW)
		var at_edge := d >= reach + 1.0 and d <= edge + 4.0
		if at_edge and them.armed and _chance(float(_p["flick"])):
			_flick = _rng.randi_range(16, 36)
			_flick_base = (theirs + _rng.randi_range(1, 2)) % 3
	if _flick > 0:
		_flick -= 1
		if d < reach:
			_flick = 0
		elif _flick % FLICK_PERIOD == 0:
			return theirs
		else:
			return _flick_base
	return _guard


## The height a thrust from them is likeliest to come at: the one they hold --
## a ducking fighter holds LOW, and a thrust out of a duck comes up at LOW --
## unless one height has been most of their thrusts, three times or more.
func _expected_thrust(view: DuelView) -> int:
	var total := _thrusts[0] + _thrusts[1] + _thrusts[2]
	if total >= 3:
		for line: int in [HIGH, MID, LOW]:
			if _thrusts[line] * 2 > total:
				return line
	return view.them.stance


func _begin_attack(view: DuelView, tell: int) -> void:
	_attack = ATTACK_PATIENCE
	_tell = tell
	_line = _choose_line(view)
	_flick = 0


## Show the line, step in, thrust. If they have moved into the line during the
## tell, a feint takes the other open one on the thrust frame; without the
## feint the thrust goes where it was shown, and is parried.
func _attacking(view: DuelView, want: Want, d: float, toward: int, reach: float) -> void:
	var me := view.me
	_attack -= 1
	if _attack <= 0:
		_attack = -1
		return
	want.stance = _line
	if _tell > 0:
		_tell -= 1
		if d > reach + view.tuning.blade_rest:
			want.dir = toward
		else:
			_face(want, me, toward)
		return
	var strike := reach - 2.0
	if _chance(float(_p["blunder"]) * 0.2):
		strike += 10.0 # lunges from too far, and will be standing in recovery
	if d > strike:
		want.dir = toward
		return
	if me.facing != toward:
		want.dir = toward
		return
	var line := _line
	if view.them.posture == line and _helpless(view) == 0 and _chance(float(_p["feint"])):
		var lines := _open_lines(view)
		line = lines[_rng.randi_range(0, lines.size() - 1)]
	want.stance = line
	want.attack = true
	_attack = -1
	_cool = view.tuning.thrust_frames + COOLDOWN


func _face(want: Want, me: DuelView.Body, toward: int) -> void:
	if me.facing != toward:
		want.dir = toward


## --- the sword in the air ----------------------------------------------------

## A thrown sword coming at this fighter: snatch it, duck it, roll under it or
## jump it. Returns true when the frame was spent on that.
func _dodge(view: DuelView, want: Want) -> bool:
	var me := view.me
	var tuning := view.tuning
	var threat: DuelView.Sword = null
	var eta := INF
	var height := 0.0
	for sword: DuelView.Sword in view.swords:
		if not sword.flying or sword.thrown_by != 1 - seat:
			continue
		var at := sword.position + sword.velocity * DT * float(view.age - 1)
		# How far ahead of the blade the body still is, along its flight, and
		# how far it must get past the middle of the body to be clear of it.
		var ahead := (me.position.x - at.x) * signf(sword.velocity.x)
		var clear := tuning.body_width * 0.5 + tuning.blade_length * 0.5
		if ahead < -clear - 1.0:
			continue
		# Zero or less while the blade is passing through the body's column: the
		# duck or the jump has to be held until it is out the other side.
		var frames := (ahead - clear) / maxf(1.0, absf(sword.velocity.x) * DT)
		var h := me.position.y - at.y
		var over_head := h - tuning.blade_thickness * 0.5 > tuning.body_height
		if frames > DODGE_LOOK or over_head or h < -2.0:
			continue
		if frames < eta:
			threat = sword
			eta = frames
			height = h
	if threat == null:
		_sword_seen = false
		return false
	if not _sword_seen:
		_sword_seen = true
		_dodging = 0 if _chance(float(_p["blunder"])) else 1
	if _dodging == 0:
		return false

	var toward_blade := _sign(threat.position.x - me.position.x, me.facing)
	var low_edge := height - tuning.blade_thickness * 0.5
	var catchable := low_edge > tuning.band_mid_bottom - 1.0
	if not me.armed and catchable:
		if me.facing != toward_blade:
			want.dir = toward_blade
		elif eta <= 2.5:
			want.throw = true
		return true
	if low_edge > tuning.duck_height + 1.0:
		want.duck = true
	elif low_edge > tuning.roll_height + 1.0 and eta <= 6.0 and _roll_room(view):
		want.roll = true
	elif eta <= 5.0:
		want.jump = DuelFeet.HOLD
	return true


## A roll goes a long way along the floor in the way the fighter faces, and
## a roll into the spike pit is a roll into the spike pit.
func _roll_room(view: DuelView) -> bool:
	var me := view.me
	var travel := view.tuning.roll_travel()
	var end := me.position.x + float(me.facing) * (travel + view.tuning.body_width)
	return me.grounded and not DuelFeet.gap_between(view.strip, me, end)


## --- empty-handed ------------------------------------------------------------

func _fetch(view: DuelView, want: Want) -> void:
	var me := view.me
	var them := view.them
	var tuning := view.tuning
	var dx := _their_x(view) - me.position.x
	var d := absf(dx)
	var toward := _sign(dx, me.facing)
	want.stance = MID

	if them.alive and them.state == Fighter.State.DOWNED and d < 48.0:
		_stamp(view, want, dx)
		return
	var sword := _nearest_sword(view)
	if sword != null:
		var sx := sword.position.x - me.position.x
		if absf(sx) < 8.0:
			want.down = true
			return
		want.dir = _sign(sx, me.facing)
		var blocking := them.alive and them.armed and signf(dx) == signf(sx) and d < absf(sx)
		if blocking and d < VAULT_LOOK:
			_vault_over(view, want, want.dir, d)
		return
	if view.leader == seat:
		want.dir = ZoneStrip.goal_direction(seat)
		if them.alive and d < VAULT_LOOK and signf(dx) == float(want.dir):
			_vault_over(view, want, want.dir, d)
		return
	if not them.alive:
		return
	# Nothing to pick up: the sweep, from just outside a thrust's reach is
	# impossible, so from inside it, and quickly.
	var sweep_range := tuning.body_width + tuning.sweep_reach - 2.0
	if d > sweep_range:
		want.dir = toward
	elif me.facing != toward:
		want.dir = toward
	elif me.grounded and _cool == 0:
		want.attack = true
		_cool = tuning.sweep_frames


## The ground pound onto a fighter who is down: up, over, and straight down.
func _stamp(view: DuelView, want: Want, dx: float) -> void:
	var me := view.me
	if me.grounded:
		want.dir = _sign(dx, me.facing)
		if absf(dx) <= 24.0:
			want.jump = DuelFeet.HOLD
		return
	want.dir = _sign(dx, 0) if absf(dx) > 3.0 else 0
	if absf(dx) < 6.0 and me.velocity.y > -60.0:
		want.attack = true


## The nearest sword lying where feet can get to it. One that fell into the
## water or the spikes is not worth dying for.
func _nearest_sword(view: DuelView) -> DuelView.Sword:
	var best: DuelView.Sword = null
	var best_d := INF
	for sword: DuelView.Sword in view.swords:
		if sword.flying:
			continue
		var column := floori(sword.position.x / ZoneStrip.TILE)
		var ground := view.strip.ground_row(column)
		if ground < 0 or sword.position.y > float(ground * ZoneStrip.TILE) + 4.0:
			continue
		var d := absf(sword.position.x - view.me.position.x)
		if d < best_d:
			best = sword
			best_d = d
	return best


## --- with the initiative -----------------------------------------------------

func _run_home(view: DuelView, want: Want) -> void:
	var me := view.me
	var them := view.them
	var dir := ZoneStrip.goal_direction(seat)
	want.dir = dir
	want.stance = _guard
	if not them.alive:
		_vault = 0
		if _respawning_ahead(view, dir):
			# They come back in front of the gate, and soon. Running onto the
			# spot they appear on is running onto their blade: stop short, and
			# vault them once they are there to be seen.
			want.dir = 0
		return
	var dx := _their_x(view) - me.position.x
	var ahead := signf(dx) == float(dir)
	var d := absf(dx)
	if not ahead:
		_vault = 0
		# Vaulted, and they have turned to follow. A jump comes down inside
		# their reach and a run keeps the gap it has, so the back is open to
		# them: roll, which carries further than they can run in the time, rise
		# included (DuelTuning.roll_travel), until it is not.
		var reach := view.tuning.body_width + view.tuning.blade_reach
		var chasing := them.armed and d < reach + 10.0
		if chasing and _roll_room(view) and me.facing == dir:
			want.roll = true
		return
	if d < VAULT_LOOK:
		# Since a roll ends standing with no blade up, and a jump over a LOW
		# blade comes down inside its reach, a vault past a fighter who is
		# ready for it is often a death: sometimes the runner fights its way
		# through instead, and a fighter who killed is still running home.
		if _vault == 0 and them.armed:
			var low := them.stance == LOW or them.posture == DuelTuning.DUCKED
			var contest := float(_p["contest"]) * (2.0 if low else 1.0)
			_vault = 4 if _chance(contest) else 0
		if _vault == 4:
			_fence(view, want)
			return
		want.stance = them.stance if them.posture != DuelTuning.DUCKED else MID
		_vault_over(view, want, dir, d)


## Whether the other fighter is about to reappear just ahead. The rule is
## public -- a screen and a half ahead of the leader, or pinned in front of the
## gate (DuelMatch.respawn_plan) -- and the ring counting their respawn down is
## on the screen, so a player near the gate knows where and when as well.
func _respawning_ahead(view: DuelView, dir: int) -> bool:
	var left := view.their_respawn - float(view.age - 1) * DT
	if left <= 0.0 or left > RESPAWN_CAUTION:
		return false
	var me := view.me
	var spot := view.strip.find_open_ground(
		me.position.x + dir * DuelMatch.RESPAWN_LEAD, me.position.x)
	if not bool(spot["ok"]):
		return false
	var ahead := ((spot["position"] as Vector2).x - me.position.x) * float(dir)
	return ahead > 0.0 and ahead < VAULT_LOOK + 10.0


## Over a low blade; under a high or middle one, mostly, and over it the rest of
## the time, so the vault is not a certainty to wait for. Decided once per
## approach, and re-decided if the blade drops to the height a roll dies to.
func _vault_over(view: DuelView, want: Want, dir: int, d: float) -> void:
	var them := view.them
	var tuning := view.tuning
	var reach := tuning.body_width + tuning.blade_reach
	var low := them.stance == LOW or them.posture == DuelTuning.DUCKED
	if _vault == 0:
		_vault = 1 if low or _chance(0.3) else 2
		if _chance(float(_p["blunder"])):
			_vault = 3 - _vault
	elif _vault == 2 and low and not _chance(float(_p["blunder"])):
		_vault = 1
	# A roll ends in the rise, standing with no blade up: started from here it
	# ends a resting blade's reach past them, out of a turn and a thrust.
	var roll_from := tuning.roll_speed * DT * float(tuning.roll_frames) \
		- (reach + tuning.blade_rest)
	var jump_from := reach + tuning.blade_rest + 2.0
	if _vault == 2 and d <= roll_from and _roll_room(view):
		want.roll = true
		want.dir = dir
	elif _vault == 1 and d <= jump_from:
		want.jump = DuelFeet.HOLD
		want.dir = dir
	elif _vault == 2 and d <= reach and not _roll_room(view):
		want.jump = DuelFeet.HOLD


## --- without it ----------------------------------------------------------------

func _intercept(view: DuelView, want: Want) -> void:
	var me := view.me
	var them := view.them
	var tuning := view.tuning
	var their_way := ZoneStrip.goal_direction(1 - seat)
	var tx := _their_x(view)
	var dx := tx - me.position.x
	var d := absf(dx)
	var toward := _sign(dx, me.facing)
	var in_their_way := (me.position.x - tx) * float(their_way) > 0.0
	if not them.alive:
		want.stance = _guard
		_their_best = -INF
		return
	if in_their_way:
		var reach := tuning.body_width + tuning.blade_reach
		if them.state == Fighter.State.ROLLING and d <= reach + 4.0 and _cool == 0:
			_face(want, me, toward)
			if me.facing == toward:
				want.stance = LOW
				want.attack = true
				_cool = tuning.thrust_frames + COOLDOWN
			return
		# Coming is moving toward their gate, now: met where it stands. But the
		# wait is only worth it while they get nearer -- a new best, not a step
		# that way. A fighter shuffling back and forth against the trailing
		# edge, or standing in a sweep or a snatch, is not on the way however
		# often their feet point at it; reading the feet, the wait reset with
		# every step and the fetch could take two minutes.
		var coming := signf(them.velocity.x) == float(their_way)
		var progress := tx * float(their_way)
		var nearer := progress > _their_best + 2.0
		if nearer:
			_their_best = progress
		if d > ENGAGE and (nearer or _waited < WAIT):
			# The respawn put this fighter on open ground ahead of them. Wait
			# there, blade up, facing them, while they come to it -- and go and
			# get them if they stop coming.
			_waited = _waited + 1 if not nearer else 0
			_face(want, me, toward)
			want.stance = _guard_stance(view, d, reach, reach + tuning.blade_rest)
			return
		_fence(view, want, coming)
		return
	# They got past: after them, with a throw at their back if they are running.
	_attack = -1
	want.dir = toward
	want.stance = _guard
	var away := them.facing != _sign(-dx, them.facing)
	if away and _wants_to_throw(view, d, true):
		_throw(want, view, toward)
		return
	var reach_now := tuning.body_width + tuning.blade_reach - 2.0
	if d <= reach_now and me.facing == toward and _cool == 0:
		want.stance = MID if them.posture == DuelTuning.DUCKED else LOW
		want.attack = true
		_cool = tuning.thrust_frames + COOLDOWN


## --- throwing ------------------------------------------------------------------

func _wants_to_throw(view: DuelView, d: float, at_a_back: bool) -> bool:
	var them := view.them
	if not view.me.armed or not them.alive or _cool > 0:
		return false
	if at_a_back:
		if d < THROW_NEAR or d > THROW_FAR:
			return false
		return _chance(float(_p["throw"]) * DT)
	# Facing it, an armed fighter can duck, jump or roll: only now and then,
	# from range, and never at a fighter already ducking under the line.
	if d < 90.0 or d > 200.0 or them.posture == DuelTuning.DUCKED:
		return false
	return _chance(float(_p["throw"]) * 0.12 * DT)


func _throw(want: Want, view: DuelView, toward: int) -> void:
	if view.me.facing != toward:
		want.dir = toward
		return
	var roll := _rng.randf()
	want.stance = LOW if roll < 0.55 else (MID if roll < 0.9 else HIGH)
	want.throw = true
	want.dir = 0
	_cool = COOLDOWN


## --- from wants to bits --------------------------------------------------------

## Everything the brain asked for, put through the feet and the press edges.
##
## The feet have the last word on direction and may add a jump of their own; a
## jump or roll the brain asked for is refused if it lands in a hazard. A press
## (jump, attack, throw) is only a press on a frame after one without it, so a
## request on the frame after a press is deferred a frame. A new jump never
## carries `down`, which would make it a roll or a dive kick. And nothing that
## takes the steering away -- a thrust, a throw -- is started in the air over
## something that would kill the fighter who stopped steering.
func _compose(view: DuelView, want: Want) -> int:
	var me := view.me
	var strip := view.strip
	var tuning := view.tuning
	var steer := DuelFeet.steer(strip, tuning, me, want.dir, _hold, int(_p["slop"]))
	var dir := int(steer["dir"])
	if want.flee and dir == 0:
		dir = want.dir
	var hop := want.jump
	if hop == 0 and bool(steer["jump"]):
		hop = int(steer["hold"])
	var roll := want.roll
	var can_press_jump := me.grounded and _hold == 0 and (_last & PlayerInput.BIT_JUMP) == 0
	if not can_press_jump:
		hop = 0
		roll = false
	if hop > 0 and not DuelFeet.safe_jump(strip, tuning, me, dir, hop):
		hop = 0
	if hop > 0:
		roll = false
		_hold = hop

	var bits := 0
	if _hold > 0:
		bits |= PlayerInput.BIT_JUMP
		_hold -= 1
	var down := want.down or want.duck
	if roll:
		bits |= PlayerInput.BIT_JUMP | PlayerInput.BIT_DOWN
	elif want.stance == HIGH:
		bits |= PlayerInput.BIT_UP
	elif want.stance == LOW or down:
		bits |= PlayerInput.BIT_DOWN
	if down:
		bits = (bits | PlayerInput.BIT_DOWN) & ~PlayerInput.BIT_UP
	# WALK is a duck with down, and a shuffle that keeps the facing without it.
	# Never on a jump or a roll: the feet predict a jump from a run.
	if (want.duck or want.walk) and not roll and hop == 0 and not bool(steer["jump"]):
		bits |= PlayerInput.BIT_WALK
	if hop > 0:
		bits &= ~PlayerInput.BIT_DOWN
	if dir < 0:
		bits |= PlayerInput.BIT_LEFT
	elif dir > 0:
		bits |= PlayerInput.BIT_RIGHT
	var committing := want.attack or want.throw
	if committing and not DuelFeet.safe_to_commit(strip, tuning, me):
		return bits
	if want.attack and (_last & PlayerInput.BIT_ATTACK) == 0:
		bits |= PlayerInput.BIT_ATTACK
	if want.throw and (_last & PlayerInput.BIT_THROW) == 0:
		bits |= PlayerInput.BIT_THROW
	return bits


func _emit(bits: int) -> int:
	_last = bits & 0xff
	return _last


## Out of the fight -- dead, or the countdown -- every plan is dropped.
func _calm() -> void:
	_hold = 0
	_attack = -1
	_flick = 0
	_vault = 0
	_standoff = 0
	_waited = 0
	_their_best = -INF


func _chance(p: float) -> bool:
	return _rng.randf() < p


static func _sign(value: float, otherwise: int) -> int:
	if value > 0.0:
		return 1
	if value < 0.0:
		return -1
	return 1 if otherwise >= 0 else -1
