class_name DawnFrame
extends Node2D
## The dawn: the one frame of The Last Light lit from the east, held under
## DAWN and THE SUN REMEMBERS (Campaign.ENDING) until the player goes back to
## the chapter select (docs/campaign.md, "Decided by the owner").
##
## One still, not a scene: a terrace in the first light, the swordknight on
## it facing the sun, the Mirror Tower behind him in the west with its great
## mirror turned and lit -- in Chapter I it hung dark and turned away -- and
## the sun low on the right, the only time it is ever there. Nothing moves
## but what always moves: the air, the cloth, the sun's own pulse.
##
## ## The mirrored solve
##
## The frame is levels/dawn.txt, dressed and shaded by the same Level every
## chapter is built by, and its shadow is solved once, at load, by the same
## SunShadow -- on the frame as written, which is the frame mirrored. The
## world node is then reflected (`scale.x = -1`) and the shader told so
## (`_reflect_mask()`), so on screen every shadow falls down and to the LEFT.
##
## Why the whole world and not only the mask: the atlas is drawn lit from the
## west (gold on the west edge of every column, the west reveal of every arch)
## and so is the prince (PlayerArt: "the lit plane is always the world-left
## side of the body"). A mask solved from the east over that art would throw
## shadows one way from stones lit the other. Reflected whole, the solve, the
## atlas and the figure all agree, and none of them needed a second copy.
##
## The sky is not reflected -- it is in its own CanvasLayer -- and does its
## own half: ParallaxSky.east puts the disc on the right and the tower on the
## left, mirrored about the middle.

const FRAME := "res://levels/dawn.txt"

## How far along the sky's dusk axis the dawn is: a low, large sun with its
## heat bands, in a sky not yet at full day. The dusk axis is the only axis
## the sky has, and a sunrise is a sunset run backwards, which is the point.
const SKY := 0.35
## The Mirror Tower, near: the Well the swordknight came up out of is at its
## foot. Behind him now, in the west, and lit.
const TOWER := 0.4
## The long shadow the swordknight throws along the floor: the sun's lane
## runs SunShadow.RUN across for each RISE down, so a body this tall casts
## this far. Drawn as the floor's cap going to its shade twin, which is what
## the solve does to a floor under any standing caster.
const FIGURE_HEIGHT := 22.0
const CAP_LIT_ROWS := 3.0
## Where the doorway wall's lit east face stands across the view.
const WALL_AT := 0.16

var level: Level
var sky: ParallaxSky
var figure: FigurePreview
var card: EndingCard
## The reflected world: the level, the figure and its shadow.
var world: Node2D

var _camera: Camera2D


func _ready() -> void:
	var sky_layer := CanvasLayer.new()
	sky_layer.name = "Sky"
	sky_layer.layer = -10
	add_child(sky_layer)
	sky = ParallaxSky.new()
	sky.seed_value = hash("Dawn")
	sky.dusk = SKY
	sky.east = true
	sky.tower = TOWER
	sky.tower_lit = true
	sky.windows_lit = true
	sky_layer.add_child(sky)

	world = Node2D.new()
	world.name = "World"
	add_child(world)
	level = Level.new()
	level.name = "Level"
	level.level_path = FRAME
	world.add_child(level)
	world.scale = Vector2(-1.0, 1.0)
	world.position = Vector2(level.world_size().x, 0.0)
	_reflect_mask()

	var feet := _feet()
	var shadow := _FigureShadow.new()
	shadow.name = "FigureShadow"
	shadow.position = feet
	world.add_child(shadow)
	figure = _HeldFigure.new()
	figure.name = "Swordknight"
	# Faces west in the frame as written, which the reflection turns to face
	# the sunrise.
	figure.facing = -1
	figure.position = feet
	world.add_child(figure)
	Wardrobe.open().look(Wardrobe.PLAYER_ONE).dress(figure)

	_camera = Camera2D.new()
	_camera.name = "Camera"
	add_child(_camera)
	_camera.make_current()
	_frame_camera()
	get_viewport().size_changed.connect(_frame_camera)

	var text_layer := CanvasLayer.new()
	text_layer.name = "Words"
	add_child(text_layer)
	card = EndingCard.new()
	card.light_from_east = true
	text_layer.add_child(card)


