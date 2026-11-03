class_name Lift
extends Mechanism
## A stone slab on two chains that carries whatever stands on it between two
## stops: `[ ]` is the slab at its home stop, `'` the shaft it travels. The
## glyphs are one mechanism, and the end of the run furthest from home is the
## other stop -- so a lift drawn with its slab at the bottom goes up (Chapter
## II's lift court), and one drawn with it at the top goes down (Chapter V's
## throat). The shaft may be broken by other mechanisms' cells, a scythe's in
## the throat; the stop is the run's far end all the same.
##
## ## Ridden, or wired
##
## Unwired, it is **ridden** (docs/campaign.md, "Counterweights"): resting at
## a stop, it leaves DEPART_FRAMES after a body stands on it, goes to its
## other stop and waits; empty at the far stop for RETURN_FRAMES, it goes home.
## A rider who arrives has to step off before he can send it back, so a
## prince who stands still on it is not ferried to and fro for ever -- the
## wait is for him to get off. Wired by a mason's mark, it is at its far stop
## while its channel is on and at home while it is off, and riders are only
## carried.
##
## It moves at SPEED, a walk's pace: a rider reads as carried, never thrown.
## The prince and every foe ride it the way they stand on terrain -- the slab
## is a kinematic body on the solid layer, and CharacterBody2D takes a moving
## floor's velocity as its own -- so nothing here moves a body but the slab.
##
## ## It never moves into a body
##
## Before every step it asks whether the slab would close on anyone who is not
## riding it -- a prince in the pit its home stop leaves behind, a guard under
## a descending slab -- or would carry a rider's head into stone, and if so it
## waits where it is, exactly as a gate waits above a body. Coming down, it
## waits CLEARANCE above a body's head rather than on it: a slab parked on a
## prince's head in a one-deep pit leaves him no room to hop out, which is a
## soft lock with extra steps, and the test that first played it found him
## there. And it does not set off while anyone hangs from its edge: a resting
## slab is stone in the level's overlay, so it can be grabbed, and a ledge
## that leaves would hold a prince in the air.
##
## ## In the overlay only at rest
##
## Resting at a stop, its cells are SOLID in the level's overlay, so the
## ledge grab, careful footing and a guard's beat treat it as the floor it
## looks like. Moving, it is in no cell: a grab cannot catch a moving slab,
## and the body alone is what the prince stands on.
##
## ## The counterweight is in sight
##
## Like every counterweight in Chapter II, the lift's is drawn: a stone on the
## chain that runs over the drum on the landing, sinking as the slab rises.
## The slab, its chains, the drum and the weight are all this node's drawing;
## the static shadow mask is not re-solved for a thing that moves, so the slab
## draws its own contact shadow, as the characters do.
##
## ## Telling the proof
##
## An unwired lift is a ladder between its stops, with the lower stop's slab
## as floor -- the same connection, both ways -- which is how the campaign's
## stand-ins drew it. A ridden lift always goes home, so the promise holds as
## long as home is where the route needs it. A wired lift claims no ride: its
## slab is floor at home while its wire is off and at the far stop while it is
## on, and nothing in between.

## Physics frames per second: every count below is in them.
const RATE := 60.0
## A walk's pace, 40 px/s.
const SPEED := Tuning.WALK_SPEED
## Frames a body stands on a resting lift before it leaves.
const DEPART_FRAMES := 30
## Frames an empty lift waits at its far stop before it goes home.
const RETURN_FRAMES := 180
## How far above a body's head a descending slab waits: two tiles, so the
## body has the room a hop needs to get out from under it.
const CLEARANCE := 2.0 * Tuning.TILE
## Frames between the chain's clinks while it runs.
const RATTLE_FRAMES := 15
## The glyphs that are the slab; every other glyph of the kind is its shaft.
const PLATFORM_GLYPHS := "[]"

## Which stop: HOME where the slab is drawn, FAR the shaft's other end.
enum Stop { HOME, FAR }

