class_name PauseMenu
extends Control
## The way out of a game, and the way back into it: a short list over the
## stopped world, shared by every mode that plays -- the adventure's levels,
## Endless, the campaign's chapters and the boss (scripts/core/game.gd), and
## the duel's three ways (scripts/duel/match_scene.gd).
##
## Pause used to stop the game and print PAUSE TO RESUME · SWORD TO QUIT in
## the band, and SWORD quit at once, with nothing in between. That made the
## only way out a press of the button the player had been swinging with a
## second before, and the only way to start a level again a death. A list
## asks what you meant, and it can offer the things a player pauses to do:
## go back to the last torch, start over, leave.
##
## ## What it is, and what it is not
##
## A page, not an overlay. The reserved band (docs/ui.md) is a promise to the
## level art that nothing is written over the floor while it is being read;
## a list of four rows does not fit in its 48 units, and while this is open
## nothing is being read but this. So it takes the whole screen under a heavy
## scrim, set like the chapter select -- the title in the display cut over a
## rule, the rows in the text cut, one caption, the hint at the foot -- and
## the world shows dimly through, stopped, so the player can see where they
## left off.
##
## The rows come from the mode (`open()`), because what "start again" means
## is the mode's: the torch and the chapter in the campaign, the ruin in
## Endless, the match in a duel. A row that would do nothing -- RESTART FROM
## TORCH before any torch is taken -- is dimmed and skipped, not hidden, as
## the wardrobe's are, so the list does not change shape under the thumb.
##
## ## Driven like every page
##
## Up and down choose, JUMP chooses the row, SWORD goes back into the game
## (`back_id`), and the owner reads PAUSE as the same back. The owner calls
## `step()` from its own physics frame, so the menu is read in the same tick
## as the game it stopped and never in a frame the game has already stepped.
## Rows can be tapped: a tap selects, a tap on the selected row chooses it,
## as on the chapter select. With the thumb buttons up the list keeps out of
## JUMP's corner and the caption out of SWORD's reach, so no tap on a row is
## a tap on a button.
##
## It decides nothing: `chosen(id)` says which row, and the owner does it.

signal chosen(id: StringName)

const ROW_HEIGHT := 14.0
const LIST_WIDTH := 176.0
const REPEAT_FIRST := 0.42
## The touch buttons with their hit padding (scripts/ui/touch_controls.gd),
## measured as the chapter select measures them.
const JUMP_CORNER := 66.0
const SWORD_REACH := Vector2(110.0, 50.0)
## Over the HUD's layer, under the touch controls' (50).
const LAYER := 40

## The heading: PAUSED, or what the screen is when the game does not stop.
var title := "PAUSED"
## One line under the list: where you are and how long you have been there.
var caption := ""
## How dark the world goes behind the list. An online duel, which cannot
## stop, keeps more of the fight in view.
var scrim := 0.74
## What SWORD and PAUSE choose: the row that goes back into the game.
var back_id: StringName = &"resume"
## The thumb buttons, if the screen has them: the list keeps clear of them.
var controls: TouchControls

## Each `{"id": StringName, "title": String, "enabled": bool}`.
var _rows: Array[Dictionary] = []
var _index := 0
var _repeat := 0.0
var _hold := 0.0
var _time := 0.0
var _row_rects: Array[Rect2] = []


## A menu on its own layer over `host`: above the world and its HUD, below
## the thumb buttons, whose words it sets. Added as the host's last child, so
## a tap on a row reaches it before the touch controls start a stick with it.
static func install(host: Node) -> PauseMenu:
	var layer := CanvasLayer.new()
	layer.name = "PauseLayer"
	layer.layer = LAYER
	var menu := PauseMenu.new()
	menu.name = "PauseMenu"
	menu.controls = TouchControls.of(host)
	layer.add_child(menu)
	host.add_child(layer)
	return menu


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	get_viewport().size_changed.connect(queue_redraw)


