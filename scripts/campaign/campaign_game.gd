class_name CampaignGame
extends Node2D
## Plays The Last Light from Campaign.selected on: one entry after another,
## each through the same res://scenes/game.tscn every other mode plays, and
## the ending card after the last.
##
## Built like GeneratedGame and for its reason: the level is handed to
## `Game.level_source` before the game enters the tree, and everything else
## -- the player, the HUD, the camera -- is the one playable scene, so the
## campaign cannot drift from the Adventure as it has always played.
##
## What it adds is the thread between levels:
##
## - **A clear is recorded** the moment it happens (`Game.level_completed`),
##   best time, relics and secrets, and the next entry opens -- before the
##   player has pressed anything, so quitting from the complete screen keeps
##   the clear.
## - **Jump goes on.** `Game.advance` plays the next entry behind the wipe,
##   JUMP TO CONTINUE; after the last it is JUMP TO DAWN and the dawn's frame
##   with the ending's words over it (DawnFrame, EndingCard);
##   and when the next entry is not built yet, JUMP TO CHAPTERS returns to the
##   chapter select, where it waits marked "still being built".
## - **Each chapter opens on its card**: numeral, name and epigraph from the
##   catalogue (Campaign.card()), in place of the level's plain title; and
##   its sky has the Mirror Tower in it, at the entry's distance.
## - **Sword goes back to the chapter select**, from pause or the complete
##   screen (`Game.quit_scene`), not to the title: the campaign is a place.

const GAME_SCENE := "res://scenes/game.tscn"
const CHAPTER_SELECT := "res://scenes/chapter_select.tscn"
const TOUCH_CONTROLS := preload("res://scenes/touch_controls.tscn")

## Test seams, set before _ready: where progress is kept, and what returning
## to the chapter select does (the scene change, by default).
var progress_path := UserData.at(CampaignProgress.PATH)
var leave := Callable()

## The entry being played.
var index := 0
var progress: CampaignProgress

var _game: Game
var _ending: EndingCard
var _dawn: DawnFrame


func _ready() -> void:
	progress = CampaignProgress.open(progress_path)
	index = clampi(Campaign.selected, 0, maxi(0, Campaign.count() - 1))
	_build()


## The game playing the current entry; null on the ending card.
func game() -> Game:
	return _game


func ending() -> EndingCard:
	return _ending


## The dawn's frame, while it is shown; null otherwise.
func dawn() -> DawnFrame:
	return _dawn


func _build() -> void:
	var entry := Campaign.entry(index)
	var file := String(entry.get("file", ""))
	if file == "" or not FileAccess.file_exists(file):
		push_error("CampaignGame: entry %d has no level to play (%s)" % [index, file])
		_leave()
		return
	var packed := load(GAME_SCENE) as PackedScene
	_game = packed.instantiate() as Game
	# Before add_child, or Game._ready falls back to its level_path export.
	_game.level_source = AsciiLevel.from_file(file)
	_game.advance = _advance
	_game.advance_label = _advance_label()
	_game.quit_scene = CHAPTER_SELECT
	# The pause menu's words: a chapter is started over, and left for the
	# chapter select. The boss is chapter V's last room, so it says chapter.
	_game.restart_label = "RESTART CHAPTER"
	_game.quit_label = "QUIT TO CHAPTERS"
	if leave.is_valid():
		_game.leave = leave
	_game.level_completed.connect(_on_completed)
	add_child(_game)
	# The chapter's own card over the level's plain one, which Game._ready
	# has just put up: the numeral and the epigraph are the campaign's, not
	# the level file's, so a level stays playable on its own as it was.
	_game.hud.show_card(Campaign.card(index))
	# The Mirror Tower, as near as this chapter has come to it.
	_game.sky.tower = float(entry.get("tower", 0.0))


func _advance_label() -> String:
	var next := index + 1
	if next >= Campaign.count():
		return String(Campaign.ENDING["title"]).to_upper()
	return "CONTINUE" if Campaign.is_built(next) else "CHAPTERS"


func _on_completed(elapsed: float, relics: int, relics_total: int) -> void:
	progress.record_clear(index, elapsed, relics, relics_total,
		_game.secrets.count, _game.secrets.total)
	var err := progress.save()
	if err != OK:
		push_warning("campaign: could not save %s: %s" % [progress.path, error_string(err)])


## Behind the complete screen's wipe: the next entry, the ending, or back.
func _advance() -> void:
	var next := index + 1
	_clear_game()
	if next >= Campaign.count():
		_show_ending()
	elif Campaign.is_built(next):
		index = next
		Campaign.selected = next
		_build()
	else:
		_leave()


## The dawn: the one frame lit from the east, with the ending's words over
## it (DawnFrame), and from it back to the chapter select.
func _show_ending() -> void:
	_dawn = DawnFrame.new()
	_dawn.name = "Dawn"
	add_child(_dawn)
	_ending = _dawn.card
	_ending.done.connect(_leave)
	# The game's thumb buttons went with the game. The dawn is a screen too,
	# and a phone needs to be told how to leave it (docs/ui.md, "Ways back").
	var controls := TOUCH_CONTROLS.instantiate() as TouchControls
	controls.name = "TouchControls"
	add_child(controls)
	_ending.controls = controls


func _clear_game() -> void:
	if _game == null:
		return
	remove_child(_game)
	_game.queue_free()
	_game = null


func _leave() -> void:
	if leave.is_valid():
		leave.call()
	elif is_inside_tree():
		get_tree().change_scene_to_file.call_deferred(CHAPTER_SELECT)
