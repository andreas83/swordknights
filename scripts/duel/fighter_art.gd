class_name FighterArt
extends PlayerArt
## Dresses a duel Fighter in the prince's figure: the hooded robe, the cloak,
## the same rig and the same four tones, posed from the fighter's own states.
##
## It used to draw the fighter as its hitboxes -- the body as the hurtbox, the
## sword as the blade rect -- on the argument that a duel is decided by where
## those rectangles are, so the art that shows them teaches the game. The
## argument survives; the rectangles do not. The blade is still drawn exactly
## where the simulation's blade rect is, at the stance's height and out to its
## reach, and the front hand is put on its hilt. What changed is that it is a
## sword held by a figure, not a grey box beside a red one. The body's figure
## is the prince's, which is 22 px tall like the hurtbox and folds to the
## duck and roll heights the fighter's tuning uses.
##
## `--hitboxes` in the user arguments draws the hurtbox and blade rect over the
## figure, which is how the alignment is checked rather than assumed.
##
## Nothing here is read by the simulation, and nothing here may enter a
## snapshot: it is presentation, and the checksum must never see it.

## Seat one keeps the crimson prince; seat two is sea-green, the colour that is
## player two's and nobody else's (docs/art-direction.md).
##
## These three planes are the seat's whatever figure and look a player chose:
## the setter below runs after a look is put on (dress()) and again when the
## art binds to its fighter, so an outfit can never stand in for a team colour.
## The look's other colours are drawn from steps neither team uses
## (CharacterLook), which is the other half of keeping the seats apart.
const SEAT_CLOTH: Array[Color] = [Palette.CLOTH, Palette.WATER_DEEP]
const SEAT_CLOTH_DARK: Array[Color] = [Palette.CLOTH_DARK, Palette.WATER_SHADE]
const SEAT_CLOAK: Array[Color] = [Palette.SHADOW_DEEP, Palette.WATER_NIGHT]

static var show_hitboxes := OS.get_cmdline_user_args().has("--hitboxes")

var seat := 0:
	set(value):
		seat = value
		var which := absi(value) % 2
		cloth = SEAT_CLOTH[which]
		cloth_dark = SEAT_CLOTH_DARK[which]
		cloak_shade = SEAT_CLOAK[which]

var _fighter: Fighter


## Attaches the art to a fighter, in `look` if one is given (the prince in the
## seat's colours if not). The match may call this, or the scene may carry a
## FighterArt child and set `seat` -- neither changes the simulation: a look is
## a costume and four colours, read by nothing but _draw().
static func dress(fighter: Fighter, which: int, look: CharacterLook = null) -> FighterArt:
	var art := fighter.get_node_or_null("FighterArt") as FighterArt
	if art == null:
		art = FighterArt.new()
		art.name = "FighterArt"
		fighter.add_child(art)
	if look != null:
		look.dress(art)
	# Last, so the seat's colour wins over the look's outfit.
	art.seat = which
	return art


## --- the body ---------------------------------------------------------------

func _bind() -> bool:
	_fighter = get_parent() as Fighter
	if _fighter == null:
		return false
	z_index = 1
	seat = seat
	# `died` is the one fighter signal that rings through a replay, because the
	# match's bookkeeping hangs on it. The flash does not: a figure that flashed
	# once per correction would be telling the player about the network.
	_fighter.died.connect(func(_v: int, _k: int) -> void:
		if not _fighter.replaying:
			_on_died())
	_fighter.disarmed.connect(func(_v: int, _b: int) -> void: _on_hurt(0))
	_fighter.clashed.connect(func(_at: Vector2) -> void: _kick(0.16))
	_fighter.knocked_down.connect(func(_v: int) -> void: _kick(-0.3))
	_fighter.caught.connect(func(_by: int, _from: int) -> void: _kick(-0.22))
	return true


func _has_body() -> bool:
	return _fighter != null


func _body_facing() -> int:
	return _fighter.facing


func _body_motion() -> Vector2:
	var tuning := _fighter.tuning
	return Vector2(
		_fighter.velocity.x * _fighter.facing / tuning.run_speed,
		_fighter.velocity.y / tuning.max_fall_speed
	)


func _speed_share() -> float:
	return absf(_fighter.velocity.x) / _fighter.tuning.run_speed


func _skip_frame() -> bool:
	return false


## The blade is the read. Whenever it is up it is drawn over the robe, and so
## is a blade just caught, which is held up before the face to be seen.
func _blade_in_front() -> bool:
	return _blade_shown() or _fighter.state == Fighter.State.CATCH


