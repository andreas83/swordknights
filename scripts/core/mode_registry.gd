class_name ModeRegistry
extends RefCounted
## The catalogue of playable modes.
##
## This is the single integration point for a new mode: add one entry and it
## appears in the menu. Keep it a plain list of dictionaries — it is edited by
## several people (and agents) at once, so a one-line addition should never
## conflict with another.
##
## `scene` is loaded when the mode is chosen, so a mode that generates a level
## or opens a network connection does no work until the player picks it.
##
## `bench` marks a tool rather than a mode -- the feel lab, a tuning bench --
## which is listed only where the game is being worked on (shows_benches()).


## The modes, benches included only when `benches` is true.
static func modes(benches: bool = shows_benches()) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for mode: Dictionary in _catalogue():
		if benches or not bool(mode.get("bench", false)):
			out.append(mode)
	return out


## Whether the benches are listed: only in a run of the editor's own binary --
## from the editor, `godot --path .`, the tests -- and never in an exported
## build. Not `OS.is_debug_build()`: the APK the owner plays on a phone is
## CI's debug export, which is a debug build, and a tuning bench on its title
## screen is a door into a room with no game in it. The export templates lack
## the `editor` feature whatever they are stamped with.
static func shows_benches() -> bool:
	return OS.has_feature("editor")


static func _catalogue() -> Array[Dictionary]:
	return [
		{
			"id": "adventure",
			"title": "Adventure",
			"subtitle": "The Last Light",
			"scene": "res://scenes/chapter_select.tscn",
			"available": true,
		},
		{
			"id": "endless",
			"title": "Endless",
			"subtitle": "A new ruin every run",
			"scene": "res://scenes/generated_game.tscn",
			"available": true,
		},
		{
			# One row; how to duel is the page's second step (DuelSelect).
			"id": "duel",
			"title": "Duel",
			# A phone has no keyboard to share (DuelSelect, "On a phone").
			"subtitle": "The computer, or online" if UiLayout.handheld()
				else "One keyboard, the computer, or online",
			"scene": "res://scenes/duel_select.tscn",
			"available": true,
		},
		{
			"id": "feel_lab",
			"title": "Feel Lab",
			"subtitle": "Tuning bench",
			"scene": "res://scenes/feel_lab.tscn",
			"available": true,
			"bench": true,
		},
	]


static func available() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for mode: Dictionary in modes():
		if mode.get("available", true):
			out.append(mode)
	return out
