class_name Sunset
extends Node
## The sun going under, drawn: the hour's grade walked from dusk to night, the
## sky's bands with it, while the great mirror's sunset runs (SunMirror).
##
## Chapter IV ends the day. When the last ray has gone down the Well, the sun
## sets -- and the bible has the chapter end at night, so the player walks to
## the great door through the change rather than being told it happened. The
## simulation's half is the great mirror's: a count of physics frames from
## the moment its wire latched, after which no mirror and no glass is lit by
## the sun (SunField.sun_is_down()). This node only reads that count and
## paints it, on the display clock, which is all a node that changes nothing
## should use. It is the WorldGrade and the ParallaxSky the level was set up
## with that it moves -- the same grade, the same axis TimeOfDay walks
## (docs/world.md, "Time of day") -- so night here is Chapter V's night.

var mirror: SunMirror

var _from := Color.WHITE
var _from_sky := 0.0
var _grade: WorldGrade
var _sky: ParallaxSky


func _ready() -> void:
	var game := mirror.level.get_parent() if mirror != null and mirror.level != null else null
	if game == null:
		return
	_grade = game.get_node_or_null(^"WorldGrade") as WorldGrade
	_sky = game.get("sky") as ParallaxSky
	if _grade != null:
		_from = _grade.hour
	if _sky != null:
		_from_sky = _sky.night


func _process(_delta: float) -> void:
	if mirror == null:
		return
	var p := smoothstep(0.0, 1.0, mirror.sunset_progress())
	if p <= 0.0:
		return
	if _grade != null:
		_grade.hour = _from.lerp(TimeOfDay.NIGHT, p)
	if _sky != null:
		_sky.night = lerpf(_from_sky, 1.0, p)