func _show_grip() -> bool:
	return false


func _grounded() -> bool:
	return _fighter.grounded or _fighter.state == Fighter.State.DEAD


func _kick(amount: float) -> void:
	_impulse = amount
	_impulse_t = 0.0


## --- poses ------------------------------------------------------------------

func _posture() -> Dictionary:
	var f := _fighter
	var t := float(f.state_frame) / 60.0
	match f.state:
		Fighter.State.IDLE, Fighter.State.DUCKING:
			return _ducked_pose() if _is_ducked() else _guard()
		Fighter.State.RUNNING:
			return _ducked_pose() if _is_ducked() else _run(t)
		Fighter.State.JUMPING:
			return _jump() if f.velocity.y < 0.0 else _drop()
		Fighter.State.THRUSTING:
			return _lunge()
		Fighter.State.ROLLING:
			return _roll()
		Fighter.State.DIVEKICK:
			return _divekick()
		Fighter.State.DISARMED:
			return _reel(t)
		Fighter.State.SWEEP:
			return _sweep()
		Fighter.State.POUND:
			return _pound()
		Fighter.State.DOWNED:
			return _downed()
		Fighter.State.SNATCH:
			return _snatch()
		Fighter.State.CATCH:
			return _catch()
		Fighter.State.DEAD:
			return _dead(t)
	return _guard()


func _is_ducked() -> bool:
	return _fighter.is_free() and _fighter.posture() == DuelTuning.DUCKED


## Planted and square to the opponent, weight forward. The front hand is moved
## onto the hilt in _rig(); the pose only has to make room for it.
func _guard() -> Dictionary:
	var breath := sin(_time * 2.4)
	return _pose({
		"squash": 0.98 + breath * 0.012,
		"bob": breath * 0.2,
		"lean": 0.9,
		"stance": 1.5,
		"knee": -0.6,
		"hem_spread": 0.8,
		"hood_tilt": 0.1,
		"arm_b": 1.65, "arm_b_len": 5.4,
		"cloak_sweep": 0.7 - breath * 0.2,
	})


## The fighter's duck folds the body down to its duck height, hood and all
## intact, which is the prince's crouch at the fighter's own numbers.
func _ducked_pose() -> Dictionary:
	var tuning := _fighter.tuning
	return _pose({
		"sink": tuning.body_height - tuning.duck_height,
		"lean": 1.2,
		"stance": 1.6,
		"knee": -1.2,
		"hem_lift": -0.8,
		"hem_spread": 2.0,
		"hood_tilt": 0.3,
		"arm_b": 1.3, "arm_b_len": 4.8,
		"cloak_sweep": 0.8, "cloak_rise": -0.4, "cloak_flare": 1.2,
	})


## Coming down: legs reaching for the floor, cloth streaming up.
func _drop() -> Dictionary:
	return _pose({
		"squash": 1.04,
		"lean": 1.0,
		"stride": 1.2,
		"knee": 1.6,
		"stance": 0.9,
		"hem_lift": 3.0,
		"hem_fwd": -0.8,
		"arm_b": 1.0, "arm_b_len": 6.0,
		"cloak_sweep": 1.6, "cloak_rise": 2.2, "cloak_flare": 1.1,
	})


## The thrust. Everything goes forward at once on the live frames -- front foot,
## shoulders, hood -- and comes back over the recovery, so the commitment is
## visible: a fighter still leaning in is a fighter that missed.
func _lunge() -> Dictionary:
	var tuning := _fighter.tuning
	var frame := _fighter.state_frame
	var live := frame <= tuning.thrust_active
	var back := 0.0 if live else float(frame - tuning.thrust_active) \
		/ float(maxi(1, tuning.thrust_frames - tuning.thrust_active))
	var reach := 1.0 - back
	return _pose({
		"squash": 0.96,
		"lean": lerpf(1.0, 4.2, reach),
		"stride": lerpf(0.6, 3.6, reach),
		"stance": 1.3,
		"knee": -0.8 * reach,
		"hem_lift": 2.0 * reach,
		"hem_fwd": 1.4 * reach,
		"hem_spread": 1.2,
		"hood_tilt": 0.2 + 0.15 * reach,
		"hood_push": 0.8 * reach,
		"arm_b": lerpf(1.6, 2.6, reach), "arm_b_len": 5.6,
		"cloak_sweep": lerpf(0.8, 2.8, reach), "cloak_rise": 1.2 * reach,
		"cloak_flare": 1.15,
		# Recovery: the blade is no longer up, so _draw_weapon() falls back to
		# this angle -- point lowered and forward, the arm still out. A fighter
		# who missed has to be SEEN to be open, and an empty hand would hide it.
		"arm_a": 0.7, "arm_a_len": 6.0,
		"blade": 0.75, "blade_len": 9.0,
	})


