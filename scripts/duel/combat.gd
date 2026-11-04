class_name DuelCombat
extends RefCounted
## The combat matrix, the clash, the disarm, the throw, the catch and the pickup.
##
## Everything here is static and reads nothing but the two fighters it is
## handed, so one call is one frame of fighting and that frame is reproducible
## from the fighters' snapshots alone.
##
## HOW A BLADE IS RESOLVED. Two tests, in this order:
##
##   1. GEOMETRY decides whether anything touched: the attacker's blade AABB
##      against the defender's hurtbox AABB (and, on the diagonal, against the
##      defender's own blade). This is where a duck and a roll earn their
##      living — DuelTuning cuts the three stance bands so that a 13px duck is
##      already under HIGH and a 7px roll is already under HIGH and MID.
##   2. THE MATRIX decides what the contact means, keyed on the attacker's
##      stance and the defender's posture, exactly as docs/duel-spec.md has it.
##
## So the geometry and the table agree by construction rather than by luck, and
## tests/combat_matrix_test.gd walks all twelve cells in both directions.
##
## A body hit is an instant kill. There is no health anywhere in the duel.

## What one fighter's blade does to the other this frame.
enum Outcome { MISS, KILL, CLASH, DISARM_ATTACKER }

## The spec's table. Rows are the attacker's stance (HIGH, MID, LOW); columns
## are the defender's posture (HIGH, MID, LOW, DUCKED), which is why those two
## enums share their ordinals.
##
##   attacker \ defender | HIGH  | MID   | LOW   | DUCKING
##   HIGH                | clash | kill  | kill  | miss (over the head)
##   MID                 | kill  | clash | kill  | kill (head)
##   LOW                 | kill  | kill  | clash | kill (torso)
const MATRIX: Array[Array] = [
	[Outcome.CLASH, Outcome.KILL, Outcome.KILL, Outcome.MISS],
	[Outcome.KILL, Outcome.CLASH, Outcome.KILL, Outcome.KILL],
	[Outcome.KILL, Outcome.KILL, Outcome.CLASH, Outcome.KILL],
]


## One cell of the table. No geometry, no state: this is the rule itself.
static func outcome(attacker_stance: int, defender_posture: int) -> int:
	if attacker_stance < 0 or attacker_stance >= MATRIX.size():
		return Outcome.MISS
	var row: Array = MATRIX[attacker_stance]
	if defender_posture < 0 or defender_posture >= row.size():
		return Outcome.MISS
	return row[defender_posture]


## One whole duel frame: both inputs, both simulations, then the fight.
##
## The match layer may call this, or do the same three things itself — the
## order is what matters, and resolve() reads every hitbox before it applies
## anything so the outcome cannot depend on which fighter is slot A.
static func step(a: Fighter, b: Fighter, bits_a: int, bits_b: int, dt: float) -> Array[Dictionary]:
	a.input.apply_bits(bits_a)
	b.input.apply_bits(bits_b)
	a.simulate(dt)
	b.simulate(dt)
	return resolve(a, b)


## Sword against sword, sword against body, feet against body, thrown sword
## against everything (open hands included), and hands against a sword on the
## floor.
##
## Returns what happened, for a HUD, a sound or a spray of gore — all of which
## are presentation and none of which may enter the snapshot.
static func resolve(a: Fighter, b: Fighter) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var fencing := a.is_alive() and b.is_alive()

	# --- read everything before applying anything --------------------------
	var ab := _probe(a, b) if fencing else Outcome.MISS
	var ba := _probe(b, a) if fencing else Outcome.MISS
	var a_strike := _strike(a, b) if fencing else Fighter.Strike.NONE
	var b_strike := _strike(b, a) if fencing else Fighter.Strike.NONE

	# --- blades ------------------------------------------------------------
	var disarmed := ab == Outcome.DISARM_ATTACKER or ba == Outcome.DISARM_ATTACKER
	if ab == Outcome.DISARM_ATTACKER:
		a.disarm(b.id)
		events.append({"kind": "disarm", "victim": a.id, "by": b.id, "at": a.position})
	if ba == Outcome.DISARM_ATTACKER:
		b.disarm(a.id)
		events.append({"kind": "disarm", "victim": b.id, "by": a.id, "at": b.position})

	if not disarmed and (ab == Outcome.CLASH or ba == Outcome.CLASH):
		var middle := (a.position + b.position) * 0.5
		a.push_back(b.position.x)
		b.push_back(a.position.x)
		events.append({"kind": "clash", "at": middle})
	elif not disarmed:
		# A double kill is a real outcome, not a tie-break: the table is read
		# in both directions from the same frame.
		if ab == Outcome.KILL:
			b.kill(a.id)
			events.append({"kind": "kill", "victim": b.id, "killer": a.id, "at": b.position})
		if ba == Outcome.KILL:
			a.kill(b.id)
			events.append({"kind": "kill", "victim": a.id, "killer": b.id, "at": a.position})

	# --- feet and fists ----------------------------------------------------
	_apply_strike(a, b, a_strike, events)
	_apply_strike(b, a, b_strike, events)

	# --- swords in flight, and swords on the floor -------------------------
	_resolve_flight(a, b, events)
	_resolve_pickups(a, b, events)
	return events


