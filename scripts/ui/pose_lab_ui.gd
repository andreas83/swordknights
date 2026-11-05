class_name PoseLabUi
extends Control
## The pose lab's words and its touch targets, over the stage: the pose's name
## in Alcazar, the arrows either side of it, the rows on the left, the frame of
## the enlarged inset, and on TRY the readout.
##
## Everything here is laid out from the measured width, as every page is
## (UiLayout): the rows keep to the left, where no thumb button is; the inset
## keeps to the right between the pause buttons above and JUMP below; the
## figure at 1:1 stands in the gap between them (`stage_point`), which is
## where PoseLab puts the camera. The rows are on a wash of ink and the figure
## is not: a figure judged for readability is judged on the stone, not on a
## panel the lab drew behind it.
##
## Each draw records where it put every row and arrow, and `hit()` answers a
## tap from those rects, so what can be tapped is exactly what is drawn.

const ROW_PITCH := 12.0
const TRY_PITCH := 11.0
const ROWS_WIDTH := 166.0
const ROWS_TOP := 40.0
## Where a row's value starts, past its label: HITBOXES is the longest.
const VALUE_X := 60.0
const INSET_SIZE := Vector2(92.0, 82.0)
## The inset sits under the pause and mute buttons (and their padding).
const INSET_TOP := 31.0
## The inset's feet: in from its back edge, so a thrust's reach still fits in
## front, and up from its sill.
const INSET_FEET := Vector2(24.0, 7.0)
## The pose arrows' distance from the name's centre, and their touch reach.
const ARROW_OFFSET := 92.0
const ARROW_REACH := Vector2(30.0, 30.0)
## How far down the screen the browse figure's feet stand.
const FEET_DOWN := 0.66
## How long a fresh outcome is drawn bright.
const FRESH_FRAMES := 45

var lab: PoseLab
## The player's byte on TRY, for the readout.
var your_bits := 0

var _hits: Array[Dictionary] = []
var _time := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_time += delta


## The rows' column, in screen units.
func rows_rect(view: Vector2) -> Rect2:
	var content := UiLayout.content(view)
	return Rect2(content.position.x, ROWS_TOP, ROWS_WIDTH,
		ROW_PITCH * PoseLab.ROWS.size())


func inset_rect(view: Vector2) -> Rect2:
	var content := UiLayout.content(view)
	return Rect2(content.end.x - INSET_SIZE.x, maxf(INSET_TOP, content.position.y + 24.0),
		INSET_SIZE.x, INSET_SIZE.y)


## Where the browse figure's feet appear on the screen: between the rows and
## the inset, two thirds of the way down.
func stage_point(view: Vector2) -> Vector2:
	var rows := rows_rect(view)
	var inset := inset_rect(view)
	return Vector2(roundf((rows.end.x + inset.position.x) * 0.5), roundf(view.y * FEET_DOWN))


## What a tap at `at` lands on: {kind: "row", id, by} or {kind: "prev"/"next"},
## or {} for nothing. A value's left third steps back, the rest forward.
func hit(at: Vector2) -> Dictionary:
	for target: Dictionary in _hits:
		var rect: Rect2 = target["rect"]
		if not rect.has_point(at):
			continue
		var out := target.duplicate()
		out.erase("rect")
		if String(out["kind"]) == "row":
			var value_left := rect.position.x + VALUE_X
			var third := (rect.end.x - value_left) / 3.0
			out["by"] = -1 if at.x > value_left and at.x < value_left + third else 1
		return out
	return {}


## Where row `id` can be tapped, as last drawn; empty if it is not on screen.
func row_rect(id: String) -> Rect2:
	for target: Dictionary in _hits:
		if String(target["kind"]) == "row" and String(target.get("id", "")) == id:
			return target["rect"]
	return Rect2()


func arrow_rect(which: String) -> Rect2:
	for target: Dictionary in _hits:
		if String(target["kind"]) == which:
			return target["rect"]
	return Rect2()