## The row of each stop: the slab's top is the row's top edge.
var home_row := 0
var far_row := 0
## The slab's columns, left and right inclusive.
var first_column := 0
var last_column := 0
## The slab's top edge, in world units.
var top := 0.0
## The stop it rests at, or is on its way to.
var stop: Stop = Stop.HOME
var moving := false
## Frames someone has stood on it at rest, toward DEPART_FRAMES.
var ridden := 0
## Frames it has rested empty at the far stop, toward RETURN_FRAMES.
var idle := 0
## Set once the slab has been empty since it last arrived: until then, the
## rider it brought cannot send it back.
var fresh := true
## Where the chains go, in world units: the axle of a drum standing on the
## landing beside the upper stop (`drum_side` +1 or -1, the landing's side),
## or a point on the ceiling over the shaft (`drum_side` 0).
var drum := Vector2.ZERO
var drum_side := 0

var _slab: AnimatableBody2D
var _ran := 0


## --- what it is --------------------------------------------------------------

## The stops and columns a run of lift cells describes: `{home, far, first,
## last}`, rows and columns. `glyphs` is the run's cell -> glyph; without it
## (a declared mark) the bottom row is the slab.
static func geometry(cells: Array[Vector2i], glyphs: Dictionary) -> Dictionary:
	var slab: Array[Vector2i] = []
	var low := cells[0].y
	var high := cells[0].y
	for cell: Vector2i in cells:
		low = maxi(low, cell.y)
		high = mini(high, cell.y)
		if PLATFORM_GLYPHS.contains(String(glyphs.get(cell, ""))):
			slab.append(cell)
	if slab.is_empty():
		for cell: Vector2i in cells:
			if cell.y == low:
				slab.append(cell)
	var home := slab[0].y
	var first := slab[0].x
	var last := slab[0].x
	for cell: Vector2i in slab:
		first = mini(first, cell.x)
		last = maxi(last, cell.x)
	var far := high if high < home else low
	return {"home": home, "far": far, "first": first, "last": last}


static func reach(mark: Dictionary, model: ReachModel) -> void:
	var shape := geometry(Mechanism.mark_cells(mark), mark.get("glyphs", {}))
	var home := int(shape["home"])
	var far := int(shape["far"])
	var home_cells := _row(shape, home)
	var far_cells := _row(shape, far)
	var channel := Mechanism.mark_channel(mark)
	if channel != &"":
		model.switch_cells(home_cells, channel, Tiles.Kind.SOLID, Tiles.Kind.EMPTY)
		model.switch_cells(far_cells, channel, Tiles.Kind.EMPTY, Tiles.Kind.SOLID)
		return
	var upper := mini(home, far)
	var lower := maxi(home, far)
	var ladder: Array[Vector2i] = []
	for y: int in range(upper - 1, lower):
		ladder.append_array(_row(shape, y))
	model.fixed_cells(ladder, Tiles.Kind.LADDER)
	model.fixed_cells(_row(shape, lower), Tiles.Kind.SOLID)


