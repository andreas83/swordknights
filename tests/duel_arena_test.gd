extends SceneTree
## The arena is a design document, and these are the claims it makes.
##
##     godot --headless --script tests/duel_arena_test.gd
##
## A duelling arena is not a level: it has to be fair, it has to connect, and
## its hazards have to actually threaten. Those are checkable, so they are
## checked — levels/arena_01.txt is edited by hand and every one of these is a
## property a stray keystroke could quietly break.

const Support := preload("res://tests/duel_support.gd")

## The traversal grammar, derived in scripts/core/tuning.gd rather than chosen:
## how far a duellist can climb and how far they can carry a jump.
const CLIMB_TILES := 3
const REACH_TILES := 3

var _s := Support.new()
var _warm := 0


func _physics_process(_delta: float) -> bool:
	_warm += 1
	if _warm < 2:
		return false

	var arena := Support.load_arena()
	_it_is_a_mirror_of_itself(arena)
	_there_is_one_spawn_and_it_mirrors_onto_solid_ground(arena)
	_nothing_standable_is_stranded(arena)
	_the_centre_pit_kills()
	_the_centre_can_still_be_crossed()

	quit(_s.report("duel_arena"))
	return true


## --- fairness ---------------------------------------------------------------

## Neither seat may be handed the better corner, and the cheapest way to
## guarantee that is for the arena to be its own reflection.
func _it_is_a_mirror_of_itself(arena: AsciiLevel) -> void:
	var wrong := 0
	var first := ""
	for y: int in arena.rows:
		for x: int in arena.cols:
			var here := arena.kind_at(x, y)
			var there := arena.kind_at(arena.cols - 1 - x, y)
			if here != there:
				wrong += 1
				if first == "":
					first = " (first at %d,%d: %d vs %d)" % [x, y, here, there]
	_s.equal(wrong, 0, "every tile mirrors about the centre line%s" % first)


## The arena carries one spawn mark; Duel mirrors it for the second seat. Both
## ends of that have to be somewhere a duellist can actually stand.
func _there_is_one_spawn_and_it_mirrors_onto_solid_ground(arena: AsciiLevel) -> void:
	var a := arena.spawn_point
	var b := Vector2i(arena.cols - 1 - a.x, a.y)
	_s.check(a != b, "the spawn is not on the centre line")

	for mark: Vector2i in [a, b]:
		_s.equal(
			arena.kind_at(mark.x, mark.y), Tiles.Kind.EMPTY,
			"the mark at %v is clear" % mark
		)
		_s.check(
			arena.is_solid(mark.x, mark.y + 1),
			"the mark at %v has solid ground under it" % mark
		)
		# A duellist is 22 px tall: that is two tiles of headroom.
		_s.equal(
			arena.kind_at(mark.x, mark.y - 1), Tiles.Kind.EMPTY,
			"the mark at %v has headroom" % mark
		)


## --- connectivity -----------------------------------------------------------

## No ledge may be an island. A perch that cannot be reached from anywhere else
## is a place to stand and wait out the round, which is the one thing a duelling
## arena must not offer.
func _nothing_standable_is_stranded(arena: AsciiLevel) -> void:
	var standable := _standable_cells(arena)
	_s.check(standable.size() > 20, "the arena has somewhere to stand (%d cells)"
		% standable.size())

	var start := arena.spawn_point
	_s.check(standable.has(start), "the spawn mark is somewhere you can stand")

	# Flood out from the spawn along moves the character can actually make.
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var at: Vector2i = queue.pop_back()
		for to: Vector2i in standable.keys():
			if seen.has(to):
				continue
			if _can_travel(arena, at, to):
				seen[to] = true
				queue.append(to)

	var stranded: Array[Vector2i] = []
	for cell: Vector2i in standable.keys():
		if not seen.has(cell):
			stranded.append(cell)
	_s.equal(
		stranded.size(), 0,
		"every standable cell can be reached from the spawn%s" % (
			"" if stranded.is_empty() else " — stranded: %s" % str(stranded.slice(0, 8))
		)
	)


## Cells a duellist can stand on: open, with something solid or one-way
## underneath, and headroom above.
func _standable_cells(arena: AsciiLevel) -> Dictionary:
	var out := {}
	for y: int in arena.rows - 1:
		for x: int in arena.cols:
			var here := arena.kind_at(x, y)
			if here != Tiles.Kind.EMPTY and here != Tiles.Kind.LADDER:
				continue
			if arena.kind_at(x, y - 1) == Tiles.Kind.SOLID:
				continue # no headroom
			var below := arena.kind_at(x, y + 1)
			if below == Tiles.Kind.SOLID or below == Tiles.Kind.PLATFORM:
				out[Vector2i(x, y)] = true
			elif here == Tiles.Kind.LADDER:
				out[Vector2i(x, y)] = true
	return out


