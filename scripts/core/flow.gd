class_name Flow
extends CanvasLayer
## The moment between moments: scene transitions, hitstop and haptics.
##
## Three small services that have nothing to do with each other mechanically
## and everything to do with each other in the player's hands — they are all
## about the half-second around an event rather than the event itself. Keeping
## them in one file keeps the budget for all three visible in one place.
##
## ## Why it is not an autoload
##
## `project.godot` is shared with every other mode and agent, so adding a
## singleton to it is a merge conflict waiting to happen. Instead this is a
## self-installing node: the first caller gets a `Flow` parented to the scene
## tree's root, which outlives `change_scene_to_file`, and every later caller
## gets the same one back. Nothing has to be registered and nothing has to be
## wired into a scene.
##
## The consequence that matters: `Flow` only exists in a scene that asks for
## it. `scripts/core/game.gd` asks; the duel does not.
##
## ## The wipe
##
## A hard-edged shadow sweeping across the frame, left to right, at the same
## low rake as the sun in `docs/art-direction.md`. Three flat values and no
## gradient anywhere: a two-pixel lit rim at the leading edge, a step of
## crimson behind it, then ink. It is a cast shadow passing over the scene, not
## a fade — a crossfade would mean a frame with no hard edges in it, which is
## the one thing the look cannot have.
##
## The caller's work happens at full cover, so a respawn, a rebuild or a scene
## swap is never seen.
##
## ## Hitstop and the duel
##
## Hitstop here is a real freeze, not a visual trick — `Game` stops stepping
## its actors while `is_hitstopped()` holds. That is only sound because the
## only caller is the single-player scene. **Nothing under `scripts/duel/` or
## `scripts/net/` may call `hitstop()`**: a duel steps in `_physics_process`
## and a frozen frame would have to be a decision both peers reached from the
## same inputs on the same frame, which a locally-detected sword hit is not.
## `tests/feel_flow_test.gd` fails if that reference ever appears.
##
## Reading the flag is harmless and `PlayerFx` does it, so particles hold still
## in a held frame. In a duel it is always false because nothing there sets it.

enum Pace { NORMAL, FAST }
enum Stage { IDLE, COVER, HOLD, UNCOVER }

const NODE_NAME := "Flow"
## Above every CanvasLayer in the game; the HUD is on 0 and the sky on -10.
const LAYER := 128

## One simulation frame. The hitstop budget is quoted in frames because that is
## how it is felt and how it is argued about.
const FRAME := 1.0 / 60.0
## A sword landing on a guard.
const HIT_FRAMES := 4
## Landing on one from above: heavier, because the whole body is behind it.
const STOMP_FRAMES := 5
## Taking a hit. Short — the player needs control back, not a lesson.
const HURT_FRAMES := 3
## A plunge that lands on a guard: the whole fall is behind it, so it takes the
## ceiling. Still never more than MAX_HITSTOP.
const PLUNGE_FRAMES := 6
## Steel turning steel. Longer than a hit, because the clang is the moment the
## player reads that the parry worked; shorter than a stomp, because the
## riposte is the point and it wants the frame back.
const PARRY_FRAMES := 5
## The ceiling. Hitstop is taken with max(), never summed, and never exceeds
## this, so three things connecting at once cannot stack into a stutter.
const MAX_HITSTOP := 6.0 * FRAME

const COVER_TIME := 0.16
## Long enough for a deferred `change_scene_to_file` to have actually built the
## next scene before the shadow starts to lift.
const HOLD_TIME := 0.07
const UNCOVER_TIME := 0.2
## Pace.FAST, used by the retry, which is the one transition the player waits
## on rather than watches.
const FAST_SCALE := 0.55

## Rake of the wipe edge as a fraction of screen height, matching the sun.
const RAKE := 0.45
## The lit rim, in pixels. The only bright thing in the transition.
const RIM := 2.0
## The crimson step behind the leading edge, in pixels.
const SHADE := 14.0

