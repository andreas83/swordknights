class_name LevelWorld
extends DuelWorld
## A Level, seen as a duellist's world. Level is a Node and cannot extend
## DuelWorld itself; the fighter's tests build their stages as Levels.

var level: Level


func _init(of: Level = null) -> void:
	level = of


func rect_hits_solid(rect: Rect2) -> bool:
	return level != null and level.rect_hits_solid(rect)


func world_size() -> Vector2:
	return level.world_size() if level != null else Vector2.ZERO
