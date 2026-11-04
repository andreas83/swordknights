class_name MatchPlacement
extends RefCounted
## Where the match puts a fighter: a respawn ahead of the leader, back on a
## mark, into the window after a double kill, and up onto a bench when the
## trailing edge shoves one into its side.
##
## Every function here is static and a pure function of the strip and the
## numbers it is handed, so a placement is the same on two peers by
## construction and a test can ask for one without building a match. DuelMatch
## decides WHEN a fighter is placed and which of these applies
## (DuelMatch.respawn_plan); this file decides WHERE.
##
## Each placement is a Dictionary { ok, position, facing, column, pinned }.

## The match does not know how big a fighter is; the interface does not say. A
## tile-and-a-bit, which is every character in this project, and only ever used
## to decide whether a shove would bury one in rock.
const BODY := Vector2(9.0, 22.0)


## THE ALGORITHM, from the specification
##   3. computed from the LEADER's position, roughly 1.5 screen widths ahead in
##      the leader's direction of travel
##   4. facing the leader, to intercept them
##   5. edge case: if the leader is already at the edge of the final zone, the
##      opponent spawns directly in front of the exit
##
## Step 5 is not a separate branch here, it is the same clamp: the band of legal
## respawn columns stops five tiles short of each gate, so a target that would
## land behind the gate is pushed up against its mouth — which is what "directly
## in front of the exit" is. The leader then has to get past a fighter standing
## between them and the gate, which is the point of the rule.
##
## THE PACIFIST LINE
## A leader who killed and ran must be able to go over or under the respawn
## rather than being forced to fight it. That survives here because the chosen
## column is not simply the nearest one to the target but the nearest one with
## open ground: five columns of unbroken floor and eighty pixels of clear air.
## ZoneStrip.is_open_ground is the predicate and tests/match_respawn_test.gd
## walks the leader across the whole strip asserting it for every spawn the
## algorithm can produce.
static func ahead_of(strip: ZoneStrip, leader_x: float, direction: int, lead: float) -> Dictionary:
	var wanted := leader_x + direction * lead
	var band := strip.spawn_columns()
	var column := floori(wanted / ZoneStrip.TILE)
	var pinned := column < band.x or column > band.y

	var found := strip.find_open_ground(wanted, leader_x)
	var at: Vector2 = found["position"]
	return {
		"ok": bool(found["ok"]),
		"position": at,
		# Facing the leader, to intercept them.
		"facing": 1 if leader_x >= at.x else -1,
		"column": int(found["column"]),
		"pinned": pinned,
	}


## A seat's start mark, facing the other one: where a match opens, and where a
## fighter comes back while nobody has the initiative.
static func on_mark(strip: ZoneStrip, slot: int) -> Dictionary:
	var mark := strip.start_position(slot)
	return {
		"ok": true, "position": mark, "facing": 1 if slot == 0 else -1,
		"column": strip.cell_of(mark).x, "pinned": false,
	}


## Where a fighter comes back when there is no living leader to be ahead of --
## a double kill, which leaves the initiative with a leader who is down too.
## Both come back in the window whose left edge is `scroll`, as far either side
## of its middle as the start marks stand from the middle zone's: the leader
## (`leading`) on the side away from its gate, which is `direction`, and the
## other between it and that gate, facing each other -- where any respawn puts
## them, at the distance a match opens at. If the open ground near the two
## spots would put them the wrong way round, the other goes ahead of the
## leader's spot by the same rule a respawn uses.
static func in_window(strip: ZoneStrip, scroll: float, direction: int, leading: bool) -> Dictionary:
	@warning_ignore("integer_division")
	var middle := strip.zone_left(strip.zone_count() / 2) + strip.zone_width() * 0.5
	var apart := absf(strip.start_position(0).x - middle)
	var centre := scroll + strip.zone_width() * 0.5
	var mine := strip.find_open_ground(centre - direction * apart, centre)
	var at: Vector2 = mine["position"]
	if not leading:
		var theirs := strip.find_open_ground(centre + direction * apart, centre)
		var there: Vector2 = theirs["position"]
		if (there.x - at.x) * direction <= 0.0:
			return ahead_of(strip, at.x, direction, apart * 2.0)
		mine = theirs
		at = there
	return {
		"ok": bool(mine["ok"]),
		"position": at,
		"facing": direction if leading else -direction,
		"column": int(mine["column"]),
		"pinned": false,
	}


## A fighter the trailing edge shoves sideways can be shoved into the side of a
## bench. Lifted onto it instead, a tile at a time, which reads as being pushed
## up a step rather than sunk into the stone.
##
## This and DuelSeat.set_x are the only two places the match moves a fighter,
## and both would rather be a `push()` on the fighter itself.
static func shoved_onto_ground(strip: ZoneStrip, at: Vector2) -> Vector2:
	var lifted := at
	for _step: int in 3:
		if not strip.rect_hits_solid(body_at(lifted)):
			return lifted
		lifted.y = float(floori((lifted.y - 1.0) / ZoneStrip.TILE)) * ZoneStrip.TILE
	return lifted


static func body_at(feet: Vector2) -> Rect2:
	return Rect2(feet.x - BODY.x * 0.5, feet.y - BODY.y, BODY.x, BODY.y)
