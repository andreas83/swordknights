extends GutTest
## A lit cap is a promise: you can stand here (docs/world.md, "Lit caps are a
## promise"; docs/art-direction.md, "Lead the eye with light").
##
## A second player on a phone jumped at the Sun Terrace's balustrade, which
## hung a cell above the terrace with a gold rail across its top -- drawn as
## a ledge is drawn -- and called the carved friezes "horizontal ladders": two
## gold rails with slots between. Held here, against the atlas as generated
## and the dressing as every level gets it:
##
## - no decoration carries a band of light (LIGHT_WARM or brighter) across 12
##   or more of its 16 columns in any row. Terrain caps and platforms do; the
##   only decor exempt is drawn over a real cap (CAP_OVERLAYS);
## - every balustrade stands on what holds the prince up, never in the air
##   over it;
## - and the rule is not met by drawing nothing: the caps that should be
##   lit still are.

const ATLAS := "res://assets/tiles.png"
## The light: a pixel this bright, across a row, reads as the top of a floor.
const LIGHTS: Array[Color] = [Palette.LIGHT_WARM, Palette.LIGHT, Palette.LIGHT_SOFT,
	Palette.PAPER]
## How much of a row is a cap: three quarters of the tile.
const CAP_WIDTH := 12
## Decoration drawn over a floor's own cap, which may show that cap.
const CAP_OVERLAYS: Array[String] = ["crack_cap"]
const LEVELS: Array[String] = [
	"res://levels/level_01.txt", "res://levels/chapter_02.txt",
	"res://levels/chapter_03.txt", "res://levels/chapter_04.txt",
	"res://levels/chapter_05.txt", "res://levels/chapter_06_eclipse.txt",
	"res://levels/dawn.txt", "res://levels/feel_lab.txt",
]

var _atlas: Image


func before_all() -> void:
	_atlas = (load(ATLAS) as Texture2D).get_image()
	_atlas.decompress()


func test_no_decoration_is_lit_across_its_top() -> void:
	var checked := 0
	for id: String in Tiles.DECOR_ATLAS:
		if CAP_OVERLAYS.has(id):
			continue
		checked += 1
		var widest := _widest_light(Tiles.DECOR_ATLAS[id])
		assert_lt(widest, CAP_WIDTH,
			"%s has %d px of light across one row: it reads as somewhere to stand"
			% [id, widest])
	assert_gt(checked, 40, "the decorations were read")


func test_what_holds_the_prince_up_is_still_lit() -> void:
	for coords: Vector2i in [Tiles.ATLAS_SOLID_CAPPED, Tiles.ATLAS_SOLID_CAPPED_LIT,
			Tiles.ATLAS_PLATFORM]:
		assert_gte(_widest_light(coords), Tiles.ATLAS_COLUMNS,
			"the cap at %s is gold across its whole width" % coords)


func test_every_balustrade_stands_on_something() -> void:
	var rails := 0
	for path: String in LEVELS:
		var level := AsciiLevel.from_file(path)
		var mid: Dictionary = WorldDresser.dress(level)["mid"]
		for cell: Vector2i in mid:
			var id := _name_of(mid[cell])
			if id != "balustrade" and id != "balustrade_rug":
				continue
			rails += 1
			var under := level.kind_at(cell.x, cell.y + 1)
			assert_true(under == Tiles.Kind.SOLID or under == Tiles.Kind.PLATFORM,
				"%s: the railing at %s stands on the floor, not over it" % [path, cell])
	assert_gt(rails, 10, "the shipping levels' railings were found")


## The most pixels of light in any one row of the tile at `coords`.
func _widest_light(coords: Vector2i) -> int:
	var widest := 0
	for y: int in Tiles.ATLAS_COLUMNS:
		var lit := 0
		for x: int in Tiles.ATLAS_COLUMNS:
			var pixel := _atlas.get_pixel(coords.x * 16 + x, coords.y * 16 + y)
			if pixel.a > 0.5 and _is_light(pixel):
				lit += 1
		widest = maxi(widest, lit)
	return widest


func _is_light(pixel: Color) -> bool:
	for light: Color in LIGHTS:
		if pixel.is_equal_approx(Color(light.r, light.g, light.b, pixel.a)):
			return true
	return false


func _name_of(coords: Vector2i) -> String:
	for id: String in Tiles.DECOR_ATLAS:
		if Tiles.DECOR_ATLAS[id] == coords:
			return id
	return ""