## A forward roll: head tucked, going over the shoulder.
##
## Folding the figure down to the roll's 7 px does not work: the hood keeps its
## size by design, so a deep sink pushes the hips below the feet and the figure
## sinks through the floor. Pitching it forward does what a roll does -- the
## head goes forward and down, the back comes up -- and keeps everything above
## the ground and low, inside the roll's hurtbox height.
func _roll() -> Dictionary:
	var tuning := _fighter.tuning
	var spin := float(_fighter.state_frame) / float(maxi(1, tuning.roll_frames))
	return _pose({
		"sink": 6.0,
		"squash": 0.78,
		"lean": 1.0,
		"tilt": 0.8 + 0.2 * sin(spin * PI),
		"stance": 0.4,
		"knee": 3.0,
		"hem_lift": 3.0,
		"hem_spread": 1.2,
		"hood_tilt": 0.7,
		"arm_a": 1.9, "arm_a_len": 4.4,
		"arm_b": 2.2, "arm_b_len": 4.0,
		"cloak_sweep": 1.2, "cloak_rise": 2.0, "cloak_flare": 0.8,
		"blade": 3.0, "blade_len": 7.0,
	})


## Heel first, body behind it, everything committed to the line of the kick.
func _divekick() -> Dictionary:
	return _pose({
		"squash": 1.04,
		"lean": -1.0,
		"tilt": 0.55,
		"stride": 4.2,
		"knee": -1.6,
		"stance": 0.4,
		"hem_lift": 5.0,
		"hem_fwd": -2.0,
		"hood_tilt": -0.2,
		"arm_b": -0.6, "arm_b_len": 5.6,
		"cloak_sweep": 3.0, "cloak_rise": -2.0, "cloak_flare": 1.2,
		"blade": 3.6, "blade_len": 8.0,
	})


## The sword is gone: rocked back, hands open.
func _reel(t: float) -> Dictionary:
	var shake := sin(t * 40.0) * maxf(0.0, 0.2 - t) * 4.0
	return _pose({
		"lean": -1.4 + shake,
		"stance": 1.2,
		"hood_tilt": -0.25,
		"arm_a": -0.5, "arm_a_len": 5.8,
		"arm_b": -0.2, "arm_b_len": 5.4,
		"cloak_sweep": -0.6, "cloak_flare": 1.2,
	})


## One leg scything out along the floor in front.
##
## Only half crouched, on purpose: the sweep keeps the fighter's full-height
## hurtbox, so a figure folded down to duck height would show an empty space
## where a high thrust still kills. The leg goes low; the body stays where it
## can be hit.
func _sweep() -> Dictionary:
	return _pose({
		"sink": 3.0,
		"lean": -0.6,
		"stride": 10.0,
		"knee": -3.0,
		"stance": 0.6,
		"hem_lift": 3.0,
		"hem_spread": 2.4,
		"hood_tilt": 0.35,
		"arm_a": 2.0, "arm_a_len": 5.0,
		"arm_b": 2.4, "arm_b_len": 5.0,
		"cloak_sweep": 1.6, "cloak_flare": 1.3,
	})


## Knocked down and sitting back, knees up, inside the small hurtbox a downed fighter
## has. Not the dead pose: a body laid out flat would reach far past the box,
## and a downed fighter is about to get up -- or be pounded.
func _downed() -> Dictionary:
	return _pose({
		# Folded down, then lifted so the hips -- and the hem, which never rides
		# above them -- stay on the floor rather than in it.
		"sink": 8.0,
		"bob": -3.0,
		"squash": 0.74,
		"lean": -0.4,
		"tilt": -0.35,
		"stance": 0.6,
		"knee": 3.4,
		"hem_lift": 3.0,
		"hood_tilt": -0.3,
		"arm_a": 2.6, "arm_a_len": 4.6,
		"arm_b": 2.9, "arm_b_len": 4.4,
		"cloak_sweep": -0.6, "cloak_rise": -0.6, "cloak_flare": 0.9,
		"blade": 3.3, "blade_len": 8.0,
		"glint": 0.3,
	})


