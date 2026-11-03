class_name DuelLobby
extends Control
## Getting two people into the same duel.
##
## Five ways in, because no single one of them works everywhere:
##
##   HOST A ROOM      opens a room on a relay and shows a four-letter code.
##                    The only option that works from a web build, which cannot
##                    listen for a connection, and the only one that works from
##                    behind a router without forwarding a port.
##   JOIN A ROOM      the other half of that.
##   HOST ON THIS WI-FI   listens on a port and shows a one-number code
##                    (scripts/net/lan_code.gd). No relay, lowest latency; needs
##                    a shared network or a forwarded port. Not on the web.
##   JOIN ON THIS WI-FI   dials that code, or any address.
##   LOCAL TWO-PLAYER no network at all. Also where you end up when a
##                    connection fails, which is why it is on this screen.
##
## A NOTE ON THE WIDGETS
## The rest of this game draws its interface by hand, and so does the frame and
## the title here. The rows and the text fields are real Control nodes, styled
## from scripts/core/palette.gd. A lobby is a form: it needs focus, it needs a
## tap target on a phone, and it needs a keyboard — including the on-screen one
## a LineEdit asks for on mobile. Re-implementing that by hand would be worse,
## not more consistent.

signal host_room_requested(relay_url: String)
signal join_room_requested(relay_url: String, code: String)
signal host_direct_requested(port: int)
signal join_direct_requested(url: String)
signal local_requested()
signal back_requested()

enum Page { MENU, ENTER_CODE, ENTER_ADDRESS, ENTER_RELAY, BUSY }

## No public relay is run for this game: start your own with
##   godot --headless --path . res://scenes/rendezvous.tscn
## and put its address in here. See docs/netplay.md.
const DEFAULT_RELAY := "ws://127.0.0.1:45678"

var relay_url := DEFAULT_RELAY
var page: Page = Page.MENU

var _font: Font
var _time := 0.0
var _status := ""
var _hint := ""
var _rows: VBoxContainer
var _field: LineEdit
var _field_row: HBoxContainer
var _buttons: Array[Button] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font
	_build()
	show_menu()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


## --- pages ------------------------------------------------------------------

func show_menu() -> void:
	page = Page.MENU
	_hint = "UP / DOWN TO CHOOSE   ·   JUMP TO CONFIRM"
	# Same Wi-Fi first: two phones in one room is the common case, and it needs
	# nothing running anywhere. A relay room is for players who are apart.
	var rows: Array[Array] = [
		["HOST ON THIS WI-FI", _on_host_direct],
		["JOIN ON THIS WI-FI", _on_join_direct],
		["HOST A ROOM", _on_host_room],
		["JOIN A ROOM", _on_join_room],
		["LOCAL TWO-PLAYER", _on_local],
		["RELAY:  %s" % _shorten(relay_url), _on_edit_relay],
		["BACK", _on_back],
	]
	if not WsTransport.new().supports_hosting():
		# A web build cannot accept a connection. Saying so beats offering it.
		rows[0] = ["HOST ON THIS WI-FI  —  NOT ON WEB", Callable()]
	_set_rows(rows)
	_field_row.visible = false


## A text page: one field, confirm and cancel.
func _show_field(
	next: Page, label: String, value: String, placeholder: String,
	limit: int, uppercase: bool, hint: String
) -> void:
	page = next
	_hint = hint
	_set_rows([])
	_field_row.visible = true
	_field.max_length = limit
	_field.placeholder_text = placeholder
	_field.text = value
	_field.set_meta("label", label)
	_field.set_meta("uppercase", uppercase)
	_field.grab_focus()
	_field.caret_column = _field.text.length()


func set_status(text: String) -> void:
	_status = text
	queue_redraw()


## Shown while a connection is being made, with nothing to press but escape.
func show_busy(text: String) -> void:
	page = Page.BUSY
	_status = text
	_hint = "SWORD TO GIVE UP AND PLAY LOCALLY"
	_set_rows([])
	_field_row.visible = false


func is_typing() -> bool:
	return _field_row.visible and _field.has_focus()


## --- row handlers -----------------------------------------------------------

