class_name GameCamera
extends Camera2D
## Follow camera with a dead zone, facing look-ahead and screen shake — and a
## frame that reacts to what the character is doing.
##
## Prince-of-Persia-style rooms want a camera that is mostly still, so the dead
## zone (Godot's drag margins) means small hops and turn-arounds do not shove
## the whole screen around. Vertical follow tracks the last grounded height so
## jumping does not pan the view.
##
## ## Framing the beat
##
## The base behaviour above is the resting state. Five beats bend it, and the
## whole budget for all five is about thirty pixels:
##
## | Beat | What the frame does | Budget |
## | --- | --- | --- |
## | idle | stops leading, comes to rest on the character | no lead |
## | running | drifts ahead in the direction of travel | `look_ahead` |
## | a long fall | follows down and leads the fall, so the | `FALL_LEAD_MAX` |
## |   | ground arrives before the player does | |
## | a ledge grab | stops leading, lifts onto the ledge taken | `GRAB_LIFT` |
## | a hard landing | settles with the weight of it, recovers | `SETTLE_MAX` |
## | a backstep | holds the lead where it was; dips a pixel | 0.3 x `SETTLE_MAX` |
##
## The rules are static functions below so they can be reasoned about and
## tested without a physics world: `_physics_process` only composes them.
##
## ## What is deliberately not here
##
## **No zoom.** Widening on a fall and tightening on a grab are the obvious
## reach for `Camera2D.zoom`, and on a 320x180 nearest-filtered pixel game they
## are both wrong: a non-integer zoom resamples the tilemap and puts a soft,
## uneven edge on every shadow in the frame, which is the one thing
## `docs/art-direction.md` does not allow. Both beats are framed with offsets
## instead — which is what the player actually needed anyway. Seeing further
## down is a matter of where the frame sits, not how wide it is.
##
## **No rotation, no kick on the roll, no spring overshoot.** If a player
## notices the camera, it is too much.

@export var look_ahead: float = 34.0
@export var look_ahead_smoothing: float = 6.0
@export var vertical_smoothing: float = 7.0

## Retracting the lead is slower than extending it: stopping dead should let
## the frame settle back, not yank it.
const LOOK_BEHIND_SMOOTHING := 2.6
## How much lead a hanging character keeps. Not zero — a sliver of lead toward
## the wall still reads as intent — but most of it comes off.
const GRAB_LEAD_SCALE := 0.3
## How far the frame lifts while hanging, so the ledge about to be mantled is
## in shot rather than at the top edge.
const GRAB_LIFT := 10.0

## A fall is only worth reframing once it is faster than this. Below it, the
## arc of an ordinary jump, and the frame should hold still. Derived from the
## soft-landing threshold rather than picked, so retuning the landings moves
## the camera's idea of "a real fall" with them.
const FALL_LEAD_FROM := Tuning.SOFT_LAND_SPEED * 0.5
## The most the frame leads a fall by. One and a half tiles: enough that the
## landing is visible before it happens, little enough that nobody sees it move.
const FALL_LEAD_MAX := 30.0
const FALL_LEAD_SMOOTHING := 3.2
## How far the character may drop below the resting frame before it follows.
const FALL_SLACK := 8.0

## The dip of a maximum-weight landing, in pixels.
const SETTLE_MAX := 4.0
const SETTLE_DECAY := 13.0

var target: Player

var _look_ahead_current: float = 0.0
var _anchor_y: float = 0.0
var _fall_lead: float = 0.0
var _settle: float = 0.0
var _shake_time: float = 0.0
var _shake_magnitude: float = 0.0
var _shake_offset := Vector2.ZERO


func _ready() -> void:
	position_smoothing_enabled = true
	position_smoothing_speed = 9.0
	drag_horizontal_enabled = true
	drag_left_margin = 0.18
	drag_right_margin = 0.18
	drag_vertical_enabled = false
	ignore_rotation = true


func setup(player: Player, world_size: Vector2) -> void:
	target = player
	limit_left = 0
	limit_top = 0
	limit_right = int(world_size.x)
	limit_bottom = int(world_size.y)
	_anchor_y = player.position.y
	_look_ahead_current = player.facing * look_ahead
	_fall_lead = 0.0
	_settle = 0.0
	_shake_time = 0.0
	_shake_magnitude = 0.0
	_shake_offset = Vector2.ZERO
	offset = Vector2.ZERO
	global_position = Vector2(player.position.x + _look_ahead_current, player.position.y)
	reset_smoothing()


func shake(magnitude: float, duration: float = 0.25) -> void:
	_shake_magnitude = maxf(_shake_magnitude, magnitude)
	_shake_time = maxf(_shake_time, duration)


