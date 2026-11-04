class_name MatchFraming
extends RefCounted
## How close the duel's camera stands, as a model with no screen and no match.
##
## The owner played the duel on a phone and liked the adventure's framing
## better: a fighter 8.5% of the screen's height reads, but it reads small.
## The adventure frames 180 world pixels tall, which puts the same body at 12%.
## The duel cannot simply adopt that, because the one thing the mode cannot
## lose is the other fighter -- a zone is 480 px and the adventure's frame is
## 320 to 440 wide. So the frame breathes: as close as the adventure while the
## two are near each other, out to the old framing as they separate.
##
## Kept apart from MatchCamera, and pure, for the reason GameCamera keeps its
## beats in static functions: "what does the frame do when they close to the
## edge, one lunges, and the other dies" has to be argued about and tested
## without standing a match in front of a window. The camera feeds this the
## fighters and the clock, and puts the answer on the screen.
##
## ## The unit is a whole screen pixel per texel
##
## A level is a whole number of screen pixels per world pixel. The far level
## is the old rule (FIGHTER_SHARE, rounded); the close level is the
## adventure's scale, rounded DOWN so the duel is never closer than the
## adventure -- 6 at 1080 px tall, 6 at 1170 (where the adventure itself is a
## fractional 6.5), 8 at 1440. At rest the frame is always on a level, so every
## texel is the same size and the pixel-grid snap in MatchCamera keeps texel
## edges on pixel edges. That is the one thing docs/art-direction.md cannot
## give up.
##
## ## Between levels it eases, and the ease is the only fractional moment
##
## One step from 4 to 5 pixels per texel is a quarter of the frame at once, and
## a cut by a quarter is a pop anybody notices. So a step is eased over
## EASE_CALM (in, and the stand-back after a kill) or EASE_SAFE (out, when
## someone is running for the edge), smoothstepped so it starts and lands
## without a jolt. During those frames the scale is fractional and texels are
## drawn n and n+1 pixels wide -- in motion, for a fraction of a second, which
## the eye reads as the zoom. A fractional scale that rests is a shimmer
## (docs/feel.md, "No zoom"); one that moves and lands is a camera move.
## Judged on rendered frames, mid-ease, at 320 and 440 units.
##
## ## No pumping
##
## Three guards, each against a thing a duel actually does:
##
## - HYSTERESIS. Coming in a level wants SIDE + HYSTERESIS of room in front of
##   each fighter at the closer level; going out happens at SIDE. The 48 px
##   between is more than a lunge or a step back carries a fighter, so fencing
##   at the edge of reach never crosses both lines.
## - DWELL. They must have fitted the closer level for DWELL seconds without a
##   break. A jump that lifts one of them out of the frame and back is shorter.
## - COOLDOWN. After stepping out, no step in for COOLDOWN seconds. A chase
##   that opens and closes the distance every second rides at the wider level
##   instead of breathing with it.
##
## ## Never fights a kill, never fights a read
##
## Only one level moves at a time, one way at a time, and never during the
## KILL_HOLD after a death: the frame holds still on the kill at the scale it
## happened, with the body's spot kept in it, and only then stands back. A
## step in is a slow ease over most of a second, centred between the two, so
## a stance does not change size under a thrust that is being read.
##
## ## Both fighters, always
##
## The rule the mode cannot lose is a hard ceiling, not a preference. Every
## update finds the closest level at which every subject fits with EDGE to
## spare -- a body's half width and a pixel -- and the frame is never closer
## than that, whatever the hysteresis, the hold or the ease were doing. During
## an ease the continuous fit caps the fractional scale too, so not even the
## eased frames can lose a fighter. If even the far level cannot hold them (a
## 16:9 desktop is narrower than a zone at that scale), the floor drops below
## it, a whole level at a time, rather than lose one.
##
## "Subjects" are what the camera hands in: the living fighters inside the
## playable window, and the spot a fighter fell on while the hold lasts. A
## fighter respawned ahead of the leader is 720 px away by the spec, outside
## the window, and no framing that keeps a fighter readable holds both; the
## camera stands at the far level while anyone is down or outside, leans the
## view toward them, and has them on screen from the moment they are inside
## the window. See MatchCamera._target().

