class_name Inscription
extends Node2D
## A few words cut into the back wall of a secret room.
##
## The reward that is not a thing to carry. A room found by looking closely
## should give the player something only looking closely earns, and in a city
## that is all architecture, that is the city talking: who built it, who sealed
## the doorway, what the sun has seen. Two or three short lines, in the game's
## own face at its smallest cut (scripts/ui/ui_font.gd), because a bitmap face
## designed at five pixels is legible in the world at five pixels.
##
## Cut, not written: the letters are a tone lighter than a recessed panel, as
## a carving catches what light reaches into a room, and the panel's lower and
## right inner edges are lit like every other recess the low sun finds
## (tools/generate_tiles_png.py, `_recess_lip`). Nothing glows.
##
## The text belongs to the level: a hand-made level names its own lines in
## AUTHORED, keyed by its title and the inscription's order left to right. A
## level with no lines of its own draws from POOL by its name, so it always
## reads the same.

## Level title -> one entry per inscription, left to right.
const AUTHORED := {
	"The Sun Terrace": [
		["THE KING", "NEVER KNEW"],
	],
	"The Long Arcade": [
		["SAME MARK", "SAME GATE"],
	],
	"The Aqueduct": [
		["WE LEFT", "BY NIGHT"],
	],
	"The Mirror Tower": [
		["NO KING", "KEEPS IT"],
	],
	"The Sun Well": [
		["THE SUN", "REMEMBERS"],
	],
}

## Two lines of at most nine letters. The smallest cut sets about seven units
## a letter, so that is a panel a little over four tiles wide: the most a
## secret room usually has to give it.
const POOL := [
	["THE SUN", "REMEMBERS"],
	["WE LEFT", "BY NIGHT"],
	["NO KING", "KEEPS IT"],
	["DUST", "TO GOLD"],
	["THE WELL", "RUNS DEEP"],
	["COUNT THE", "DOORS"],
]

const PADDING := Vector2(4.0, 3.0)
## How high the panel's bottom edge sits off the floor: eye level for a
## character twenty-two units tall, so the words are beside his face.
const SILL := 9.0

var lines: PackedStringArray = PackedStringArray()


static func text_for(level_name: String, index: int) -> PackedStringArray:
	var authored: Array = AUTHORED.get(level_name, [])
	if index < authored.size():
		return PackedStringArray(authored[index])
	var pick := posmod(hash(level_name) + index, POOL.size())
	return PackedStringArray(POOL[pick])


## The panel in local space; the node's origin is the floor under its cell.
func panel() -> Rect2:
	var wide := 0.0
	for line: String in lines:
		wide = maxf(wide, UiFont.width(line, UiFont.Cut.MICRO))
	var tall := float(lines.size()) * UiFont.line(UiFont.Cut.MICRO) - 2.0
	var size := (Vector2(wide, tall) + PADDING * 2.0).round()
	return Rect2(Vector2(-roundf(size.x * 0.5), -SILL - size.y), size)


func _draw() -> void:
	if lines.is_empty():
		return
	var box := panel()
	draw_rect(box, Palette.SHADOW_PIT)
	draw_rect(Rect2(box.position, Vector2(box.size.x, 1.0)), Palette.INK)
	draw_rect(Rect2(box.position, Vector2(1.0, box.size.y)), Palette.INK)
	draw_rect(Rect2(box.position.x + 1.0, box.end.y - 1.0, box.size.x - 1.0, 1.0),
		Palette.SHADOW)
	draw_rect(Rect2(box.end.x - 1.0, box.position.y + 1.0, 1.0, box.size.y - 1.0),
		Palette.SHADOW)
	var pen := Vector2(box.get_center().x, box.position.y + PADDING.y)
	for line: String in lines:
		UiFont.draw_text(self, line, pen, UiFont.Cut.MICRO, Palette.SHADOW_WARM,
			UiFont.Align.CENTER, 0.8)
		pen.y += UiFont.line(UiFont.Cut.MICRO)
