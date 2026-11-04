class_name PrinceMoves
extends RefCounted
## The duel's moves as the prince has them: the roll, the dive kick, the sword
## throw, and what is left to him without a sword -- the sweep, and stooping
## for the blade. docs/character.md ("The duel's moves in the adventure")
## argues each one; this file is how they run.
##
## It is the rest of the prince's state machine, in a second file. The states
## are Player.State's, the transitions are entered with Player._enter(), and
## it reaches the player's private helpers (_careful(), _steer(), the jump
## and sword buffers) on purpose: it is a part of the Player, split off
## because one file holds only so much, and so the new moves are one
## additive block that the chapter work going on in player.gd beside it does
## not collide with. Six states: ROLL, DIVE_KICK and its landing KICK_LAND,
## THROW, SWEEP and PICKUP. Nothing outside Player constructs one.
##
## ## Where each move sits on the controls, and why there
##
## - **Roll: down + JUMP, on stone, not at a run.** Down + JUMP already drops
##   through a one-way floor, and that is kept exactly: on a floor of one-way
##   tiles the press drops, and wherever stone is under the feet -- where a
##   drop could not happen and the press used to do nothing -- it rolls. At a
##   run the press stays the jump it always was, because at a run a JUMP is
##   nearly always a gap, and a thumb's stick drifts down: a roll there would
##   stop at the lip and lose the jump. So the roll comes from a stand, a
##   walk or a crouch, toward the stick or the facing.
## - **Dive kick: down + JUMP in the air**, the duel's own pairing. A JUMP in
##   the air did nothing but wait in the buffer, so nothing is taken from it,
##   except in coyote time, where the late jump keeps its press.
## - **Throw: THROW**, the duel's eighth bit, read by every device already.
## - **Pickup: down, standing over the blade**, as in the duel.
##
## None of them is reachable from a parry, a plunge, a backstep or a swing,
## which keep their inputs: tests/unit/test_moves_input.gd plays each pair.

var blade := PrinceBlade.new()

var _player: Player


func _init(player: Player) -> void:
	_player = player


func armed() -> bool:
	return blade.is_held()


## Back in the hand: the respawn's promise, whatever became of the blade.
func rearm() -> void:
	blade.hold()


## --- every frame --------------------------------------------------------------

## Steps the blade, and hears it come home. Before the state machine, so a
## blade back this frame is a sword this frame.
func step(delta: float) -> void:
	if blade.is_held():
		return
	if blade.step(delta, _player.level, hand()):
		_player.rearmed.emit()


## Where the blade leaves the hand and comes back to it.
func hand() -> Vector2:
	return _player.position + Vector2(_player.facing * 5.0, -Tuning.THROW_HEIGHT)


## --- starting a move --------------------------------------------------------

## Called first in Player._free_movement(): a press that starts one of these
## moves takes the frame. True when one started.
func try_start(delta: float, want_x: int, grounded: bool) -> bool:
	var input := _player.input
	if input.just_pressed_throw and blade.is_held():
		_start_throw(delta, want_x, grounded)
		return true
	if input.down and input.just_pressed_jump:
		if not grounded and _can_dive():
			_start_dive_kick()
			return true
		if grounded and _can_roll():
			_start_roll(delta, want_x)
			return true
	if grounded and input.down and not blade.is_held() and _over_blade():
		_player.velocity.x = 0.0
		_player._enter(Player.State.PICKUP)
		blade.hold()
		_player.rearmed.emit()
		return true
	return false


## SWORD with no sword. On the ground a sweep, or the backstep, which is
## footwork and keeps its stick; up + SWORD is spent on nothing, because a
## thumb reaching for the parry must not throw a leg into a cut. In the air,
## nothing, and the press keeps in the buffer as a swing's would.
func start_unarmed(delta: float, want_x: int, grounded: bool) -> bool:
	if not grounded:
		return false
	_player._attack_buffer = 0.0
	if _player.input.up:
		return true
	if _player._reads_backstep(want_x):
		_player._start_backstep(delta)
		return true
	_player.velocity.x = 0.0
	_player._enter(Player.State.SWEEP)
	_player.kicked.emit()
	return true


