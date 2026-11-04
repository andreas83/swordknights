class_name PrinceHands
extends RefCounted
## The prince on his hands: the ledge grab, the hang, the mantle, the ladder
## and the leap off it -- every state in which the feet are not what holds
## him up.
##
## It is part of the Player, split off along the one seam in its state machine
## that is a different kind of body rather than a different move: everywhere
## else the prince stands, runs, falls or fights on his feet and move_and_slide
## carries him, and here he is put where his hands are -- snapped to a corner,
## lerped up a mantle, walked up rungs at the ladder's own speed. Like
## PrinceMoves it reaches the player's private helpers (_height(), _enter(),
## _move(), the jump buffer, the ladder lockout) on purpose, and nothing
## outside Player constructs one. The states are Player.State's: HANG,
## CLIMB_UP and LADDER, dispatched from Player._physics_process(); the grab is
## asked for by Player._resolve_air_state() on every falling frame, which is
## why a hazard narrower than grab reach is no hazard (CLAUDE.md).
##
## The reachability proof copies the grab and the mantle step for step
## (scripts/levels/reachability.gd), so a change here is a change there.

## Where a mantle starts and ends, and how far along it is.
var _climb_from := Vector2.ZERO
var _climb_to := Vector2.ZERO
var _climb_progress := 0.0

var _p: Player


func _init(player: Player) -> void:
	_p = player


## --- ledges ----------------------------------------------------------------

## Looks for a corner at hand height in the facing direction. The player has to
## be falling (not too fast) and not pushing down, which keeps grabs
## intentional rather than sticky. Because it is a geometry probe and not a
## trigger volume, every corner in every level is grabbable without authoring.
func grab_ledge() -> void:
	var level := _p.level
	if level == null or _p.velocity.y > Tuning.MAX_GRAB_FALL_SPEED or _p.input.down:
		return

	var direction := _p.input.axis_x if _p.input.axis_x != 0 else _p.facing
	var half := Tuning.BODY_WIDTH * 0.5
	var hand_x := _p.position.x + (half + Tuning.GRAB_REACH) * direction
	var top_y := _p.position.y - _p._height()
	var cell := level.cell_of(Vector2(hand_x, top_y + Tuning.GRAB_PROBE_Y))

	# A grabbable ledge is a solid tile with nothing solid directly on top.
	if not level.is_solid_cell(cell) or level.is_solid_cell(cell + Vector2i.UP):
		return

	var ledge_top := float(cell.y) * Player.TILE
	var hang_feet_y := ledge_top - Tuning.GRAB_PROBE_Y + _p._height()
	var hang_x := cell.x * Player.TILE - half if direction > 0 \
		else (cell.x + 1) * Player.TILE + half

	var hang_rect := Rect2(hang_x - half, hang_feet_y - _p._height(), Tuning.BODY_WIDTH,
		_p._height())
	if level.rect_hits_solid(hang_rect):
		return

	_p.position = Vector2(hang_x, hang_feet_y)
	_p.velocity = Vector2.ZERO
	_p.facing = direction
	_p._enter(Player.State.HANG)
	_p.grabbed_ledge.emit()


func hang() -> void:
	_p.velocity = Vector2.ZERO
	if _p.state_time < Tuning.HANG_HOLD_TIME:
		return

	if _p.input.down:
		_p.velocity.y = 20.0
		_p._enter(Player.State.FALL)
		return

	if not (_p.input.up or _p._jump_buffer > 0.0):
		return
	_p._jump_buffer = 0.0

	var ledge_top := _p.position.y - _p._height() + Tuning.GRAB_PROBE_Y
	var target := Vector2(_p.position.x + Player.TILE * 0.5 * _p.facing, ledge_top)

	var stand_rect := Rect2(
		target.x - Tuning.BODY_WIDTH * 0.5, target.y - _p._height(),
		Tuning.BODY_WIDTH, _p._height()
	)
	if _p.level != null and _p.level.rect_hits_solid(stand_rect):
		_p._enter(Player.State.FALL) # no room to stand up — let go rather than clip in
		return

	_climb_from = _p.position
	_climb_to = target
	_climb_progress = 0.0
	_p._enter(Player.State.CLIMB_UP)


func climb_up(delta: float) -> void:
	_climb_progress = clampf(_climb_progress + delta / Tuning.CLIMB_UP_TIME, 0.0, 1.0)
	# Up first, then across: the classic mantle arc.
	var vertical := minf(1.0, _climb_progress * 1.6)
	var horizontal := maxf(0.0, (_climb_progress - 0.45) / 0.55)
	_p.position = Vector2(
		lerpf(_climb_from.x, _climb_to.x, horizontal),
		lerpf(_climb_from.y, _climb_to.y, vertical)
	)
	if _climb_progress >= 1.0:
		_p.velocity = Vector2.ZERO
		_p._enter(Player.State.IDLE)


## --- ladders ---------------------------------------------------------------

func ladder(delta: float) -> void:
	if _p.level == null or not _p.level.rect_is_climbable(_p.body_rect()):
		_p._enter(Player.State.FALL)
		return

	# Before moving, so the frame the thumb taps JUMP is a leap, not a rung.
	if _p._jump_buffer > 0.0:
		leap_off_ladder()
		return

	var input := _p.input
	_p.velocity = Vector2(input.axis_x * Tuning.WALK_SPEED * 0.5,
		input.axis_y * Tuning.LADDER_SPEED)
	if input.axis_x != 0:
		_p.facing = input.axis_x
	_p._move(delta)


## Leaves the rungs with a jump: sideways at full stride when a direction is
## held, straight up off the rungs when none is. The sideways leap takes the
## run's speed rather than the ladder's half-walk shuffle, because a jump that
## drifts off a ladder at 20 px/s is still on the ladder when it lands.
##
## Either way the hands are kept off every ladder for LADDER_REGRAB_TIME. A
## ladder jump existed before this, and on a phone it did nothing: the stick
## was still pushed up when JUMP was tapped, and on the very next frame
## Player._free_movement() saw a vertical input over a ladder and put the
## prince back on it. The lockout is what makes the jump a jump.
func leap_off_ladder() -> void:
	var input := _p.input
	_p._jump_buffer = 0.0
	_p._ladder_lockout = Tuning.LADDER_REGRAB_TIME
	var stride := Tuning.WALK_SPEED if input.walk else Tuning.RUN_SPEED
	_p.velocity = Vector2(input.axis_x * stride,
		-Tuning.JUMP_SPEED * Tuning.LADDER_JUMP_SCALE)
	if input.axis_x != 0:
		_p.facing = input.axis_x
	_p._enter(Player.State.JUMP)
	_p.jumped.emit()
