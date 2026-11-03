class_name DuelWorld
extends RefCounted
## What a duellist asks of the ground it stands on, and nothing more.
##
## A fighter resolves two things against the tile grid rather than with a
## physics query: whether it can stand up out of a roll, and where a loose sword
## flies and lands. Both need exactly these two questions. The match answers
## them with a ZoneStrip; the fighter's own tests answer them with a Level,
## through LevelWorld.
##
## This is a class rather than a comment because the comment version failed.
## Fighter.level was typed `Level`, the match handed it a ZoneStrip, and the
## typed assignment did nothing: the fighter ran with no world, so a thrown
## sword froze in the air and a roll could end standing up inside a ceiling.
## A shared base turns that into a type the compiler checks.


## True if any solid tile overlaps `rect`, in world pixels.
func rect_hits_solid(_rect: Rect2) -> bool:
	push_error("DuelWorld.rect_hits_solid() is abstract")
	return false


## The world's extent in pixels, from the origin.
func world_size() -> Vector2:
	push_error("DuelWorld.world_size() is abstract")
	return Vector2.ZERO
