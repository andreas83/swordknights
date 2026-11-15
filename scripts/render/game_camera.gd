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
## The base behaviour above is the resting state. Seven beats bend it; they
## never overlap in time except a settle on top of one other, so the budget is
## the largest of them plus the settle, not their sum:
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
## | at a lip | standing or walking up to a drop, looks down at the floor | `peek_max()` |
## |   | it lands on, so the landing is in shot before the jump | |
## | under a ledge | facing a wall a jump can grab the top of, looks up | `lift_max()` |
## |   | until its lip is in shot | |
##
## The rules are static functions below so they can be reasoned about and
## tested without a physics world: `_physics_process` only composes them.
##
## ## A fixed 1.5x
##
## The camera stands at `ZOOM` and never moves off it. The owner's call: at
## 1:1 the 22-unit figure filled an eighth of the screen's height, which on a
## phone at arm's length is a figure you squint at; at 1.5x it fills nearly a
## fifth, and the view is 120 world units tall instead of the viewport's 180.
## The viewport itself stays 180 units (`tools/configure_project.gd`), so the
## HUD, the touch controls and the sky, which live on CanvasLayers, are drawn
## exactly as before: only the world comes closer.
##
## This used to argue for no zoom at all, on the grounds that a non-integer
## zoom resamples the nearest-filtered tilemap and softens every shadow edge
## (`docs/art-direction.md`). That holds for a zoom against the texels, and
## 1.5 is not one: the 2D is stretched with `canvas_items`/`keep_height`, so
## the tilemap is already drawn at window_height / 180 screen pixels a unit,
## and 1.5x takes that product -- not the 1.5 -- to the screen. It stays a
## whole number on the common desktop heights (720 -> 6, 1080 -> 9,
## 1440 -> 12), and on a phone where window_height / 180 is already
## fractional it is no worse in kind than 1:1 was.
##
## What still holds is the rest of that argument: **no dynamic zoom.**
## Widening on a fall and tightening on a grab are the obvious reach for
## `Camera2D.zoom`, and both are wrong: a scale that moves passes through
## every fraction on the way, and the frame would shimmer as it breathed.
## Both beats are framed with offsets instead -- which is what the player
## actually needed anyway. Seeing further down is a matter of where the frame
## sits, not how wide it is. `tests/feel_camera_test.gd` reads the source and
## fails on any second write to `zoom`.
##
## Every number below is in world units and zooms with the world, on purpose:
## the lead, the lift, the fall lead, the settle and the shake are each sized
## against the body and the tile they frame, and a closer camera shows the
## same film larger rather than a different one. The look-ahead was checked
## against the narrowest screen the game runs on, 4:3 landscape: 160 x 120
## world units at 1.5x, so a full lead plus the dead zone puts the prince 48
## units off centre, still 32 inside the trailing edge. What 1.5x costs is
## height: centred on the feet, the frame shows 60 units above and below them
## where it showed 90, so a four-tile ledge's lip was out of shot from the
## floor and a drop past three tiles landed out of frame at take-off. The two
## beats below answer that, which is what keeps the campaign's "No blind
## jumps" true at 1.5x.
##
## ## Looking where the jump goes
##
## A static frame cannot show both a four-tile ledge above and a five-tile
## drop below inside 120 units, and it does not need to: a player only needs
## the one in front of them. So the frame reads the level a step or two ahead
## of the feet (`LOOK_TILES`), and only while the character stands or walks:
##
## - **At a lip**, it measures the drop to whatever stops a fall -- floor,
##   one-way floor, spikes or water, since a pit is a landing too -- and
##   lowers the frame just far enough to put that surface in shot
##   (`peek_for_drop()`). Never further than leaves the head in shot
##   (`peek_max()`): the deepest the rule allows, five tiles, needs 26 of the
##   34 that leaves.
## - **Under a ledge** -- a wall in front whose top a jump can still grab,
##   `Tuning.grab_tiles()` -- it raises the frame until the lip is in shot
##   (`lift_for_rise()`); a three-tile ledge already is.
##
## Both read the level's real tiles, so a level is framed by what it is and
## not by a tag an author has to remember. Both ease in and out on the
## simulation's clock like the rest of the frame, and both stop the moment the
## feet leave the floor: in the air the fall lead and the grab lift take over,
## and a frame that kept peeking under a jump would fight them.
##
## ## What is deliberately not here
##
## **No rotation, no kick on the roll, no spring overshoot.** If a player
## notices the camera, it is too much.

## The camera's one and only scale (see "A fixed 1.5x" above).
const ZOOM := 1.5

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

## How far ahead of the feet, in tiles, the frame looks for a lip or a ledge:
## two, the stride at which a running player decides to jump.
const LOOK_TILES := 2
## How far down a drop is measured before it counts as bottomless, in tiles.
const DROP_DEPTH_MAX := 8
## How much of a landing surface, or a ledge's lip, the frame wants in shot
## beyond the line itself: a sliver of the tile, so a floor reads as a floor.
const SURFACE_MARGIN := 6.0
## Room left over the head when the frame looks down.
const HEAD_ROOM := 4.0
const LOOK_SMOOTHING := 4.0
## What stops a fall, and so is the bottom of a drop.
const DROP_BOTTOMS: Array[int] = [
	Tiles.Kind.SOLID, Tiles.Kind.PLATFORM, Tiles.Kind.SPIKES, Tiles.Kind.WATER,
]

var target: Player

var _look_ahead_current: float = 0.0
var _anchor_y: float = 0.0
var _fall_lead: float = 0.0
var _settle: float = 0.0
## The look at a lip (+, down) or under a ledge (-, up), eased.
var _look_y: float = 0.0
var _shake_time: float = 0.0
var _shake_magnitude: float = 0.0
var _shake_offset := Vector2.ZERO


