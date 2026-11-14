class_name WardrobeScreen
extends Control
## The wardrobe: choose the figure each player plays, and what it wears.
##
## Six rows on the left -- which player, which figure, then robe, sash, hair
## and skin -- and on the right the figure itself, standing in a horseshoe
## arch with the sky behind it and cycling through a few poses, at three times
## its size and again at the size the game draws it. The sky is the reason for
## the arch: a look is judged against the gold and crimson it will be played
## against, and a figure on a flat swatch tells you nothing about that.
##
## ## Driven like every other page
##
## Up/down choose a row, left/right change it, jump steps it forward, sword or
## pause go back -- the same four actions as the title screen and SETTINGS, so a
## keyboard, a gamepad and the on-screen stick all work with no plumbing.
## Rows can also be tapped: the left half of a value steps it back, the right
## half forward. The list is on the left on purpose. The touch buttons own the
## bottom right of every screen (JUMP and SWORD, with their hit padding, reach
## 66 units in from the right edge and 66 up from the bottom), and a tappable
## row under a thumb button is a tap that does two things.
##
## ## What cannot be chosen
##
## Rows that would change nothing are shown, dimmed, and skipped: the prince's
## hair and face are under his hood, and player two's robe is sea-green,
## because in a duel the robe is always the seat's colour (FighterArt.dress).
## Showing them dimmed rather than hiding them keeps the list from reflowing
## when the figure changes, and says *why* the row is not there to change.
##
## Every change is saved at once (Wardrobe.save), so a phone that kills the app
## from the background never loses a choice.

const MENU_SCENE := "res://scenes/menu.tscn"

const LIST_WIDTH := 172.0
## The arch, plus the run of sill outside it for the figure at its true size.
const NICHE_WIDTH := 116.0
const GAP := 12.0
const ROW_HEIGHT := 15.0
const LIST_TOP := 38.0
## The floor of the arch the figure stands on, in canvas units from the top.
const SILL_Y := 122.0
## The large preview is drawn at a whole multiple, so its edges stay hard.
const PREVIEW_SCALE := 3.0
## How thick the arch's frame is.
const ARCH_WALL := 6.0
## The sill runs on past the arch this far, for the figure at its true size.
const AT_SIZE_ROOM := 20.0
const REPEAT_DELAY := 0.22
const REPEAT_FIRST := 0.42

const ROWS: Array[Dictionary] = [
	{"id": "player", "label": "FOR"},
	{"id": "figure", "label": "FIGURE"},
	{"id": "outfit", "label": "ROBE"},
	{"id": "accent", "label": "SASH"},
	{"id": "hair", "label": "HAIR"},
	{"id": "skin", "label": "SKIN"},
]
const PLAYER_NAMES: Array[String] = ["PLAYER ONE", "PLAYER TWO"]

## Test seams: set before _ready. Where the wardrobe is kept, and what going
## back does -- the title screen, by default.
var store_path := UserData.at(Wardrobe.PATH)
var leave := Callable()

var _wardrobe: Wardrobe
var _player := Wardrobe.PLAYER_ONE
var _look := CharacterLook.new()
var _index := 0
var _repeat := 0.0
var _hold := 0.0
var _time := 0.0
var _row_rects: Array[Rect2] = []
var _value_rects: Array[Rect2] = []
var _preview: FigurePreview
var _actual: FigurePreview


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_wardrobe = Wardrobe.open(store_path)
	_look = _wardrobe.look(_player)

	var sky := get_node_or_null(^"Sky/ParallaxSky") as ParallaxSky
	if sky != null:
		sky.seed_value = 0xa17e5

	_preview = FigurePreview.new()
	_preview.name = "Preview"
	_preview.scale = Vector2.ONE * PREVIEW_SCALE
	_preview.facing = -1
	add_child(_preview)
	_actual = FigurePreview.new()
	_actual.name = "AtSize"
	_actual.facing = -1
	add_child(_actual)
	_dress_previews()

	get_viewport().size_changed.connect(queue_redraw)


## --- the model the page shows -------------------------------------------------

func rows() -> Array[Dictionary]:
	return ROWS


func index() -> int:
	return _index


func player() -> int:
	return _player


## The look being edited, as a copy.
func look() -> CharacterLook:
	return _look.duplicate_look()


## Whether a row can be changed for this player and figure.
func is_open(row: int) -> bool:
	match String(ROWS[row]["id"]):
		"outfit":
			return _player == Wardrobe.PLAYER_ONE
		"hair", "skin":
			return _look.shows_face()
	return true