func _draw() -> void:
	_hits.clear()
	if lab == null or size.x <= 0.0:
		return
	_place_inset()
	if lab.page == PoseLab.Page.TRY:
		_draw_try()
	else:
		_draw_browse()


## --- browse ---------------------------------------------------------------------

func _draw_browse() -> void:
	var view := size
	var content := UiLayout.content(view)
	var cx := roundf(view.x * 0.5)
	var entry := lab.pose()

	# The name: the one line on the page that must be read at a glance.
	var top := content.position.y
	UiMarks.wash(self, Rect2(0.0, 0.0, view.x, top + 30.0),
		Palette.with_alpha(Palette.INK, 0.62), Palette.with_alpha(Palette.INK, 0.0))
	var name := String(entry.get("label", ""))
	var room := ARROW_OFFSET * 2.0 - 24.0
	var cut := UiFont.Cut.DISPLAY if UiFont.width(name, UiFont.Cut.DISPLAY) <= room \
		else UiFont.Cut.TEXT
	var name_y := top + (0.0 if cut == UiFont.Cut.DISPLAY else 4.0)
	UiFont.draw_text(self, name, Vector2(cx, name_y), cut, Palette.PAPER,
		UiFont.Align.CENTER, 0.85)
	var count := "%s %d / %d" % [PoseLab.KIND_NAMES[lab.kind], lab.index + 1,
		lab.poses().size()]
	var detail := lab.pose_detail()
	var line := UiFont.fit(PackedStringArray([
		"%s  ·  %s" % [count, detail], detail, count,
	]), content.size.x, UiFont.Cut.MICRO)
	UiFont.draw_text(self, line, Vector2(cx, top + 18.0), UiFont.Cut.MICRO,
		Palette.with_alpha(Palette.LIGHT_SOFT, 0.9), UiFont.Align.CENTER, 0.6)
	var mid := name_y + UiFont.cap(cut) * 0.5
	_arrow(Vector2(cx - ARROW_OFFSET, mid), -1, "prev")
	_arrow(Vector2(cx + ARROW_OFFSET, mid), 1, "next")

	var rows := rows_rect(view)
	UiMarks.wash(self, rows.grow(4.0), Palette.with_alpha(Palette.INK, 0.55),
		Palette.with_alpha(Palette.INK, 0.4))
	for i: int in PoseLab.ROWS.size():
		var id := PoseLab.ROWS[i]
		_draw_row(id, Rect2(rows.position.x, rows.position.y + i * ROW_PITCH,
			rows.size.x, ROW_PITCH), i == lab.row)

	var inset := inset_rect(view)
	draw_rect(inset, Palette.with_alpha(Palette.INK, 0.72))
	draw_rect(Rect2(inset.position.x, inset.end.y - INSET_FEET.y, inset.size.x, 1.0),
		Palette.with_alpha(Palette.LIGHT, 0.6))
	draw_rect(inset, Palette.with_alpha(Palette.LIGHT_SOFT, 0.5), false, 1.0)
	UiFont.draw_text(self, "X%d" % int(PoseLab.INSET_SCALE),
		Vector2(inset.end.x - 3.0, inset.position.y + 3.0), UiFont.Cut.MICRO,
		Palette.with_alpha(Palette.PAPER, 0.6), UiFont.Align.RIGHT)

	_draw_hint(content, PackedStringArray([
		"LEFT / RIGHT A POSE  ·  UP / DOWN A ROW  ·  JUMP CHANGES IT  ·  SWORD BACK",
		"LEFT / RIGHT A POSE  ·  JUMP CHANGES A ROW",
		"TAP A ROW TO CHANGE IT",
	]))