## Set once, at construction, and never again: the scale is a fact of the
## Adventure, not a beat of the frame, and a camera that exists is already at
## it -- before it enters a tree, which a test building one by hand may never
## let it finish doing.
func _init() -> void:
	zoom = Vector2.ONE * ZOOM


func _ready() -> void:
	# Smoothed on the simulation's clock, not the display's. The frame is a
	# rule of play -- a foe acts only while the camera shows it (CameraView)
	# -- so where it is has to be a fact of the physics step. Smoothed per
	# rendered frame, it was a function of the frame rate: the same input
	# played on a faster display, or in a test run faster than the wall
	# clock, put the frame elsewhere, a cat saw the prince a frame sooner,
	# and a frozen clear run took a scratch it never took at 60 fps
	# (tests/unit/test_campaign_run.gd found it). Everything the frame
	# follows moves on the physics step anyway, so the image loses nothing.
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
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
	_look_y = 0.0
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


## Half of what the frame shows, top to bottom, in world units.
static func half_shown() -> float:
	return 180.0 / ZOOM * 0.5


## The furthest the frame may look down: what leaves the head in shot.
static func peek_max() -> float:
	return half_shown() - Tuning.BODY_HEIGHT - HEAD_ROOM


## The furthest the frame may look up: what puts the lip of the tallest ledge
## a jump can grab in shot. Derived from the jump, like the ledge itself.
static func lift_max() -> float:
	return maxf(0.0, Tuning.grab_tiles() * Tuning.TILE + SURFACE_MARGIN - half_shown())


## How far down to look for a drop of `tiles`: just enough to put its bottom
## in shot, never past `peek_max()`. Zero for no drop.
static func peek_for_drop(tiles: int) -> float:
	if tiles <= 0:
		return 0.0
	var wanted := tiles * Tuning.TILE + SURFACE_MARGIN - half_shown()
	return clampf(wanted, 0.0, peek_max())


## How far up to look at a ledge `tiles` tall: just enough to put its lip in
## shot. Zero for a wall too tall to grab, which is a wall, not a ledge.
static func lift_for_rise(tiles: int) -> float:
	if tiles <= 0 or tiles > Tuning.grab_tiles():
		return 0.0
	return clampf(tiles * Tuning.TILE + SURFACE_MARGIN - half_shown(), 0.0, lift_max())


## What lies ahead of feet standing in `foot_cell`, facing `facing`, read
## through `kind_at` (cell -> Tiles.Kind): a drop as a positive depth in
## tiles, a grabbable-or-taller wall as a negative height, or 0 for neither
## within `LOOK_TILES`. The first thing met decides: a wall in front of a lip
## hides the lip.
static func ahead(kind_at: Callable, foot_cell: Vector2i, facing: int) -> int:
	var floor_row := foot_cell.y + 1
	for step: int in range(1, LOOK_TILES + 1):
		var x := foot_cell.x + facing * step
		if int(kind_at.call(Vector2i(x, foot_cell.y))) == Tiles.Kind.SOLID:
			var height := 1
			while height < DROP_DEPTH_MAX \
					and int(kind_at.call(Vector2i(x, foot_cell.y - height))) == Tiles.Kind.SOLID:
				height += 1
			return -height
		for depth: int in DROP_DEPTH_MAX:
			if int(kind_at.call(Vector2i(x, floor_row + depth))) in DROP_BOTTOMS:
				if depth > 0:
					return depth
				break
			if depth == DROP_DEPTH_MAX - 1:
				return DROP_DEPTH_MAX
	return 0


## The look for what `ahead()` found: down for a drop, up for a ledge.
static func look_for(found: int) -> float:
	if found > 0:
		return peek_for_drop(found)
	if found < 0:
		return -lift_for_rise(-found)
	return 0.0


## The centre of the frame as play reads it (CameraView): where the camera
## holds, without the shake or the settle laid over the image. A shake is
## random and a settle is a beat of feel; neither may decide whether a foe
## sees the prince.
func frame_centre() -> Vector2:
	return get_screen_center_position() - offset


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
	_look_y = lerpf(_look_y, _look_goal(grounded and not hanging),
		1.0 - exp(-LOOK_SMOOTHING * delta))

	var desired := Vector2(target.position.x + _look_ahead_current,
		_anchor_y + _fall_lead + _look_y)
	global_position.x = desired.x
	global_position.y = lerpf(
		global_position.y, desired.y, 1.0 - exp(-vertical_smoothing * delta)
	)

	_settle = lerpf(_settle, 0.0, 1.0 - exp(-SETTLE_DECAY * delta))
	_step_shake(delta)
	# Whole pixels: the world is drawn with nearest filtering, so a shake or a
	# settle on a fraction of a pixel is a shimmer rather than a movement.
	offset = (_shake_offset + Vector2(0.0, _settle)).round()


## Where the frame wants to look this step: at a lip or under a ledge while
## the feet are on the floor, nowhere otherwise.
func _look_goal(standing: bool) -> float:
	if not standing or target.level == null:
		return 0.0
	var level := target.level
	var feet := level.cell_of(target.position + Vector2(0.0, -1.0))
	return look_for(ahead(level.kind_at_cell, feet, target.facing))


func _step_shake(delta: float) -> void:
	if _shake_time <= 0.0:
		_shake_offset = Vector2.ZERO
		_shake_magnitude = 0.0
		return
	_shake_time -= delta
	var amount := _shake_magnitude * clampf(_shake_time / 0.25, 0.0, 1.0)
	_shake_offset = Vector2(randf_range(-amount, amount), randf_range(-amount, amount))