## What a row reads, as drawn.
func value_text(row: int) -> String:
	var id := String(ROWS[row]["id"])
	if id == "player":
		return PLAYER_NAMES[_player]
	if not is_open(row):
		if id == "outfit":
			return "SEA-GREEN"
		return "HOODED" if _look.figure == CharacterLook.Figure.PRINCE else "NONE"
	return String(_look.option(id)["name"])


func move(by: int) -> void:
	var next := _index
	for _step: int in ROWS.size():
		next = wrapi(next + by, 0, ROWS.size())
		if is_open(next):
			break
	_index = next
	GameAudio.cue("ui_move")
	queue_redraw()


## Left (-1) or right (+1) on the selected row.
func adjust(by: int) -> void:
	if not is_open(_index):
		return
	var id := String(ROWS[_index]["id"])
	if id == "player":
		_player = wrapi(_player + by, 0, PLAYER_NAMES.size())
		_look = _wardrobe.look(_player)
	else:
		_look.set_index(id, _look.index_of(id) + by)
		_wardrobe.set_look(_player, _look)
		var err := _wardrobe.save()
		if err != OK:
			push_warning("wardrobe: could not save %s: %s" % [store_path, error_string(err)])
	# A figure or a player change can close the row the cursor would land on
	# next; the cursor itself stays, because only open rows are ever selected.
	_dress_previews()
	GameAudio.cue("ui_move")
	queue_redraw()


func confirm() -> void:
	adjust(1)


func back() -> void:
	GameAudio.cue("ui_back")
	if leave.is_valid():
		leave.call()
	else:
		get_tree().change_scene_to_file(MENU_SCENE)


## Android's Back is SWORD on a page: one page back (docs/ui.md, "Ways back").
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		back()


## A tap at `at`, in this control's coordinates. Returns true if it landed on
## a row. Public so a test can tap without synthesising a touch.
func tap(at: Vector2) -> bool:
	for row: int in _row_rects.size():
		if not _row_rects[row].has_point(at):
			continue
		if not is_open(row):
			return true
		_index = row
		var value := _value_rects[row]
		if value.has_point(at):
			adjust(-1 if at.x < value.get_center().x else 1)
		else:
			GameAudio.cue("ui_move")
			queue_redraw()
		# The same thumb is now on the floating stick: hold off a few frames so
		# a wobble in the tap is not read as a second change.
		_hold = REPEAT_FIRST
		return true
	return false


## The previews wear what the game will draw: player one in the chosen robe,
## player two in the seat's sea-green.
func _dress_previews() -> void:
	for art: FigurePreview in [_preview, _actual]:
		if art == null:
			continue
		_look.dress(art)
		if _player == Wardrobe.PLAYER_TWO:
			art.cloth = FighterArt.SEAT_CLOTH[1]
			art.cloth_dark = FighterArt.SEAT_CLOTH_DARK[1]
			art.cloak_shade = FighterArt.SEAT_CLOAK[1]


## --- input ------------------------------------------------------------------

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
	# Jump steps the selected row to its next choice (confirm()).
	TouchControls.label(self, "NEXT", "BACK")

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


## --- drawing ----------------------------------------------------------------

func _draw() -> void:
	var view := size
	if view.x <= 0.0:
		return
	var content := UiLayout.content(view)
	var wide := minf(content.size.x, LIST_WIDTH + GAP + NICHE_WIDTH)
	var left := roundf(content.position.x + (content.size.x - wide) * 0.5)
	var list := Rect2(left, LIST_TOP, wide - GAP - NICHE_WIDTH, ROWS.size() * ROW_HEIGHT)
	var niche := Rect2(list.end.x + GAP, content.position.y + 26.0, NICHE_WIDTH,
		SILL_Y - content.position.y - 26.0)

	UiMarks.wash(self, Rect2(0.0, 0.0, view.x, view.y * 0.5),
		Palette.with_alpha(Palette.INK, 0.5), Palette.with_alpha(Palette.INK, 0.3))
	UiMarks.wash(self, Rect2(0.0, view.y * 0.5, view.x, view.y * 0.5),
		Palette.with_alpha(Palette.INK, 0.3), Palette.with_alpha(Palette.INK, 0.5))
	var rail := UiMarks.balustrade(self, view)

	var cx := roundf(left + wide * 0.5)
	var title_top := content.position.y + 2.0
	UiFont.draw_text(self, "WARDROBE", Vector2(cx, title_top), UiFont.Cut.DISPLAY,
		Palette.PAPER, UiFont.Align.CENTER, 0.85)
	UiMarks.rule(self, Vector2(cx, title_top + UiFont.cap(UiFont.Cut.DISPLAY) + 5.0),
		minf(wide * 0.3, 64.0), Palette.with_alpha(Palette.LIGHT_SOFT, 0.8))

	_row_rects.clear()
	_value_rects.clear()
	for row: int in ROWS.size():
		_draw_row(row, Rect2(list.position.x, list.position.y + row * ROW_HEIGHT,
			list.size.x, ROW_HEIGHT))

	# One caption slot, so choosing does not reflow anything. It may run on
	# under the arch's sill: the sill is the only thing there.
	# With the thumbs up the JUMP button sits at the end of that line, so the
	# caption keeps to the list's own width.
	var surface := get_node_or_null(^"TouchControls/Surface") as Control
	var room := list.size.x + 8.0 if surface != null and surface.visible else wide - 8.0
	var caption := UiFont.fit(_caption(), room, UiFont.Cut.MICRO)
	UiFont.draw_text(self, caption, Vector2(list.position.x + 8.0, list.end.y + 5.0),
		UiFont.Cut.MICRO, Palette.with_alpha(Palette.LIGHT_SOFT, 0.8), UiFont.Align.LEFT, 0.6)

	_draw_niche(niche)
	_draw_hint(content, cx, rail)


