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

var grade: Dictionary = {}


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
	if sky != null:
		sky.dusk = float(grade["sky"])
		sky.night = float(grade["night"])
	game.add_child(node)
	return node


## The modulate that brings a lifted node back to its own light.
func lift() -> Color:
	return Color(1.0 / color.r, 1.0 / color.g, 1.0 / color.b)


func _process(_delta: float) -> void:
	var back := lift()
	for node: Node in get_tree().get_nodes_in_group(MatchDusk.LIT):
		var item := node as CanvasItem
		if item != null:
			item.modulate = back
