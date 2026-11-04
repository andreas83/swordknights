class_name MatchGround
extends DuelWorld
## The strip as a fighter finds it on this frame: the tiles, plus every slab of
## crumbling stone that has not yet fallen.
##
## A fighter asks its world two questions, both on the grid rather than through
## the physics engine (DuelWorld): can it stand up out of a roll here, and
## where does a loose sword come to rest. On a strip with crumbling stone the
## answer changes during a match, so the strip alone -- which is the level, and
## never changes -- would put a dropped sword through a slab that is still
## there. This answers from the strip and the match's own `stones`, which are
## in the snapshot, so two peers that agree on the state agree on where a sword
## lies.
##
## Only built for a strip that has stones. On any other the fighter is handed
## the strip itself, exactly as before (DuelMatch.build()).

var strip: ZoneStrip
var fight: DuelMatch


func _init(on: ZoneStrip = null, of: DuelMatch = null) -> void:
	strip = on
	fight = of


func rect_hits_solid(rect: Rect2) -> bool:
	if strip == null:
		return false
	if strip.rect_hits_solid(rect):
		return true
	return fight != null and strip.hazards.rect_hits_stone(rect, fight.stones)


func world_size() -> Vector2:
	return strip.world_size() if strip != null else Vector2.ZERO
