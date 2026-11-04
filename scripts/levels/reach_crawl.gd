class_name ReachCrawl
extends RefCounted
## The crawl, for the reachability proof: through a passage one tile high,
## from standing room on one side to standing room on the other.
##
## The prince crawls from a crouch (PrinceCrawl.take()): the crouch's 13-px body
## on the floor at Tuning.CRAWL_SPEED, under any ceiling that leaves it room.
## That body fits wholly inside one row of cells, so the passage is a run of
## cells in the standing row whose own cell is clear of stone and hazard and
## whose floor holds him -- and in which he could not stand, or it would be
## a walk. The move is offered only when the run ends in a cell he can stand
## in, on the same row, so the proof claims exactly one thing: in one side,
## out the other, flat. A crawl off the end of a ledge, or into a fall, is a
## real thing a player can do and is not offered, by the same rule as the
## coyote jump (LevelReachability's docstring): the proof is of a reduced
## character, never a perfect one.
##
## It is kept out of the solver's own primitives, in one call from
## `Solver._expand_stand()`, so the search a level was proved by before the
## crawl is the search with `enabled` off -- and the tests compare the two:
## every chapter, the races, the secrets audit (tests/unit/test_crawl.gd).
##
## The race proof charges it by its own clock (ReachRace.CRAWL_TILE per
## cell): slower than a walk, so a passage it opens can only ever be a slower
## way to somewhere.

## Test seam: off, the proof is the one every level was proved by before the
## crawl existed.
static var enabled := true


## Appends to `out` every standing cell a crawl from standing in (x, y)
## reaches, left and right, setting the solver's `crawl_tiles` for the cost
## while it offers each.
static func offer(solver: LevelReachability.Solver, x: int, y: int, out: Array[int]) -> void:
	if not enabled:
		return
	for dir: int in [-1, 1]:
		var at := x + dir
		var tiles := 0
		while is_passage(solver, at, y):
			tiles += 1
			at += dir
		if tiles == 0 or not solver.is_stand(at, y):
			continue
		# The cells crawled, and the one he stands up in at the far end.
		solver.crawl_tiles = tiles + 1
		solver._offer_stand(at, y, out)
		solver.crawl_tiles = 0


## A cell of a passage: too low to stand in, room for the crouch, a floor.
static func is_passage(solver: LevelReachability.Solver, x: int, y: int) -> bool:
	if x < 0 or x >= solver.cols or y < 0 or y >= solver.rows:
		return false
	if solver.at(x, y) & (LevelReachability.F_SOLID | LevelReachability.F_HAZARD) != 0:
		return false
	if solver.at(x, y + 1) & (LevelReachability.F_SOLID | LevelReachability.F_PLATFORM) == 0:
		return false
	return not solver.is_stand(x, y)
