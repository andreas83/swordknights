class_name SettingsPanel
extends Control
## Volume, the one switch that silences the game, haptics, and the one assist.
##
## A sub-screen of the menu rather than a mode: it is not something you play,
## and ModeRegistry is the list of things you play.
##
## LONGER WARNINGS is here because this is where a player looks for anything
## they can set, and a page of its own for one switch would be a page nobody
## opens. It writes through Assist.set_longer_warnings(), which saves for
## itself (scripts/core/assist.gd). HAPTICS is here for the same reason: the
## buzz on a landing or a hit (Flow.haptic()) was on by default on a phone and
## could not be switched off anywhere. It writes through
## Flow.set_haptics_enabled(), which saves for itself, and buzzes once when
## switched on, so the switch is felt as well as read.
##
## Everything here already existed — AudioDirector persists master, music, SFX
## and mute to user://audio.cfg — and only a keyboard `M` could reach any of
## it. This panel is the rest of that feature. It writes through
## `AudioDirector.set_volume()` and `AudioDirector.toggle_mute()`, which save
## for themselves, and it listens to `AudioDirector.settings.changed` so a
## change made elsewhere (the mute key, the touch button) is on screen
## immediately.
##
## Driven by the same four actions as the menu, so a keyboard, a gamepad and
## the on-screen stick all work: up/down to choose, left/right to set, jump to
## confirm, sword to go back. Rows can be tapped, as on every page: a tap
## selects, a tap on the selected row does what JUMP would -- flips a switch,
## goes BACK -- and a tap on a gauge's cells sets the volume there.
##
## Under the list, small and dim, the build that is running: its name, build
## number and commit. Here rather than on the title screen because only the
## person reporting a bug needs it, and they will look for it where the
## settings are; the title screen's lintel is kept for the one notice that
## needs to be seen, a newer build.

signal closed()

const BuildStamp := preload("res://scripts/core/build_stamp.gd")

const REPEAT_DELAY := 0.22
const REPEAT_FIRST := 0.42
const STEP := 0.1
const GAUGE_CELLS := 10
## Thirteen since HAPTICS made it seven rows: at fifteen (six rows) the build
## line under a seventh landed on the rail. Thirteen is the selection band's
## own height, so the bands meet and a tap has no gap between rows to fall in.
const ROW_HEIGHT := 13.0
## From the top of the title to the first row: four units tighter than six
## rows had, for the same reason.
const LIST_DROP := 30.0
## The gauge's cells, as drawn and as tapped.
const GAUGE_CELL := Vector2(4.0, 7.0)
## How long the stick is ignored after a tap: the same thumb is now on the
## floating stick, and a wobble in the tap is not a second move.
const TAP_HOLD := 0.42
## SWORD with its hit padding (scripts/ui/touch_controls.gd), measured from
## the bottom right as the chapter select measures it.
const SWORD_REACH := Vector2(110.0, 50.0)
const COLUMN_WIDTH := 168.0

enum Kind { GAUGE, TOGGLE, ACTION }

## Test seam: set before _ready to drive a panel without the autoload.
var audio: Node

var _index := 0
var _repeat := 0.0
var _hold := 0.0
var _settings: AudioSettings
## Where each row, and each gauge's cells, can be tapped, as last drawn.
var _row_rects: Array[Rect2] = []
var _gauge_rects: Dictionary = {}
var _rows: Array[Dictionary] = [
	{"id": "master", "label": "MASTER", "kind": Kind.GAUGE, "bus": &"Master"},
	{"id": "music", "label": "MUSIC", "kind": Kind.GAUGE, "bus": &"Music"},
	{"id": "sfx", "label": "SWORDS", "kind": Kind.GAUGE, "bus": &"SFX"},
	{"id": "mute", "label": "MUTE", "kind": Kind.TOGGLE, "bus": &""},
	{"id": "haptics", "label": "HAPTICS", "kind": Kind.TOGGLE, "bus": &""},
	{"id": "warnings", "label": "LONGER WARNINGS", "kind": Kind.TOGGLE, "bus": &""},
	{"id": "back", "label": "BACK", "kind": Kind.ACTION, "bus": &""},
]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if audio == null:
		audio = get_tree().root.get_node_or_null(^"AudioDirector")
	_settings = audio.settings if audio != null else AudioSettings.new()
	if not _settings.changed.is_connected(queue_redraw):
		_settings.changed.connect(queue_redraw)
	get_viewport().size_changed.connect(queue_redraw)
	# A hidden Control is not laid out, so the frame it is shown on its rect is
	# still zero. Redraw once it has one.
	resized.connect(queue_redraw)
	visibility_changed.connect(queue_redraw)


