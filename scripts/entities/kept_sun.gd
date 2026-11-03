class_name KeptSun
extends Node2D
## The last light of the day, hung on chains under the dome of the Vault: the
## light the prince sent down the Well in Chapter IV, and the arena's only
## light (docs/campaign.md, "V. The Sun Well").
##
## ## It lights its own room
##
## The Vault is underground, so the sky the game paints behind every level --
## the far city at night -- must not show through it, and the atlas's
## backdrop tile, a wall of carved niches, is far too busy for a hall this
## size. So the kept sun draws the room it lights, in three planes:
##
## - **The back wall**, on this node, under the tiles: every open cell of the
##   level in deep shade with the joints of its courses, graded with the world
##   like any stone, so the night and the dark both fall on it.
## - **Its light on the wall**, also under the tiles: flat rings at whole-pixel
##   radii in the sun's own tones, stepping on the 12 fps clock the way a
##   torch's glow does -- hard edges, no gradient (docs/art-direction.md). Lit,
##   so the hour does not dim the light itself, only the stone around it.
## - **The sun and its chains**, over the tiles: the disc, the chains that
##   run up into the dark of the dome, and, while the vault is put out, the
##   one-pixel rim of corona light along the floor's lip and the galleries'.
##
## ## What it shows is the King's
##
## It holds no state of its own. It reads the Eclipse (Eclipse.KING) every
## frame and draws what he is doing with the light: kept and burning; poured
## down a shaft into his disc in the second phase and the finale; put out in
## the third, to an ember with the corona gone into his disc; and after the
## last blow, rising up the Well and out of the frame. With no King in the
## level -- after he has fallen and the level is played on -- it is simply
## the sun, risen.

## The kept sun's group, so the King's art finds the light it drinks.
const GROUP := &"kept_sun"
## How far above its mark the sun's centre hangs.
const HANG := 8.0
const RADIUS := 10.0
## The light on the wall, inner to outer: radius and opacity of each ring.
const RINGS: Array[Vector2] = [
	Vector2(22.0, 0.16), Vector2(42.0, 0.11), Vector2(70.0, 0.07), Vector2(110.0, 0.045),
]
const FPS := 12.0
## How fast it climbs the Well once released: pixels a second, squared.
const RISE_ACCEL := 90.0

## Open cells of the level, as rects in world units: the room it lights.
var room: Array[Rect2] = []
## Where the chains are hung from: the dome above the mark.
var ceiling_y := 0.0

var _light: Node2D
var _sun: Node2D
var _time := 0.0


func _ready() -> void:
	add_to_group(GROUP)
	z_index = -2
	_light = _Layer.new(self, &"draw_light")
	_light.z_index = 1
	add_child(_light)
	_sun = _Layer.new(self, &"draw_sun")
	_sun.z_index = 2
	add_child(_sun)


## --- the entity protocol --------------------------------------------------------

func place(site: EntitySite) -> void:
	position = site.at + Vector2(0.0, -HANG)
	if site.level == null or site.level.data == null:
		return
	var data := site.level.data
	room = rooms_of(data)
	var row := site.cell.y
	while row > 0 and not data.is_solid(site.cell.x, row - 1):
		row -= 1
	ceiling_y = float(row * Level.TILE)


## Nothing to meet: it is light, not a thing in the way.
func meet(_contact: Contact) -> void:
	pass


## Every open cell of `data`, merged along rows: the back wall to paint.
static func rooms_of(data: AsciiLevel) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var tile := float(Level.TILE)
	for y: int in data.rows:
		var start := -1
		for x: int in data.cols + 1:
			var open := x < data.cols and data.kind_at(x, y) == Tiles.Kind.EMPTY
			if open and start < 0:
				start = x
			elif not open and start >= 0:
				out.append(Rect2(start * tile, y * tile, (x - start) * tile, tile))
				start = -1
	return out


## The King, if he is in the level.
func eclipse() -> Eclipse:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(Eclipse.KING) as Eclipse


## How bright it is, 0 to 1: kept, put out, gathered into the disc.
func brightness() -> float:
	var king := eclipse()
	if king == null:
		return 1.0
	var out := 1.0 - king.darkness()
	if king.phase == Eclipse.Phase.FINALE:
		match king.state:
			Eclipse.State.GATHER:
				out *= 1.0 - 0.6 * clampf(king.state_time / king.gather_time(), 0.0, 1.0)
			Eclipse.State.POUR:
				out *= 0.35
	return out


## How far it has climbed the Well since the King let it go, in pixels.
func risen() -> float:
	var king := eclipse()
	if king == null or king.state != Eclipse.State.FALL:
		return 0.0
	var t := maxf(0.0, king.state_time - Eclipse.RELEASE_AT)
	return 0.5 * RISE_ACCEL * t * t


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()
	_light.queue_redraw()
	_sun.queue_redraw()


