class_name Gate
extends Mechanism
## A portcullis: a vertical run of `!` hung from a lintel that carries its
## mason's mark. Open while its wire is on, shut while it is off -- what keeps
## the wire on is the plate's and the level's business (a latch, a hold of so
## many seconds, a foot), never the gate's.
##
## ## Timings (docs/campaign.md, "Counterweights")
##
## It rises over RISE_FRAMES: its foot clears the prince's 22 px about two
## thirds of the way up a two-course gate, frame 21. It falls in FALL_FRAMES
## and lands with a slam: steel points on stone, felt when it is near.
##
## ## A gate never closes on a body
##
## Each frame of its fall it asks whether its foot would come down on anyone
## -- the prince, a guard, a Bastion -- and if so it waits where it is, above
## them, until they have gone. There is no crush death, so there is none to
## misread: the race you lost costs you the time, never the chapter.
##
## ## The counterweight is the clock
##
## Beside the gate, on the side its plate is on, hangs its counterweight: a
## stone on a chain from the lintel. While the gate is held it is up; when the
## last foot leaves a held plate it sinks for exactly the hold, and the gate
## falls when it lands -- so the time left is in sight from anywhere on
## screen, as architecture, without a gauge. Its last second ticks: five
## chain ticks, one every TICK_FRAMES, each a jolt of the weight and a link's
## clink. A latched gate's weight goes up and stays: the clock that never runs
## down. The rules are the same on every gate, so the first gate -- which
## latches -- teaches the reading the race street then tests.
##
## The hold is not a warning that guards a death -- a race lost costs time --
## so LONGER WARNINGS leaves it alone; the races are proved with 25% slack
## instead (ReachRace).
##
## ## Drawing
##
## Bars in ink, two pixels wide -- a thin caster narrower than two pixels
## dots its shadow (docs/world.md) -- each lit down its sun-facing left edge;
## cross-rails every RAIL px; the points along the foot in steel, because a
## portcullis's points are spikes and spikes are what steel is for. It slides
## up into its lintel, so only what is still below the lintel is drawn, and
## the rails ride up with it. The static shadow mask is not re-solved for a
## thing that moves: the gate draws its own contact shadow on the floor.
##
## ## Collision
##
## One body, its shape the bars still below the lintel, resized as they move,
## so the foot is exactly where it is drawn; and in the level's overlay every
## cell the bars still reach is stone, for the probes. A gate cannot be
## grabbed: its top cell always has the lintel or more bars above it.

const RISE_FRAMES := 30
const FALL_FRAMES := 12
## The last second of a hold ticks this many times, this many frames apart.
const TICKS := 5
const TICK_FRAMES := 12
## Bars per course and their spacing.
const BARS := [2.0, 7.0, 12.0]
const RAIL := 8.0
## The steel at the foot of each bar.
const POINT := 3.0
## The counterweight.
const WEIGHT := Vector2(6.0, 10.0)
## Within this distance of the prince a slam is felt as well as heard.
const FELT := 8.0 * TILE

## How far the foot has risen above the floor, in pixels.
var raised := 0.0
## Which side the counterweight hangs: -1 left, +1 right.
var side := -1
## The counterweight's height as a share of its travel: 1 up (time in hand),
## 0 landed.
var weight := 0.0
## Frames of jolt left on the weight from a tick.
var jolt := 0

var _top := 0.0
var _floor := 0.0
var _column := 0
var _height := 0.0
var _shape: RectangleShape2D
var _mark := Vector2i(-1, -1)
var _covered := -1
var _was_on := false


static func reach(mark: Dictionary, model: ReachModel) -> void:
	model.switch_cells(Mechanism.mark_cells(mark), Mechanism.mark_channel(mark),
		Tiles.Kind.SOLID, Tiles.Kind.EMPTY)


static func wired() -> bool:
	return true


func _setup() -> void:
	var low := cells[0].y
	var high := cells[0].y
	for cell: Vector2i in cells:
		low = maxi(low, cell.y)
		high = mini(high, cell.y)
	_column = cells[0].x
	_top = float(high) * TILE
	_floor = float(low + 1) * TILE
	_height = _floor - _top
	_was_on = bus != null and bus.is_on(channel)
	raised = _height if _was_on else 0.0
	weight = 1.0 if _was_on else 0.0
	side = _plate_side()
	_mark = MasonsMark.cell_of(level, cells, channel)
	_build()
	_apply()


