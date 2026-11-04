class_name TouchControls
extends CanvasLayer
## On-screen controls for touch devices.
##
## The left half is a floating virtual stick: wherever the thumb lands becomes
## the origin, which beats a fixed pad on phones of every size. The right half
## holds the action buttons. Touches are tracked per index, so holding a
## direction while tapping jump works.
##
## Presses are injected straight into the input map, so gameplay code never
## learns that touch exists — the same `Input.is_action_pressed("jump")` works
## for a keyboard, a gamepad and a thumb.
##
## ## What the buttons say
##
## The action is always the same -- JUMP presses `jump` -- but what `jump`
## does is the screen's: on the pause menu it chooses a row, on the complete
## screen it goes on, on a page it plays. A button lettered JUMP over a menu
## is an instruction that is wrong, and a thumb reads the button, not the hint
## line under the list. So every screen says what the two thumb buttons do
## there, right now, with one call: `set_labels(jump, sword)`, or
## `TouchControls.label(screen, jump, sword)` from a screen that carries its
## controls as a child named TouchControls, as every scene with them does.
## Play is `play_labels()`: JUMP and SWORD, and THROW where the layout has
## it. THROW has no meaning on a menu, so it is hidden whenever the labels
## are not play's.
##
## A label is a list of phrasings, longest first, split on `|`
## ("CONTINUE|NEXT"), and the button shows the first that fits inside its
## ring (`fit_label()`), the way `UiFont.fit()` shortens a hint line. The
## circles do not grow with the screen, so a word that fits at 320 units fits
## at 440: JUMP holds six MICRO letters and SWORD five, which is why the
## complete screen's button says NEXT where its hint says CONTINUE. A word
## that does not fit is never drawn over the ring; a label none of whose
## phrasings fits says nothing, and tests/unit/test_touch_labels.gd fails it.

const STICK_RADIUS := 30.0
const STICK_DEADZONE := 7.0
const VERTICAL_DEADZONE := 14.0
const HIT_PADDING := 8.0
## --- the duel's moves --- where THROW sits, from the safe area's bottom
## right: straight above JUMP, in the column the right thumb already works.
## It used to sit up and to the left of JUMP, over the stretch of floor the
## camera leads the prince into -- where the next guard, gap or spike row is
## -- and its padded circle overlapped JUMP's by ten units. Here it covers
## the screen's edge rather than the way ahead, and its ring is eight units
## clear of JUMP's. The adventure and the duel lay it out the same, from
## this one place, so a thumb that has learned one finds it in the other.
const THROW_AT := Vector2(34.0, 84.0)
const THROW_RADIUS := 18.0
const JUMP_RADIUS := 24.0
const SWORD_RADIUS := 19.0
## --- labels --- the play words, and the ring a label must stay inside: it
## is drawn 1.2 units wide on the radius.
const PLAY_JUMP := "JUMP"
const PLAY_SWORD := "SWORD"
const LABEL_RING := 1.2
## The buttons that carry words, by id.
const LABELLED: Array[String] = ["jump", "attack"]

## --- the duel's moves --- whether this layout carries THROW: the scenes
## that play set it (scenes/game.tscn, the computer's duel and the online
## one); the menus have nothing to throw. The duel once drew its own THROW
## in a node of its own with its own hit test, and one tap on the overlap
## pressed JUMP and THROW together: every thumb button is in this one list
## now, so one hit test decides every touch (button_at()).
@export var throw_button := false

var _buttons: Array[Dictionary] = []
var _held: Dictionary = {} # touch index -> action name
var _stick_index := -1
var _stick_origin := Vector2.ZERO
var _stick_point := Vector2.ZERO
var _active_directions: Array[String] = []
# --- labels --- button id -> the phrasings it was given, "|"-separated.
var _labels: Dictionary = {"jump": PLAY_JUMP, "attack": PLAY_SWORD}

@onready var _surface: Control = $Surface


