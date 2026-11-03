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


static func modes() -> Array[Dictionary]:
	return [
		{
			"id": "adventure",
			"title": "Adventure",
			"subtitle": "The Sun Terrace",
			"scene": "res://scenes/game.tscn",
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
			"id": "duel",
			"title": "Duel",
			"subtitle": "Tug of war, one keyboard",
			"scene": "res://scenes/duel_match.tscn",
			"available": true,
		},
		{
			"id": "duel_cpu",
			"title": "Duel vs CPU",
			"subtitle": "One phone, one opponent",
			"scene": "res://scenes/duel_match_cpu.tscn",
			"available": true,
			"choices": ["Easy", "Medium", "Hard"],
		},
		{
			"id": "duel_online",
			"title": "Duel Online",
			"subtitle": "Two phones, one Wi-Fi",
			"scene": "res://scenes/duel_match_online.tscn",
			"available": true,
		},
		{
			"id": "feel_lab",
			"title": "Feel Lab",
			"subtitle": "Tuning bench",
			"scene": "res://scenes/feel_lab.tscn",
			"available": true,
		},
	]


static func available() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for mode: Dictionary in modes():
		if mode.get("available", true):
			out.append(mode)
	return out


## --- choices ---------------------------------------------------------------
##
## A mode may offer `choices`, a short list the menu steps through with left
## and right on its row (DUEL VS CPU's difficulty). What was chosen is kept
## here, by mode id, for the rest of the session, so the scene the mode opens
## can read it and the menu shows it again on the way back. Not saved to disk:
## the menu starts every launch on a mode's first choice, which for the
## computer opponent is the gentlest.

static var _chosen := {}


static func choose(id: String, index: int) -> void:
	_chosen[id] = index


static func chosen(id: String, otherwise: int = 0) -> int:
	return int(_chosen.get(id, otherwise))