const SETTINGS_PATH := "user://feel.cfg"
const SETTINGS_SECTION := "feel"
const HAPTIC_MIN_MS := 12
const HAPTIC_MAX_MS := 45

static var _instance: Flow = null
## -1 unknown, 0 off, 1 on. Read from disk once, lazily.
static var _haptics := -1

var _stage: Stage = Stage.IDLE
var _time: float = 0.0
var _pace: float = 1.0
var _on_covered := Callable()
## Leading edge of the shadow, 0 (off the left) to 1 (off the right).
var _lead: float = 0.0
## Trailing edge, which only moves once the screen is covered.
var _trail: float = 0.0
var _hitstop: float = 0.0

var _veil: Control


## --- installation ----------------------------------------------------------

## The Flow for this tree, creating it if it is not there yet. Returns null
## only when there is no scene tree at all to attach to.
static func install(from: Node) -> Flow:
	if _instance != null and is_instance_valid(_instance):
		return _instance
	var tree := _tree_for(from)
	if tree == null:
		return null
	var root := tree.root
	var existing := root.get_node_or_null(NODE_NAME) as Flow
	if existing != null:
		_instance = existing
		return existing
	var flow := Flow.new()
	flow.name = NODE_NAME
	flow.layer = LAYER
	# Deferred because the usual caller is a scene's _ready(), and the root is
	# busy adding that scene at the time. The state below is set immediately
	# either way, so a wipe asked for now starts covered.
	root.add_child.call_deferred(flow)
	_instance = flow
	return flow


## Call from a scene's `_ready()`: lifts the shadow off whatever just loaded.
##
## A no-op when a transition is already running, which is the case when the
## previous scene changed scenes through `change_scene()`. That makes it safe
## to call unconditionally, and means a scene reached by a bare
## `change_scene_to_file()` elsewhere still gets the incoming half.
static func enter(from: Node, pace: Pace = Pace.NORMAL) -> void:
	var flow := install(from)
	if flow == null:
		return
	# A hitstop is a beat of the blow that struck it, and dies with the scene
	# it was struck in. Flow outlives scenes, so a kill on the last frame
	# before a door -- or the last frame of one test -- froze the next level's
	# first frames, and a run started late by as many: whether the prince
	# spawned moving depended on what had happened before him.
	flow._hitstop = 0.0
	if flow.is_busy():
		return
	flow._lead = 1.0
	flow._trail = 0.0
	flow._stage = Stage.HOLD
	flow._time = 0.0
	flow._pace = _scale_for(pace)
	flow._on_covered = Callable()


## True while a transition owns the screen. Callers gate their input on this so
## a button pressed mid-wipe does not queue a second one. Deliberately does not
## install anything: a predicate that creates a node is a trap.
static func busy() -> bool:
	var flow := _current()
	return flow != null and flow.is_busy()


func is_busy() -> bool:
	return _stage != Stage.IDLE


## --- transitions -----------------------------------------------------------

## Cover the screen, run `when_covered`, uncover. The work happens in the one
## frame nobody can see, which is the whole point.
static func wipe(from: Node, when_covered: Callable, pace: Pace = Pace.NORMAL) -> void:
	var flow := install(from)
	if flow == null:
		# No tree to draw on. Still do the work, or the caller silently stalls.
		if when_covered.is_valid():
			when_covered.call()
		return
	flow.start_wipe(when_covered, pace)


## The one wrapper around `change_scene_to_file`. Every scene change in the
## game goes through here so that none of them is a hard cut.
static func change_scene(from: Node, path: String, pace: Pace = Pace.NORMAL) -> void:
	var tree := _tree_for(from)
	if tree == null:
		push_error("Flow.change_scene: no scene tree to change")
		return
	wipe(from, func() -> void: tree.change_scene_to_file(path), pace)


func start_wipe(when_covered: Callable, pace: Pace = Pace.NORMAL) -> void:
	if is_busy():
		return
	_on_covered = when_covered
	_pace = _scale_for(pace)
	_stage = Stage.COVER
	_time = 0.0
	_lead = 0.0
	_trail = 0.0


