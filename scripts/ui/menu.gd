class_name MenuScene
extends Control
## The title screen: a gallery above a city, and a list of ways into it.
##
## The first ten seconds should establish the place before they establish the
## menu, so the screen is built back to front — the parallax city, a scrim, a
## loggia of horseshoe arches across the top, the floor you are standing on —
## and the list is set on that, not floated over it.
##
## Navigated with up/down and confirmed with jump, so the keyboard, a gamepad
## and the on-screen touch controls all work without any extra plumbing. Sword
## backs out of a sub-screen.
##
## Only the selected mode shows its subtitle. Five modes each with a caption is
## a wall of small type; one caption that moves is a list with a voice.
##
## A development build also asks the dev channel whether it has been
## superseded (UpdateCheck), and if so hangs a plaque from the lintel:
## UPDATE AVAILABLE · BUILD n. Tapping it hands the APK's URL to the browser,
## which downloads it and lets Android install it over this copy. The plaque is
## the one thing on this screen that is touched rather than chosen with the
## stick, because it is not a way into the game and should not sit in the list
## the stick walks. A release build never asks, so never shows it.

const ROW_HEIGHT := 13.0
const COLUMN_WIDTH := 104.0
const REPEAT_DELAY := 0.26
## Depth of the lintel across the top, before its scalloped fringe.
const LINTEL_HEIGHT := 9.0
const SETTINGS_ID := "settings"
## Horizontal room for the plaque's text either side of it. The touch pause and
## mute buttons, with their hit padding, take the top-right 52 units; the same
## is kept clear on the left so the plaque stays centred over the title.
const PLAQUE_CLEARANCE := 56.0
const PLAQUE_PAD := 9.0
## How far the plaque hangs below the lintel.
const PLAQUE_DROP := 7.0
## The plaque's touch target reaches this far below the top of the safe area:
## 24 of the 180 units is about 9 mm on a phone held sideways, over the usual
## 7 mm floor for a thumb. It overlaps the top of the title, which is not
## touchable, rather than shrinking.
const PLAQUE_TOUCH := 24.0

var _index := 0
var _time := 0.0
var _repeat := 0.0
var _rows: Array[Dictionary] = []
var _settings: SettingsPanel
var _update: UpdateCheck
var _offer: Dictionary = {}
var _offer_rect := Rect2()

## Test seam: what a tap on the plaque calls with the APK's URL. The browser,
## by default; Godot cannot install a package without an Android plugin, and
## the browser's download-then-install is the path Android already trusts.
var opener := Callable(OS, "shell_open")

@onready var _sky: ParallaxSky = $Sky/ParallaxSky


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_sky.seed_value = 0xa17e5
	_rows = _build_rows()
	_index = _first_enabled()

	_settings = SettingsPanel.new()
	_settings.name = "SettingsPanel"
	_settings.visible = false
	_settings.closed.connect(_close_settings)
	add_child(_settings)

	_update = UpdateCheck.new()
	_update.name = "UpdateCheck"
	_update.checked.connect(offer_update)
	add_child(_update)
	_update.start()

	get_viewport().size_changed.connect(queue_redraw)


## Shows the update plaque for `offer`, a manifest from DevUpdate.offer(); an
## empty one takes it down. Public so a screenshot can show the plaque without
## a network.
func offer_update(offer: Dictionary) -> void:
	_offer = offer
	if offer.is_empty():
		_offer_rect = Rect2()
	queue_redraw()


func offered() -> Dictionary:
	return _offer


## The rectangle a tap must land in, in this control's coordinates. Empty until
## the plaque has been drawn once.
func offer_rect() -> Rect2:
	return _offer_rect


## The modes, plus the one entry that is not a mode. Settings is a sub-screen
## of this menu, not something ModeRegistry should have to know about.
func _build_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for mode: Dictionary in ModeRegistry.modes():
		out.append({
			"id": String(mode["id"]),
			"title": String(mode["title"]).to_upper(),
			"subtitle": String(mode["subtitle"]).to_upper(),
			"scene": String(mode["scene"]),
			"enabled": bool(mode.get("available", true)),
		})
	out.append({
		"id": SETTINGS_ID,
		"title": "SOUND",
		"subtitle": "VOLUME AND SILENCE",
		"scene": "",
		"enabled": true,
	})
	return out