## The back wall: deep shade, a joint every course, staggered every other.
func _draw() -> void:
	var stone := Palette.SHADOW_PIT
	var joint := Palette.INK
	for rect: Rect2 in room:
		var local := Rect2(rect.position - position, rect.size)
		draw_rect(local, stone)
		draw_rect(Rect2(local.position.x, local.position.y, local.size.x, 1.0), joint)
		var course := int(rect.position.y / Level.TILE)
		var x := rect.position.x + (16.0 if course % 2 == 0 else 0.0)
		while x < rect.end.x:
			draw_rect(Rect2(x - position.x, local.position.y, 1.0, local.size.y), joint)
			x += 32.0


## --- the layers -------------------------------------------------------------------

func draw_light(into: Node2D) -> void:
	var lit := brightness()
	if lit <= 0.02:
		return
	var at := Vector2(0.0, -risen())
	var step := int(_time * FPS) % 3
	for i: int in RINGS.size():
		var ring: Vector2 = RINGS[i]
		var radius := ring.x + float((step + i) % 2)
		into.draw_circle(at, roundf(radius * (0.6 + 0.4 * lit)),
			Palette.with_alpha(Palette.LIGHT, ring.y * lit))


func draw_sun(into: Node2D) -> void:
	var lit := brightness()
	var up := risen()
	var at := Vector2(0.0, -up)
	_draw_chains(into, at, up)
	var flicker := float(int(_time * FPS) % 2)
	if lit > 0.05:
		into.draw_circle(at, RADIUS + 3.0 + flicker, Palette.with_alpha(Palette.LIGHT, 0.4 * lit))
		into.draw_circle(at, RADIUS, Palette.LIGHT.lerp(Palette.SHADOW_PIT, 1.0 - lit))
		into.draw_circle(at, RADIUS - 2.0, Palette.LIGHT_SOFT.lerp(Palette.SHADOW_PIT, 1.0 - lit))
		into.draw_circle(at + Vector2(-2.0, -2.0), RADIUS - 5.0,
			Palette.PAPER.lerp(Palette.SHADOW_PIT, 1.0 - lit))
	else:
		# Put out: an ember, its light in the King's disc.
		into.draw_circle(at, RADIUS, Palette.SHADOW_PIT)
		into.draw_arc(at, RADIUS - 0.5, 0.0, TAU, 24, Palette.MID, 1.0)
	_draw_rim(into)


## Two chains from the dome to the sun's shoulders, a link every 4 px: the
## ink of iron, with the sun's light on the side that faces it. Once the sun
## is rising they hang empty.
func _draw_chains(into: Node2D, at: Vector2, up: float) -> void:
	var top := ceiling_y - position.y
	for side: float in [-1.0, 1.0]:
		var anchor := Vector2(side * RADIUS * 1.6, top)
		# Hung, the chains meet the sun's shoulders; let go, they swing slack
		# a little wider where it was.
		var spread := 0.6 if up <= 0.0 else 0.9
		var hook := Vector2(side * RADIUS * spread, -RADIUS * 0.8)
		var length := hook.distance_to(anchor)
		var links := int(length / 4.0)
		for i: int in links:
			var p := anchor.lerp(hook, (float(i) + 0.5) / float(links)).round()
			var lit := i % 2 == 0
			into.draw_rect(Rect2(p.x - 1.0, p.y - 1.5, 2.0, 3.0),
				Palette.SHADOW_DEEP if lit else Palette.INK)
		if up <= 0.0:
			into.draw_line(hook, at + Vector2(side * RADIUS * 0.6, -RADIUS * 0.7),
				Palette.INK, 1.0)


## While the vault is put out, the corona's light still finds the lip of the
## floor and of each gallery: one pixel, so the ground is never lost.
func _draw_rim(into: Node2D) -> void:
	var king := eclipse()
	if king == null:
		return
	var dark := king.darkness()
	if dark <= 0.05:
		return
	var color := Palette.with_alpha(Palette.LIGHT_WARM, 0.75 * dark)
	var y := king.floor_y - position.y
	into.draw_rect(Rect2(king.west_x - position.x, y, king.east_x - king.west_x, 1.0), color)
	if king.gallery_y < king.floor_y:
		var g := king.gallery_y - position.y
		into.draw_rect(Rect2(king.west_x - position.x, g, king.west_lip - king.west_x, 1.0), color)
		into.draw_rect(Rect2(king.east_lip - position.x, g, king.east_x - king.east_lip, 1.0), color)


## A child canvas that draws through its owner, so one script holds the three
## planes and each plane can be in or out of the grade's lit group.
class _Layer extends Node2D:
	var owner_node: KeptSun
	var method: StringName

	func _init(by: KeptSun, drawer: StringName) -> void:
		owner_node = by
		method = drawer
		add_to_group(MatchDusk.LIT)

	func _draw() -> void:
		owner_node.call(method, self)
