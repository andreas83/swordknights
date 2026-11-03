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

const GAME_SCENE := "res://scenes/game.tscn"

## Target width in tiles. Long enough to be a level, short enough that the
## whole run is a couple of minutes.
@export var length: int = 170
@export_range(0.0, 1.0, 0.05) var difficulty: float = 0.55
## Non-zero replays one particular level instead of rolling a fresh one.
@export var seed_override: int = 0

var seed_value: int = 0

var _game: Game
var _readout: Readout


func _ready() -> void:
	seed_value = seed_override if seed_override != 0 else _fresh_seed()

	var result := LevelGenerator.build(seed_value, length, difficulty)
	_readout = Readout.new()
	_readout.seed_value = seed_value
	_readout.difficulty = difficulty

	if not bool(result["ok"]):
		# The generator already pushed the detail; say enough on screen that a
		# tester can report the seed that broke it.
		_readout.failure = "GENERATION FAILED"
		_mount_readout()
		push_error("GeneratedGame: %s" % String(result["reason"]))
		return

	var level := result["level"] as AsciiLevel
	var packed := load(GAME_SCENE) as PackedScene
	if packed == null:
		_readout.failure = "MISSING GAME SCENE"
		_mount_readout()
		push_error("GeneratedGame: could not load %s" % GAME_SCENE)
		return

	_game = packed.instantiate() as Game
	# Before add_child, or Game._ready falls back to its level_path export.
	_game.level_source = level
	add_child(_game)

	_readout.level_name = level.name
	_readout.beats = int((result["beats"] as Array).size())
	_readout.columns = level.cols
	_mount_readout()

	print("GeneratedGame: seed %d, %d columns, %d beats, %d attempt(s), %s" % [
		seed_value, level.cols, _readout.beats, int(result["attempts"]),
		String((result["report"] as Dictionary).get("reason", "")),
	])


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
	var level_name: String = ""
	var beats: int = 0
	var columns: int = 0
	var failure: String = ""

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
			return

		UiFont.draw_text(self, "SEED %d" % seed_value, Vector2(left, bottom - 14.0),
			UiFont.Cut.TEXT, Palette.PAPER, UiFont.Align.LEFT, 0.7)
		UiFont.draw_text(self,
			"%d COLS  %d BEATS  DIFF %.2f" % [columns, beats, difficulty],
			Vector2(left, bottom - 5.0), UiFont.Cut.MICRO,
			Palette.with_alpha(Palette.LIGHT_SOFT, 0.75), UiFont.Align.LEFT, 0.7)