## Shows the menu with `rows`, the cursor on the first that can be chosen.
func open(rows: Array[Dictionary]) -> void:
	_rows = rows
	_index = 0
	for i: int in _rows.size():
		if bool(_rows[i].get("enabled", true)):
			_index = i
			break
	# A stick still held from play is not a move on the list.
	_hold = REPEAT_FIRST
	_repeat = 0.0
	visible = true
	queue_redraw()


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func rows() -> Array[Dictionary]:
	return _rows


func index() -> int:
	return _index


## The id of the row under the cursor.
func selected() -> StringName:
	return StringName(_rows[_index]["id"]) if _index < _rows.size() else &""


## Whether the row `id` is there and can be chosen.
func is_enabled(id: StringName) -> bool:
	for row: Dictionary in _rows:
		if StringName(row["id"]) == id:
			return bool(row.get("enabled", true))
	return false


func move(by: int) -> void:
	if _rows.is_empty():
		return
	var next := _index
	for _step: int in _rows.size():
		next = wrapi(next + by, 0, _rows.size())
		if bool(_rows[next].get("enabled", true)):
			break
	_index = next
	GameAudio.cue("ui_move")
	queue_redraw()


## Puts the cursor on `id` (for a test, or a mode that knows better).
func select(id: StringName) -> void:
	for i: int in _rows.size():
		if StringName(_rows[i]["id"]) == id:
			_index = i


func confirm() -> void:
	if _rows.is_empty() or not visible:
		return
	if not bool(_rows[_index].get("enabled", true)):
		GameAudio.cue("ui_back")
		return
	GameAudio.cue("ui_confirm")
	chosen.emit(selected())


func back() -> void:
	if not visible:
		return
	chosen.emit(back_id)


## One frame of the menu, from its owner's physics frame: the stick, JUMP and
## SWORD. PAUSE is the owner's.
func step(delta: float) -> void:
	if not visible:
		return
	_time += delta
	_repeat = maxf(0.0, _repeat - delta)
	_hold = maxf(0.0, _hold - delta)
	var vertical := Input.get_axis("move_up", "move_down")
	if _hold > 0.0:
		pass
	elif absf(vertical) > 0.5:
		if is_zero_approx(_repeat):
			move(signi(int(signf(vertical))))
			_repeat = REPEAT_FIRST
	else:
		_repeat = 0.0
	if Input.is_action_just_pressed("jump"):
		confirm()
	elif Input.is_action_just_pressed("attack"):
		back()
	queue_redraw()


## A tap at `at`, in this control's coordinates: selects a row, or chooses the
## one already selected. True if it landed on a row.
func tap(at: Vector2) -> bool:
	if not visible:
		return false
	for row: int in _row_rects.size():
		if not _row_rects[row].has_point(at):
			continue
		if row == _index:
			confirm()
		elif bool(_rows[row].get("enabled", true)):
			_index = row
			GameAudio.cue("ui_move")
			queue_redraw()
		# The same thumb is now on the floating stick: a wobble in the tap is
		# not a second move.
		_hold = REPEAT_FIRST
		return true
	return false


## Where row `row` can be tapped; empty until the menu has been drawn once.
func row_rect(row: int) -> Rect2:
	return _row_rects[row] if row < _row_rects.size() else Rect2()


func _input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch == null or not touch.pressed or not visible:
		return
	var local := make_input_local(touch) as InputEventScreenTouch
	if tap(local.position):
		get_viewport().set_input_as_handled()


## --- drawing ----------------------------------------------------------------

func _thumbs_up() -> bool:
	if controls == null:
		return false
	var surface := controls.get_node_or_null(^"Surface") as Control
	return surface != null and surface.visible


