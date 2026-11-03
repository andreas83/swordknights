class_name ChapterSelect
extends Control
## The Last Light, chapter by chapter: where the title screen's ADVENTURE goes.
##
## CONTINUE first, and the cursor starts on it: the one thing a returning
## player wants is to carry on, and it should cost one press
## (CampaignProgress.continue_index()). Under it every entry of the campaign
## in order (Campaign.entries()), each with its numeral, its title and, on
## the right, what the player has done there: the best time once cleared,
## LOCKED until the one before it is, TO COME while it is still being built.
## The cursor visits every row, locked ones included, because what is ahead
## is part of the reason to go on; jump on a row that cannot be played says
## so with the back sound and does nothing.
##
## Two lines under the list speak for the selected row: the hour it is set
## at and its epigraph, then its bests in full -- time, relics and secrets
## -- or why it cannot be played yet.
##
## ## Driven like every other page
##
## Up/down choose, jump plays, sword or pause go back to the title screen:
## the menu's four actions, so a keyboard, a gamepad and the on-screen stick
## all work. Rows can be tapped, too: a tap selects, a tap on the selected
## row plays it. With the thumb buttons up, the list keeps out of JUMP's
## corner and the caption out of SWORD's reach, as the wardrobe's list does,
## so no tap on a row is also a tap on a button and no line runs under one.

const MENU_SCENE := "res://scenes/menu.tscn"
const CAMPAIGN_SCENE := "res://scenes/campaign_game.tscn"

## The campaign's name, which the page is headed with (an owner decision,
## docs/campaign.md).
const TITLE := "The Last Light"
## Seven rows -- CONTINUE and six entries -- and two caption lines must clear
## the rail; at fifteen the second caption landed on it. Still more than the
## title screen's eleven, and a row is the whole width of the list to tap.
const ROW_HEIGHT := 14.0
const LIST_WIDTH := 228.0
## Room for a numeral, right-aligned, before the titles start.
const NUMERAL_GUTTER := 20.0
## The touch buttons with their hit padding (scripts/ui/touch_controls.gd):
## JUMP fills this square of the bottom-right corner, and SWORD, beside it,
## reaches this far in from the right edge and up from the bottom.
const JUMP_CORNER := 66.0
const SWORD_REACH := Vector2(110.0, 50.0)
const REPEAT_DELAY := 0.22
const REPEAT_FIRST := 0.42

## Test seams, set before _ready: where progress is kept, what playing an
## entry does (`play.call(index)`; the campaign scene by default), and what
## going back does (the title screen).
var store_path := CampaignProgress.PATH
var play := Callable()
var leave := Callable()

var _progress: CampaignProgress
## Each: `{"continue": bool, "index": int}`, CONTINUE first.
var _rows: Array[Dictionary] = []
var _index := 0
var _time := 0.0
var _repeat := 0.0
var _hold := 0.0
var _row_rects: Array[Rect2] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_progress = CampaignProgress.open(store_path)
	var sky := get_node_or_null(^"Sky/ParallaxSky") as ParallaxSky
	if sky != null:
		sky.seed_value = 0xa17e5
	_rows.append({"continue": true, "index": _progress.continue_index()})
	for index: int in Campaign.count():
		_rows.append({"continue": false, "index": index})
	get_viewport().size_changed.connect(queue_redraw)


## --- the model the page shows -----------------------------------------------

func rows() -> Array[Dictionary]:
	return _rows


func index() -> int:
	return _index


func progress() -> CampaignProgress:
	return _progress


## The entry row `row` plays.
func entry_of(row: int) -> int:
	return int(_rows[row]["index"])


## Whether jump on row `row` plays something.
func is_open(row: int) -> bool:
	return _progress.is_playable(entry_of(row))


## What the row says on the left: CONTINUE, or the entry's title.
func row_title(row: int) -> String:
	if bool(_rows[row]["continue"]):
		return "CONTINUE"
	return String(Campaign.entry(entry_of(row))["title"]).to_upper()


## What the row says on the right.
func row_value(row: int) -> String:
	var at := entry_of(row)
	var entry := Campaign.entry(at)
	if bool(_rows[row]["continue"]):
		var target := "%s  %s" % [Campaign.numeral_of(at), String(entry["title"])]
		return target.strip_edges().to_upper()
	if not Campaign.is_built(at):
		return "TO COME"
	if not _progress.is_unlocked(at):
		return "LOCKED"
	var record := _progress.record_of(String(entry["id"]))
	if not bool(record["cleared"]):
		return "NEW"
	return format_time(float(record["best_time"]))