## Knees driven straight down.
func _pound() -> Dictionary:
	return _pose({
		"squash": 0.86,
		"lean": 0.2,
		"stride": 0.4,
		"knee": 3.8,
		"stance": 0.5,
		"hem_lift": 4.0,
		"hood_tilt": 0.4,
		"arm_a": -1.2, "arm_a_len": 5.8,
		"arm_b": -1.4, "arm_b_len": 5.6,
		"cloak_sweep": 0.4, "cloak_rise": 3.0, "cloak_flare": 1.2,
	})


## Both hands out in front of the chest, open, weight forward onto the front
## foot: the snatch. The hands sit inside the simulation's catch rect -- from
## the face down to the bottom of MID and a few pixels past the body -- so a
## blade seen arriving at them is a blade that will be caught. Over the
## recovery they sag and the body settles back, and a fighter still standing
## there with empty hands half-raised is SEEN to have snatched at nothing, as a
## missed thrust is.
func _snatch() -> Dictionary:
	var tuning := _fighter.tuning
	var frame := _fighter.state_frame
	var back := 0.0 if frame <= tuning.catch_window else float(frame - tuning.catch_window) \
		/ float(maxi(1, tuning.snatch_frames - tuning.catch_window))
	var reach := 1.0 - clampf(back, 0.0, 1.0)
	return _pose({
		"squash": 0.97,
		"lean": lerpf(0.2, 1.6, reach),
		"stride": lerpf(0.8, 2.2, reach),
		"stance": 1.5,
		"knee": -0.9,
		"hem_spread": 1.2,
		"hem_fwd": 0.6 * reach,
		"hood_tilt": lerpf(0.3, -0.1, reach),
		"hood_push": 0.4 * reach,
		"arm_a": lerpf(1.25, 0.2, reach), "arm_a_len": 6.6,
		"arm_b": lerpf(1.5, 0.35, reach), "arm_b_len": 6.2,
		"cloak_sweep": lerpf(0.7, 1.4, reach), "cloak_flare": 1.15,
	})


## The catch: the blade pulled in and stood up point-first before the face, the
## body rocked back on its heels by the weight of it arriving, the edge flashing
## on the first frames. Held for catch_settle frames, which is exactly how long
## the simulation keeps the new blade out of play -- so the pose is the window.
func _catch() -> Dictionary:
	var tuning := _fighter.tuning
	var settle := float(_fighter.state_frame) / float(maxi(1, tuning.catch_settle))
	var jolt := 1.0 - clampf(settle, 0.0, 1.0)
	return _pose({
		"squash": 1.0 - 0.04 * jolt,
		"lean": lerpf(0.4, -1.2, jolt),
		"stance": 1.6,
		"knee": -0.7,
		"hem_spread": 1.0,
		"hem_fwd": -0.8 * jolt,
		"hood_tilt": -0.2 * jolt,
		# The front hand where the blade was taken: up by the face for a HIGH
		# catch, before the chest for a MID one. The held stance is the height.
		"arm_a": -1.05 if _fighter.stance == DuelTuning.Stance.HIGH else -0.55,
		"arm_a_len": 5.0,
		"arm_b": 0.6, "arm_b_len": 4.8,
		"cloak_sweep": lerpf(0.7, -0.3, jolt), "cloak_rise": 0.8 * jolt, "cloak_flare": 1.25,
		"blade": -1.3, "blade_len": 9.0,
		"blade_hot": 1.0 if _fighter.state_frame <= 2 else 0.0,
	})


## --- the blade --------------------------------------------------------------

## The simulation's blade rect in this node's space, or an empty rect.
func _blade_local() -> Rect2:
	var rect := _fighter.blade_rect()
	if rect.size == Vector2.ZERO:
		return rect
	return Rect2(rect.position - _fighter.position, rect.size)


func _blade_shown() -> bool:
	return _blade_local().size != Vector2.ZERO


## Puts the front hand on the hilt of the blade that is actually there.
func _rig(pose: Dictionary) -> void:
	super._rig(pose)
	var blade := _blade_local()
	if blade.size == Vector2.ZERO:
		return
	_hand_front = _hilt(blade)


func _hilt(blade: Rect2) -> Vector2:
	var near := blade.position.x if _fighter.facing > 0 else blade.end.x
	return Vector2(near, blade.position.y + blade.size.y * 0.5)


