extends Node
## Entry point. Kept deliberately thin: it exists so that the first scene the
## engine loads is one we control, which is where platform setup (screen
## wake-lock, audio bus warm-up, save loading) belongs.

const MENU_SCENE := "res://scenes/menu.tscn"
const FALLBACK_SCENE := "res://scenes/game.tscn"


func _ready() -> void:
	# The assists are a save, so they load here and only here: anything that
	# never boots the game -- a test, the trace tool -- plays unassisted.
	Assist.load_saved()
	# Deferred: the tree is still building children while _ready runs, and
	# swapping the scene from inside it is not allowed.
	_go.call_deferred()


func _go() -> void:
	if ResourceLoader.exists(MENU_SCENE):
		get_tree().change_scene_to_file(MENU_SCENE)
	elif ResourceLoader.exists(FALLBACK_SCENE):
		get_tree().change_scene_to_file(FALLBACK_SCENE)
	else:
		push_error("no playable scene found")