## Deliberately generous: it is here to catch a ledge nothing can reach, not to
## model the jump arc. A climb of more than CLIMB_TILES needs a ladder in the
## column, and a ladder carries you the whole height of its run.
func _can_travel(arena: AsciiLevel, from: Vector2i, to: Vector2i) -> bool:
	var climb := from.y - to.y # positive means going up
	if _is_ladder_run(arena, from, to):
		return true
	if absi(to.x - from.x) > REACH_TILES:
		return false
	if climb > CLIMB_TILES:
		return false
	return true


## Two cells in the same column joined by an unbroken ladder.
func _is_ladder_run(arena: AsciiLevel, from: Vector2i, to: Vector2i) -> bool:
	if absi(to.x - from.x) > 1:
		return false
	var column := to.x
	var top := mini(from.y, to.y)
	var bottom := maxi(from.y, to.y)
	var rungs := 0
	for y: int in range(top, bottom + 1):
		if arena.kind_at(column, y) == Tiles.Kind.LADDER:
			rungs += 1
	# Allow a step on and a step off at either end.
	return rungs >= bottom - top - 1 and rungs > 0


## --- the centre -------------------------------------------------------------

## A duellist who walks into the middle of the arena dies there.
##
## This is a regression test with a story. The pit used to be two tiles wide,
## and it killed nobody: a duellist who walked off the lip was still falling
## slowly a few pixels later, the ledge-grab probe found the far wall, and they
## mantled up on the other side. The hazard was free passage. Four tiles puts
## the far wall out of reach.
func _the_centre_pit_kills() -> void:
	var duel := Support.spawn_duel(root)
	_fight(duel)
	var died := -1
	for i: int in 400:
		duel.step(PlayerInput.BIT_RIGHT, PlayerInput.BIT_LEFT)
		if not duel.players[DuelRules.SLOT_A].is_alive():
			died = i
			break
	_s.check(died >= 0, "walking into the centre is fatal")
	_s.check(
		not duel.players[DuelRules.SLOT_B].is_alive(),
		"and it is fatal from the other side too"
	)
	_s.check(
		duel.players[DuelRules.SLOT_A].state != Player.State.HANG,
		"nobody ends up hanging in the pit instead of falling in it"
	)
	duel.free()


## ...but it is not a wall. There is a stepping stone over the middle, and a
## duellist who jumps for it gets across.
func _the_centre_can_still_be_crossed() -> void:
	var duel := Support.spawn_duel(root)
	_fight(duel)
	var runner := duel.players[DuelRules.SLOT_A]
	var middle := duel.arena_size().x * 0.5

	# Run at the pit and jump as the ground runs out. The lip is four tiles
	# left of the middle; give the jump a tile of run-up.
	var lip := middle - 2.0 * 16.0
	var crossed := false
	var holding_jump := false
	for i: int in 400:
		# Hop whenever the ground ahead is about to disappear, which happens
		# twice: onto the stone, and off it again. Hold the button through the
		# rise — letting go early triggers the jump cut in Player, which is
		# exactly how a real hop gets fumbled into the pit.
		if runner.is_grounded():
			holding_jump = _needs_a_hop(duel, runner)
		elif runner.velocity.y >= 0.0:
			holding_jump = false

		var bits := PlayerInput.BIT_RIGHT
		if holding_jump:
			bits |= PlayerInput.BIT_JUMP
		duel.step(bits, 0)
		if not runner.is_alive():
			break
		if runner.position.x > middle + 2.0 * 16.0 and runner.is_grounded():
			crossed = true
			break

	_s.check(
		crossed,
		"a duellist who jumps for the stepping stone crosses the pit (ended at %.0f, lip %.0f, alive %s)"
			% [runner.position.x, lip, runner.is_alive()]
	)
	duel.free()


## True when there is nothing solid just ahead of and just below the feet.
func _needs_a_hop(duel: Duel, runner: Player) -> bool:
	if not runner.is_grounded():
		return false
	var ahead := runner.position + Vector2(float(runner.facing) * 12.0, 2.0)
	return not _is_footing(duel, ahead)


func _is_footing(duel: Duel, at: Vector2) -> bool:
	var kind := duel.level.kind_at_world(at)
	return kind == Tiles.Kind.SOLID or kind == Tiles.Kind.PLATFORM


func _fight(duel: Duel) -> void:
	for i: int in 240:
		if duel.phase == Duel.Phase.FIGHTING:
			return
		duel.step(0, 0)