func _draw_row(row: int, rect: Rect2) -> void:
	var open := is_open(row)
	var selected := row == _index
	var y := rect.position.y + 4.0
	_row_rects.append(rect)
	var value_box := Rect2(rect.position.x + 62.0, rect.position.y,
		rect.size.x - 62.0, rect.size.y)
	_value_rects.append(value_box)

	if selected:
		var pulse := 0.16 + sin(_time * 3.4) * 0.05
		draw_rect(Rect2(rect.position.x, rect.position.y + 1.0, rect.size.x, 13.0),
			Palette.with_alpha(Palette.LIGHT_SOFT, pulse))
		UiMarks.caret(self, Vector2(rect.position.x - 6.0, y + 3.5), 4.0, Palette.LIGHT)

	var ink := Palette.with_alpha(Palette.PAPER, 0.3)
	if open:
		ink = Palette.PAPER if selected else Palette.with_alpha(Palette.PAPER, 0.74)
	UiFont.draw_text(self, String(ROWS[row]["label"]), Vector2(rect.position.x + 8.0, y),
		UiFont.Cut.TEXT, ink, UiFont.Align.LEFT, 0.6 if open else 0.3)

	# The value between two arrows, with a swatch of the colour it names.
	var right := value_box.end.x - 4.0
	var text := value_text(row)
	UiFont.draw_text(self, text, Vector2(right - 7.0, y + 1.0), UiFont.Cut.MICRO,
		ink, UiFont.Align.RIGHT, 0.5 if open else 0.2)
	var text_left := right - 7.0 - UiFont.width(text, UiFont.Cut.MICRO)
	var swatch: Variant = _swatch(row)
	if swatch != null:
		text_left -= 9.0
		UiMarks.lozenge(self, Vector2(text_left + 3.0, y + 3.5), 3.5,
			swatch as Color if open else Palette.with_alpha(swatch as Color, 0.45),
			0.6 if open else 0.0)
	if open:
		var arrow := Palette.LIGHT if selected else Palette.with_alpha(Palette.LIGHT, 0.45)
		UiMarks.caret(self, Vector2(right, y + 3.5), 2.5, arrow)
		UiMarks.caret(self, Vector2(text_left - 4.0, y + 3.5), -2.5, arrow)


## The colour a row's value names, or null for a row that names no colour --
## including the prince's hair and face, which are not there to show.
func _swatch(row: int) -> Variant:
	var id := String(ROWS[row]["id"])
	if (id == "hair" or id == "skin") and not is_open(row):
		return null
	match id:
		"outfit":
			return _look.option(id)["cloth"] if is_open(row) else FighterArt.SEAT_CLOTH[1]
		"accent":
			return _look.option(id)["colour"]
		"hair", "skin":
			return _look.option(id)["lit"]
	return null


