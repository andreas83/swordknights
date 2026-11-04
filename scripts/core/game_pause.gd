class_name GamePause
extends RefCounted
## The level's pause menu as a game plays it: when it opens -- PAUSE,
## Android's Back, the app losing the screen -- what its rows are, and what
## each one does. The list itself, its drawing and its taps, are PauseMenu's
## (scripts/ui/pause_menu.gd), which the duel shares; this is the half that
## is the adventure's.
##
## Its own file because Game is the referee and was at the length a file is
## allowed (.gdlintrc), and the menu is the one part of it that is about the
## player stepping out of play rather than about play. It holds no state of
## the level's: it asks the game, and has the game do what a row means.
##
## Driven from Game's physics step, never from a callback: `step()` reads
## PAUSE and the app's requests in the same tick as the game they stop.
##
## ## The rows
##
## RESUME, RESTART FROM TORCH, RESTART <the mode's unit>, QUIT TO <where the
## mode came from>. Each is something a player pauses to do, in the order
## they are reached for:
##
## - **Resume** first and under the cursor, so pause-then-JUMP is the
##   cheapest thing on the list and a stray pause costs nothing.
## - **From the torch** is what a death does, without the death: for a player
##   who has walked into a state they would rather not play out -- a gate shut
##   behind them, a relic fallen out of reach. It keeps what a death keeps
##   (the clock runs, the latches hold, the fallen stay down) because it IS
##   the respawn, and before any torch is taken it is dimmed, since it would
##   be the next row.
## - **Restart** is the level from nothing -- clock, relics, secrets -- for a
##   player going for a clean run; in the campaign it is the chapter, in
##   Endless the same ruin, never a new one: a roll is reported by its seed.
## - **Quit** is last and furthest from the thumb, and goes where the mode
##   came from: the chapter select in the campaign, the title screen
##   otherwise. It is the only way out, and it is never one press from play.
##
## ## Back, and going away
##
## Back is PAUSE in play and on the menu, and SWORD on the complete screen,
## where SWORD is the way out. Going away -- a call, a switch to another app,
## the notification shade -- opens the menu: a phone call should not cost the
## prince his life while the phone is at an ear. Both are heard as
## notifications (`hear()`), outside any frame, and answered in the next
## step. One that arrives behind a wipe or in the death beat waits for play
## rather than being dropped: the player asked for the menu, and gets it as
## the shadow lifts.

var _game: Game
## A RESUME chosen with JUMP or SWORD, waiting for the button to come up.
var _resuming := false
var _back_asked := false
var _went_away := false


func _init(game: Game) -> void:
	_game = game


## From Game._notification().
func hear(what: int) -> void:
	match what:
		Node.NOTIFICATION_WM_GO_BACK_REQUEST:
			_back_asked = true
		Node.NOTIFICATION_APPLICATION_PAUSED, Node.NOTIFICATION_APPLICATION_FOCUS_OUT:
			_went_away = true


## One physics step, before the game reads its phase: a resume landing, then
## PAUSE, then what the app asked for.
func step() -> void:
	# A resume chosen with JUMP or SWORD lands here, once the button that
	# chose it is up, so the press is not also the prince's first jump or
	# swing (see resume()).
	if _resuming and not (Input.is_action_pressed("jump") or Input.is_action_pressed("attack")):
		_resuming = false
		if _game.phase == Game.Phase.PAUSED:
			_game._set_phase(Game.Phase.PLAYING)
	# A transition owns the screen while it runs, so nothing queues a second
	# one behind it.
	if Flow.busy():
		return
	if Input.is_action_just_pressed("pause"):
		toggle()
	if _game.phase == Game.Phase.DYING:
		return
	if _back_asked:
		_back_asked = false
		if _game.phase == Game.Phase.COMPLETE:
			_game._quit()
			return
		# On a PAUSED with no menu up, the RESUME already chosen is on its
		# way; toggle() leaves that alone.
		toggle()
	if _went_away:
		_went_away = false
		if _game.phase == Game.Phase.PLAYING:
			toggle()


## PAUSE: opens the menu over play, closes it back into play.
func toggle() -> void:
	var menu := _game.menu
	if _game.phase == Game.Phase.PLAYING:
		_game._set_phase(Game.Phase.PAUSED)
		menu.open(rows())
		GameAudio.cue("pause_in")
	elif _game.phase == Game.Phase.PAUSED and menu.is_open():
		menu.close()
		_game._set_phase(Game.Phase.PLAYING)
		GameAudio.cue("pause_out")


func rows() -> Array[Dictionary]:
	return [
		{"id": &"resume", "title": "RESUME", "enabled": true},
		{"id": &"torch", "title": "RESTART FROM TORCH",
			"enabled": not _game.checkpoint.is_equal_approx(
				_game.level.spawn_world_position())},
		{"id": &"restart", "title": _game.restart_label, "enabled": true},
		{"id": &"quit", "title": _game.quit_label, "enabled": true},
	]


## The line under the list: the clock, the relics, the secrets.
func caption() -> String:
	var said := "%s  ·  %d/%d RELICS" % [ChapterSelect.format_time(_game.elapsed),
		_game.relics, _game.relics_total]
	if _game.secrets.total > 0:
		said += "  ·  SECRETS %d/%d" % [_game.secrets.count, _game.secrets.total]
	return said


## PauseMenu.chosen: does what the row means.
func choose(id: StringName) -> void:
	if _game.phase != Game.Phase.PAUSED or Flow.busy():
		return
	var menu := _game.menu
	match id:
		&"resume":
			resume()
		&"torch":
			menu.close()
			Flow.wipe(_game, _game._respawn, Flow.Pace.FAST)
		&"restart":
			menu.close()
			Flow.wipe(_game, _game._restart)
		&"quit":
			menu.close()
			_game._quit()


## Back to play once the button is up. The press that chose RESUME is JUMP or
## SWORD, and the prince finds his presses as edges against what he last saw
## held -- which, frozen, was nothing -- so thawed while it is down he would
## jump or swing with it.
func resume() -> void:
	_game.menu.close()
	GameAudio.cue("pause_out")
	_resuming = true