func _ready() -> void:
	layer = 50
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	var view := _surface.size
	if view == Vector2.ZERO:
		view = get_viewport().get_visible_rect().size
	# UiLayout converts the physical-pixel safe area into canvas units and
	# refuses to believe a desktop-sized inset, which used to push these
	# buttons clean off the right edge of a windowed build.
	var safe := UiLayout.safe(view)
	var right := safe.end.x
	var bottom := safe.end.y

	_buttons = [
		{"id": "jump", "action": "jump", "label": "", "mark": "",
			"at": Vector2(right - 34.0, bottom - 34.0), "r": JUMP_RADIUS},
		{"id": "attack", "action": "attack", "label": "", "mark": "",
			"at": Vector2(right - 82.0, bottom - 22.0), "r": SWORD_RADIUS},
		{"id": "pause", "action": "pause", "label": "", "mark": "pause",
			"at": Vector2(right - 12.0, safe.position.y + 12.0), "r": 10.0},
		{"id": "mute", "action": "", "label": "", "mark": "sound",
			"at": Vector2(right - 34.0, safe.position.y + 12.0), "r": 10.0},
	]
	if throw_button:
		_buttons.append({"id": "throw", "action": "throw", "label": "", "mark": "throw",
			"at": Vector2(right, bottom) - THROW_AT, "r": THROW_RADIUS})
	_surface.queue_redraw()


## --- labels -----------------------------------------------------------------

## What JUMP and SWORD do on this screen now, each as phrasings, longest
## first, split on "|". An empty string letters the button with nothing: it
## does nothing here.
func set_labels(jump: String, sword: String) -> void:
	if labels_of("jump") == jump and labels_of("attack") == sword:
		return
	_labels = {"jump": jump, "attack": sword}
	if is_node_ready():
		_surface.queue_redraw()


## Back to the verbs: the screen is play.
func play_labels() -> void:
	set_labels(PLAY_JUMP, PLAY_SWORD)


## Whether the buttons are lettered for play, and so THROW is up where the
## layout has it.
func is_play() -> bool:
	return labels_of("jump") == PLAY_JUMP and labels_of("attack") == PLAY_SWORD


## The phrasings button `id` ("jump" or "attack") was given.
func labels_of(id: String) -> String:
	return String(_labels.get(id, ""))


## The word button `id` shows: the first of its phrasings that fits its ring.
func label_of(id: String) -> String:
	return fit_label(labels_of(id), radius_of(id))


static func radius_of(id: String) -> float:
	return JUMP_RADIUS if id == "jump" else SWORD_RADIUS


## The first of `phrasings` ("|"-separated, longest first) that fits inside a
## ring of `radius`, or "" when none does.
static func fit_label(phrasings: String, radius: float) -> String:
	for option: String in phrasings.split("|", false):
		if label_fits(option, radius):
			return option
	return ""


## Whether `word`, set in MICRO on a button's centre as draw_surface() sets
## it, keeps all four corners of its box inside the ring's inner edge.
static func label_fits(word: String, radius: float) -> bool:
	var half := Vector2(UiFont.width(word, UiFont.Cut.MICRO) * 0.5,
		UiFont.cap(UiFont.Cut.MICRO) * 0.5)
	return half.length() <= radius - LABEL_RING


## The TouchControls a screen carries as its child, or null on a screen with
## none (the one-keyboard duel).
static func of(screen: Node) -> TouchControls:
	if screen == null:
		return null
	return screen.get_node_or_null(^"TouchControls") as TouchControls


## `set_labels()` on the controls `screen` carries, if it carries any: the one
## call every screen makes.
static func label(screen: Node, jump: String, sword: String) -> void:
	var controls := of(screen)
	if controls != null:
		controls.set_labels(jump, sword)


func _shown(button: Dictionary) -> bool:
	return String(button["id"]) != "throw" or is_play()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_on_drag(event as InputEventScreenDrag)
	elif event is InputEventKey or event is InputEventJoypadButton:
		if _surface.visible:
			_surface.visible = false
			_release_all()