func _arrow(at: Vector2, way: int, kind: String) -> void:
	var ink := Palette.with_alpha(Palette.LIGHT, 0.95)
	var tip := at + Vector2(5.0 * way, 0.0)
	var back := at - Vector2(4.0 * way, 0.0)
	draw_colored_polygon(PackedVector2Array([
		tip, back + Vector2(0.0, -6.0), back + Vector2(0.0, 6.0),
	]), ink)
	_hits.append({"kind": kind, "rect": Rect2(at - ARROW_REACH * 0.5, ARROW_REACH)})


func _draw_row(id: String, rect: Rect2, selected: bool) -> void:
	_hits.append({"kind": "row", "id": id, "rect": rect})
	var live := lab.is_live(id)
	var y := rect.position.y + 3.0
	if selected:
		var pulse := 0.17 + sin(_time * 3.4) * 0.05
		draw_rect(Rect2(rect.position.x, rect.position.y + 0.5, rect.size.x, rect.size.y - 1.0),
			Palette.with_alpha(Palette.LIGHT_SOFT, pulse))
		UiMarks.caret(self, Vector2(rect.position.x + 2.0, y + 2.5), 3.0, Palette.LIGHT)
	var label_ink := Palette.with_alpha(Palette.LIGHT_SOFT, 0.85 if live else 0.3)
	var value_ink := Palette.PAPER if selected else Palette.with_alpha(Palette.PAPER, 0.8)
	if not live:
		value_ink = Palette.with_alpha(Palette.PAPER, 0.3)
	UiFont.draw_text(self, PoseLab.row_label(id), Vector2(rect.position.x + 8.0, y),
		UiFont.Cut.MICRO, label_ink, UiFont.Align.LEFT, 0.5)
	var room := rect.size.x - VALUE_X - 2.0
	var value := UiFont.fit(_phrasings(id), room, UiFont.Cut.MICRO)
	UiFont.draw_text(self, value, Vector2(rect.position.x + VALUE_X, y), UiFont.Cut.MICRO,
		value_ink, UiFont.Align.LEFT, 0.5)


## A row's value, longest first, for a narrow column.
func _phrasings(id: String) -> PackedStringArray:
	var full := lab.value_of(id)
	if id == "light":
		return PackedStringArray([full, lab.stage.strip_id.to_upper() + " · "
			+ lab.stage.short_label(), lab.stage.short_label()])
	if id == "seat":
		return PackedStringArray([full, "ONE" if lab.seat == 0 else "TWO"])
	if id == "try":
		return PackedStringArray([full, "THE GUARD"])
	return PackedStringArray([full])


func _draw_hint(content: Rect2, phrasings: PackedStringArray) -> void:
	# Kept to the left half: SWORD and JUMP own the bottom right.
	var room := content.size.x * 0.5
	var hint := UiFont.fit(phrasings, room, UiFont.Cut.MICRO)
	UiFont.draw_text(self, hint, Vector2(content.position.x, content.end.y - 5.0),
		UiFont.Cut.MICRO, Palette.with_alpha(Palette.PAPER, 0.7), UiFont.Align.LEFT, 0.7)


## Lays the inset's clip and its figure's feet out where the frame is drawn.
func _place_inset() -> void:
	var clip := get_node_or_null(^"../Inset") as Control
	if clip == null:
		return
	var rect := inset_rect(size)
	clip.position = rect.position
	clip.size = rect.size
	var holder := clip.get_node_or_null(^"Holder") as Node2D
	if holder != null:
		holder.position = Vector2(INSET_FEET.x, rect.size.y - INSET_FEET.y)


## --- try ------------------------------------------------------------------------