func _can_dive() -> bool:
	var state := _player.state
	return (state == Player.State.JUMP or state == Player.State.FALL) and _player._coyote <= 0.0


## Stone under the feet, not at a run, and room to stand: the roll keeps the
## standing body's collision shape (below, Player.hurt_rect()).
func _can_roll() -> bool:
	if absf(_player.velocity.x) > Tuning.WALK_SPEED + 1.0 or not _stone_underfoot():
		return false
	_player._set_crouched(false)
	return not _player._crouched


func _stone_underfoot() -> bool:
	var level := _player.level
	if level == null:
		return true
	var half := Tuning.BODY_WIDTH * 0.5
	var x := _player.position.x
	var row := floori((_player.position.y + 1.0) / Player.TILE)
	for column: int in range(floori((x - half) / Player.TILE),
			floori((x + half - 0.001) / Player.TILE) + 1):
		if level.kind_at_cell(Vector2i(column, row)) == Tiles.Kind.SOLID:
			return true
	return false


func _over_blade() -> bool:
	if not blade.is_loose():
		return false
	return _player.body_rect().grow(2.0).intersects(blade.rect())


func _start_roll(delta: float, want_x: int) -> void:
	if want_x != 0:
		_player.facing = want_x
	# The press asked for the roll: spent here, as the drop-through spends it.
	_player._jump_buffer = 0.0
	_player._coyote = 0.0
	_player._enter(Player.State.ROLL)
	_player.velocity.x = _player._careful(_player.facing * Tuning.ROLL_SPEED, delta)
	_player.rolled.emit()


func _start_dive_kick() -> void:
	_player._jump_buffer = 0.0
	_player._enter(Player.State.DIVE_KICK)
	_player.velocity = _dive_velocity()
	_player.kicked.emit()


func _start_throw(delta: float, want_x: int, grounded: bool) -> void:
	# A throw from a crouch stands him up into it, where there is room: the
	# arm goes over the shoulder.
	_player._set_crouched(false)
	_player._enter(Player.State.THROW)
	if not grounded:
		_player._steer(delta, want_x, _player.input.walk, false)


func _dive_velocity() -> Vector2:
	return Vector2(_player.facing * Tuning.DIVE_KICK_DRIFT, Tuning.DIVE_KICK_DROP)


## --- running a move ---------------------------------------------------------

## One frame of whichever of the six states the prince is in. Gravity, the
## move and the landing are Player._update_free()'s, after this.
func update(delta: float, want_x: int, grounded: bool) -> void:
	var p := _player
	var t := p.state_time
	match p.state:
		Player.State.ROLL:
			_update_roll(delta, want_x, grounded)
		Player.State.DIVE_KICK:
			# Committed: no steering, no ledge, a straight line until
			# something stops it.
			p.velocity = _dive_velocity()
		Player.State.THROW:
			if grounded:
				p.velocity.x = move_toward(p.velocity.x, 0.0, Tuning.GROUND_FRICTION * delta)
			else:
				p._steer(delta, want_x, p.input.walk, false)
			if blade.is_held() and t >= Tuning.THROW_RELEASE:
				blade.launch(hand(), p.facing)
				p.threw.emit()
			if t >= Tuning.THROW_TIME:
				_end(grounded)
		Player.State.KICK_LAND:
			_brake(delta)
			if t >= Tuning.DIVE_KICK_RECOVER:
				_end(grounded)
		Player.State.SWEEP:
			_brake(delta)
			if t >= Tuning.SWEEP_TIME:
				_end(grounded)
		Player.State.PICKUP:
			_brake(delta)
			if t >= Tuning.PICKUP_TIME:
				_end(grounded)


