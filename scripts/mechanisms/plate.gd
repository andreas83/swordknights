class_name Plate
extends Mechanism
## A pressure plate: one of the floor's own stones, with the mason's mark of
## its wire cut in the stone under it (`o` over a digit). It is pressed while
## a body's weight is on it -- the prince, a guard, a Bastion, a Glassbearer;
## a cat or an owl is too light (Weight, Foe.has_weight()) -- and what a press
## means is its wire's: latched for good, held for a time, or only while
## stood on (ChannelBus). A plate never decides that; it is only a stone that
## gives under a foot.
##
## It sinks SINK px over SINK_FRAMES with a click, and comes back up the same
## way. The stone does not move in the world -- the tile under it is the
## floor and stays the floor, so nothing about footing changes -- only its
## drawing does: the seams that say "this stone is loose" and the dark
## recess its sinking opens at the top.
##
## A foe that stands on it from the first frame (Chapter II's weighed gate)
## presses it from the first frame, silently: the click is for something
## stepping on, not for a level loading with its weight already in place.
##
## ## Telling the proof
##
## Plates are floor, in the proof as in play. On a latched wire, standing on
## one latches it: the proof's one verb that sets a bit. On a held wire the
## press is a race (ReachRace); on a momentary wire it is nothing, because
## the prince cannot stand on a plate and walk through the gate it holds.

## How far the stone sinks, in pixels, and over how many frames.
const SINK := 2.0
const SINK_FRAMES := 4

var pressed := false
## How far the stone is down now, in pixels: the drawing's only state.
var sink := 0.0

var _met := false
var _mark := Vector2i(-1, -1)


static func reach(mark: Dictionary, model: ReachModel) -> void:
	var channel := Mechanism.mark_channel(mark)
	if channel == &"":
		return
	if model.channel_mode(channel) == "latch":
		model.latch_on_stand(Mechanism.cells_above(Mechanism.mark_cells(mark)), channel)


static func wired() -> bool:
	return true


func _setup() -> void:
	_mark = MasonsMark.cell_of(level, cells, channel)
	queue_redraw()


func meet(contact: Contact) -> void:
	var on := Weight.anyone_on(self, contact, top(), left(), right())
	if on and not pressed:
		bus.press(channel, self)
		if _met:
			cue.emit(&"masonry", {"pitch": 1.8, "volume_db": -10.0})
	elif pressed and not on:
		bus.release(channel, self)
	pressed = on
	_met = true
	var settled := move_toward(sink, SINK if pressed else 0.0, SINK / float(SINK_FRAMES))
	if not is_equal_approx(settled, sink):
		sink = settled
		queue_redraw()


## The plate's top surface, in world units.
func top() -> float:
	return float(cells[0].y) * TILE


func left() -> float:
	var x := cells[0].x
	for cell: Vector2i in cells:
		x = mini(x, cell.x)
	return float(x) * TILE


func right() -> float:
	var x := cells[0].x
	for cell: Vector2i in cells:
		x = maxi(x, cell.x)
	return float(x + 1) * TILE


func _draw() -> void:
	var o := position
	var x0 := left() - o.x
	var x1 := right() - o.x
	var y := top() - o.y
	# The seams that make it a stone of its own, and the hairline it sits
	# below the floor by even at rest: a loose stone is a stone that has
	# already given a little. Pressed, the recess opens to its full sink.
	for x: float in [x0, x1 - 1.0]:
		draw_rect(Rect2(x, y, 1.0, TILE), Palette.SHADOW_PIT)
	var gap := 1.0 + sink
	draw_rect(Rect2(x0 + 1.0, y, x1 - x0 - 2.0, gap), Palette.SHADOW_PIT)
	draw_rect(Rect2(x0 + 1.0, y + gap, x1 - x0 - 2.0, 1.0), Palette.LIGHT)
	if _mark.x >= 0:
		MasonsMark.draw(self, Vector2(_mark) * TILE - o, String(channel))