func _draw_try() -> void:
	var view := size
	var content := UiLayout.content(view)
	var rows := Rect2(content.position.x, content.position.y, ROWS_WIDTH,
		TRY_PITCH * PoseLab.TRY_ROWS.size())
	UiMarks.wash(self, rows.grow(4.0), Palette.with_alpha(Palette.INK, 0.55),
		Palette.with_alpha(Palette.INK, 0.4))
	for i: int in PoseLab.TRY_ROWS.size():
		var id := PoseLab.TRY_ROWS[i]
		var rect := Rect2(rows.position.x, rows.position.y + i * TRY_PITCH, rows.size.x,
			TRY_PITCH)
		if id == "back":
			_hits.append({"kind": "row", "id": id, "rect": rect})
			UiMarks.caret(self, Vector2(rect.position.x + 6.0, rect.position.y + 5.5), -3.0,
				Palette.LIGHT)
			UiFont.draw_text(self, "POSES", Vector2(rect.position.x + 8.0, rect.position.y + 3.0),
				UiFont.Cut.MICRO, Palette.PAPER, UiFont.Align.LEFT, 0.5)
			continue
		_draw_row(id, rect, false)
	_draw_readout(content)
	_draw_hint(content, PackedStringArray([
		"STICK AND BUTTONS FIGHT  ·  PAUSE OR BACK FOR THE POSES",
		"PAUSE OR BACK FOR THE POSES",
	]))


## The readout: what the player's fighter is, what the thumb is holding, how
## long the posture has held, the dummy, and the last thing that happened.
## Right-aligned under the pause buttons, clear of the stick's side.
func _draw_readout(content: Rect2) -> void:
	var spar := lab.spar
	if spar.you == null:
		return
	var right := content.end.x
	var y := maxf(INSET_TOP, content.position.y + 24.0)
	var you := spar.you
	var lines: Array[Array] = [
		["YOU", "%s · %s" % [PoseLabSpar.state_name(you), PoseLabSpar.posture_name(you)]],
		["STICK", PoseLabSpar.bits_name(your_bits)],
		["HELD", "%d FRAMES" % spar.held],
		["DUMMY", "%s · %s" % [PoseLabSpar.state_name(spar.dummy),
			PoseLabSpar.posture_name(spar.dummy)]],
	]
	var band := Rect2(right - 128.0, y - 3.0, 132.0, lines.size() * 8.0 + 26.0)
	UiMarks.wash(self, band, Palette.with_alpha(Palette.INK, 0.55),
		Palette.with_alpha(Palette.INK, 0.4))
	for i: int in lines.size():
		var at := y + i * 8.0
		UiFont.draw_text(self, String(lines[i][0]), Vector2(band.position.x + 4.0, at),
			UiFont.Cut.MICRO, Palette.with_alpha(Palette.LIGHT_SOFT, 0.85), UiFont.Align.LEFT,
			0.5)
		UiFont.draw_text(self, String(lines[i][1]), Vector2(right, at), UiFont.Cut.MICRO,
			Palette.PAPER, UiFont.Align.RIGHT, 0.5)
	var last := spar.last
	var word := String(last.get("word", "NOTHING YET"))
	var fresh := not last.is_empty() and spar.frame - int(last.get("frame", 0)) < FRESH_FRAMES
	var at_y := y + lines.size() * 8.0 + 2.0
	UiFont.draw_text(self, word, Vector2(right, at_y), UiFont.Cut.TEXT,
		Palette.LIGHT if fresh else Palette.with_alpha(Palette.PAPER, 0.75),
		UiFont.Align.RIGHT, 0.7)
	UiFont.draw_text(self, "LAST", Vector2(band.position.x + 4.0, at_y + 2.0),
		UiFont.Cut.MICRO, Palette.with_alpha(Palette.LIGHT_SOFT, 0.85), UiFont.Align.LEFT, 0.5)
	var detail := UiFont.fit(PackedStringArray([String(last.get("detail", ""))]),
		band.size.x - 6.0, UiFont.Cut.MICRO)
	UiFont.draw_text(self, detail, Vector2(right, at_y + 11.0), UiFont.Cut.MICRO,
		Palette.with_alpha(Palette.PAPER, 0.75), UiFont.Align.RIGHT, 0.5)
