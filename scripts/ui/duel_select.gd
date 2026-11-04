class_name DuelSelect
extends Control
## The duel, three ways: where the title screen's DUEL goes.
##
## The title screen had a row for each of them -- DUEL, DUEL VS CPU with its
## three levels stepped on the row, DUEL ONLINE -- which made three of its
## eight rows the same mode, and the one with levels the only row on that
## screen that did two things. Now the title screen has one DUEL, and this
## page asks how: ONE KEYBOARD, VS CPU, or ONLINE. It is the chapter select's
## shape on purpose (scripts/ui/chapter_select.gd), so the two second steps
## read as one place: the same sky, wash and rail, a title over a short list,
## the selected row lit, a caption under it, the hint cut in the rail.
##
## ## What it remembers
##
## The cursor opens on the way last played, and VS CPU on the level last
## played at (DuelChoice, user://duel.cfg). Someone who plays the computer
## every evening presses DUEL and then jump; nobody has to step past two
## other rows or walk the level up from EASY each time. Saved when a duel is
## started, not while browsing: what is remembered is what was played.
##
## ## The level is on its row
##
## VS CPU shows its level on the right, between carets that say which way it
## can step -- EASY points only right, HARD only left -- and left and right
## step it while the row is selected, stopping at the ends: HARD is a wall to
## push against, not a way round to EASY. The same left/right sets a value on
## every other page, so the level needs no page of its own; a third step would
## be one press more for the choice made most often.
##
## ## Driven like every other page
##
## Up/down choose, left/right set the level, jump plays, sword or pause go back
## to the title screen. Rows can be tapped: a tap selects, a tap on the selected
## row plays it, and a tap on VS CPU's level steps it toward the side tapped.
## With the thumb buttons up, the list keeps out of JUMP's corner and the
## caption out of SWORD's reach, as the chapter select's does.

const MENU_SCENE := "res://scenes/menu.tscn"

const TITLE := "DUEL"
## Three rows, so each is as tall as a thumb wants: sixteen units is about
## 6 mm on a phone held sideways, against the chapter select's fourteen.
const ROW_HEIGHT := 16.0
const LIST_WIDTH := 228.0
## The level and its carets, at the right end of VS CPU's row.
const LEVEL_SLOT := 66.0
## The touch buttons with their hit padding (scripts/ui/touch_controls.gd),
## as the chapter select measures them.
const JUMP_CORNER := 66.0
const SWORD_REACH := Vector2(110.0, 50.0)
const REPEAT_FIRST := 0.42

## What each row says: its title, what it is on the right, and the caption's
## phrasings, longest first.
const ROWS: Array[Dictionary] = [
	{
		"title": "ONE KEYBOARD",
		"value": "TWO PLAYERS",
		"caption": ["TWO PLAYERS, ONE KEYBOARD  ·  A D W S AGAINST THE ARROWS",
			"TWO PLAYERS, ONE KEYBOARD"],
	},
	{
		"title": "VS CPU",
		"value": "",
		"caption": ["ONE PHONE AGAINST THE COMPUTER", "AGAINST THE COMPUTER"],
	},
	{
		"title": "ONLINE",
		"value": "TWO PHONES",
		"caption": ["TWO PHONES ON ONE WI-FI, PAIRED WITH A CODE",
			"TWO PHONES ON ONE WI-FI"],
	},
]
const CPU_ROW := 1

## Test seams, set before _ready: where the choice is kept, what playing does
## (`play.call(scene_path)`; a scene change by default), and what going back
## does (the title screen).
var store_path := DuelChoice.PATH
var play := Callable()
var leave := Callable()

var _choice: DuelChoice
var _index := 0
var _time := 0.0
var _repeat := 0.0
var _repeat_across := 0.0
var _hold := 0.0
var _row_rects: Array[Rect2] = []
var _level_rect := Rect2()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_choice = DuelChoice.open(store_path)
	_index = clampi(_choice.way, 0, ROWS.size() - 1)
	var sky := get_node_or_null(^"Sky/ParallaxSky") as ParallaxSky
	if sky != null:
		sky.seed_value = 0xa17e5
	get_viewport().size_changed.connect(queue_redraw)


## --- the model the page shows -----------------------------------------------

func index() -> int:
	return _index


func choice() -> DuelChoice:
	return _choice


func row_title(row: int) -> String:
	return String(ROWS[row]["title"])


## What the row says on the right: VS CPU's level, or what the others are.
func row_value(row: int) -> String:
	if row == CPU_ROW:
		return DuelBrain.level_name(_choice.level)
	return String(ROWS[row]["value"])


## --- what the player does ---------------------------------------------------

func move(by: int) -> void:
	_index = wrapi(_index + by, 0, ROWS.size())
	GameAudio.cue("ui_move")
	queue_redraw()