func meet(contact: Contact) -> void:
	var on := bus != null and bus.is_on(channel)
	if on and not _was_on:
		cue.emit(&"chain", {"pitch": 0.7})
	_was_on = on
	if on:
		raised = minf(_height, raised + _height / float(RISE_FRAMES))
	elif raised > 0.0:
		var next := maxf(0.0, raised - _height / float(FALL_FRAMES))
		if not _closes_on_body(contact, next):
			raised = next
			if raised <= 0.0:
				_slam(contact)
	_run_clock(on)
	_apply()


## The foot of the bars, in world units.
func foot() -> float:
	return _floor - raised


func is_shut() -> bool:
	return raised <= 0.0


## The bars' rect while `lifted` px up.
func bars(lifted: float) -> Rect2:
	return Rect2(float(_column) * TILE, _top, TILE, maxf(0.0, _height - lifted))


## --- the clock -------------------------------------------------------------------

func _run_clock(on: bool) -> void:
	jolt = maxi(0, jolt - 1)
	var left := bus.hold_left(channel) if bus != null else 0
	if on and left > 0:
		var total := maxi(1, roundi(_hold_seconds() * 60.0))
		weight = clampf(float(left) / float(total), 0.0, 1.0)
		if left <= TICKS * TICK_FRAMES and left % TICK_FRAMES == 0:
			jolt = 3
			var tick := TICKS - left / TICK_FRAMES
			cue.emit(&"chain", {"pitch": 1.0 + 0.06 * float(tick), "volume_db": -4.0})
	elif on:
		weight = minf(1.0, weight + 1.0 / float(RISE_FRAMES))
	else:
		weight = 0.0


func _hold_seconds() -> float:
	if level == null or level.data == null:
		return 0.0
	var spec: Dictionary = level.data.channels.get(String(channel), {})
	return float(spec.get("seconds", 0.0))


## --- the fall ------------------------------------------------------------------------

func _closes_on_body(contact: Contact, next: float) -> bool:
	var reach_to := bars(next)
	for body: Rect2 in Weight.bodies(self, contact):
		if body.intersects(reach_to):
			return true
	return false


func _slam(contact: Contact) -> void:
	cue.emit(&"land_hard", {"pitch": 0.8})
	cue.emit(&"masonry", {"volume_db": -4.0})
	var at := Vector2(float(_column) * TILE + TILE * 0.5, _floor)
	if contact != null and contact.alive and contact.body.get_center().distance_to(at) < FELT:
		impact.emit(at, 0, 1.2, 0.3)


## The side of the nearest plate on the same wire, where the counterweight
## hangs in sight of whoever is about to race it.
func _plate_side() -> int:
	if level == null or level.data == null:
		return -1
	var best := INF
	var out := -1
	for mark: Dictionary in level.data.entities:
		if String(mark["kind"]) != "plate":
			continue
		if String((mark.get("params", {}) as Dictionary).get("channel", "")) != String(channel):
			continue
		var dx := float((mark["cell"] as Vector2i).x - _column)
		if absf(dx) < best and dx != 0.0:
			best = absf(dx)
			out = 1 if dx > 0.0 else -1
	return out


## --- collision -------------------------------------------------------------------

func _build() -> void:
	var body := StaticBody2D.new()
	body.name = "Bars"
	body.collision_layer = Tiles.MASK_SOLID
	body.collision_mask = 0
	body.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	var shape := CollisionShape2D.new()
	_shape = RectangleShape2D.new()
	shape.shape = _shape
	body.add_child(shape)
	add_child(body)


## The body to the bars' extent, and every cell they still reach is stone.
func _apply() -> void:
	var rect := bars(raised)
	var shape := _shape_node()
	if shape != null:
		shape.disabled = rect.size.y <= 0.0
		_shape.size = Vector2(TILE, maxf(1.0, rect.size.y))
		shape.position = rect.get_center() - position
	var covered := 0
	for cell: Vector2i in cells:
		if float(cell.y) * TILE < rect.end.y - 0.01:
			covered += 1
	if covered != _covered:
		_covered = covered
		if level != null:
			level.clear_overlay(self)
			for cell: Vector2i in cells:
				if float(cell.y) * TILE < rect.end.y - 0.01:
					level.set_overlay(cell, Tiles.Kind.SOLID, self)
	queue_redraw()


func _shape_node() -> CollisionShape2D:
	var body := get_node_or_null(^"Bars")
	if body == null or body.get_child_count() == 0:
		return null
	return body.get_child(0) as CollisionShape2D


func _draw() -> void:
	PortcullisArt.draw(self, _top, _floor, _column, _mark)
