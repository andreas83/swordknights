class_name GeneratedGame
extends Node2D
## Plays a freshly generated level.
##
## Wraps res://scenes/game.tscn rather than duplicating it: the generated level
## is handed over through `Game.level_source`, which has to be set *before*
## `add_child` because `Game._ready` is what reads it. Everything else — the
## player, camera, HUD, touch controls, parallax — is the same scene the
## hand-authored Adventure mode runs, so this mode cannot drift away from it.
##
## Every entry picks a new seed, and the seed is on screen for as long as the
## level is: a generator is only useful if a good roll can be reported and
## played again. `godot --headless --script tools/generate_level.gd --
## --seed <n>` reproduces exactly what was played, and `seed_override` pins a
## seed from the editor.
##
## ## The descent
##
## Escaping a ruin leads down into the next one rather than replaying it. The
## mode used to stop at the first door — jump rebuilt the same seed at the same
## 0.55 — so it had no second level, no curve and nothing to carry on toward.
## Now ruin 1 opens gentler than that (`difficulty`, 0.4) and each door down
## adds DIFFICULTY_STEP until MAX_DIFFICULTY. The generator already ramps
## *within* a ruin from 55% to 100% of what it is asked for, so the two curves
## stack: every ruin opens a little easier than the last one ended, which is
## the breather a run needs, and still opens harder than the last one opened.
##
## Ruin n's seed follows from ruin 1's (`next_seed()`), so a pinned seed pins
## the whole descent and the readout's seed is still the one to report.

const GAME_SCENE := "res://scenes/game.tscn"
const MENU_SCENE := "res://scenes/menu.tscn"
const TOUCH_CONTROLS := preload("res://scenes/touch_controls.tscn")
## Added per ruin descended.
const DIFFICULTY_STEP := 0.1
## The top of the generator's dial, where every segment is in play and gaps
## open to their full width. Asking for more would ask for nothing new.
const MAX_DIFFICULTY := 0.95

## Target width in tiles. Long enough to be a level, short enough that the
## whole run is a couple of minutes.
@export var length: int = 170
## The first ruin's difficulty; each ruin below it adds DIFFICULTY_STEP.
@export_range(0.0, 1.0, 0.05) var difficulty: float = 0.4
## Non-zero replays one particular descent instead of rolling a fresh one.
@export var seed_override: int = 0

## The ruin being played, and how many doors down it is.
var seed_value: int = 0
var depth: int = 1

## Test seam: what leaving a ruin that would not generate does instead of
## changing to the title screen.
var leave := Callable()

var _first_seed: int = 0
var _stranded := false
var _game: Game
var _readout: Readout


## How hard ruin `at_depth` is, starting from `start`.
static func difficulty_at(at_depth: int, start: float) -> float:
	return minf(start + float(at_depth - 1) * DIFFICULTY_STEP, MAX_DIFFICULTY)


## The seed of ruin `at_depth` in the descent that starts at `first`.
static func next_seed(first: int, at_depth: int) -> int:
	if at_depth <= 1:
		return first
	return hash([first, at_depth]) & 0x7FFFFFFF


func current_difficulty() -> float:
	return difficulty_at(depth, difficulty)


func _ready() -> void:
	_first_seed = seed_override if seed_override != 0 else _fresh_seed()
	seed_value = _first_seed
	_readout = Readout.new()
	_mount_readout()
	_build()


## Behind the cover of the complete screen's wipe: the next ruin down.
func _descend() -> void:
	depth += 1
	seed_value = next_seed(_first_seed, depth)
	if _game != null:
		remove_child(_game)
		_game.queue_free()
		_game = null
	_build()


func _build() -> void:
	var result := LevelGenerator.build(seed_value, length, current_difficulty())
	_readout.seed_value = seed_value
	_readout.difficulty = current_difficulty()
	_readout.depth = depth
	_readout.queue_redraw()

	if not bool(result["ok"]):
		# The generator already pushed the detail; say enough on screen that a
		# tester can report the seed that broke it.
		_readout.failure = "GENERATION FAILED"
		push_error("GeneratedGame: %s" % String(result["reason"]))
		_strand()
		return

	var level := result["level"] as AsciiLevel
	var packed := load(GAME_SCENE) as PackedScene
	if packed == null:
		_readout.failure = "MISSING GAME SCENE"
		push_error("GeneratedGame: could not load %s" % GAME_SCENE)
		return

	_game = packed.instantiate() as Game
	# Before add_child, or Game._ready falls back to its level_path export.
	_game.level_source = level
	_game.advance = _descend
	# The pause menu starts this ruin over, never a new one: a roll is
	# reported by its seed, and the seed on screen must stay the one played.
	_game.restart_label = "RESTART RUIN"
	if leave.is_valid():
		_game.leave = leave
	add_child(_game)

	_readout.level_name = level.name
	_readout.beats = int((result["beats"] as Array).size())
	_readout.columns = level.cols
	_readout.queue_redraw()

	print("GeneratedGame: seed %d, %d columns, %d beats, %d attempt(s), %s" % [
		seed_value, level.cols, _readout.beats, int(result["attempts"]),
		String((result["report"] as Dictionary).get("reason", "")),
	])


