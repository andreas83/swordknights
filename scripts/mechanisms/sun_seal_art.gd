class_name SunSealArt
extends Node2D
## The light filling a sun-seal: its eight carved rays lighting one at a
## time, and the carved disc going from ink to paper as the last one lights.
##
## The fill is the seal's tell -- how close it is to opening, readable from
## across the room -- so it is lifted out of the hour's grade with every
## other tell (MatchDusk.LIT), while the slab it is carved in takes the grade
## with the wall (SunSeal). Each ray is a hard-edged notch of LIGHT_SOFT; the
## eighth, and the disc when it is full, are PAPER. A ray that drains goes
## back to the carving's dark at once: there are only two states a ray can
## be in, which is the art direction's rule for everything.

## The carved disc's radius, and where the rays run from and to.
const SUN_R := 3.0
const RAY_FROM := 4.5
const RAY_TO := 7.0

var seal: SunSeal


## The middle of the carving on a slab of `size`: centred across, and on a
## door at the height of a standing chest, where the eye already is.
static func sun_centre(size: Vector2) -> Vector2:
	if size.y > size.x:
		return Vector2(floorf(size.x * 0.5), floorf(size.y - 14.0))
	return Vector2(floorf(size.x * 0.5), floorf(size.y * 0.5))


func _ready() -> void:
	add_to_group(MatchDusk.LIT)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if seal == null or seal.phase == SunSeal.Phase.OPEN:
		return
	var size := seal.door_rect().size
	var drop := seal.sunk()
	var centre := sun_centre(size) + Vector2(0.0, drop)
	var floor_y := size.y
	var lit := seal.lit_rays()
	for i: int in SunSeal.RAYS:
		# The first ray points straight up and they light clockwise, so the
		# fill reads like a clock hand going round.
		var a := -PI * 0.5 + TAU * float(i) / float(SunSeal.RAYS)
		var dir := Vector2(cos(a), sin(a))
		var from := (centre + dir * RAY_FROM).round()
		var to := (centre + dir * RAY_TO).round()
		if maxf(from.y, to.y) >= floor_y:
			continue
		var colour := Palette.SHADOW_PIT
		if i < lit:
			colour = Palette.PAPER if i == SunSeal.RAYS - 1 else Palette.LIGHT_SOFT
		draw_line(from, to, colour, 1.0)
	if centre.y + SUN_R < floor_y:
		var core := Palette.SHADOW_PIT
		if lit >= SunSeal.RAYS:
			core = Palette.PAPER
		elif lit > SunSeal.RAYS / 2:
			core = Palette.MID
		elif lit > 0:
			core = Palette.SHADOW_WARM
		draw_circle(centre, SUN_R - 0.5, core)