## Steps VS CPU's level, if that row is selected. Stops at the ends.
func shift_level(by: int) -> void:
	if _index != CPU_ROW:
		return
	var next := clampi(int(_choice.level) + by, 0, DuelBrain.LEVEL_NAMES.size() - 1)
	if next == int(_choice.level):
		GameAudio.cue("ui_back")
		return
	_choice.level = next as DuelBrain.Difficulty
	GameAudio.cue("ui_move")
	queue_redraw()


## Plays the selected way, and remembers it and the level.
func confirm() -> void:
	_choice.way = _index
	if _choice.save() != OK:
		push_warning("the duel choice was not saved to %s" % store_path)
	var scene := _choice.scene()
	if not ResourceLoader.exists(scene):
		GameAudio.cue("ui_back")
		push_error("DUEL's %s points at a missing scene: %s" % [row_title(_index), scene])
		return
	GameAudio.cue("ui_confirm")
	if play.is_valid():
		play.call(scene)
	else:
		get_tree().change_scene_to_file(scene)


func back() -> void:
	GameAudio.cue("ui_back")
	if leave.is_valid():
		leave.call()
	else:
		get_tree().change_scene_to_file(MENU_SCENE)


## A tap at `at`, in this control's coordinates: steps VS CPU's level if it
## lands on it, otherwise selects a row or plays the one already selected.
## True if it landed on a row. Public so a test can tap without a touch.
func tap(at: Vector2) -> bool:
	for row: int in _row_rects.size():
		if not _row_rects[row].has_point(at):
			continue
		if row == _index and row == CPU_ROW and _level_rect.has_point(at):
			shift_level(-1 if at.x < _level_rect.get_center().x else 1)
		elif row == _index:
			confirm()
		else:
			_index = row
			GameAudio.cue("ui_move")
			queue_redraw()
		# The same thumb is now on the floating stick: a wobble in the tap is
		# not a second move.
		_hold = REPEAT_FIRST
		return true
	return false


## Where a row is, in this control's coordinates, as last drawn. Empty before
## the first draw.
func row_rect(row: int) -> Rect2:
	return _row_rects[row] if row < _row_rects.size() else Rect2()


func level_rect() -> Rect2:
	return _level_rect


func _input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch == null or not touch.pressed:
		return
	var local := make_input_local(touch) as InputEventScreenTouch
	if tap(local.position):
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_time += delta
	_repeat = maxf(0.0, _repeat - delta)
	_repeat_across = maxf(0.0, _repeat_across - delta)
	_hold = maxf(0.0, _hold - delta)
	queue_redraw()
	TouchControls.label(self, "PLAY", "BACK")

	var vertical := Input.get_axis("move_up", "move_down")
	var across := Input.get_axis("move_left", "move_right")
	if _hold > 0.0:
		pass
	elif absf(vertical) > 0.5:
		if is_zero_approx(_repeat):
			move(signi(int(signf(vertical))))
			_repeat = REPEAT_FIRST
	elif absf(across) > 0.5:
		if is_zero_approx(_repeat_across):
			shift_level(signi(int(signf(across))))
			_repeat_across = REPEAT_FIRST
	else:
		_repeat = 0.0
		_repeat_across = 0.0

	if Input.is_action_just_pressed("jump"):
		confirm()
	elif Input.is_action_just_pressed("attack") or Input.is_action_just_pressed("pause"):
		back()


## --- drawing ----------------------------------------------------------------

func _thumbs_up() -> bool:
	var surface := get_node_or_null(^"TouchControls/Surface") as Control
	return surface != null and surface.visible


## The list's column: centred on the page, or, with the thumb buttons up,
## centred in what is left of the page beside their corner.
func list_column(view: Vector2) -> Rect2:
	var content := UiLayout.content(view)
	var left := content.position.x
	var right := content.end.x
	if _thumbs_up():
		right = minf(right, view.x - JUMP_CORNER)
	var wide := minf(LIST_WIDTH, right - left)
	return Rect2(roundf(left + (right - left - wide) * 0.5), content.position.y,
		wide, content.size.y)