func _on_host_room() -> void:
	show_busy("OPENING A ROOM…")
	host_room_requested.emit(relay_url)


func _on_join_room() -> void:
	_show_field(
		Page.ENTER_CODE, "ROOM CODE", "", "ABCD", NetProtocol.CODE_LENGTH, true,
		"TYPE THE %d-LETTER CODE   ·   ENTER TO JOIN" % NetProtocol.CODE_LENGTH
	)


func _on_host_direct() -> void:
	# The code is what the other phone types; the full address is for a
	# desktop, or a network where the two do not share the first three numbers.
	var address := LanCode.my_address()
	if address == "":
		show_busy("LISTENING ON PORT %d…" % WsTransport.DEFAULT_PORT)
	else:
		show_busy("CODE %s   ·   OR %s" % [LanCode.code_for(address), address])
	host_direct_requested.emit(WsTransport.DEFAULT_PORT)


func _on_join_direct() -> void:
	_show_field(
		Page.ENTER_ADDRESS, "HOST CODE", "", "23", 64, false,
		"THE CODE ON THE HOST'S SCREEN, OR ITS ADDRESS   ·   ENTER TO CONNECT"
	)


func _on_edit_relay() -> void:
	_show_field(
		Page.ENTER_RELAY, "RELAY ADDRESS", relay_url, DEFAULT_RELAY, 64, false,
		"THE RENDEZVOUS SERVER   ·   ENTER TO SAVE"
	)


func _on_local() -> void:
	local_requested.emit()


func _on_back() -> void:
	back_requested.emit()


func _submit_field() -> void:
	var value := _field.text.strip_edges()
	match page:
		Page.ENTER_CODE:
			var code := value.to_upper()
			if not NetProtocol.is_room_code(code):
				set_status("'%s' IS NOT A ROOM CODE" % code)
				return
			show_busy("JOINING ROOM %s…" % code)
			join_room_requested.emit(relay_url, code)
		Page.ENTER_ADDRESS:
			if value == "":
				set_status("ENTER AN ADDRESS")
				return
			var target := LanCode.resolve(value, LanCode.my_address())
			show_busy("CONNECTING TO %s…" % target)
			join_direct_requested.emit(target)
		Page.ENTER_RELAY:
			relay_url = value if value != "" else DEFAULT_RELAY
			set_status("RELAY SET")
			show_menu()
		_:
			pass


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.is_pressed() and not event.is_echo()):
		return
	var key := event as InputEventKey
	if key.keycode == KEY_ESCAPE and page != Page.MENU:
		show_menu()
		accept_event()


## --- building ---------------------------------------------------------------

func _build() -> void:
	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.alignment = BoxContainer.ALIGNMENT_BEGIN
	_rows.add_theme_constant_override("separation", 1)
	_rows.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_rows.anchor_left = 0.5
	_rows.anchor_right = 0.5
	_rows.offset_left = -78.0
	_rows.offset_right = 78.0
	_rows.offset_top = 50.0
	add_child(_rows)

	_field_row = HBoxContainer.new()
	_field_row.name = "Field"
	_field_row.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_field_row.anchor_left = 0.5
	_field_row.anchor_right = 0.5
	_field_row.offset_left = -78.0
	_field_row.offset_right = 78.0
	_field_row.offset_top = 70.0
	add_child(_field_row)

	_field = LineEdit.new()
	_field.custom_minimum_size = Vector2(156.0, 16.0)
	_field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_field.add_theme_font_size_override("font_size", 9)
	_field.add_theme_color_override("font_color", Palette.PAPER)
	_field.add_theme_color_override(
		"font_placeholder_color", Palette.with_alpha(Palette.PAPER, 0.3)
	)
	_field.add_theme_color_override("caret_color", Palette.LIGHT)
	_field.add_theme_stylebox_override("normal", _box(0.45, 0.5))
	_field.add_theme_stylebox_override("focus", _box(0.55, 0.95))
	_field.text_submitted.connect(func(_t: String) -> void: _submit_field())
	_field_row.add_child(_field)