func rows() -> Array[Dictionary]:
	return _rows


func index() -> int:
	return _index


func _first_enabled() -> int:
	for i: int in _rows.size():
		if bool(_rows[i]["enabled"]):
			return i
	return 0


func move(by: int) -> void:
	if _rows.is_empty():
		return
	var next := _index
	for _step: int in _rows.size():
		next = wrapi(next + by, 0, _rows.size())
		if bool(_rows[next]["enabled"]):
			break
	_index = next
	GameAudio.cue("ui_move")
	queue_redraw()


func confirm() -> void:
	if _rows.is_empty():
		return
	var row := _rows[_index]
	if not bool(row["enabled"]):
		GameAudio.cue("ui_back")
		return
	if String(row["id"]) == SETTINGS_ID:
		GameAudio.cue("ui_confirm")
		_open_settings()
		return

	var scene := String(row["scene"])
	if ResourceLoader.exists(scene):
		GameAudio.cue("ui_confirm")
		get_tree().change_scene_to_file(scene)
	else:
		GameAudio.cue("ui_back")
		push_error("mode '%s' points at a missing scene: %s" % [row["id"], scene])


## Hands the APK's URL to the browser. Android then downloads it and offers to
## install it over this copy; that needs "install unknown apps" allowed for the
## browser once, which Android asks for itself the first time.
func take_offer() -> void:
	if _offer.is_empty():
		return
	GameAudio.cue("ui_confirm")
	opener.call(String(_offer["apk_url"]))


## Touch only: the plaque is not in the list the stick and keys walk. With
## emulate_touch_from_mouse on, a mouse click arrives here as a touch too, and
## a real touch also produces an emulated mouse click -- so listening to the
## touch alone is what makes one tap open the browser once.
func _input(event: InputEvent) -> void:
	if _offer.is_empty() or not _offer_rect.has_area():
		return
	if _settings != null and _settings.visible:
		return
	var touch := event as InputEventScreenTouch
	if touch == null or not touch.pressed:
		return
	var local := make_input_local(touch) as InputEventScreenTouch
	if _offer_rect.has_point(local.position):
		get_viewport().set_input_as_handled()
		take_offer()


func _open_settings() -> void:
	_settings.visible = true
	queue_redraw()


func _close_settings() -> void:
	_settings.visible = false
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	_repeat = maxf(0.0, _repeat - delta)
	queue_redraw()

	if _settings != null and _settings.visible:
		return

	var axis := Input.get_axis("move_up", "move_down")
	if absf(axis) > 0.5 and is_zero_approx(_repeat):
		move(signi(int(signf(axis))))
		_repeat = REPEAT_DELAY
	elif absf(axis) <= 0.5:
		_repeat = 0.0

	if Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("attack"):
		confirm()


## --- drawing ----------------------------------------------------------------

func _draw() -> void:
	var view := size
	if view.x <= 0.0:
		return
	var safe := UiLayout.safe(view)
	var content := UiLayout.content(view)
	var column := UiLayout.column(view, COLUMN_WIDTH)
	var cx := column.position.x + column.size.x * 0.5

	# The city is already behind us; this only stops it shouting over the type.
	# Heaviest at the top, where the title is, and again at the foot.
	UiMarks.wash(self, Rect2(0.0, 0.0, view.x, view.y * 0.45),
		Palette.with_alpha(Palette.INK, 0.46), Palette.with_alpha(Palette.INK, 0.26))
	UiMarks.wash(self, Rect2(0.0, view.y * 0.45, view.x, view.y * 0.55),
		Palette.with_alpha(Palette.INK, 0.26), Palette.with_alpha(Palette.INK, 0.5))

	var lintel := _lintel(safe)
	var soffit := _draw_soffit(view, lintel)
	var rail := _draw_balustrade(view)

	# The settings page is a page, not a dialogue: it keeps the scenery and
	# replaces everything else, so the two screens read as one place.
	if _settings != null and _settings.visible:
		return

	if not _offer.is_empty():
		_draw_plaque(safe, lintel, cx)

	var title_top := soffit + 8.0
	UiFont.draw_text(self, "SWORDKNIGHTS", Vector2(cx, title_top),
		UiFont.Cut.DISPLAY, Palette.PAPER, UiFont.Align.CENTER, 0.85)
	UiMarks.rule(self, Vector2(cx, title_top + UiFont.cap(UiFont.Cut.DISPLAY) + 7.0),
		minf(view.x * 0.26, 76.0), Palette.with_alpha(Palette.LIGHT_SOFT, 0.8))

	var list_top := title_top + 32.0
	for i: int in _rows.size():
		_draw_row(_rows[i], column, list_top + i * ROW_HEIGHT, i == _index)

	# One caption slot, below the list, so choosing does not reflow anything.
	var caption_y := list_top + _rows.size() * ROW_HEIGHT + 5.0
	if not _rows.is_empty():
		var row := _rows[_index]
		var caption := String(row["subtitle"])
		if not bool(row["enabled"]):
			caption = "COMING SOON"
		UiFont.draw_text(self, caption, Vector2(cx, caption_y), UiFont.Cut.MICRO,
			Palette.with_alpha(Palette.LIGHT_SOFT, 0.8), UiFont.Align.CENTER, 0.6)

	_draw_hint(content, cx, rail)