## --- the blade --------------------------------------------------------------

## What `att`'s blade does to `def` this frame.
##
## The diagonal of the matrix — equal stance against equal posture — is where
## the fencing lives, so it is resolved first and with slightly more reach: two
## blades meet before either reaches a body. Off the diagonal the table decides
## and the only question is whether the blade touched the body at all.
static func _probe(att: Fighter, def: Fighter) -> int:
	if att.state != Fighter.State.THRUSTING:
		return Outcome.MISS
	var tuning := att.tuning
	# The disarm read is allowed one frame past the active window; see
	# docs/duel-combat.md on why the window is five frames and not four.
	var in_window := att.state_frame <= tuning.disarm_window
	if not att.is_attacking() and not in_window:
		return Outcome.MISS

	var blade := tuning.blade_rect(att.position, att.facing, att.stance, tuning.blade_reach)
	var body := def.hurt_rect()
	var guard := def.blade_rect()
	var defender_posture := def.posture()

	if defender_posture == att.stance and guard.size.x > 0.0 and _faces(def, att):
		if not (blade.intersects(guard) or blade.intersects(body)):
			return Outcome.MISS
		# Both committed at the same height: the blades bounce off each other.
		if def.is_attacking():
			return Outcome.CLASH
		# The read. The defender moved their blade INTO the height of a thrust
		# that is still in its opening frames: the attacker loses the sword.
		if def.stance_changed and in_window:
			return Outcome.DISARM_ATTACKER
		# A stance that was already there turns the blade aside: a parry.
		return Outcome.CLASH

	if not att.is_attacking():
		return Outcome.MISS # recovery frames cut nothing
	if not blade.intersects(body):
		return Outcome.MISS
	var table := outcome(att.stance, defender_posture)
	# The table's clash cell assumes a blade at that height to turn the thrust
	# aside. Empty-handed, tucked into a roll, or in the recovery of a thrust
	# that missed, there is nothing there and the cut lands.
	return Outcome.KILL if table == Outcome.CLASH else table


## Whether the defender's blade is on the side the thrust is coming from.
##
## Not in the spec's table, which is keyed on heights alone, and added
## deliberately: a blade can only turn aside a thrust it is facing. Without it
## a fighter running away with a matching stance would be immune to being
## stabbed in the back. scripts/player/player.gd drew the same line for the
## guard state it used to have, and a duel where the back is safe is not one.
static func _faces(def: Fighter, att: Fighter) -> bool:
	var toward := signf(att.position.x - def.position.x)
	return is_zero_approx(toward) or int(toward) == def.facing


## --- feet and fists ---------------------------------------------------------

## The dive kick, the leg sweep and the ground pound. The sweep is the unarmed
## fighter's way back into the fight; the pound is the finisher the spec gives
## it, and only a fighter who is already down can be finished.
static func _strike(att: Fighter, def: Fighter) -> int:
	var kind := att.strike_kind()
	if kind == Fighter.Strike.NONE:
		return Fighter.Strike.NONE
	if not att.strike_rect().intersects(def.hurt_rect()):
		return Fighter.Strike.NONE
	return kind


static func _apply_strike(att: Fighter, def: Fighter, kind: int, events: Array[Dictionary]) -> void:
	if kind == Fighter.Strike.NONE or not def.is_alive() or not att.is_alive():
		return
	if def.state == Fighter.State.DOWNED:
		# Only the pound has anything to say to a fighter who is already down.
		# A sweep whose active frames are still passing over one does not keep
		# knocking it down — which would also report the event every frame.
		if kind == Fighter.Strike.POUND:
			def.kill(att.id)
			events.append({
				"kind": "kill", "victim": def.id, "killer": att.id, "at": def.position,
			})
		return
	# A kick puts the fighter down for less time than the kicker spends getting
	# up from it; a sweep for long enough to be finished. See DuelTuning.
	var frames := att.tuning.kick_downed_frames if kind == Fighter.Strike.KICK else -1
	def.knock_down(att.position.x, frames)
	events.append({"kind": "knockdown", "victim": def.id, "by": att.id, "at": def.position})


## --- thrown swords ----------------------------------------------------------

