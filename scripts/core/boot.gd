extends Node
## Entry point. Kept deliberately thin: it exists so that the first scene the
## engine loads is one we control, which is where platform setup (screen
## wake-lock, audio bus warm-up, save loading) belongs.

const MENU_SCENE := "res://scenes/menu.tscn"


func _ready() -> void:
	if ResourceLoader.exists(MENU_SCENE):
		get_tree().change_scene_to_file(MENU_SCENE)
	else:
		push_warning("menu scene missing — staying on the boot screen")