## The sword the simulation is holding up, drawn along its own rect: from the
## hilt at the body's edge to the tip at the reach, at the stance's height. When
## the blade is held but not up -- a roll, a dive, a recovery -- it is the
## prince's sword, carried along the pose's angle. When it is not held at all,
## it is not drawn here; _draw() draws it where it lies.
func _draw_weapon(pose: Dictionary) -> void:
	var blade := _blade_local()
	if blade.size == Vector2.ZERO:
		if _fighter.is_armed():
			super._draw_weapon(pose)
		else:
			blade_hot = 0.0
		return

	var hilt := _hilt(blade)
	var along := float(_fighter.facing)
	var tip := Vector2(hilt.x + along * blade.size.x, hilt.y)
	var thick := clampf(blade.size.y * 0.5, 1.0, 1.8)
	var hot := _fighter.is_attacking()
	blade_tip = tip
	blade_hot = 1.0 if hot else 0.0

	var point := tip
	var shoulder := Vector2(tip.x - along * 2.4, hilt.y)
	draw_colored_polygon(PackedVector2Array([
		Vector2(hilt.x, hilt.y - thick * 0.5), Vector2(shoulder.x, hilt.y - thick * 0.5),
		point, Vector2(shoulder.x, hilt.y + thick * 0.5),
		Vector2(hilt.x, hilt.y + thick * 0.5),
	]), Palette.STEEL)
	# The edge the sun catches: the top of the blade, gold on a live thrust.
	draw_rect(Rect2(minf(hilt.x, shoulder.x), hilt.y - thick * 0.5,
		absf(shoulder.x - hilt.x), 0.6), Palette.LIGHT_SOFT if hot else Palette.STEEL_DARK)
	# Crossguard, upright, so the stance's height reads even at rest.
	draw_rect(Rect2(hilt.x - 0.7, hilt.y - 2.2, 1.4, 4.4), Palette.LIGHT_WARM)


## --- drawing ----------------------------------------------------------------

func _draw() -> void:
	if not _has_body():
		return
	super._draw()
	_draw_open_hands()
	_draw_loose()
	if show_hitboxes:
		_draw_hitboxes()


## Two open palms on the live frames of a snatch, fingers up: the read that the
## hands are ready, and the one thing that tells a snatch from a reel at a
## glance. Gone the frame the window closes, as the catch rect is.
func _draw_open_hands() -> void:
	if not _fighter.hands_open():
		return
	for hand: Vector2 in [_hand_back, _hand_front]:
		draw_rect(Rect2(hand.x - 0.9, hand.y - 2.2, 1.8, 2.8), _c(ink))
		draw_rect(Rect2(hand.x - 0.9, hand.y - 2.2, 1.8, 0.7), Palette.LIGHT_SOFT)


## A sword that is not in a hand: flying, or on the floor. Drawn along the
## loose blade rect the simulation resolves pickups and hits against.
func _draw_loose() -> void:
	var blade := _fighter.blade
	if blade.is_held():
		return
	var rect := blade.rect(_fighter.tuning)
	var local := Rect2(rect.position - _fighter.position, rect.size)
	var flying := blade.mode == DuelBlade.Mode.FLYING
	var mid := local.position.y + local.size.y * 0.5
	draw_rect(Rect2(local.position.x, mid - 0.7, local.size.x, 1.4),
		Palette.PAPER if flying else Palette.STEEL)
	draw_rect(Rect2(local.position.x, mid - 0.7, local.size.x, 0.5), Palette.STEEL_DARK)
	var guard_x := local.position.x + local.size.x * (0.2 if blade.velocity.x >= 0.0 else 0.8)
	draw_rect(Rect2(guard_x - 0.6, mid - 1.8, 1.2, 3.6), Palette.LIGHT_WARM)


func _draw_hitboxes() -> void:
	var origin := _fighter.position
	var body := _fighter.hurt_rect()
	if body.size != Vector2.ZERO:
		draw_rect(Rect2(body.position - origin, body.size), Palette.PAPER, false, 0.5)
	var blade := _fighter.blade_rect()
	if blade.size != Vector2.ZERO:
		draw_rect(Rect2(blade.position - origin, blade.size), Palette.LIGHT, false, 0.5)
	var strike := _fighter.strike_rect()
	if strike.size != Vector2.ZERO:
		draw_rect(Rect2(strike.position - origin, strike.size), Palette.WATER, false, 0.5)
	var hands := _fighter.catch_rect()
	if hands.size != Vector2.ZERO:
		draw_rect(Rect2(hands.position - origin, hands.size), Palette.LIGHT_WARM, false, 0.5)
