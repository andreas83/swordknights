class_name SpikeSlot
extends BeatBlade
## A spike slot on a beat (`i`, docs/campaign.md "Blades on the beat"): a
## grille in the floor whose spikes come up on the beat. The cell is the air
## over the floor stone -- where a body stands -- and a run of slots side by
## side is one slot, wired by the mark cut in the stone under one of them.
##
## ## The cycle
##
## | | frames | what it is |
## | --- | --- | --- |
## | tell | 27 (warn) | the grille rattles three times and the tips glint at the floor's lip |
## | up | 30 | the spikes are up: the cells are spikes, lethal like `^` |
## | down | the rest | a dark grille flush with the floor: the way over |
##
## Up, the cells are SPIKES through `set_kind()`, so the prince's own hazard
## check kills him exactly as a spike tile does and the ledge grab and the
## footing check see them too. A runner crosses two slots in 28 frames, so of
## the 70 frames they are down, 42 are a moment to set off from.
##
## Drawn in the spike tile's own steel, four points to a cell, lit the same
## way, so a slot that is up reads as the spikes the player has known since
## the Sun Terrace -- and only while it is up: the rise is two frames and the
## points are back under the grille on the frame the cells stop killing. A
## spike that is drawn is a spike that kills, and a spike that kills is drawn.

const UP := 30
const SPIKE_H := 11.0


static func live_frames() -> int:
	return UP


static func recover_frames() -> int:
	return 0


func live() -> int:
	return UP


func _apply() -> void:
	var kind := Tiles.Kind.SPIKES if is_live() else Tiles.Kind.EMPTY
	if _body == null or current_kind() != kind:
		set_kind(kind)


func _on_tell_step(step: int) -> void:
	if _on_screen():
		cue.emit(&"ladder", {"pitch": 2.5 + 0.1 * float(step), "volume_db": -12.0})


func _on_cut() -> void:
	if _on_screen():
		cue.emit(&"masonry", {"pitch": 2.0, "volume_db": -10.0})
		cue.emit(&"sword_hit", {"pitch": 1.6, "volume_db": -10.0})


## --- drawing ------------------------------------------------------------------

## How far up the points are, in pixels, for the current `t`.
func spike_height() -> float:
	if is_live():
		return SPIKE_H * minf(1.0, float(t + 1) / 2.0)
	if is_telling():
		# The rattle: the tips at the lip, jumping a pixel on each tooth.
		var step := (t - (PERIOD - tell_frames())) * 3 / tell_frames()
		return 1.0 + float(step % 2)
	return 0.0


func _draw() -> void:
	for cell: Vector2i in cells:
		var box := cell_rect(cell)
		box.position -= position
		_grille(box)
		var height := spike_height()
		if height > 0.0:
			_points(box, height)


## The grille cut into the floor's lip: ink, three bars of shade across it.
func _grille(box: Rect2) -> void:
	var lip := box.end.y
	draw_rect(Rect2(box.position.x + 1.0, lip, box.size.x - 2.0, 3.0), Palette.INK)
	for i: int in 4:
		draw_rect(Rect2(box.position.x + 2.0 + 4.0 * float(i), lip, 1.0, 3.0), Palette.SHADOW_DEEP)


## Four points to a cell, as the spike tile draws them: steel, darker on the
## left half.
func _points(box: Rect2, height: float) -> void:
	var lip := box.end.y
	for i: int in 4:
		var cx := box.position.x + float(i) * 4.0 + 2.0
		var h := roundf(height)
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx - 2.0, lip), Vector2(cx, lip - h), Vector2(cx + 2.0, lip),
		]), Palette.STEEL)
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx - 2.0, lip), Vector2(cx, lip - h), Vector2(cx, lip),
		]), Palette.STEEL_DARK)
		if is_telling():
			draw_rect(Rect2(cx, lip - h, 1.0, 1.0), Palette.PAPER)