func _draw() -> void:
	var view := size if size.x > 0.0 else get_viewport_rect().size
	if view.x <= 0.0:
		return
	UiMarks.wash(self, Rect2(0.0, 0.0, view.x, view.y * 0.5),
		Palette.with_alpha(Palette.INK, 0.5), Palette.with_alpha(Palette.INK, 0.32))
	UiMarks.wash(self, Rect2(0.0, view.y * 0.5, view.x, view.y * 0.5),
		Palette.with_alpha(Palette.INK, 0.32), Palette.with_alpha(Palette.INK, 0.5))
	var rail := UiMarks.balustrade(self, view)

	var column := list_column(view)
	var cx := roundf(column.position.x + column.size.x * 0.5)
	# Set lower than the chapter select's: three rows leave the room, and the
	# list then sits in the middle of the stone rather than up under the sky.
	var title_top := column.position.y + 14.0
	UiFont.draw_text(self, TITLE, Vector2(cx, title_top), UiFont.Cut.DISPLAY,
		Palette.PAPER, UiFont.Align.CENTER, 0.85)
	UiMarks.rule(self, Vector2(cx, title_top + UiFont.cap(UiFont.Cut.DISPLAY) + 5.0),
		minf(column.size.x * 0.3, 64.0), Palette.with_alpha(Palette.LIGHT_SOFT, 0.8))

	var list_top := title_top + 30.0
	_row_rects.clear()
	for row: int in ROWS.size():
		_draw_row(row, Rect2(column.position.x, list_top + row * ROW_HEIGHT - 4.0,
			column.size.x, ROW_HEIGHT))

	# The caption keeps to the stone left of SWORD when the thumbs are up.
	var caption_y := list_top + ROWS.size() * ROW_HEIGHT + 3.0
	var caption_right := column.end.x
	if _thumbs_up():
		caption_right = minf(caption_right, view.x - SWORD_REACH.x)
	var phrasings := PackedStringArray(ROWS[_index]["caption"] as Array)
	var text := UiFont.fit(phrasings, caption_right - column.position.x, UiFont.Cut.MICRO)
	UiFont.draw_text(self, text,
		Vector2(roundf((column.position.x + caption_right) * 0.5), caption_y),
		UiFont.Cut.MICRO, Palette.with_alpha(Palette.LIGHT_SOFT, 0.85),
		UiFont.Align.CENTER, 0.6)

	_draw_hint(view, cx, rail)


func _draw_row(row: int, rect: Rect2) -> void:
	_row_rects.append(rect)
	var selected := row == _index
	var y := rect.position.y + 4.0

	if selected:
		var pulse := 0.17 + sin(_time * 3.4) * 0.05
		draw_rect(Rect2(rect.position.x, y - 3.0, rect.size.x, 13.0),
			Palette.with_alpha(Palette.LIGHT_SOFT, pulse))
		UiMarks.caret(self, Vector2(rect.position.x - 6.0, y + 3.5), 4.0, Palette.LIGHT)

	var ink := Palette.PAPER if selected else Palette.with_alpha(Palette.PAPER, 0.74)
	UiFont.draw_text(self, row_title(row), Vector2(rect.position.x + 12.0, y),
		UiFont.Cut.TEXT, ink, UiFont.Align.LEFT, 0.6)

	var right := rect.end.x - 6.0
	if row != CPU_ROW:
		UiFont.draw_text(self, row_value(row), Vector2(right, y + 1.0), UiFont.Cut.MICRO,
			Palette.with_alpha(Palette.PAPER, 0.45), UiFont.Align.RIGHT, 0.5)
		return

	# The level, centred in its slot between the carets that say which way it
	# can go. Lit while the row is selected, since only then do they move it.
	var slot := Rect2(right - LEVEL_SLOT, rect.position.y, LEVEL_SLOT, rect.size.y)
	_level_rect = slot
	var level := row_value(row)
	var mid := y + 1.0 + UiFont.cap(UiFont.Cut.MICRO) * 0.5
	var lit := Palette.LIGHT if selected else Palette.with_alpha(Palette.LIGHT, 0.7)
	UiFont.draw_text(self, level, Vector2(roundf(slot.get_center().x), y + 1.0),
		UiFont.Cut.MICRO, lit, UiFont.Align.CENTER, 0.5)
	if not selected:
		return
	if int(_choice.level) > 0:
		UiMarks.caret(self, Vector2(slot.position.x + 4.0, mid), -3.0, Palette.LIGHT)
	if int(_choice.level) < DuelBrain.LEVEL_NAMES.size() - 1:
		UiMarks.caret(self, Vector2(slot.end.x - 4.0, mid), 3.0, Palette.LIGHT)


## The instructions, on the rail, as the title screen cuts its own. With the
## thumb buttons up it moves to the rail's left end and says less: the
## buttons are lettered.
func _draw_hint(view: Vector2, cx: float, rail: float) -> void:
	var content := UiLayout.content(view)
	var thumbs := _thumbs_up()
	var room := content.size.x if not thumbs else content.size.x * 0.5
	var phrasings := PackedStringArray([
		"UP / DOWN TO CHOOSE   ·   JUMP TO BEGIN   ·   SWORD TO GO BACK",
		"UP / DOWN  ·  JUMP TO BEGIN  ·  SWORD BACK",
		"JUMP TO BEGIN",
	])
	if _index == CPU_ROW:
		phrasings = PackedStringArray([
			"LEFT / RIGHT: HOW HARD   ·   JUMP TO BEGIN   ·   SWORD TO GO BACK",
			"LEFT / RIGHT: HOW HARD  ·  JUMP TO BEGIN",
			"LEFT / RIGHT  ·  JUMP",
		])
	var hint := UiFont.fit(phrasings, room, UiFont.Cut.MICRO)
	var at := Vector2(cx, rail + 1.0)
	var align := UiFont.Align.CENTER
	if thumbs:
		at.x = content.position.x
		align = UiFont.Align.LEFT
	UiFont.draw_text(self, hint, at, UiFont.Cut.MICRO,
		Palette.with_alpha(Palette.PAPER, 0.66), align)