## The list's column: centred, or with the thumbs up, centred in what is left
## beside JUMP's corner.
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
	draw_rect(Rect2(Vector2.ZERO, view), Palette.with_alpha(Palette.INK, scrim))
	var column := list_column(view)
	var cx := roundf(column.position.x + column.size.x * 0.5)
	var title_top := column.position.y + 8.0
	UiFont.draw_text(self, title, Vector2(cx, title_top), UiFont.Cut.DISPLAY,
		Palette.PAPER, UiFont.Align.CENTER, 0.85)
	UiMarks.rule(self, Vector2(cx, title_top + UiFont.cap(UiFont.Cut.DISPLAY) + 5.0),
		minf(column.size.x * 0.3, 56.0), Palette.with_alpha(Palette.LIGHT_SOFT, 0.8))

	var list_top := title_top + 30.0
	_row_rects.clear()
	for row: int in _rows.size():
		var rect := Rect2(column.position.x, list_top + row * ROW_HEIGHT - 3.0,
			column.size.x, ROW_HEIGHT)
		_row_rects.append(rect)
		_draw_row(row, rect)

	var caption_y := list_top + _rows.size() * ROW_HEIGHT + 3.0
	var caption_right := column.end.x
	if _thumbs_up():
		caption_right = minf(caption_right, view.x - SWORD_REACH.x)
	if caption != "":
		var line := UiFont.fit(PackedStringArray([caption]), caption_right - column.position.x,
			UiFont.Cut.MICRO)
		if UiFont.width(line, UiFont.Cut.MICRO) <= caption_right - column.position.x:
			UiFont.draw_text(self, line,
				Vector2(roundf((column.position.x + caption_right) * 0.5), caption_y),
				UiFont.Cut.MICRO, Palette.with_alpha(Palette.LIGHT_SOFT, 0.85),
				UiFont.Align.CENTER, 0.6)
	_draw_hint(view, cx)


func _draw_row(row: int, rect: Rect2) -> void:
	var selected_row := row == _index
	var open := bool(_rows[row].get("enabled", true))
	var y := rect.position.y + 3.0
	if selected_row:
		var pulse := 0.17 + sin(_time * 3.4) * 0.05
		draw_rect(Rect2(rect.position.x, y - 3.0, rect.size.x, 13.0),
			Palette.with_alpha(Palette.LIGHT_SOFT, pulse))
		UiMarks.caret(self, Vector2(rect.position.x - 6.0, y + 3.5), 4.0, Palette.LIGHT)
	var ink := Palette.with_alpha(Palette.PAPER, 0.3)
	if open:
		ink = Palette.PAPER if selected_row else Palette.with_alpha(Palette.PAPER, 0.74)
	UiFont.draw_text(self, String(_rows[row]["title"]),
		Vector2(roundf(rect.position.x + rect.size.x * 0.5), y), UiFont.Cut.TEXT, ink,
		UiFont.Align.CENTER, 0.6 if open else 0.3)


## The instructions at the foot of the content rectangle. With the thumbs up
## they move to the left end and say less: the buttons are lettered.
func _draw_hint(view: Vector2, cx: float) -> void:
	var content := UiLayout.content(view)
	var thumbs := _thumbs_up()
	var room := content.size.x if not thumbs else content.size.x * 0.5
	var hint := UiFont.fit(PackedStringArray([
		"UP / DOWN TO CHOOSE   ·   JUMP TO SELECT   ·   SWORD TO GO BACK",
		"UP / DOWN  ·  JUMP SELECT  ·  SWORD BACK",
		"JUMP TO SELECT",
	]), room, UiFont.Cut.MICRO)
	var at := Vector2(cx, content.end.y - UiFont.cap(UiFont.Cut.MICRO) - 2.0)
	var align := UiFont.Align.CENTER
	if thumbs:
		at.x = content.position.x
		align = UiFont.Align.LEFT
	UiFont.draw_text(self, hint, at, UiFont.Cut.MICRO,
		Palette.with_alpha(Palette.PAPER, 0.66), align)
