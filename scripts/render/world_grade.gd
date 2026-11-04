class_name WorldGrade
extends CanvasModulate
## A level's hour, laid over the world (TimeOfDay).
##
## MatchDusk's grade, held still: a multiply over the world's canvas that
## keeps red and takes green and blue along MatchDusk.DUSK -- or goes past it
## to TimeOfDay.NIGHT -- with the sky painting its own hour rather than being
## multiplied down, and everything in MatchDusk.LIT lifted back out by the
## inverse of the multiply. The duel's grade follows the camera between rooms;
## a level's is fixed, so this is the same three moves without the camera.
##
## What is lifted is what must be read: the prince, every foe -- their tells
## are drawn in LIGHT and PAPER, and a tell that dims is a death that cannot
## be read -- every projectile, the torches and the relics. Each joins
## MatchDusk.LIT itself (Player, Foe, FoeProjectile, Torch, Relic), so a new
## foe is lifted by the contract, not by a list here. The grade falls on the
## city, not on what you fight.
##
## Presentation only, like MatchDusk: nothing here reaches the simulation. An
## afternoon level gets no grade at all -- `install()` adds nothing -- so the
## game as it always looked is the game as it always was, pixel for pixel.
##
## ## Put out for a while
##
## `dim` takes the hour further down, toward DARK times its own multiply, and
## the lift goes up with it, so the lit group stays exactly as bright while the
## city around it goes nearly black. The Eclipse's third phase is this: the
## vault put out, with the prince, the corona, the crown and the torches lifted
## out of it (docs/campaign.md, "How he uses the light"), so the dark never
## hides what must be read. A grade is found by GROUP rather than handed round:
## whoever darkens the world for a moment is presentation too, and has no
## business holding Game's nodes.
##
## ## The stone takes the grade by hand
##
## The world shader is unshaded and writes its colour outright -- the lit or
## the shade twin of each tile, picked from the mask -- so a CanvasModulate
## never lands on the stone: left to the canvas, the hour would grade the
## dressing's columns and the doves' terrace while the terrace itself stayed
## at four in the afternoon, and Chapter IV's dusk would be gold stone under a
## crimson sky. So the multiply the canvas gets, `color`, is laid on the stone
## too, through the shader's `tint`, every frame it changes: one grade, on the
## whole city. The hour walked by a sunset (Sunset moves `hour`) and the
## King's dim both arrive through the same multiply, and so through the same
## tint. What is lifted out of the canvas grade is lifted out of this one by
## construction: actors, lights, beams and bolts are drawn by their own nodes,
## never through the world shader. An afternoon installs no grade, and the
## tint stays white -- a multiply by exactly one, pixel for pixel the look the
## game always had.

## Every installed grade joins this.
const GROUP := &"world_grade"
## The multiply at full `dim`, as a share of the hour's own. Not zero: the
## lift is its inverse, and a little of the room should still be there.
const DARK := 0.2

var grade: Dictionary = {}
## The hour's own multiply: the grade's, until a sunset walks it to night.
var hour := Color.WHITE
## How far the world is put out past its hour: 0 none, 1 DARK.
var dim := 0.0
## The multiply last laid on the stone, and on which materials.
var _stone := Color.WHITE
var _materials: Array[ShaderMaterial] = []
var _layers_seen := -1


## Grades `game`'s world and `sky` for `level`'s hour. Returns the node, or
## null for an afternoon, which needs none.
static func install(game: Node, level: AsciiLevel, sky: ParallaxSky) -> WorldGrade:
	var grade := TimeOfDay.grade_of(level)
	if TimeOfDay.is_plain(grade):
		return null
	var node := WorldGrade.new()
	node.name = "WorldGrade"
	node.grade = grade
	node.hour = grade["world"]
	node.color = node.hour
	node.add_to_group(GROUP)
	if sky != null:
		sky.dusk = float(grade["sky"])
		sky.night = float(grade["night"])
	game.add_child(node)
	return node


## The modulate that brings a lifted node back to its own light.
func lift() -> Color:
	return Color(1.0 / color.r, 1.0 / color.g, 1.0 / color.b)


## The world's multiply with `dim` applied: the hour's own at 0.
func multiply() -> Color:
	var k := lerpf(1.0, DARK, clampf(dim, 0.0, 1.0))
	return Color(hour.r * k, hour.g * k, hour.b * k)


func _process(_delta: float) -> void:
	color = multiply()
	_grade_the_stone(color)
	var back := lift()
	for node: Node in get_tree().get_nodes_in_group(MatchDusk.LIT):
		var item := node as CanvasItem
		if item != null:
			item.modulate = back


## `tint` on every material the world shader draws the level's stone with:
## the tile layers and the slabs that share their material, and each secret's
## cover. Set when the multiply changes, and on any material that has joined
## since -- a secret's layers are made after the grade is installed.
func _grade_the_stone(tint: Color) -> void:
	var level := get_parent().get_node_or_null(^"Level") if get_parent() != null else null
	if level == null:
		return
	var layers := level.find_children("*", "TileMapLayer", true, false)
	if layers.size() != _layers_seen:
		_layers_seen = layers.size()
		_materials.clear()
		for layer: Node in layers:
			var material := (layer as TileMapLayer).material as ShaderMaterial
			if material != null and material.shader == Level.SUN_SHADER \
					and not _materials.has(material):
				_materials.append(material)
		_stone = Color(-1.0, -1.0, -1.0)
	if tint.is_equal_approx(_stone):
		return
	_stone = tint
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter(&"tint", Color(tint.r, tint.g, tint.b))
