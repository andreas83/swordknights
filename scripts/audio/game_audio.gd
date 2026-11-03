class_name GameAudio
extends RefCounted
## The compile-time-resolvable front door to the AudioDirector autoload.
##
## Calling an autoload by its name — `AudioDirector.play(...)` — does not
## compile under `godot --headless --script ...`. Autoload names live in the
## editor/runtime global scope but not in the compiler's when a bare script is
## the main loop, which is exactly how every standalone test runs.
##
## The failure is nasty rather than loud: the script that calls it fails to
## compile, a scene instantiated from it comes up *without its script*, and a
## test then measures nothing while reporting success. That is how
## character_traversal_test spent a day claiming to drive the character
## through the feel lab without ever loading it.
##
## A class_name is in global scope everywhere, so gameplay code calls this and
## the autoload stays an implementation detail.

const NODE_NAME := ^"AudioDirector"

static var _director: Node


## Play a one-shot voice. Silently does nothing when the autoload is absent —
## a headless test has no mixer and should not have to care.
static func cue(voice: StringName, options: Dictionary = {}) -> void:
	var director := _resolve()
	if director != null:
		director.play(voice, options)


static func available() -> bool:
	return _resolve() != null


static func _resolve() -> Node:
	if _director != null and is_instance_valid(_director):
		return _director
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null:
		return null
	_director = loop.root.get_node_or_null(NODE_NAME)
	return _director