## The instructions, cut into the rail rather than floating above the floor.
##
## The on-screen stick puts a sword button over the right end of that rail, so
## when it is up the hint moves to the left end and says less. The buttons are
## lettered; they are the instruction at that point.
func _draw_hint(content: Rect2, cx: float, rail: float) -> void:
	var surface := get_node_or_null(^"TouchControls/Surface") as Control
	var thumbs := surface != null and surface.visible

	var room := content.size.x if not thumbs else content.size.x * 0.5
	var hint := UiFont.fit(PackedStringArray([
		"UP / DOWN TO CHOOSE   ·   JUMP TO BEGIN",
		"UP / DOWN  ·  JUMP TO BEGIN",
		"JUMP TO BEGIN",
	]), room, UiFont.Cut.MICRO)

	var at := Vector2(cx, rail + 1.0)
	var align := UiFont.Align.CENTER
	if thumbs:
		at.x = content.position.x
		align = UiFont.Align.LEFT
	UiFont.draw_text(self, hint, at, UiFont.Cut.MICRO,
		Palette.with_alpha(Palette.PAPER, 0.66), align)


## The y the lintel's face ends at, above its fringe. It may run under a notch —
## it is scenery, not chrome — so it only reaches past the safe top by a little.
func _lintel(safe: Rect2) -> float:
	return maxf(LINTEL_HEIGHT, safe.position.y + 4.0)


## The underside of whatever we are standing under: a shallow lintel with a
## fringe of pendant scallops. Returns the y it ends at.
##
## Shallow on purpose. An arcade deep enough to read as architecture costs
## forty of the hundred and eighty units this screen has, and the list needs
## them more. The foreground balustrade does the heavy lifting.
func _draw_soffit(view: Vector2, bottom: float) -> float:
	var ink := Palette.with_alpha(Palette.INK, 0.88)
	draw_rect(Rect2(0.0, 0.0, view.x, bottom), ink)
	draw_rect(Rect2(0.0, bottom - 1.0, view.x, 1.0),
		Palette.with_alpha(Palette.LIGHT_WARM, 0.45))

	var step := 10.0
	var x := roundf(fposmod(view.x * 0.5, step) - step)
	while x < view.x:
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, bottom), Vector2(x + step * 0.5, bottom),
			Vector2(x + step * 0.25, bottom + 4.0),
		]), ink)
		x += step
	return bottom + 4.0