func rows() -> Array[Dictionary]:
	return _rows


## The running build, as this page prints it.
func build_line() -> String:
	return DevUpdate.running_label(BuildStamp.NAME, BuildStamp.CODE, BuildStamp.SHA)


func index() -> int:
	return _index


## The value a row shows, 0..1 for a gauge and 0/1 for the switch. Public so a
## test can read the panel without reading pixels.
func value_of(row: Dictionary) -> float:
	match int(row["kind"]):
		Kind.GAUGE:
			return _settings.linear_for(row["bus"])
		Kind.TOGGLE:
			return 1.0 if is_on(row) else 0.0
		_:
			return 0.0


## Whether a toggle row is switched on: MUTE when the game is silent, LONGER
## WARNINGS when the assist is on, HAPTICS when the phone buzzes.
func is_on(row: Dictionary) -> bool:
	match String(row["id"]):
		"warnings":
			return Assist.longer_warnings()
		"haptics":
			return Flow.haptics_enabled()
		_:
			return _settings.muted


func move(by: int) -> void:
	_index = wrapi(_index + by, 0, _rows.size())
	_play("ui_move")
	queue_redraw()


## Left/right on the selected row. `by` is -1 or 1.
func adjust(by: int) -> void:
	var row := _rows[_index]
	match int(row["kind"]):
		Kind.GAUGE:
			var next := snappedf(
				clampf(value_of(row) + float(by) * STEP, 0.0, 1.0), STEP
			)
			if is_equal_approx(next, value_of(row)):
				return
			_set_volume(row["bus"], next)
			_play("ui_move")
		Kind.TOGGLE:
			# Right turns the switch on, left turns it off; on the MUTE row
			# "on" is silence.
			if (by > 0) != is_on(row):
				_flip(row)
		_:
			return
	queue_redraw()


## Jump on the selected row.
func confirm() -> void:
	var row := _rows[_index]
	match int(row["kind"]):
		Kind.ACTION:
			_play("ui_back")
			closed.emit()
		Kind.TOGGLE:
			_flip(row)
			queue_redraw()
		_:
			# A gauge has nothing to confirm; nudge it so the press is felt.
			adjust(1)


func back() -> void:
	_play("ui_back")
	closed.emit()


## A tap at `at`, in this control's coordinates: selects a row, or on the
## selected row does what JUMP does there -- except on a gauge's cells, where
## it sets the volume to the cell tapped (the first cell, tapped when it is
## all that is lit, is silence). True if it landed on a row; a tap that is a
## thumb button's is the button's alone (TouchControls.claims()).
func tap(at: Vector2) -> bool:
	if not visible or TouchControls.claims(get_parent(), at):
		return false
	for row: int in _row_rects.size():
		if not _row_rects[row].has_point(at):
			continue
		_hold = TAP_HOLD
		if row != _index:
			_index = row
			_play("ui_move")
		elif _gauge_rects.has(row) and (_gauge_rects[row] as Rect2).has_point(at):
			_set_from_cell(_rows[row], _gauge_rects[row], at.x)
		else:
			confirm()
		queue_redraw()
		return true
	return false


## Where row `row` can be tapped; empty until the panel has been drawn.
func row_rect(row: int) -> Rect2:
	return _row_rects[row] if row < _row_rects.size() else Rect2()


## Where row `row`'s gauge can be tapped; empty for a row with none.
func gauge_rect(row: int) -> Rect2:
	return _gauge_rects.get(row, Rect2())