static func _scale_for(pace: Pace) -> float:
	return FAST_SCALE if pace == Pace.FAST else 1.0


## --- hitstop ---------------------------------------------------------------

## Freeze the moment for `seconds`, clamped to MAX_HITSTOP and taken with
## max() so overlapping impacts do not add up.
##
## Single-player only. See the class docs: the duel must never call this.
static func hitstop(from: Node, seconds: float) -> void:
	var flow := install(from)
	if flow == null:
		return
	flow._hitstop = maxf(flow._hitstop, clampf(seconds, 0.0, MAX_HITSTOP))


static func hitstop_remaining() -> float:
	var flow := _current()
	return flow._hitstop if flow != null else 0.0


static func is_hitstopped() -> bool:
	return hitstop_remaining() > 0.0


## --- haptics ---------------------------------------------------------------

## Defaults to on where there is something to vibrate and off everywhere else,
## so a desktop or web build never pays for it and a phone gets it without a
## trip through a settings screen that does not exist yet.
static func haptics_enabled() -> bool:
	if _haptics < 0:
		var fallback := OS.has_feature("mobile")
		var file := ConfigFile.new()
		if file.load(UserData.at(SETTINGS_PATH)) == OK:
			fallback = bool(file.get_value(SETTINGS_SECTION, "haptics", fallback))
		_haptics = 1 if fallback else 0
	return _haptics == 1


static func set_haptics_enabled(on: bool) -> void:
	_haptics = 1 if on else 0
	var file := ConfigFile.new()
	# Keep whatever else lives in the file; this is the shared settings path.
	file.load(UserData.at(SETTINGS_PATH))
	file.set_value(SETTINGS_SECTION, "haptics", on)
	file.save(UserData.at(SETTINGS_PATH))


## A buzz scaled 0..1 by how hard the thing hit. `vibrate_handheld()` does
## nothing off a phone, so this is free everywhere else.
static func haptic(strength: float) -> void:
	var amount := clampf(strength, 0.0, 1.0)
	if amount <= 0.02 or not haptics_enabled():
		return
	var ms := int(roundf(lerpf(float(HAPTIC_MIN_MS), float(HAPTIC_MAX_MS), amount)))
	Input.vibrate_handheld(ms, amount)


## --- internals -------------------------------------------------------------

static func _current() -> Flow:
	if _instance != null and is_instance_valid(_instance):
		return _instance
	return null


## `from.get_tree()` is null until the node is actually inside the tree, which
## it is not during a SceneTree script's `_initialize()` — so the headless
## tests would get nothing back. Fall through to the main loop, which is the
## same tree in every case this project has.
static func _tree_for(from: Node) -> SceneTree:
	if from != null and from.is_inside_tree():
		return from.get_tree()
	return Engine.get_main_loop() as SceneTree


func _ready() -> void:
	# The wipe has to keep running while the scene below it is paused or held
	# in a hitstop, which is most of when it is used.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = LAYER
	var veil := _Veil.new()
	veil.flow = self
	veil.name = "Veil"
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	_veil = veil


## The wipe runs on the simulation clock, not the display clock.
##
## A wipe looks like pure presentation and `MatchCamera` makes the opposite
## choice for exactly that reason — but this one fires the caller's work at
## full cover, and that work is a respawn or a scene change. CLAUDE.md:
## *nothing gameplay-relevant may depend on `_process` or on `delta` varying*.
## A retry that happens on frame 23 at 60 fps and frame 11 at 30 fps is
## gameplay depending on the display, so the whole state machine runs here
## with the hitstop clock instead.
##
## The reason `MatchCamera` avoids the physics clock — a client reconciling a
## duel may step it twice in one frame — cannot reach this file: `Flow` is
## installed by `Game._ready()` and a duel never runs `Game`.
func _physics_process(delta: float) -> void:
	_step_hitstop(delta)
	if _stage == Stage.IDLE:
		return
	_time += delta
	match _stage:
		Stage.COVER:
			var cover_span := maxf(0.001, COVER_TIME * _pace)
			_lead = minf(1.0, _time / cover_span)
			if _lead >= 1.0:
				_advance(Stage.HOLD)
				var work := _on_covered
				_on_covered = Callable()
				if work.is_valid():
					work.call()
		Stage.HOLD:
			if _time >= HOLD_TIME * _pace:
				_advance(Stage.UNCOVER)
		Stage.UNCOVER:
			var uncover_span := maxf(0.001, UNCOVER_TIME * _pace)
			_trail = minf(1.0, _time / uncover_span)
			if _trail >= 1.0:
				_stage = Stage.IDLE
				_lead = 0.0
				_trail = 0.0
	if _veil != null:
		_veil.queue_redraw()