## The update notice: a plaque hung from the lintel, over the scallops and
## clear of the title.
##
## Hung from the architecture rather than floated as a toast, so it reads as
## part of the place and not as an interruption; in the lintel's own ink, so
## it is quiet, with the one bright line of type on the screen apart from the
## selected row, so it is still found. It sits at the top centre because that
## is the only spot on this screen that is neither the list nor a touch button,
## and the only one wide enough for the whole phrase at 320 units.
func _draw_plaque(safe: Rect2, lintel: float, cx: float) -> void:
	var room := safe.size.x - PLAQUE_CLEARANCE * 2.0 - PLAQUE_PAD * 2.0
	var label := UiFont.fit(DevUpdate.offer_phrasings(int(_offer["code"])), room,
		UiFont.Cut.MICRO)
	var wide := UiFont.width(label, UiFont.Cut.MICRO)
	var plate := Rect2(roundf(cx - wide * 0.5 - PLAQUE_PAD), 0.0,
		roundf(wide + PLAQUE_PAD * 2.0), lintel + PLAQUE_DROP)

	var edge := Palette.with_alpha(Palette.LIGHT_WARM, 0.55)
	draw_rect(plate, Palette.with_alpha(Palette.INK, 0.94))
	draw_rect(Rect2(plate.position.x, plate.end.y - 1.0, plate.size.x, 1.0), edge)
	draw_rect(Rect2(plate.position.x, lintel - 1.0, 1.0, plate.end.y - lintel), edge)
	draw_rect(Rect2(plate.end.x - 1.0, lintel - 1.0, 1.0, plate.end.y - lintel), edge)

	var text_y := plate.end.y - 3.0 - UiFont.cap(UiFont.Cut.MICRO)
	UiFont.draw_text(self, label, Vector2(cx, text_y), UiFont.Cut.MICRO,
		Palette.LIGHT, UiFont.Align.CENTER, 0.6)
	var mark_y := text_y + UiFont.cap(UiFont.Cut.MICRO) * 0.5
	for x: float in [plate.position.x + 4.5, plate.end.x - 4.5]:
		UiMarks.lozenge(self, Vector2(x, mark_y), 2.0,
			Palette.with_alpha(Palette.LIGHT, 0.7))

	_offer_rect = Rect2(plate.position.x - 4.0, 0.0, plate.size.x + 8.0,
		maxf(plate.end.y + 8.0, safe.position.y + PLAQUE_TOUCH))


## The terrace rail you are standing behind. The nearest plane in the picture
## and the only piece of foreground occlusion on this screen — which, per the
## art direction, is worth more than any amount of ornament. Returns the y of
## the rail's face, where the hint line is cut.
func _draw_balustrade(view: Vector2) -> float:
	var ink := Palette.with_alpha(Palette.INK, 0.9)
	var top := UiLayout.rail(view) - 2.0
	var rail := Rect2(0.0, top, view.x, 8.0)
	draw_rect(rail, ink)
	draw_rect(Rect2(rail.position, Vector2(view.x, 1.0)),
		Palette.with_alpha(Palette.LIGHT_WARM, 0.55))

	# Balusters, with the sky between them.
	var step := 9.0
	var x := roundf(fposmod(view.x * 0.5, step))
	while x < view.x:
		draw_rect(Rect2(x, rail.end.y, 4.0, view.y - rail.end.y), ink)
		draw_rect(Rect2(x - 1.0, rail.end.y, 6.0, 2.0), ink)
		x += step
	draw_rect(Rect2(0.0, view.y - 4.0, view.x, 4.0), ink)
	return rail.position.y + 2.0


func _draw_row(row: Dictionary, column: Rect2, y: float, selected: bool) -> void:
	var enabled := bool(row["enabled"])
	var label := String(row["title"])

	if selected:
		var pulse := 0.17 + sin(_time * 3.4) * 0.05
		draw_rect(Rect2(column.position.x, y - 3.0, column.size.x, 13.0),
			Palette.with_alpha(Palette.LIGHT_SOFT, pulse))
		UiMarks.caret(self, Vector2(column.position.x - 6.0, y + 3.5), 4.0, Palette.LIGHT)
		UiMarks.lozenge(self, Vector2(column.end.x - 4.0, y + 3.5), 3.0,
			Palette.with_alpha(Palette.LIGHT, 0.8))

	var colour := Palette.with_alpha(Palette.PAPER, 0.28)
	if enabled:
		colour = Palette.PAPER if selected else Palette.with_alpha(Palette.PAPER, 0.74)
	UiFont.draw_text(self, label, Vector2(column.position.x + 12.0, y),
		UiFont.Cut.TEXT, colour, UiFont.Align.LEFT, 0.7 if enabled else 0.3)
