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
## The tiles are the exception the dim has to reach by hand. The world shader
## is unshaded and writes its colour outright, so the canvas multiply never
## lands on the stone (the hour's grade does not either: its night is the
## atlas's shade half). While the world is dimmed, the same factor is laid
## on the stone through the shader's `tint`, and taken off again after.

## Every installed grade joins this.
const GROUP := &"world_grade"
## The multiply at full `dim`, as a share of the hour's own. Not zero: the
## lift is its inverse, and a little of the room should still be there.
const DARK := 0.2

var grade: Dictionary = {}
## How far the world is put out past its hour: 0 none, 1 DARK.
var dim := 0.0
## The factor last laid on the stone.
var _stone := 1.0


## Grades `game`'s world and `sky` for `level`'s hour. Returns the node, or
## null for an afternoon, which needs none.
static func install(game: Node, level: AsciiLevel, sky: ParallaxSky) -> WorldGrade:
	var grade := TimeOfDay.grade_of(level)
	if TimeOfDay.is_plain(grade):
		return null
	var node := WorldGrade.new()
	node.name = "WorldGrade"
	node.grade = grade
	node.color = grade["world"]
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
	var hour: Color = grade.get("world", Color.WHITE)
	var k := lerpf(1.0, DARK, clampf(dim, 0.0, 1.0))
	return Color(hour.r * k, hour.g * k, hour.b * k)


func _process(_delta: float) -> void:
	color = multiply()
	_tint_the_stone()
	var back := lift()
	for node: Node in get_tree().get_nodes_in_group(MatchDusk.LIT):
		var item := node as CanvasItem
		if item != null:
			item.modulate = back


## The dim, on the level's stone: the world shader's tint, set while there is
## any dim and once more to put it back to white.
func _tint_the_stone() -> void:
	var k := lerpf(1.0, DARK, clampf(dim, 0.0, 1.0))
	if is_equal_approx(k, _stone):
		return
	_stone = k
	var level := get_parent().get_node_or_null(^"Level") if get_parent() != null else null
	if level == null:
		return
	for layer: Node in level.find_children("*", "TileMapLayer", true, false):
		var material := (layer as TileMapLayer).material as ShaderMaterial
		if material != null and material.shader == Level.SUN_SHADER:
			material.set_shader_parameter(&"tint", Color(k, k, k))

