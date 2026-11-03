class_name Mechanism
extends Node2D
## The contract every level mechanism keeps: pressure plates, gates, crumbling
## floors, timed traps, lifts. A new one is a file that extends this, one line
## in the entity registry, and a `;! mark` declaration in the level that uses
## it (docs/architecture.md, "Adding a mechanism").
##
## ## Placed and wired from the level text
##
## A mechanism is placed like any entity (scripts/entities/entity_registry.gd)
## from a declared glyph, `;! mark 1 plate channel=west_gate`, and gets every
## cell of the glyph's connected run in `cells` -- one gate three cells tall
## is one gate -- and the declaration's `key=value` words in `params`.
## `channel` is the wire: every mechanism naming the same one shares it on the
## level's ChannelBus. A trigger turns it on (`bus.hold`, `bus.latch`) from
## `meet()`, where it sees the prince; a receiver overrides `_on_channel()`.
##
## ## Changing what the character can pass
##
## `set_kind()` makes the mechanism's cells stone, a one-way platform, spikes,
## a ladder or air. It does both halves a cell needs, never the tilemap: its
## own StaticBody2D on Tiles.MASK_SOLID or MASK_ONE_WAY, which the character's
## move_and_slide() meets exactly as it meets terrain -- so dropping through a
## platform still works by clearing the one-way bit -- and the level's overlay
## (Level.set_overlay), which his ledge grab, footing and hazard checks read.
## The body stays active through a hitstop (DISABLE_MODE_KEEP_ACTIVE), so a
## gate does not blink out of the world for a frozen frame.
##
## ## Restarts and respawns put it back as authored
##
## A restart rebuilds every entity. A checkpoint respawn rebuilds every
## mechanism too, with a new bus, so it comes back exactly as the level text
## placed it -- see Game._respawn() for the argument: the respawn state has to
## be the state the checkpoint was proved in. So keep all state in the node;
## `_setup()` is the authored state, and that is the only reset there is.
##
## ## Telling the proof
##
## `static func reach(mark, model)` describes, to the reachability proof, how
## this kind changes passability (scripts/levels/reach_model.gd). The default
## says nothing, which the proof reads as "never changes": right for scenery,
## and conservative for anything that only ever helps. A mechanism that can
## open the way, or close it, must say so, or a level depending on it cannot
## be proved and a level it can break is not caught.

## A sound to play, through Game and GameAudio.cue.
signal cue(voice: StringName, options: Dictionary)
## A beat of weight, through Game's one impact budget.
signal impact(at: Vector2, frames: int, shake: float, weight: float)

const TILE := 16.0

var level: Level
var bus: ChannelBus
## Every cell of the mark, in reading order.
var cells: Array[Vector2i] = []
## The declaration's `key=value` words, as strings.
var params: Dictionary = {}
## The wire this mechanism is on; empty for one on no wire.
var channel: StringName = &""
var post := ""

var _body: StaticBody2D
var _kind: Tiles.Kind = Tiles.Kind.EMPTY


## --- the entity protocol ------------------------------------------------------

func place(site: EntitySite) -> void:
	position = site.at
	level = site.level
	bus = site.bus
	cells = site.cells.duplicate()
	params = site.params.duplicate()
	post = site.post
	channel = StringName(site.param("channel"))
	if bus != null and channel != &"":
		bus.changed.connect(_on_bus_changed)
	_setup()


## What this mechanism does about the prince on this frame. A trigger senses
## him here; the default does nothing.
func meet(_contact: Contact) -> void:
	pass


## --- for a mechanism to override ---------------------------------------------

## The authored state: the collision and look the level text describes. Called
## once, from place(), before the node enters the tree.
func _setup() -> void:
	pass


## The wire this mechanism listens to went on or off.
func _on_channel(_on: bool) -> void:
	pass


## How this kind changes passability, for the reachability proof. `mark` is
## the level's mark; see ReachModel for what can be said.
static func reach(_mark: Dictionary, _model: ReachModel) -> void:
	pass


## --- collision ------------------------------------------------------------------

## Makes every cell `kind`: SOLID and PLATFORM collide (one-way for the
## latter), SPIKES and WATER kill, LADDER climbs, EMPTY is air.
func set_kind(kind: Tiles.Kind) -> void:
	_kind = kind
	if _body == null:
		_body = _build_body()
	match kind:
		Tiles.Kind.SOLID:
			_body.collision_layer = Tiles.MASK_SOLID
		Tiles.Kind.PLATFORM:
			_body.collision_layer = Tiles.MASK_ONE_WAY
		_:
			_body.collision_layer = 0
	for shape: Node in _body.get_children():
		(shape as CollisionShape2D).one_way_collision = kind == Tiles.Kind.PLATFORM
	if level == null:
		return
	level.clear_overlay(self)
	if kind != Tiles.Kind.EMPTY:
		for cell: Vector2i in cells:
			level.set_overlay(cell, kind, self)


func current_kind() -> Tiles.Kind:
	return _kind


## A cell of the level, in world units.
static func cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(Vector2(cell) * TILE, Vector2(TILE, TILE))


## The prince is standing on one of this mechanism's cells: grounded, his feet
## at the cell's floor, and his body over it. The plate's test.
func feet_on(contact: Contact) -> bool:
	if not contact.grounded:
		return false
	for cell: Vector2i in cells:
		var box := cell_rect(cell)
		if absf(contact.feet.y - box.end.y) > 1.0:
			continue
		if contact.body.position.x < box.end.x and contact.body.end.x > box.position.x:
			return true
	return false


## Any part of the prince's body is in one of this mechanism's cells.
func body_in(contact: Contact) -> bool:
	for cell: Vector2i in cells:
		if contact.body.intersects(cell_rect(cell)):
			return true
	return false


## --- for the reach hook ------------------------------------------------------

static func mark_cells(mark: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell: Vector2i in mark.get("cells", [mark["cell"]]):
		out.append(cell)
	return out


static func mark_channel(mark: Dictionary) -> StringName:
	return StringName(String((mark.get("params", {}) as Dictionary).get("channel", "")))


## --- internals ------------------------------------------------------------------

func _build_body() -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = "Body"
	body.collision_layer = 0
	body.collision_mask = 0
	body.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	for cell: Vector2i in cells:
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(TILE, TILE)
		shape.shape = rect
		shape.position = cell_rect(cell).get_center() - position
		body.add_child(shape)
	add_child(body)
	return body


func _on_bus_changed(which: StringName, on: bool) -> void:
	if which == channel:
		_on_channel(on)


func _exit_tree() -> void:
	if level != null:
		level.clear_overlay(self)