## One line under the list about the selected row: longest phrasing first.
func _caption() -> PackedStringArray:
	match String(ROWS[_index]["id"]):
		"player":
			if _player == Wardrobe.PLAYER_ONE:
				return PackedStringArray([
					"ADVENTURE, ENDLESS AND THE CRIMSON SEAT", "ADVENTURE AND CRIMSON SEAT",
				])
			return PackedStringArray([
				"THE SEA-GREEN SEAT OF A DUEL", "THE SEA-GREEN SEAT",
			])
		"figure":
			return PackedStringArray([
				"SAME REACH, SAME HITBOX · ONLY THE LOOK", "ONLY THE LOOK CHANGES",
			])
		"outfit":
			return PackedStringArray([
				"THE ADVENTURE'S ROBE · CRIMSON IN A DUEL", "CRIMSON IN A DUEL",
			])
		"accent":
			match _look.figure:
				CharacterLook.Figure.HEROINE:
					return PackedStringArray(["HEADBAND, BELT AND RIBBON", "HEADBAND AND BELT"])
				CharacterLook.Figure.STICK:
					return PackedStringArray(["THE SCARF AT THE NECK", "THE SCARF"])
				CharacterLook.Figure.PRINCESS:
					return PackedStringArray(["BROW BAND, TRIM AND CREST", "BAND AND TRIM"])
			return PackedStringArray(["THE SASH AND THE CREST OF THE HOOD", "SASH AND CREST"])
		"hair":
			return PackedStringArray(["THE BRAID", "BRAID"])
	return PackedStringArray(["THE FACE, LIT BY THE LOW SUN", "THE FACE"])


## The arch the figure stands in: a horseshoe frame with the sky through it, a
## lit sill, and the figure three times its size, so the costume can be read.
## The same figure at its true size stands on the sill outside the arch,
## because that is the size that has to read. Outside and to the right, so it
## is clear of the caption and above the reach of the JUMP button.
func _draw_niche(niche: Rect2) -> void:
	var span := niche.size.x - AT_SIZE_ROOM
	var radius := minf(span * 0.5 - ARCH_WALL, niche.size.y * 0.5)
	var centre := Vector2(roundf(niche.position.x + span * 0.5),
		niche.position.y + radius + ARCH_WALL)
	_draw_arch(centre, radius, niche.end.y, Palette.with_alpha(Palette.INK, 0.86))
	var outer := radius + ARCH_WALL
	var sill := Rect2(centre.x - outer - 3.0, niche.end.y, outer * 2.0 + AT_SIZE_ROOM, 1.0)
	draw_rect(sill, Palette.with_alpha(Palette.LIGHT, 0.9))
	draw_rect(Rect2(sill.position.x, sill.end.y, sill.size.x, 3.0),
		Palette.with_alpha(Palette.SHADOW_DEEP, 0.9))

	if _preview != null:
		_preview.position = Vector2(centre.x - 3.0, niche.end.y)
		_actual.position = Vector2(centre.x + outer + AT_SIZE_ROOM * 0.5, niche.end.y)


## A horseshoe arch as an ink frame `ARCH_WALL` thick, built a column at a time
## like UiMarks.arcade: solid from the outer curve down to the opening, and
## solid again below the haunches, where a horseshoe closes back in before its
## jambs drop to the sill.
func _draw_arch(centre: Vector2, radius: float, sill: float, colour: Color) -> void:
	var outer := radius + ARCH_WALL
	var jamb := radius * 0.9
	var x := floorf(centre.x - outer)
	while x < centre.x + outer:
		var dx := absf(x + 0.5 - centre.x)
		var top := centre.y - sqrt(maxf(0.0, outer * outer - dx * dx))
		if dx >= radius:
			draw_rect(Rect2(x, roundf(top), 1.0, sill - roundf(top)), colour)
		else:
			var reach := sqrt(radius * radius - dx * dx)
			draw_rect(Rect2(x, roundf(top), 1.0, roundf(centre.y - reach) - roundf(top)),
				colour)
			if dx > jamb:
				var low := roundf(centre.y + reach)
				draw_rect(Rect2(x, low, 1.0, sill - low), colour)
		x += 1.0


## The instructions, cut into the rail like the title screen's. With the
## on-screen stick up, the SWORD button sits over the right of the rail, so
## the hint moves left and says less.
func _draw_hint(content: Rect2, cx: float, rail: float) -> void:
	var surface := get_node_or_null(^"TouchControls/Surface") as Control
	var thumbs := surface != null and surface.visible
	var room := content.size.x if not thumbs else content.size.x * 0.5
	var hint := UiFont.fit(PackedStringArray([
		"LEFT / RIGHT TO CHANGE   ·   SWORD TO GO BACK",
		"LEFT / RIGHT  ·  SWORD TO GO BACK",
		"TAP TO CHANGE",
	]), room, UiFont.Cut.MICRO)
	var at := Vector2(cx, rail + 1.0)
	var align := UiFont.Align.CENTER
	if thumbs:
		at.x = content.position.x
		align = UiFont.Align.LEFT
	UiFont.draw_text(self, hint, at, UiFont.Cut.MICRO,
		Palette.with_alpha(Palette.PAPER, 0.66), align)