func _on_touch(event: InputEventScreenTouch) -> void:
	var point := _local(event)
	if event.pressed:
		_surface.visible = true
		var button := button_at(point)
		if not button.is_empty():
			if String(button["id"]) == "mute":
				# Not an input action: the only touch-reachable way to silence
				# the game, short of the settings screen.
				GameAudio.toggle_mute()
			else:
				_held[event.index] = button["action"]
				_press(button["action"])
		elif _stick_index < 0 and point.x < _surface.size.x * 0.55:
			_stick_index = event.index
			_stick_origin = point
			_stick_point = point
	else:
		if _held.has(event.index):
			var action: String = _held[event.index]
			_held.erase(event.index)
			if not _held.values().has(action):
				_release(action)
		if _stick_index == event.index:
			_stick_index = -1
			_release_directions()
	_surface.queue_redraw()


func _on_drag(event: InputEventScreenDrag) -> void:
	if _stick_index != event.index:
		return
	_stick_point = _local(event)
	_apply_stick()
	_surface.queue_redraw()


func _apply_stick() -> void:
	var delta := _stick_point - _stick_origin
	var wanted: Array[String] = []
	if delta.x < -STICK_DEADZONE:
		wanted.append("move_left")
	elif delta.x > STICK_DEADZONE:
		wanted.append("move_right")
	# Vertical needs a bigger push so running does not trigger ladders.
	if delta.y < -VERTICAL_DEADZONE:
		wanted.append("move_up")
	elif delta.y > VERTICAL_DEADZONE:
		wanted.append("move_down")
	# A small push walks, a full push runs.
	if absf(delta.x) > STICK_DEADZONE and absf(delta.x) < STICK_RADIUS * 0.55:
		wanted.append("walk")

	for action: String in _active_directions:
		if not wanted.has(action):
			_release(action)
	for action: String in wanted:
		if not _active_directions.has(action):
			_press(action)
	_active_directions = wanted


func _release_directions() -> void:
	for action: String in _active_directions:
		_release(action)
	_active_directions.clear()


func _release_all() -> void:
	_release_directions()
	for action: String in _held.values():
		_release(action)
	_held.clear()
	_stick_index = -1


func _press(action: String) -> void:
	if InputMap.has_action(action):
		Input.action_press(action)


func _release(action: String) -> void:
	if InputMap.has_action(action):
		Input.action_release(action)


## The one button a touch at `point` presses, or {} for none: of the buttons
## whose padded circle holds it, the one whose ring it is nearest. The
## padding reaches past a ring so a thumb that lands just outside still
## counts, and neighbours' paddings overlap -- the mute button's and pause's
## by a fifth of mute's area, JUMP's and SWORD's by ten units. The first in
## the list used to take the whole overlap, so a tap on the edge of mute
## paused the game. Nearest ring, not nearest centre, so a touch inside a
## drawn ring is never given to a bigger neighbour; for rings of one size
## it is the same thing.
func button_at(point: Vector2) -> Dictionary:
	var best := {}
	var nearest := INF
	for button: Dictionary in _buttons:
		if not _shown(button):
			continue
		var r: float = button["r"]
		var from_ring := point.distance_to(button["at"]) - r
		if from_ring <= HIT_PADDING and from_ring < nearest:
			nearest = from_ring
			best = button
	return best


## Whether a touch at `point`, in `screen`'s coordinates, is one of the
## thumb buttons' -- for a page whose rows can be tapped, so that a tap
## pressing a button is not also a tap on a row under it. False on a screen
## with no thumb buttons. Asks whether a button is there, not whether the
## buttons are up: the first touch is the one that puts them up.
static func claims(screen: Node, point: Vector2) -> bool:
	var controls := of(screen)
	return controls != null and not controls.button_at(point).is_empty()


## Where a touch is, in the surface's own coordinates -- the ones the buttons
## are laid out and drawn in.
##
## A touch reaches _input already in canvas units: with the canvas_items
## stretch mode the window converts every event before any node sees it. This
## used to convert again, from window pixels, scaling each touch down by the
## stretch factor -- by six on a 1080p phone -- so a tap on JUMP in the bottom
## right landed on the stick in the top left, and the buttons drawn on screen
## were not where they could be pressed. make_input_local() is the engine's
## own conversion, and stays right if this layer is ever offset or scaled.
func _local(event: InputEvent) -> Vector2:
	var local := _surface.make_input_local(event)
	if local is InputEventScreenDrag:
		return (local as InputEventScreenDrag).position
	return (local as InputEventScreenTouch).position