## A standing fighter's share of the screen's height at the far level. The old,
## fixed framing; see docs/duel-match.md, "Status", item 1.
const FIGHTER_SHARE := 0.085

## World pixels kept between a fighter's feet and the side of the frame.
## EDGE is the hard rule: half a body (4.5) and a pixel and a half, so a fighter
## held against the window's wall (DuelMatch.WINDOW_WALL, 7) by a view exactly
## one zone wide is on screen. SIDE is where the frame chooses to stand out: a
## resting blade, a thrust's reach (18) and a step of warning in front of it.
const EDGE := 6.0
const SIDE := 40.0
## Extra room asked for before coming in a level. Bigger than a lunge.
const HYSTERESIS := 48.0
## Above the head and below the feet: four pixels hard, and room for a jump's
## apex (33 px) to stay inside a frame chosen standing.
const EDGE_UPRIGHT := 4.0
const SIDE_UPRIGHT := 24.0

const DWELL := 0.6
const COOLDOWN := 1.2
const KILL_HOLD := 0.8
## How long a step takes: calm when nothing is escaping the frame, quick when
## something is. At two fighters' separating speed (240 px/s) the quick one is
## 72 px of spread, which the 34 px between SIDE and EDGE on each side covers.
const EASE_CALM := 0.6
const EASE_SAFE := 0.3

## Screen size in pixels, and screen pixels per canvas unit (the canvas_items
## stretch). With no window to measure -- a headless test -- the camera passes
## the canvas itself and 1.0.
var screen := Vector2(1920.0, 1080.0)
var per_unit := 6.0
## A standing fighter's height in world pixels.
var body := 22.0

## The level aimed at, and the scale actually on the screen now, both in
## screen pixels per texel. They differ only while easing.
var level := 4
var shown := 4.0

var _from := 4.0
var _ease := 0.0
var _ease_time := EASE_CALM
var _dwell := 0.0
var _cooldown := 0.0
var _hold := 0.0


## The widest level: a standing fighter FIGHTER_SHARE of the screen tall.
func far_level() -> int:
	return maxi(1, roundi(screen.y * FIGHTER_SHARE / body))


## The closest level: the adventure's scale, rounded down, and never wider than
## the far level on a screen too small to tell the two apart.
func close_level() -> int:
	return maxi(far_level(), floori(per_unit + 0.001))


## The world the screen shows at `pixels` per texel, in world pixels.
func room(pixels: float) -> Vector2:
	return screen / maxf(pixels, 0.001)


## The Camera2D zoom for the scale on the screen now.
func zoom() -> float:
	return shown / maxf(per_unit, 0.001)


## Whether the scale on the screen is a whole number of pixels per texel.
func at_rest() -> bool:
	return is_equal_approx(shown, float(level))


## Starts on the level the subjects call for, without easing to it: a match
## opening, a rematch, a camera put somewhere new.
func reset(subjects: PackedVector2Array, together: bool) -> void:
	var ceiling := close_level() if together else far_level()
	var soft := mini(ceiling, _closest_fitting(subjects, SIDE, SIDE_UPRIGHT))
	level = mini(maxi(soft, far_level()), hard_level(subjects))
	shown = float(level)
	_from = shown
	_ease = _ease_time
	_dwell = 0.0
	_cooldown = 0.0
	_hold = 0.0


## A death: hold the frame still for KILL_HOLD. Only the hard rule moves it.
func kill_beat() -> void:
	_hold = KILL_HOLD
	_dwell = 0.0


func holding() -> bool:
	return _hold > 0.0