## Lethal on contact with any unguarded hurtbox; countered by ducking, rolling
## (both of which the band geometry already handles), by a thrust that deflects
## the flying blade out of the air, or -- by an empty hand only -- by catching it.
##
## THE ORDER, for each blade in flight, and every step is deterministic:
##
##   1. a live thrust in its path bats it away: the deflect, unchanged
##   2. open hands in its path take it: the catch
##   3. a body in its path dies
##
## A CATCH AND A KILL ON THE SAME FRAME. A frame is a sample of continuous
## motion. A blade flying INTO open hands has to pass them to reach the body
## behind them, so a frame on which it touches both is a frame on which it met
## the hands first: the catch wins, exactly as a parry wins over a cut on the
## diagonal of the matrix (_probe), where two blades meet before either reaches
## a body. The direction is what earns it -- a blade overtaking a fighter from
## behind reaches the back first, and kills, open hands or not. And a fighter
## already cut down this frame by a thrust or finished by a pound catches
## nothing: blades and feet are resolved before flight, so a body that is dead
## has no hands. docs/duel-combat.md has the argument and the alternatives.
##
## The blades in flight are listed before any is resolved, and each is found
## again by identity. A catch swaps records between the two fighters (as a
## pickup does), so walking the two slots instead would skip a blade that had
## just moved into a slot already visited, and would make the outcome depend
## on which fighter is slot A.
static func _resolve_flight(a: Fighter, b: Fighter, events: Array[Dictionary]) -> void:
	var flying: Array[DuelBlade] = []
	for slot: Fighter in [a, b]:
		if slot.blade.mode == DuelBlade.Mode.FLYING:
			flying.append(slot.blade)
	for record: DuelBlade in flying:
		if record.mode != DuelBlade.Mode.FLYING:
			continue
		var owner := a if a.blade == record else b
		var rect := record.rect(owner.tuning)
		var deflector := _deflector(a, b, rect)
		if deflector != null:
			var away := signf(record.velocity.x)
			record.mode = DuelBlade.Mode.LOOSE
			record.velocity = Vector2(-away * 60.0, -60.0)
			events.append({"kind": "deflect", "by": deflector.id, "at": record.position})
			continue
		for target: Fighter in [a, b]:
			if not target.is_alive() or target.id == record.thrown_by:
				continue
			if _catches(target, record, rect):
				_catch(target, owner, events)
				break
			if not rect.intersects(target.hurt_rect()):
				continue
			var killer := record.thrown_by
			record.mode = DuelBlade.Mode.LOOSE
			record.velocity = Vector2.ZERO
			target.kill(killer)
			events.append({
				"kind": "kill", "victim": target.id, "killer": killer, "at": target.position,
			})
			break


static func _deflector(a: Fighter, b: Fighter, flying: Rect2) -> Fighter:
	for guard: Fighter in [a, b]:
		if guard.is_attacking() and guard.blade_rect().intersects(flying):
			return guard
	return null


## Whether `target`'s open hands take this blade this frame: an empty hand in
## the opening frames of a snatch (Fighter.hands_open), the blade coming at the
## front of the body rather than overtaking it, and the blade inside the hands'
## reach -- which stops above LOW, so a low throw is never caught.
static func _catches(target: Fighter, record: DuelBlade, rect: Rect2) -> bool:
	if not target.hands_open():
		return false
	if int(signf(record.velocity.x)) != -target.facing:
		return false
	return rect.intersects(target.catch_rect())


## The catcher takes the record that was flying, the way a pickup does: the
## two records swap so the count stays two, and the thrower keeps whatever the
## catcher's record held -- the sword the catcher lost earlier, lying wherever
## it fell. The thrower stays empty-handed.
static func _catch(catcher: Fighter, owner: Fighter, events: Array[Dictionary]) -> void:
	var record := owner.blade
	var thrower := record.thrown_by
	var at := record.position
	var height := catcher.position.y - record.position.y
	if owner != catcher:
		owner.blade = catcher.blade
		catcher.blade = record
	record.hold()
	catcher.catch_blade(catcher.tuning.catch_stance(height), thrower)
	events.append({"kind": "catch", "by": catcher.id, "from": thrower, "at": at})


## --- picking a sword back up ------------------------------------------------

## "Standing over a dropped sword and pressing down picks it up in one frame."
##
## Swords are indistinguishable, so taking the other fighter's record swaps the
## two records rather than inventing a third slot: the sword count is conserved
## and the whole of the duel's sword state stays inside the two snapshots.
##
## Slot A is checked first. Two unarmed fighters standing on the same sword and
## both pressing down is a coin toss that has to land the same way on every
## machine, so it lands on A.
static func _resolve_pickups(a: Fighter, b: Fighter, events: Array[Dictionary]) -> void:
	for taker: Fighter in [a, b]:
		if taker.is_armed() or not taker.is_alive() or not taker.is_free():
			continue
		if not taker.input.down:
			continue
		var reach := taker.hurt_rect().grow(2.0)
		for owner: Fighter in [a, b]:
			if not owner.blade.is_loose():
				continue
			if not reach.intersects(owner.blade.rect(owner.tuning)):
				continue
			if owner != taker:
				var mine := taker.blade
				taker.blade = owner.blade
				owner.blade = mine
			taker.blade.hold()
			events.append({"kind": "pickup", "by": taker.id, "at": taker.position})
			break