## The two lines under the list for row `row`: its hour and epigraph, then
## its bests or why it cannot be played. Each a list of phrasings, longest
## first, for UiFont.fit.
func caption(row: int) -> Array[PackedStringArray]:
	var at := entry_of(row)
	var entry := Campaign.entry(at)
	var hour := TimeOfDay.label(String(entry["time"])).to_upper()
	var epigraph := String(entry["epigraph"]).to_upper()
	var first := PackedStringArray([hour])
	if epigraph != "":
		first = PackedStringArray(["%s  ·  %s" % [hour, epigraph], epigraph])
	return [first, _standing(at)]


func _standing(at: int) -> PackedStringArray:
	if not Campaign.is_built(at):
		return PackedStringArray(["STILL BEING BUILT"])
	if not _progress.is_unlocked(at):
		var before := String(Campaign.entry(at - 1).get("title", "")).to_upper()
		return PackedStringArray([
			"CLEAR %s TO OPEN IT" % before, "CLEAR %s FIRST" % before, "LOCKED",
		])
	var record := _progress.record_of(String(Campaign.entry(at)["id"]))
	if not bool(record["cleared"]):
		return PackedStringArray(["NOT YET CLEARED"])
	var time := format_time(float(record["best_time"]))
	var relics := "%d/%d" % [int(record["relics"]), int(record["relics_total"])]
	var secrets := "%d/%d" % [int(record["secrets"]), int(record["secrets_total"])]
	# The best time is on the row already; it is what gives way first.
	return PackedStringArray([
		"BEST %s  ·  RELICS %s  ·  SECRETS %s" % [time, relics, secrets],
		"RELICS %s  ·  SECRETS %s" % [relics, secrets],
		"%s RELICS  %s SECRETS" % [relics, secrets],
	])


## Seconds as the HUD's clock reads them, to the tenth: 1:02.4.
static func format_time(seconds: float) -> String:
	if seconds < 0.0:
		return "--"
	var tenths := roundi(seconds * 10.0)
	return "%d:%02d.%d" % [tenths / 600, (tenths / 10) % 60, tenths % 10]


## --- what the player does ---------------------------------------------------

func move(by: int) -> void:
	_index = wrapi(_index + by, 0, _rows.size())
	GameAudio.cue("ui_move")
	queue_redraw()


func confirm() -> void:
	if not is_open(_index):
		GameAudio.cue("ui_back")
		return
	var at := entry_of(_index)
	Campaign.selected = at
	GameAudio.cue("ui_confirm")
	if play.is_valid():
		play.call(at)
	else:
		get_tree().change_scene_to_file(CAMPAIGN_SCENE)


func back() -> void:
	GameAudio.cue("ui_back")
	if leave.is_valid():
		leave.call()
	else:
		get_tree().change_scene_to_file(MENU_SCENE)


## A tap at `at`, in this control's coordinates: selects a row, or plays the
## one already selected. True if it landed on a row. Public so a test can tap
## without synthesising a touch.
func tap(at: Vector2) -> bool:
	for row: int in _row_rects.size():
		if not _row_rects[row].has_point(at):
			continue
		if row == _index:
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
	_hold = maxf(0.0, _hold - delta)
	queue_redraw()

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
	var title_top := column.position.y + 2.0
	UiFont.draw_text(self, TITLE.to_upper(), Vector2(cx, title_top), UiFont.Cut.DISPLAY,
		Palette.PAPER, UiFont.Align.CENTER, 0.85)
	UiMarks.rule(self, Vector2(cx, title_top + UiFont.cap(UiFont.Cut.DISPLAY) + 5.0),
		minf(column.size.x * 0.3, 64.0), Palette.with_alpha(Palette.LIGHT_SOFT, 0.8))

	var list_top := title_top + 27.0
	_row_rects.clear()
	for row: int in _rows.size():
		_draw_row(row, Rect2(column.position.x, list_top + row * ROW_HEIGHT - 3.0,
			column.size.x, ROW_HEIGHT))

	# The caption sits low enough to be beside SWORD, so with the thumbs up it
	# keeps to the stone left of the button and gives way there.
	var caption_y := list_top + _rows.size() * ROW_HEIGHT + 1.0
	var caption_right := column.end.x
	if _thumbs_up():
		caption_right = minf(caption_right, view.x - SWORD_REACH.x)
	var caption_cx := roundf((column.position.x + caption_right) * 0.5)
	var lines := caption(_index)
	var tints: Array[Color] = [Palette.with_alpha(Palette.LIGHT_SOFT, 0.85),
		Palette.with_alpha(Palette.PAPER, 0.7)]
	for line: int in lines.size():
		var text := UiFont.fit(lines[line], caption_right - column.position.x, UiFont.Cut.MICRO)
		UiFont.draw_text(self, text, Vector2(caption_cx, caption_y + line * 8.0),
			UiFont.Cut.MICRO, tints[line], UiFont.Align.CENTER, 0.6)

	_draw_hint(view, cx, rail)


