class_name MatchDusk
extends CanvasModulate
## Dusk falls over the last room at each end of the strip.
##
## The gate zones are where a match is won, and the light says so: as the view
## moves into either end zone the world goes down from the duotone noon of the
## middle to a dusk lit by a burning sun on the horizon, and the view starts
## to tremble. Anything in the LIT group
## is lifted back out of it: the two duellists, so the darkest room is also the
## one where they read most clearly against the ground, and the torches, which
## are the only lights in it and should look like it.
##
## Presentation only. It reads the camera, never the match, and nothing it
## does reaches a snapshot or a checksum.
##
## A tint rather than a second, darker tile atlas: re-lighting the whole strip
## would be the palette edit docs/art-direction.md describes, but one room
## changing light inside a match needs both lights at once, and a multiply over
## the duotone keeps its hard edges and its two-tone structure.

## The light in the last room, as a multiply over the world: firelight from a
## sun on the horizon. Red is kept, green and blue are taken away, so crimson
## goes to blood and gold to burnt orange -- the final scene lit by the fire
## behind it, not merely darker.
const DUSK := Color(0.68, 0.36, 0.42)
## How far into a zone, in zone widths, dusk begins and is complete. Measured
## from the end of the strip: it starts as the view crosses into the last zone
## and is full by the time the view is centred on it.
const BEGINS := 1.35
const COMPLETE := 0.85

## Nodes in this group keep their own light through the dusk. Streamed nodes --
## the torches come and go with their zone -- join it when they are made.
const LIT := &"lit_at_dusk"

var camera: MatchCamera
var strip: ZoneStrip
var sky: ParallaxSky

## 0 at noon, 1 in full dusk. Public so a screenshot or a test can read it.
var amount := 0.0
## The strip's own hour (ZoneStrip.hour, through TimeOfDay): the light the
## whole strip is in before the gate rooms add their dusk. The afternoon for
## the Tug of War, which is the light it always had.
var hour: Dictionary = {"world": Color.WHITE, "sky": 0.0, "night": 0.0}


func setup(view: MatchCamera, zones: ZoneStrip, sky_node: ParallaxSky) -> void:
	camera = view
	strip = zones
	sky = sky_node
	hour = TimeOfDay.grade_of(strip.as_level(0, 1)) if strip != null else hour
	_apply()


func _process(_delta: float) -> void:
	_apply()


func _apply() -> void:
	if camera == null or strip == null:
		return
	var width := strip.zone_width()
	var from_west := camera.get_screen_center_position().x / width
	var from_east := float(strip.zone_count()) - from_west
	var west := smoothstep(BEGINS, COMPLETE, from_west)
	var east := smoothstep(BEGINS, COMPLETE, from_east)
	amount = maxf(west, east)

	# The darker of the hour and the gate's dusk, channel by channel: a strip
	# already at night is not lit back up by walking into its last room.
	var gate := Color.WHITE.lerp(DUSK, amount)
	var base: Color = hour["world"]
	color = Color(minf(gate.r, base.r), minf(gate.g, base.g), minf(gate.b, base.b))
	# The sky paints its own dusk -- a burning sun under ink -- rather than being
	# multiplied down, which would dim the very sun that is meant to glow.
	if sky != null:
		sky.dusk = maxf(amount, float(hour["sky"]))
		sky.night = float(hour["night"])
	camera.tremor = amount
	# Lifted back to full light: the inverse of the world's multiply, so the
	# dusk falls on the room and not on what is lit.
	var lift := Color(1.0 / color.r, 1.0 / color.g, 1.0 / color.b)
	for node: Node in get_tree().get_nodes_in_group(LIT):
		var item := node as CanvasItem
		if item != null:
			item.modulate = lift