func _set_from_cell(row: Dictionary, gauge: Rect2, x: float) -> void:
	var cell := clampi(int((x - gauge.position.x) / (GAUGE_CELL.x + 1.0)), 0, GAUGE_CELLS - 1)
	var next := float(cell + 1) * STEP
	if cell == 0 and is_equal_approx(value_of(row), next):
		next = 0.0
	if is_equal_approx(next, value_of(row)):
		return
	_set_volume(row["bus"], next)
	_play("ui_move")


## Touch only, as the title screen listens: the emulated mouse click a real
## touch also makes would be a second tap.
func _input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch == null or not touch.pressed or not visible:
		return
	var local := make_input_local(touch) as InputEventScreenTouch
	if tap(local.position):
		get_viewport().set_input_as_handled()


## What JUMP does on the selected row, for the thumb button's word: a gauge
## steps up, a switch flips, BACK goes back.
func jump_word() -> String:
	match int(_rows[_index]["kind"]):
		Kind.GAUGE:
			return "LOUDER|MORE"
		Kind.TOGGLE:
			return "SWITCH"
		_:
			return "BACK"


func _process(delta: float) -> void:
	if not visible:
		return
	_repeat = maxf(0.0, _repeat - delta)
	_hold = maxf(0.0, _hold - delta)
	# The page draws over the title screen, whose controls these are.
	TouchControls.label(get_parent(), jump_word(), "BACK")

	var vertical := Input.get_axis("move_up", "move_down")
	var horizontal := Input.get_axis("move_left", "move_right")

	if _hold > 0.0:
		pass
	elif absf(vertical) > 0.5:
		if is_zero_approx(_repeat):
			move(signi(int(signf(vertical))))
			_repeat = REPEAT_FIRST
	elif absf(horizontal) > 0.5:
		if is_zero_approx(_repeat):
			adjust(signi(int(signf(horizontal))))
			_repeat = REPEAT_DELAY
	else:
		_repeat = 0.0

	if Input.is_action_just_pressed("jump"):
		confirm()
	elif Input.is_action_just_pressed("attack") or Input.is_action_just_pressed("pause"):
		back()


func _set_volume(bus: StringName, value: float) -> void:
	if audio != null:
		audio.set_volume(bus, value)
	else:
		match String(bus):
			"Music":
				_settings.music = value
			"SFX":
				_settings.sfx = value
			_:
				_settings.master = value


func _flip(row: Dictionary) -> void:
	match String(row["id"]):
		"warnings":
			var err := Assist.set_longer_warnings(not Assist.longer_warnings())
			if err != OK:
				push_warning("assist: could not save: %s" % error_string(err))
		"haptics":
			Flow.set_haptics_enabled(not Flow.haptics_enabled())
			# Felt as well as read: what HAPTICS ON means, once.
			Flow.haptic(0.6)
		_:
			_toggle_mute()
			return
	_play("ui_confirm")


func _toggle_mute() -> void:
	if audio != null:
		audio.toggle_mute()
	else:
		_settings.muted = not _settings.muted
	_play("ui_confirm")


func _play(event: String) -> void:
	if audio != null:
		audio.play(event)


## --- drawing ----------------------------------------------------------------

