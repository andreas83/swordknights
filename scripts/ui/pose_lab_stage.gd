class_name PoseLabStage
extends Node2D
## The pose lab's ground: a real duel strip's middle zone, dressed, lit at the
## strip's hour, with the sky behind it -- because a figure's readability is
## judged against what it will be played against, and a figure on a flat
## swatch says nothing about the Well at night.
##
## Built from the duel's own parts, not a picture of them: ZoneView draws the
## zone as a match draws it (terrain, architecture, cast shadow, torches),
## MatchGround builds the floor the sparring fighters stand on, and the light
## is MatchDusk's rule held still -- the strip's hour as a multiply over the
## world, the sky painting its own, and everything in MatchDusk.LIT lifted
## back out of it, which is how both figures are lit in play. MatchDusk itself
## follows a MatchCamera through the gate rooms; the lab stands in the middle
## zone, where that dusk is nothing, so it keeps only the hour.
##
## What is not here: the strip's hazards. Their drawing reads a running match
## (HazardView), and the middle of every strip is open ground, which is where
## the marks are.

## The strips in the order the LIGHT row steps through them: their hours run
## from the brightest to the darkest.
const ORDER: Array[String] = ["tug", "floodgates", "aqueduct", "roofs", "well"]
const GROUND_TILES: TileSet = preload("res://assets/tiles.tres")

var strip: ZoneStrip
var strip_id := ""
## The strip's hour: {world: Color, sky: float, night: float} (TimeOfDay).
var hour: Dictionary = {"world": Color.WHITE, "sky": 0.0, "night": 0.0}
var sky: ParallaxSky

var _view: ZoneView
var _ground: TileMapLayer
var _grade: CanvasModulate


func _ready() -> void:
	_view = ZoneView.new()
	_view.name = "ZoneView"
	add_child(_view)
	_grade = CanvasModulate.new()
	_grade.name = "Grade"
	add_child(_grade)


## Puts the stage on strip `id`. False, with the stage left as it was, for a
## strip this build does not have.
func use_strip(id: String) -> bool:
	var next := DuelStrips.open(id)
	if next == null:
		return false
	strip = next
	strip_id = id
	_view.setup(strip)
	_view.focus(strip.zone_left(middle_zone()), PackedFloat32Array())
	if _ground != null:
		_ground.queue_free()
	_ground = MatchGround.ground_layer(strip, GROUND_TILES)
	add_child(_ground)
	_ground.update_internals()
	hour = TimeOfDay.grade_of(strip.as_level(0, 1))
	if sky != null:
		sky.seed_value = hash(strip.name)
	_light()
	return true


## The zone a match opens in, where the marks are.
func middle_zone() -> int:
	return strip.zone_of_x(strip.start_position(0).x)


## Where seat `slot` stands at the start of a match on this strip.
func mark(slot: int) -> Vector2:
	return strip.start_position(slot)


## A place to stand at exactly `x` when the floor there is the first mark's
## floor, at its height; otherwise the open ground nearest it, in whole columns
## the way a respawn is placed. Not ZoneStrip.is_open_ground(): that asks for
## room a respawn needs either side, and a column beside a mark can lack it.
func stand_at(x: float) -> Vector2:
	var column := floori(x / ZoneStrip.TILE)
	var home := mark(0)
	var row := strip.ground_row(column)
	if row >= 0 and float(row * ZoneStrip.TILE) == home.y \
			and strip.kind_at(column, row) == Tiles.Kind.SOLID:
		return Vector2(x, home.y)
	var found := strip.find_open_ground(x, home.x)
	return found["position"] if bool(found["ok"]) else home


## The line the LIGHT row shows: the strip and its hour.
func label() -> String:
	if strip == null:
		return ""
	return "%s · %s" % [DuelStrips.label(strip_id), TimeOfDay.label(strip.hour).to_upper()]


## The short form, for a narrow screen.
func short_label() -> String:
	return TimeOfDay.label(strip.hour).to_upper() if strip != null else ""


## The strip after this one in ORDER, stepping by `by`, round the end.
static func step(id: String, by: int) -> String:
	var at := maxi(0, ORDER.find(id))
	return ORDER[posmod(at + by, ORDER.size())]


func _process(_delta: float) -> void:
	_light()


## MatchDusk's rule at the middle of a strip: the hour's multiply over the
## world, the sky's own hour, and the lit group lifted back to full light.
func _light() -> void:
	var world: Color = hour.get("world", Color.WHITE)
	_grade.color = world
	if sky != null:
		sky.dusk = float(hour.get("sky", 0.0))
		sky.night = float(hour.get("night", 0.0))
	var lift := Color(1.0 / world.r, 1.0 / world.g, 1.0 / world.b)
	for node: Node in get_tree().get_nodes_in_group(MatchDusk.LIT):
		var item := node as CanvasItem
		if item != null:
			item.modulate = lift if _in_world(item) else Color.WHITE


## Whether `item` is drawn on the world's canvas, where the grade falls. The
## enlarged inset is on a layer of its own, which the grade never reaches, and
## lifting it would burn it white.
func _in_world(item: CanvasItem) -> bool:
	var node: Node = item
	while node != null:
		if node is CanvasLayer:
			return false
		node = node.get_parent()
	return true