static func _row(shape: Dictionary, y: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x: int in range(int(shape["first"]), int(shape["last"]) + 1):
		out.append(Vector2i(x, y))
	return out


## --- in play -------------------------------------------------------------------

func _setup() -> void:
	var glyphs := {}
	if level != null and level.data != null:
		glyphs = level.data.mechanism_glyphs
	var shape := geometry(cells, glyphs)
	home_row = int(shape["home"])
	far_row = int(shape["far"])
	first_column = int(shape["first"])
	last_column = int(shape["last"])
	stop = Stop.FAR if channel != &"" and bus != null and bus.is_on(channel) else Stop.HOME
	top = top_of(stop)
	_slab = AnimatableBody2D.new()
	_slab.name = "Slab"
	_slab.sync_to_physics = false
	_slab.collision_layer = Tiles.MASK_SOLID
	_slab.collision_mask = 0
	_slab.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	var shape_node := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(width(), TILE)
	shape_node.shape = box
	_slab.add_child(shape_node)
	add_child(_slab)
	_find_drum()
	_place_slab()
	_rest()


func meet(contact: Contact) -> void:
	var riding := Weight.anyone_on(self, contact, top, left(), left() + width(), true)
	if channel != &"":
		_follow_wire()
	elif not moving:
		_ride_rules(riding)
	if moving:
		_advance(contact)


## The world y of the slab's top at `at`.
func top_of(at: Stop) -> float:
	return float(home_row if at == Stop.HOME else far_row) * TILE


func left() -> float:
	return float(first_column) * TILE


func width() -> float:
	return float(last_column - first_column + 1) * TILE


## The slab now, in world units.
func slab_rect() -> Rect2:
	return Rect2(left(), top, width(), TILE)


func is_resting() -> bool:
	return not moving


## --- the rules -------------------------------------------------------------------

func _ride_rules(riding: bool) -> void:
	if not riding:
		fresh = true
		ridden = 0
		if stop == Stop.FAR:
			idle += 1
			if idle >= RETURN_FRAMES:
				_go(Stop.HOME)
		return
	idle = 0
	if not fresh:
		return
	ridden += 1
	if ridden >= DEPART_FRAMES:
		_go(Stop.FAR if stop == Stop.HOME else Stop.HOME)


func _follow_wire() -> void:
	var want := Stop.FAR if bus != null and bus.is_on(channel) else Stop.HOME
	if want != stop:
		_go(want)


func _go(to: Stop) -> void:
	stop = to
	if not moving:
		moving = true
		_ran = 0
		_unrest()
		cue.emit(&"chain", {"pitch": 0.8})


## One frame of travel, unless the slab would close on somebody.
func _advance(contact: Contact) -> void:
	var goal := top_of(stop)
	var next := move_toward(top, goal, SPEED / RATE)
	if _held(contact, next):
		return
	top = next
	_place_slab()
	_ran += 1
	if _ran % RATTLE_FRAMES == 0:
		cue.emit(&"chain", {"pitch": 1.1, "volume_db": -12.0})
	if is_equal_approx(top, goal):
		top = goal
		_place_slab()
		moving = false
		_rest()
		cue.emit(&"masonry", {"pitch": 1.7, "volume_db": -14.0})


## Whether moving the slab's top to `next` would close on a body: one in the
## way that is not riding it, a rider whose head would meet stone, or anyone
## hanging from its edge.
func _held(contact: Contact, next: float) -> bool:
	var x0 := left()
	var x1 := x0 + width()
	var lifted := next - top
	var ahead := Rect2(x0, next, width(), TILE + (CLEARANCE if lifted > 0.0 else 0.0))
	var edges := Rect2(x0 - 1.0, top, width() + 2.0, TILE)
	for body: Rect2 in Weight.bodies(self, contact):
		var on_it := absf(body.end.y - top) <= Weight.TOLERANCE \
			and body.position.x < x1 and body.end.x > x0
		if on_it:
			if lifted < 0.0 and level != null \
					and level.rect_hits_solid(Rect2(body.position + Vector2(0.0, lifted),
						body.size)):
				return true
			continue
		if body.intersects(ahead) or body.intersects(edges):
			return true
	return false


## At a stop: its cells are the floor they look like, in the overlay.
func _rest() -> void:
	ridden = 0
	idle = 0
	fresh = false
	_unrest()
	if level == null:
		return
	var row := home_row if stop == Stop.HOME else far_row
	for x: int in range(first_column, last_column + 1):
		level.set_overlay(Vector2i(x, row), Tiles.Kind.SOLID, self)


## Off its stop: in no cell, so nothing grabs or stands on it but its body.
func _unrest() -> void:
	if level != null:
		level.clear_overlay(self)


func _place_slab() -> void:
	if _slab != null:
		_slab.position = Vector2(left() + width() * 0.5, top + TILE * 0.5) - position
	queue_redraw()


## The drum stands on a landing beside the upper stop -- the side where there
## is stone to stand on with air above it, right first -- and failing one, the
## chains go up to the first stone over the shaft, or to a tile and a half
## above the upper stop.
func _find_drum() -> void:
	var upper := mini(home_row, far_row)
	var axle_y := float(upper) * TILE - 6.0
	for side: int in [1, -1]:
		var x := last_column + 1 if side > 0 else first_column - 1
		if level != null and level.is_solid_cell(Vector2i(x, upper)) \
				and not level.is_solid_cell(Vector2i(x, upper - 1)):
			drum = Vector2(float(x) * TILE + (4.0 if side > 0 else TILE - 4.0), axle_y)
			drum_side = side
			return
	drum_side = 0
	var centre := left() + width() * 0.5
	drum = Vector2(centre, float(upper) * TILE - TILE * 1.5)
	if level == null:
		return
	for y: int in range(upper - 1, maxi(upper - 14, -1), -1):
		if level.is_solid_cell(Vector2i(first_column, y)):
			drum = Vector2(centre, float(y + 1) * TILE)
			return


## --- drawing ---------------------------------------------------------------------

func _draw() -> void:
	LiftArt.draw(self)