## Where the swordknight's feet are on screen, in the world's (reflected)
## coordinates: the spawn mark's cell, standing on its floor.
func _feet() -> Vector2:
	var cell := level.data.spawn_point
	return Vector2((cell.x + 0.5) * Level.TILE, (cell.y + 1) * Level.TILE)


## The point on screen the frame's mask says is in shade, for a point given
## in screen-space world coordinates: the reflection undone, then the mask
## the solve made. What a test samples to know where the light comes from.
func shaded(at: Vector2) -> bool:
	var mask := SunShadow.last_mask if level != null else null
	if mask == null:
		return false
	var local := world.to_local(at)
	var x := int(floorf(local.x))
	var y := int(floorf(local.y))
	if x < 0 or y < 0 or x >= mask.get_width() or y >= mask.get_height():
		return false
	return mask.get_pixel(x, y).r > 0.5


## The world shader samples the mask by world position, and the world is now
## reflected about its own east edge: `x` on screen is `width - x` in the
## mask. A negative width in `level_px` is exactly that, so the shader is
## untouched.
func _reflect_mask() -> void:
	var size := level.world_size()
	for layer: TileMapLayer in [level.tilemap, level.decor_map, level.props_map]:
		var material := layer.material as ShaderMaterial
		if material == null:
			continue
		material.set_shader_parameter("mask_origin", Vector2(world.position.x, 0.0))
		material.set_shader_parameter("level_px", Vector2(-size.x, size.y))


## The frame's composition, held on the doorway wall's lit east face at
## WALL_AT of the view's width, whatever the width: the Mirror Tower stands in
## the sky just east of it (ParallaxSky's own place for it, mirrored), the
## swordknight on the floor toward the sun, his feet on the lower rail of the
## view and the reserved band clear above him for the words. Keyed on the
## prince instead, a wider screen slid the wall over the tower and left its
## mirror hanging off the masonry.
func _frame_camera() -> void:
	var view := get_viewport_rect().size
	var feet := world.to_global(_feet())
	var face := _wall_face()
	_camera.position = Vector2(roundf(face + view.x * (0.5 - WALL_AT)),
		roundf(feet.y - view.y * 0.29))


## The doorway wall's east face on screen: the most easterly stone standing
## on the swordknight's floor west of him.
func _wall_face() -> float:
	var data := level.data
	var row := data.spawn_point.y
	var face := 0.0
	for x: int in data.cols:
		if data.is_solid(x, row):
			var edge := world.to_global(Vector2(x * Level.TILE, 0.0)).x
			face = maxf(face, edge)
	return face


## The swordknight held in his standing pose: FigurePreview's mannequin
## without its loop, so the still stays still.
class _HeldFigure:
	extends FigurePreview

	func _advance(_delta: float) -> void:
		pass


## The swordknight's shadow along the floor's cap, behind him from the sun:
## a body FIGURE_HEIGHT tall on a lane of RUN across per RISE down.
class _FigureShadow:
	extends Node2D

	func _draw() -> void:
		var reach := DawnFrame.FIGURE_HEIGHT * float(SunShadow.RUN) / float(SunShadow.RISE)
		# The frame as written has the sun in the west, so the shadow runs east
		# (+x); the reflection sends it west, away from the sunrise.
		var cap := DawnFrame.CAP_LIT_ROWS
		draw_rect(Rect2(-2.0, 0.0, reach + 2.0, cap), Palette.SHADOW)
		draw_rect(Rect2(-2.0, cap, reach + 2.0, 1.0), Palette.SHADOW_DEEP)