func _set_rows(rows: Array[Array]) -> void:
	for child: Node in _rows.get_children():
		child.queue_free()
	_buttons.clear()

	for row: Array in rows:
		var button := Button.new()
		button.text = String(row[0])
		button.custom_minimum_size = Vector2(156.0, 13.0)
		button.focus_mode = Control.FOCUS_ALL
		button.add_theme_font_size_override("font_size", 7)
		button.add_theme_color_override(
			"font_color", Palette.with_alpha(Palette.PAPER, 0.72)
		)
		button.add_theme_color_override("font_hover_color", Palette.PAPER)
		button.add_theme_color_override("font_focus_color", Palette.PAPER)
		button.add_theme_color_override("font_pressed_color", Palette.LIGHT_SOFT)
		button.add_theme_stylebox_override("normal", _box(0.22, 0.0))
		button.add_theme_stylebox_override("hover", _box(0.34, 0.5))
		button.add_theme_stylebox_override("focus", _box(0.34, 0.9))
		button.add_theme_stylebox_override("pressed", _box(0.5, 0.9))

		var handler: Callable = row[1]
		if handler.is_valid():
			button.pressed.connect(handler)
		else:
			button.disabled = true
			button.add_theme_color_override(
				"font_disabled_color", Palette.with_alpha(Palette.PAPER, 0.22)
			)
		_rows.add_child(button)
		_buttons.append(button)

	for button: Button in _buttons:
		if not button.disabled:
			button.grab_focus()
			break


func _box(ink_alpha: float, edge_alpha: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Palette.with_alpha(Palette.INK, ink_alpha)
	box.content_margin_left = 6.0
	box.content_margin_right = 6.0
	box.content_margin_top = 1.0
	box.content_margin_bottom = 1.0
	if edge_alpha > 0.0:
		box.border_width_left = 1
		box.border_color = Palette.with_alpha(Palette.LIGHT_SOFT, edge_alpha)
	return box


## --- drawing ----------------------------------------------------------------

func _draw() -> void:
	var view := size
	draw_rect(Rect2(Vector2.ZERO, view), Palette.with_alpha(Palette.INK, 0.5))

	var cx := view.x * 0.5
	_centered("DUEL", cx, view.y * 0.14, 20, Palette.PAPER, 7.0)
	draw_rect(Rect2(cx - 44.0, view.y * 0.14 + 13.0, 88.0, 1.0),
		Palette.with_alpha(Palette.LIGHT_SOFT, 0.7))

	if _field_row.visible:
		_centered(
			String(_field.get_meta("label", "")), cx, 60.0, 7,
			Palette.with_alpha(Palette.LIGHT_SOFT, 0.8), 2.0
		)

	if page == Page.BUSY:
		# Three dots marching, so a slow connection does not look like a freeze.
		var lit := int(_time * 2.5) % 4
		for i: int in 3:
			var at := Vector2(cx - 10.0 + i * 10.0, view.y * 0.52)
			draw_circle(at, 2.2, Palette.with_alpha(
				Palette.LIGHT_SOFT, 0.85 if i < lit else 0.25
			))

	if _status != "":
		_centered(_status.to_upper(), cx, view.y - 30.0, 7, Palette.LIGHT_SOFT, 1.4)
	if _hint != "":
		_centered(_hint, cx, view.y - 14.0, 6,
			Palette.with_alpha(Palette.LIGHT_SOFT, 0.5), 1.2)


func _shorten(url: String) -> String:
	var text := url.trim_prefix("ws://").trim_prefix("wss://")
	return text if text.length() <= 22 else text.substr(0, 21) + "…"


## Centred text with letter spacing, as in scripts/ui/menu.gd.
func _centered(
	value: String, cx: float, cy: float, font_size: int, colour: Color, tracking: float
) -> void:
	if value == "":
		return
	var widths: Array[float] = []
	var total := 0.0
	for i: int in value.length():
		var w := _font.get_string_size(
			value[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
		).x
		widths.append(w)
		total += w + tracking
	total -= tracking

	var pen := cx - total * 0.5
	for i: int in value.length():
		draw_string(_font, Vector2(pen, cy + font_size * 0.35), value[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)
		pen += widths[i] + tracking