## Hitstop is counted in simulation frames, so it is spent on the simulation
## clock — one call to `hitstop(4 frames)` must hold for exactly four steps of
## the thing it is freezing. Called from `_physics_process` above, so the wipe
## and the hold are measured by one clock.
func _step_hitstop(delta: float) -> void:
	if _hitstop <= 0.0:
		return
	_hitstop -= delta
	# A remainder shorter than a frame cannot hold anything for a frame, and
	# n * FRAME minus n deltas leaves one. Without this a four-frame stop holds
	# for five, which is exactly the kind of drift a budget is meant to prevent.
	if _hitstop < FRAME * 0.5:
		_hitstop = 0.0


func _advance(next: Stage) -> void:
	_stage = next
	_time = 0.0


## --- drawing ---------------------------------------------------------------

func _paint(veil: Control) -> void:
	if _stage == Stage.IDLE:
		return
	var view := veil.size
	if view.x <= 0.0 or view.y <= 0.0:
		return

	var rake := view.y * RAKE
	var span := _span(view)
	var lead := _lead * span - RIM
	var trail := _trail * span - RIM

	if lead > trail:
		_band(veil, trail, lead, rake, Palette.INK)
		_band(veil, maxf(trail, lead - SHADE), lead, rake, Palette.SHADOW_DEEP)
	# The rim is the edge of the light, so it only exists while there is light
	# on that side of the shadow to be cut off or handed back.
	if _lead < 1.0:
		_band(veil, lead, lead + RIM, rake, Palette.LIGHT)
	if _trail > 0.0:
		_band(veil, trail - RIM, trail, rake, Palette.LIGHT_WARM)


func _band(veil: Control, from_x: float, to_x: float, rake: float, color: Color) -> void:
	if to_x <= from_x:
		return
	var bottom := veil.size.y
	veil.draw_colored_polygon(
		PackedVector2Array([
			Vector2(from_x, 0.0),
			Vector2(to_x, 0.0),
			Vector2(to_x - rake, bottom),
			Vector2(from_x - rake, bottom),
		]),
		color
	)


## The full-cover test, exposed so `tests/feel_flow_test.gd` can check the
## geometry rather than trusting the arithmetic above by eye: at `_lead == 1`
## and `_trail == 0` the ink must cover every row of the screen.
static func covers_row(lead: float, trail: float, view: Vector2, y: float) -> bool:
	var at := y / maxf(1.0, view.y) * (view.y * RAKE)
	var span := _span(view)
	var left := trail * span - RIM - at
	var right := lead * span - RIM - at
	return left <= 0.0 and right >= view.x


## How far one edge travels to cross the frame: the width, plus the rake it
## leans by, plus the rim at the near end and the crimson step at the far one.
## Counting the step is what keeps its wedge from resting in the corner of a
## fully covered frame, where it reads as a stray shape rather than as a
## shadow's edge that has already left.
static func _span(view: Vector2) -> float:
	return view.x + view.y * RAKE + RIM * 2.0 + SHADE


## A Control, because a CanvasLayer cannot draw and this is the only thing in
## the file that needs to be one. It owns no state: the stage lives on Flow.
class _Veil extends Control:
	var flow: Flow

	func _draw() -> void:
		if flow != null and is_instance_valid(flow):
			flow._paint(self)