## The frame drops with the weight of a landing and eases back up. `weight` is
## `Tuning.impact_weight()`, so the dust, the art and the camera all scale off
## the same number and cannot disagree about how hard a landing was.
func settle(weight: float) -> void:
	_settle = maxf(_settle, SETTLE_MAX * clampf(weight, 0.0, 1.0))


## --- the rules -------------------------------------------------------------
##
## Static and pure, so tests/feel_camera_test.gd can pin the behaviour without
## building a level and a physics world to get a character to fall in.

## How much of `look_ahead` to use. Full tilt at a run, nothing at a standstill,
## a sliver while hanging.
static func lead_scale(speed_x: float, hanging: bool) -> float:
	if hanging:
		return GRAB_LEAD_SCALE
	return clampf(absf(speed_x) / Tuning.RUN_SPEED, 0.0, 1.0)


## How far below the character the frame sits on the way down. Zero for an
## ordinary jump arc; it only opens up on a real fall.
static func fall_lead(fall_speed: float, grounded: bool, hanging: bool) -> float:
	if grounded or hanging or fall_speed <= FALL_LEAD_FROM:
		return 0.0
	var span := maxf(1.0, Tuning.MAX_FALL_SPEED - FALL_LEAD_FROM)
	return FALL_LEAD_MAX * clampf((fall_speed - FALL_LEAD_FROM) / span, 0.0, 1.0)


## Where the frame rests vertically.
##
## Grounded, it is the floor the character is standing on, which is what keeps
## a jump from panning the view. On a ladder it is the feet on the rung, up and
## down: a climb is a ledge taken one rung at a time, and a frame that held
## still for it put the prince's head out of the top of a five-tile ladder.
## Hanging, it lifts onto the ledge. Falling, it follows down — with
## `FALL_SLACK` of give, so the drop reads as a drop — and it never follows
## back up, because that is what jumping is.
static func anchor_for(previous: float, foot_y: float, fall_speed: float,
		grounded: bool, hanging: bool, climbing: bool = false) -> float:
	if grounded or climbing:
		return foot_y
	if hanging:
		return foot_y - GRAB_LIFT
	if fall_speed > 0.0:
		return maxf(previous, foot_y - FALL_SLACK)
	return previous


## --- per frame -------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if target == null:
		return

	# A held frame is held: no lead, no follow, no fresh shake. The offset from
	# the frame before stays exactly where it was, so the image is still.
	if Flow.is_hitstopped():
		return

	# is_grounded(), not is_on_floor(): a duel does not use move_and_slide, so
	# the engine's own flag is stale there. This camera never runs in a duel,
	# but the character has one public answer to that question and this is it.
	var grounded := target.is_grounded()
	var hanging := target.is_hanging()
	var fall_speed := target.velocity.y

	var lead_goal := target.facing * look_ahead * lead_scale(target.velocity.x, hanging)
	# A backstep is a step, not travel. The lead is scaled by speed and aimed
	# by facing, and a backstep is the one move that is fast while facing
	# against its motion, so left alone it threw the frame most of a full lead
	# toward the guard and drifted it back over a second -- a lurch on every
	# dodge. The lead holds where it was; the dead zone absorbs the step.
	if target.is_backstepping():
		lead_goal = _look_ahead_current
	# Asymmetric: extending the lead is a decision, retracting it is a settle.
	var toward := (
		look_ahead_smoothing
		if absf(lead_goal) >= absf(_look_ahead_current)
		else LOOK_BEHIND_SMOOTHING
	)
	_look_ahead_current = lerpf(_look_ahead_current, lead_goal, 1.0 - exp(-toward * delta))

	_fall_lead = lerpf(
		_fall_lead,
		fall_lead(fall_speed, grounded, hanging),
		1.0 - exp(-FALL_LEAD_SMOOTHING * delta)
	)
	_anchor_y = anchor_for(_anchor_y, target.position.y, fall_speed, grounded, hanging,
		target.is_climbing())

	var desired := Vector2(target.position.x + _look_ahead_current, _anchor_y + _fall_lead)
	global_position.x = desired.x
	global_position.y = lerpf(
		global_position.y, desired.y, 1.0 - exp(-vertical_smoothing * delta)
	)

	_settle = lerpf(_settle, 0.0, 1.0 - exp(-SETTLE_DECAY * delta))
	_step_shake(delta)
	# Whole pixels: the world is drawn with nearest filtering, so a shake or a
	# settle on a fraction of a pixel is a shimmer rather than a movement.
	offset = (_shake_offset + Vector2(0.0, _settle)).round()


func _step_shake(delta: float) -> void:
	if _shake_time <= 0.0:
		_shake_offset = Vector2.ZERO
		_shake_magnitude = 0.0
		return
	_shake_time -= delta
	var amount := _shake_magnitude * clampf(_shake_time / 0.25, 0.0, 1.0)
	_shake_offset = Vector2(randf_range(-amount, amount), randf_range(-amount, amount))