func _draw_row(row: int, rect: Rect2) -> void:
	_row_rects.append(rect)
	var selected := row == _index
	var open := is_open(row)
	var y := rect.position.y + 3.0
	var continuing := bool(_rows[row]["continue"])
	var at := entry_of(row)

	if selected:
		var pulse := 0.17 + sin(_time * 3.4) * 0.05
		draw_rect(Rect2(rect.position.x, y - 3.0, rect.size.x, 13.0),
			Palette.with_alpha(Palette.LIGHT_SOFT, pulse))
		UiMarks.caret(self, Vector2(rect.position.x - 6.0, y + 3.5), 4.0, Palette.LIGHT)

	var ink := Palette.with_alpha(Palette.PAPER, 0.3)
	if open:
		ink = Palette.PAPER if selected else Palette.with_alpha(Palette.PAPER, 0.74)
	var title_x := rect.position.x + NUMERAL_GUTTER
	if not continuing:
		var numeral := String(Campaign.entry(at)["numeral"])
		if numeral != "":
			UiFont.draw_text(self, numeral, Vector2(title_x - 6.0, y), UiFont.Cut.TEXT, ink,
				UiFont.Align.RIGHT, 0.6 if open else 0.3)
		else:
			# A finale is drawn under its chapter: no numeral, set in.
			UiMarks.lozenge(self, Vector2(title_x + 2.0, y + 3.5), 2.0, ink)
			title_x += 8.0

	var value := row_value(row)
	var title := row_title(row)
	if continuing:
		# The title is fixed; the chapter it goes to gives way instead.
		var spare := rect.end.x - 6.0 - (title_x + UiFont.width(title, UiFont.Cut.TEXT) + 8.0)
		value = UiFont.fit(PackedStringArray([
			value, value.replace(" THE ", " "), Campaign.numeral_of(at),
		]), spare, UiFont.Cut.MICRO)
	else:
		var room := rect.end.x - 6.0 - UiFont.width(value, UiFont.Cut.MICRO) - 8.0 - title_x
		title = UiFont.fit(PackedStringArray([title, title.trim_prefix("THE ")]), room,
			UiFont.Cut.TEXT)
	UiFont.draw_text(self, title, Vector2(title_x, y), UiFont.Cut.TEXT, ink,
		UiFont.Align.LEFT, 0.6 if open else 0.3)

	var value_ink := Palette.with_alpha(Palette.PAPER, 0.45)
	if continuing or (open and _progress.is_cleared(String(Campaign.entry(at)["id"]))):
		value_ink = Palette.LIGHT
	UiFont.draw_text(self, value, Vector2(rect.end.x - 6.0, y + 1.0), UiFont.Cut.MICRO,
		value_ink, UiFont.Align.RIGHT, 0.5)


## The instructions, on the rail, as the title screen cuts its own. With the
## thumb buttons up it moves to the rail's left end and says less: the
## buttons are lettered.
func _draw_hint(view: Vector2, cx: float, rail: float) -> void:
	var content := UiLayout.content(view)
	var thumbs := _thumbs_up()
	var room := content.size.x if not thumbs else content.size.x * 0.5
	var hint := UiFont.fit(PackedStringArray([
		"UP / DOWN TO CHOOSE   ·   JUMP TO PLAY   ·   SWORD TO GO BACK",
		"UP / DOWN  ·  JUMP TO PLAY  ·  SWORD BACK",
		"JUMP TO PLAY",
	]), room, UiFont.Cut.MICRO)
	var at := Vector2(cx, rail + 1.0)
	var align := UiFont.Align.CENTER
	if thumbs:
		at.x = content.position.x
		align = UiFont.Align.LEFT
	UiFont.draw_text(self, hint, at, UiFont.Cut.MICRO,
		Palette.with_alpha(Palette.PAPER, 0.66), align)