func _draw() -> void:
	# Measured against the viewport rather than this node's own rect: a panel
	# that was created hidden has no rect until the layout pass after it is
	# shown, and the first frame of a settings screen should not be blank.
	var view := size if size.x > 0.0 else get_viewport_rect().size
	if view.x <= 0.0:
		return
	draw_rect(Rect2(Vector2.ZERO, view), Palette.with_alpha(Palette.INK, 0.22))

	var content := UiLayout.content(view)
	var column := UiLayout.column(view, COLUMN_WIDTH)
	var cx := column.position.x + column.size.x * 0.5

	var top := content.position.y + 10.0
	UiFont.draw_text(self, "SETTINGS", Vector2(cx, top), UiFont.Cut.DISPLAY,
		Palette.PAPER, UiFont.Align.CENTER, 0.8)
	UiMarks.rule(self, Vector2(cx, top + UiFont.cap(UiFont.Cut.DISPLAY) + 6.0),
		minf(column.size.x * 0.5, 54.0), Palette.with_alpha(Palette.LIGHT_SOFT, 0.7))

	var list_top := top + LIST_DROP
	_row_rects.clear()
	_gauge_rects.clear()
	for i: int in _rows.size():
		var y := list_top + i * ROW_HEIGHT
		_row_rects.append(Rect2(column.position.x, y - 3.0, column.size.x, ROW_HEIGHT))
		var gauge := _draw_row(_rows[i], column, y, i == _index)
		if gauge.has_area():
			_gauge_rects[i] = gauge

	var controls := TouchControls.of(get_parent())
	var surface := controls.get_node_or_null(^"Surface") as Control if controls else null
	var thumbs := surface != null and surface.visible

	# The build line sits low enough to reach SWORD's ring at 320 units, so
	# with the thumbs up it slides left, just clear of SWORD's reach, rather
	# than shortening: the person reporting a bug needs all of it.
	var right := view.x - SWORD_REACH.x if thumbs else content.end.x
	var build := UiFont.fit(PackedStringArray([
		build_line(), "BUILD %d" % BuildStamp.CODE,
	]), right - content.position.x, UiFont.Cut.MICRO)
	var half := UiFont.width(build, UiFont.Cut.MICRO) * 0.5
	var build_x := maxf(content.position.x + half, minf(cx, right - half))
	UiFont.draw_text(self, build, Vector2(roundf(build_x),
		list_top + _rows.size() * ROW_HEIGHT + 4.0), UiFont.Cut.MICRO,
		Palette.with_alpha(Palette.PAPER, 0.42), UiFont.Align.CENTER, 0.5)

	# On the same course of stone the title screen cuts its hint into, and
	# like its hint it moves to the rail's left end when the thumb buttons
	# are up: SWORD covers the right end, and says BACK itself.
	var hint := UiFont.fit(PackedStringArray([
		"LEFT / RIGHT TO SET   ·   SWORD TO GO BACK",
		"LEFT / RIGHT  ·  SWORD TO GO BACK",
		"SWORD TO GO BACK",
	]), content.size.x * (0.5 if thumbs else 1.0), UiFont.Cut.MICRO)
	UiFont.draw_text(self, hint,
		Vector2(content.position.x if thumbs else cx, UiLayout.rail(view) + 1.0),
		UiFont.Cut.MICRO, Palette.with_alpha(Palette.PAPER, 0.66),
		UiFont.Align.LEFT if thumbs else UiFont.Align.CENTER)


## Draws one row; returns its gauge's cells, grown to the row's height so a
## thumb need not land on a seven-unit cell, or an empty rect.
func _draw_row(row: Dictionary, column: Rect2, y: float, selected: bool) -> Rect2:
	var left := column.position.x + 12.0
	var right := column.end.x
	var band := Rect2(column.position.x + 4.0, y - 3.0, column.size.x - 8.0, 13.0)

	if selected:
		draw_rect(band, Palette.with_alpha(Palette.LIGHT_SOFT, 0.16))
		UiMarks.caret(self, Vector2(column.position.x - 4.0, y + 3.5), 4.0, Palette.LIGHT)

	var colour := Palette.PAPER if selected else Palette.with_alpha(Palette.PAPER, 0.7)
	UiFont.draw_text(self, String(row["label"]), Vector2(left, y),
		UiFont.Cut.TEXT, colour, UiFont.Align.LEFT, 0.5)

	match int(row["kind"]):
		Kind.GAUGE:
			var wide := GAUGE_CELLS * (GAUGE_CELL.x + 1.0) - 1.0
			var at := Vector2(right - wide - 2.0, y)
			UiMarks.gauge(self, at, GAUGE_CELLS, GAUGE_CELL, value_of(row),
				Palette.LIGHT_SOFT, selected)
			return Rect2(at.x, y - 3.0, wide, ROW_HEIGHT)
		Kind.TOGGLE:
			var on := is_on(row)
			UiFont.draw_text(self, "ON" if on else "OFF", Vector2(right - 2.0, y + 1.0),
				UiFont.Cut.MICRO,
				Palette.CLOTH if on else Palette.with_alpha(Palette.PAPER, 0.55),
				UiFont.Align.RIGHT, 0.5)
		_:
			pass
	return Rect2()