func draw_surface() -> void:
	for button: Dictionary in _buttons:
		if not _shown(button):
			continue
		var at: Vector2 = button["at"]
		var r: float = button["r"]
		var action := String(button["action"])
		var held := action != "" and Input.is_action_pressed(action)
		_surface.draw_circle(at, r, Palette.with_alpha(Palette.INK, 0.4 if held else 0.22))
		_surface.draw_arc(at, r, 0.0, TAU, 32,
			Palette.with_alpha(Palette.LIGHT_SOFT, 0.85 if held else 0.45), 1.2)

		var ink := Palette.with_alpha(Palette.PAPER, 1.0 if held else 0.75)
		var label := String(button["label"])
		if LABELLED.has(String(button["id"])):
			label = label_of(String(button["id"]))
		if label != "":
			UiFont.draw_text(_surface, label,
				Vector2(at.x, at.y - UiFont.cap(UiFont.Cut.MICRO) * 0.5),
				UiFont.Cut.MICRO, ink, UiFont.Align.CENTER)
		match String(button["mark"]):
			"pause":
				_surface.draw_rect(Rect2(at.x - 3.0, at.y - 4.0, 2.0, 8.0), ink)
				_surface.draw_rect(Rect2(at.x + 1.0, at.y - 4.0, 2.0, 8.0), ink)
			"sound":
				_draw_sound_mark(at, ink)
			"throw":
				_draw_throw_mark(at, held)
			_:
				pass

	if _stick_index >= 0:
		var delta := _stick_point - _stick_origin
		var knob := _stick_origin + delta.limit_length(STICK_RADIUS)
		_surface.draw_circle(_stick_origin, STICK_RADIUS, Palette.with_alpha(Palette.INK, 0.18))
		_surface.draw_circle(knob, 11.0, Palette.with_alpha(Palette.LIGHT_SOFT, 0.55))


## A sword flying point-first with two speed lines behind it: the throw,
## readable without a label at thumb size.
func _draw_throw_mark(at: Vector2, held: bool) -> void:
	var steel := Palette.with_alpha(Palette.STEEL, 0.95 if held else 0.6)
	var light := Palette.with_alpha(Palette.LIGHT_SOFT, 0.9 if held else 0.5)
	var dir := Vector2(1.0, -0.55).normalized()
	var side := Vector2(-dir.y, dir.x)
	var tip := at + dir * 8.0
	var hilt := at - dir * 4.0
	_surface.draw_colored_polygon(PackedVector2Array([
		hilt + side * 1.1, tip, hilt - side * 1.1,
	]), steel)
	_surface.draw_line(hilt + side * 3.0, hilt - side * 3.0, light, 1.4)
	for k: int in 2:
		var back := hilt - dir * (3.0 + 2.5 * float(k)) + side * (2.5 - 5.0 * float(k))
		_surface.draw_line(back, back - dir * 4.0, light, 1.0)


## A horn, and a bar struck through it when the game is silent. Drawn rather
## than lettered: "SOUND" and "MUTED" are the same width at five pixels and
## nobody reads a label on a button they are tapping with a thumb.
func _draw_sound_mark(at: Vector2, ink: Color) -> void:
	_surface.draw_colored_polygon(PackedVector2Array([
		Vector2(at.x - 4.0, at.y - 2.0), Vector2(at.x - 1.0, at.y - 2.0),
		Vector2(at.x + 2.0, at.y - 5.0), Vector2(at.x + 2.0, at.y + 5.0),
		Vector2(at.x - 1.0, at.y + 2.0), Vector2(at.x - 4.0, at.y + 2.0),
	]), ink)
	if GameAudio.is_muted():
		_surface.draw_line(Vector2(at.x - 5.0, at.y + 5.0),
			Vector2(at.x + 5.0, at.y - 5.0), Palette.CLOTH, 1.6)
	else:
		for i: int in 2:
			var radius := 4.0 + i * 2.5
			_surface.draw_arc(Vector2(at.x + 2.0, at.y), radius,
				-PI * 0.3, PI * 0.3, 8, Palette.with_alpha(ink, 0.8 - i * 0.25), 1.0)