## The tuck travels and stops at any lip; the rise stands still, and the
## stick may turn him in it. That turn is what lets a roll that came up
## behind a foe cut his back at once: without it, the stick going back and
## SWORD together read as a backstep (Player._reads_backstep()).
func _update_roll(delta: float, want_x: int, grounded: bool) -> void:
	var p := _player
	if not grounded:
		# The floor went from under it (a slab gave way): a fall, carrying no
		# more speed than a run off the same lip would.
		p.velocity.x = clampf(p.velocity.x, -Tuning.RUN_SPEED, Tuning.RUN_SPEED)
		p._enter(Player.State.FALL)
		return
	if p.state_time < Tuning.ROLL_TUCK:
		p.velocity.x = p._careful(p.facing * Tuning.ROLL_SPEED, delta)
		return
	# The rise is planted: the tuck's speed stops with it, so the roll's
	# ground is Tuning.roll_distance() and nothing more.
	p.velocity.x = 0.0
	if want_x != 0:
		p.facing = want_x
	if p.state_time >= Tuning.ROLL_TIME:
		_end(grounded)


func _brake(delta: float) -> void:
	_player.velocity.x = move_toward(_player.velocity.x, 0.0, Tuning.GROUND_FRICTION * delta)


func _end(grounded: bool) -> void:
	_player._enter(Player.State.IDLE if grounded else Player.State.FALL)


## A dive kick that met the floor. True when it was one.
func on_touch_ground() -> bool:
	if _player.state != Player.State.DIVE_KICK:
		return false
	_player.velocity.x = 0.0
	_player._enter(Player.State.KICK_LAND)
	return true


## --- what the referee asks ----------------------------------------------------

## The body as a foe sees it: tucked to Tuning.ROLL_HEIGHT under a roll, the
## standing (or crouched) body otherwise. The world -- floors, ceilings,
## spikes, water -- always sees body_rect(), the standing body, so a roll
## enters no space and passes no hazard the reachability proof's body does
## not: it is lower only to what is aimed at him.
func hurt_rect() -> Rect2:
	var body := _player.body_rect()
	if not rolling_under():
		return body
	return Rect2(body.position.x, body.end.y - Tuning.ROLL_HEIGHT, body.size.x, Tuning.ROLL_HEIGHT)


## In the tuck: a rollable danger from either side goes over him.
func rolling_under() -> bool:
	return _player.state == Player.State.ROLL and _player.state_time < Tuning.ROLL_TUCK


## The feet, this frame: the dive kick's heel for the whole dive, the sweep's
## leg inside its live window. Empty otherwise.
func strike_rect() -> Rect2:
	var p := _player
	var half := Tuning.BODY_WIDTH * 0.5
	match p.state:
		Player.State.DIVE_KICK:
			var reach := half + Tuning.DIVE_KICK_REACH
			var x := p.position.x if p.facing > 0 else p.position.x - reach
			return Rect2(x, p.position.y - 8.0, reach, 8.0 + Tuning.DIVE_KICK_REACH)
		Player.State.SWEEP:
			if p.state_time < Tuning.SWEEP_FROM or p.state_time > Tuning.SWEEP_TO:
				return Rect2()
			var front := p.position.x + half * p.facing
			var x := front if p.facing > 0 else front - Tuning.SWEEP_REACH
			return Rect2(x, p.position.y - Tuning.SWEEP_HEIGHT, Tuning.SWEEP_REACH,
				Tuning.SWEEP_HEIGHT)
	return Rect2()


## Which blow the feet strike this frame: KICK or SWEEP.
func strike_blow() -> Foe.Blow:
	return Foe.Blow.KICK if _player.state == Player.State.DIVE_KICK else Foe.Blow.SWEEP


## The heel found a foe: up off him as a stomp springs, and back the way it
## came, as a jump the player can steer -- a second kick is a decision, not
## a bounce. A sweep stays on its feet.
func rebound() -> void:
	var p := _player
	if p.state != Player.State.DIVE_KICK:
		return
	p.velocity = Vector2(-p.facing * Tuning.KICK_RECOIL, -Tuning.JUMP_SPEED * Tuning.STOMP_BOUNCE)
	p._enter(Player.State.JUMP)


## The thrown blade reached a foe: it falls from there.
func blade_struck() -> void:
	if blade.is_flying():
		blade.knock_down()
