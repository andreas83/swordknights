extends GutTest
## `;! checkpoints route` (scripts/levels/reach_route.gd, Game._progress()):
## "further on" as the moves left to the door along the proved route.
##
## The tower is the case the door's column gets wrong: three steps zig-zag up
## to a door at the top left, the lower torch right under the door's column
## and the higher one far across from it. By the column, the lower torch is
## the further on, and a prince who has taken it is refused the higher one --
## his next death would send him back down. Along the route, the higher torch
## is further, and the rule stays forward only. A level that does not ask
## keeps the column, which is what every shipping level was proved with.

const GAME_SCENE := "res://scenes/game.tscn"

## Each step is three tiles above the last -- a ledge grab -- so the climb
## has to go step by step: six tiles from the lowest step to the door's is
## further than any grab reaches.
const TOWER := """;! checkpoints route
; Tower






 D
######

            t
       #######

 t
######

          @
##############
"""

const LOW := Vector2i(1, 12)
const HIGH := Vector2i(12, 9)


func _parse(text: String) -> AsciiLevel:
	var level := AsciiLevel.new()
	level.parse(text)
	assert_eq(level.problems, PackedStringArray(), "the tower parses clean")
	return level


func _at(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * Level.TILE + Level.TILE * 0.5, (cell.y + 1) * Level.TILE)


func _play(text: String) -> Game:
	var game := (load(GAME_SCENE) as PackedScene).instantiate() as Game
	game.level_source = _parse(text)
	add_child_autofree(game)
	await wait_physics_frames(2)
	return game


func test_the_tower_is_climbed_and_both_torches_are_checkpoints() -> void:
	var level := _parse(TOWER)
	assert_true(bool(LevelReachability.verify(level)["ok"]), "the tower can be climbed")
	assert_eq(Game.checkpoint_cells(level), [HIGH, LOW] as Array[Vector2i],
		"and both torches lead to the door")


func test_the_route_counts_down_the_climb() -> void:
	var left := ReachRoute.remaining(_parse(TOWER))
	assert_true(left.has(LOW) and left.has(HIGH), "both torches are on the route")
	var spawn: int = left.get(Vector2i(10, 15), -1)
	assert_gt(spawn, int(left.get(LOW, 0)), "the lower torch is further on than the spawn")
	assert_gt(int(left.get(LOW, 0)), int(left.get(HIGH, 0)), "and the higher one than that")
	assert_eq(left.get(Vector2i(1, 6)), 0, "the door is no distance from the door")


func test_along_the_route_the_higher_torch_is_further_on() -> void:
	var game := await _play(TOWER)
	assert_true(game._offer_checkpoint(_at(LOW)), "the lower torch is taken")
	assert_true(game._offer_checkpoint(_at(HIGH)), "and then the higher one, across the tower")
	assert_false(game._offer_checkpoint(_at(LOW)), "and never the lower one again")
	assert_eq(game.checkpoint, _at(HIGH))


func test_by_the_doors_column_the_tower_is_read_wrong() -> void:
	var game := await _play(TOWER.replace(";! checkpoints route\n", ""))
	assert_true(game._offer_checkpoint(_at(LOW)), "the lower torch, under the door's column")
	assert_false(game._offer_checkpoint(_at(HIGH)),
		"refuses the higher one: what `;! checkpoints route` is for")