## A ruin that would not generate leaves a screen with no game on it, so no
## pause menu and no thumb buttons: once the only dead end in the game.
## It gets the title screen's way back -- any of jump, sword or pause, or a
## tap -- said on screen, and buttons lettered with it.
func _strand() -> void:
	_stranded = true
	_readout.failure_hint = "SWORD OR PAUSE TO GO BACK"
	var controls := TOUCH_CONTROLS.instantiate() as TouchControls
	controls.name = "TouchControls"
	add_child(controls)
	controls.set_labels("BACK", "BACK")


func _process(_delta: float) -> void:
	if not _stranded:
		return
	if Input.is_action_just_pressed("attack") or Input.is_action_just_pressed("pause") \
			or Input.is_action_just_pressed("jump"):
		_stranded = false
		if leave.is_valid():
			leave.call()
		else:
			get_tree().change_scene_to_file(MENU_SCENE)


func _mount_readout() -> void:
	var layer := CanvasLayer.new()
	layer.name = "SeedLayer"
	# Above the HUD's own layer so the seed is never covered by the title card.
	layer.layer = 5
	layer.add_child(_readout)
	add_child(layer)


## Deliberately its own RandomNumberGenerator: the generator is seeded and
## reproducible, and nothing in this mode is allowed to disturb — or depend
## on — the global random state.
static func _fresh_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi() & 0x7FFFFFFF


## The seed, top right, drawn in the game's own palette rather than with a
## stock Label so it sits in the picture instead of on top of it.
class Readout extends Control:
	var seed_value: int = 0
	var difficulty: float = 0.0
	var depth: int = 1
	var level_name: String = ""
	var beats: int = 0
	var columns: int = 0
	var failure: String = ""
	var failure_hint: String = ""

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
		# A Control under a CanvasLayer draws once before its anchors resolve,
		# which would put this off the left edge at size zero. Redraw when the
		# layout settles and whenever the window changes shape.
		resized.connect(queue_redraw)
		get_viewport().size_changed.connect(queue_redraw)
		queue_redraw.call_deferred()

	func _draw() -> void:
		# Measured against the viewport rather than this node's own rect, so
		# the readout is correct on the very first frame too.
		var view := get_viewport_rect().size
		if view.x <= 0.0:
			return
		# Bottom-left of the safe area: health holds the top-left corner, the
		# pause and mute buttons the top-right, the stick and the action
		# buttons the bottom-right. UiFont.draw_text casts its own shadow.
		var content := UiLayout.content(view)
		var left := content.position.x
		var bottom := content.end.y

		if failure != "":
			UiFont.draw_text(self, failure, Vector2(left, bottom - 15.0),
				UiFont.Cut.TEXT, Palette.PAPER, UiFont.Align.LEFT, 0.7)
			UiFont.draw_text(self, "SEED %d" % seed_value, Vector2(left, bottom - 5.0),
				UiFont.Cut.MICRO, Palette.LIGHT_SOFT, UiFont.Align.LEFT, 0.7)
			if failure_hint != "":
				UiFont.draw_text(self, failure_hint, Vector2(left, bottom - 25.0),
					UiFont.Cut.MICRO, Palette.PAPER, UiFont.Align.LEFT, 0.7)
			return

		UiFont.draw_text(self, "RUIN %d  ·  SEED %d" % [depth, seed_value],
			Vector2(left, bottom - 14.0),
			UiFont.Cut.TEXT, Palette.PAPER, UiFont.Align.LEFT, 0.7)
		UiFont.draw_text(self,
			"%d COLS  %d BEATS  DIFF %.2f" % [columns, beats, difficulty],
			Vector2(left, bottom - 5.0), UiFont.Cut.MICRO,
			Palette.with_alpha(Palette.LIGHT_SOFT, 0.75), UiFont.Align.LEFT, 0.7)