## One display frame. `subjects` are the feet that must be on screen;
## `together` says both fighters are alive and inside the window, which is the
## only time the frame comes closer than the far level. Returns the scale to
## draw at, in screen pixels per texel.
func update(delta: float, subjects: PackedVector2Array, together: bool) -> float:
	_hold = maxf(0.0, _hold - delta)
	_cooldown = maxf(0.0, _cooldown - delta)
	var far := far_level()
	var hard := hard_level(subjects)
	var want := level

	if _hold > 0.0:
		pass # the kill reads at the scale it happened
	elif not together:
		_dwell = 0.0
		if level > far:
			want = far
		elif level < far:
			want = _stepped_in(subjects, far, EDGE + HYSTERESIS, EDGE_UPRIGHT, delta)
	elif level > far and not fits(float(level), subjects, SIDE, SIDE_UPRIGHT):
		want = level - 1
	else:
		var margin := SIDE + HYSTERESIS if level + 1 > far else EDGE + HYSTERESIS
		var upright := SIDE_UPRIGHT if level + 1 > far else EDGE_UPRIGHT
		want = _stepped_in(subjects, close_level(), margin, upright, delta)

	want = mini(want, hard)
	if want != level:
		# Quick when something is escaping the frame; calm when the frame is
		# only standing back because someone is down or away.
		_go(want, want < level and (together or hard < level))
	_ease = minf(_ease + delta, _ease_time)
	shown = lerpf(_from, float(level), smoothstep(0.0, 1.0, _ease / _ease_time))
	# The hard ceiling holds on the eased frames too.
	shown = minf(shown, maxf(fit_scale(subjects), float(hard)))
	return shown


## The closest whole level at which every subject is on screen with EDGE to
## spare. Never below 1.
func hard_level(subjects: PackedVector2Array) -> int:
	return maxi(1, _closest_fitting(subjects, EDGE, EDGE_UPRIGHT))


## The exact scale at which the subjects just fit with EDGE to spare.
func fit_scale(subjects: PackedVector2Array) -> float:
	if subjects.is_empty():
		return INF
	var span := _span(subjects)
	return minf(
		screen.x / (span.x + EDGE * 2.0),
		screen.y / (span.y + body + EDGE_UPRIGHT * 2.0)
	)


## Whether the subjects fit at `pixels` per texel with `side` in front of each
## and `upright` above the highest head and below the lowest feet.
func fits(pixels: float, subjects: PackedVector2Array, side: float, upright: float) -> bool:
	if subjects.is_empty():
		return true
	var span := _span(subjects)
	var seen := room(pixels)
	return span.x + side * 2.0 <= seen.x + 0.001 \
		and span.y + body + upright * 2.0 <= seen.y + 0.001


func _closest_fitting(subjects: PackedVector2Array, side: float, upright: float) -> int:
	for pixels: int in range(close_level(), 0, -1):
		if fits(float(pixels), subjects, side, upright):
			return pixels
	return 1


## One level closer, once the subjects have fitted it with `margin` for DWELL.
func _stepped_in(subjects: PackedVector2Array, ceiling: int, margin: float,
		upright: float, delta: float) -> int:
	if level >= ceiling or _cooldown > 0.0 or not at_rest() \
			or not fits(float(level + 1), subjects, margin, upright):
		_dwell = 0.0
		return level
	_dwell += delta
	if _dwell < DWELL:
		return level
	_dwell = 0.0
	return level + 1


func _go(next: int, urgent: bool) -> void:
	if next < level:
		_cooldown = COOLDOWN
	_from = shown
	_ease = 0.0
	_ease_time = EASE_SAFE if urgent else EASE_CALM
	level = next


static func _span(subjects: PackedVector2Array) -> Vector2:
	var low := subjects[0]
	var high := subjects[0]
	for at: Vector2 in subjects:
		low = low.min(at)
		high = high.max(at)
	return high - low
