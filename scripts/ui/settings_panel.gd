class_name SettingsPanel
extends Control
## Volume, and the one switch that silences the game.
##
## A sub-screen of the menu rather than a mode: it is not something you play,
## and ModeRegistry is the list of things you play.
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
## confirm, sword to go back.

signal closed()

const REPEAT_DELAY := 0.22
const REPEAT_FIRST := 0.42
const STEP := 0.1
const GAUGE_CELLS := 10
const ROW_HEIGHT := 16.0
const COLUMN_WIDTH := 168.0

enum Kind { GAUGE, TOGGLE, ACTION }

## Test seam: set before _ready to drive a panel without the autoload.
var audio: Node

var _index := 0
var _repeat := 0.0
var _settings: AudioSettings
var _rows: Array[Dictionary] = [
	{"id": "master", "label": "MASTER", "kind": Kind.GAUGE, "bus": &"Master"},
	{"id": "music", "label": "MUSIC", "kind": Kind.GAUGE, "bus": &"Music"},
	{"id": "sfx", "label": "SWORDS", "kind": Kind.GAUGE, "bus": &"SFX"},
	{"id": "mute", "label": "MUTE", "kind": Kind.TOGGLE, "bus": &""},
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


func index() -> int:
	return _index


## The value a row shows, 0..1 for a gauge and 0/1 for the switch. Public so a
## test can read the panel without reading pixels.
func value_of(row: Dictionary) -> float:
	match int(row["kind"]):
		Kind.GAUGE:
			return _settings.linear_for(row["bus"])
		Kind.TOGGLE:
			return 0.0 if _settings.muted else 1.0
		_:
			return 0.0


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
			# Right turns the switch on, left turns it off; the row is MUTE,
			# so "on" is silence.
			if (by > 0) != _settings.muted:
				_toggle_mute()
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
			_toggle_mute()
			queue_redraw()
		_:
			# A gauge has nothing to confirm; nudge it so the press is felt.
			adjust(1)


func back() -> void:
	_play("ui_back")
	closed.emit()


func _process(delta: float) -> void:
	if not visible:
		return
	_repeat = maxf(0.0, _repeat - delta)

	var vertical := Input.get_axis("move_up", "move_down")
	var horizontal := Input.get_axis("move_left", "move_right")

	if absf(vertical) > 0.5:
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
	UiFont.draw_text(self, "SOUND", Vector2(cx, top), UiFont.Cut.DISPLAY,
		Palette.PAPER, UiFont.Align.CENTER, 0.8)
	UiMarks.rule(self, Vector2(cx, top + UiFont.cap(UiFont.Cut.DISPLAY) + 6.0),
		minf(column.size.x * 0.5, 54.0), Palette.with_alpha(Palette.LIGHT_SOFT, 0.7))

	var list_top := top + 40.0
	for i: int in _rows.size():
		_draw_row(_rows[i], column, list_top + i * ROW_HEIGHT, i == _index)

	# On the same course of stone the title screen cuts its hint into.
	var hint := UiFont.fit(PackedStringArray([
		"LEFT / RIGHT TO SET   ·   SWORD TO GO BACK",
		"LEFT / RIGHT  ·  SWORD TO GO BACK",
		"SWORD TO GO BACK",
	]), content.size.x, UiFont.Cut.MICRO)
	UiFont.draw_text(self, hint, Vector2(cx, UiLayout.rail(view) + 1.0),
		UiFont.Cut.MICRO, Palette.with_alpha(Palette.PAPER, 0.66),
		UiFont.Align.CENTER)


func _draw_row(row: Dictionary, column: Rect2, y: float, selected: bool) -> void:
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
			var cell := Vector2(4.0, 7.0)
			var wide := GAUGE_CELLS * (cell.x + 1.0) - 1.0
			UiMarks.gauge(self, Vector2(right - wide - 2.0, y), GAUGE_CELLS, cell,
				value_of(row), Palette.LIGHT_SOFT, selected)
		Kind.TOGGLE:
			var word := "ON" if _settings.muted else "OFF"
			UiFont.draw_text(self, word, Vector2(right - 2.0, y + 1.0),
				UiFont.Cut.MICRO,
				Palette.CLOTH if _settings.muted
					else Palette.with_alpha(Palette.PAPER, 0.55),
				UiFont.Align.RIGHT, 0.5)
		_:
			pass
