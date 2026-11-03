extends GutTest
## The computer opponent's legs (scripts/duel/duel_feet.gd) on the real fighter:
## every hazard on the strip, crossed alive, from both sides.
##
## DuelFeet predicts jumps on the tile grid; the fighter moves through the
## physics engine. The two agree to the pixel on flat ground and can disagree
## at a corner, which is what this holds them to: the prediction is only worth
## anything if the real body, steered by it, lives. Run from the middle to
## each gate -- over the mound, onto the stepping stone, off it, over the moat
## -- with a perfect jumper and with the easy opponent's late one; then from a
## standstill at every distance from every lip, which is how a fighter meets a
## hazard after a fight rather than at a run.

const Support := preload("res://tests/duel_support.gd")
## Frames a run from the middle to a gate may take: about 530 at a clean run.
const RUN_LIMIT := 900
## Frames to get over one hazard from a standstill.
const HOP_LIMIT := 150

var _strip: ZoneStrip


func before_all() -> void:
	_strip = Support.load_strip()


func test_it_runs_home_over_everything_from_the_middle() -> void:
	await wait_physics_frames(1)
	for seat: int in 2:
		for slop: int in [0, 2]:
			var fight := _open(seat)
			var outcome := _drive(fight, seat, slop, RUN_LIMIT)
			assert_eq(outcome, "home", "seat %d, %d frames late: %s" % [seat, slop, outcome])
			fight.free()


func test_it_crosses_every_hazard_from_a_standstill() -> void:
	await wait_physics_frames(1)
	var lips := _lips()
	assert_eq(lips.size(), 8, "two lips each of two moats and two pits")
	var crossings := 0
	var failed: Array[String] = []
	for lip: Vector2 in lips:
		var dir := int(lip.y)
		for back: int in range(0, 40, 2):
			for slop: int in [0, 2]:
				var seat := 0 if dir < 0 else 1
				var fight := _open(seat)
				var me := fight.seats[seat].node as Fighter
				var x := lip.x - dir * (me.tuning.body_width * 0.5 + back)
				# On whatever is under the feet there: the floor, or the mound
				# beside the pit, never inside it.
				me.respawn_at(Vector2(x, float(_strip.ground_row(floori(x / 16.0)) * 16)), dir)
				var outcome := _drive(fight, seat, slop, HOP_LIMIT, lip.x + dir * 64.0)
				if outcome == "past" or outcome == "home":
					crossings += 1
				else:
					failed.append("%s from %d px short of x=%d going %+d, %d late"
						% [outcome, back, lip.x, dir, slop])
				fight.free()
	assert_eq(failed, [] as Array[String], "every standstill crossed")
	assert_eq(crossings, lips.size() * 40, "and all of them were run")


## The prediction everything else rests on: a jump leap() calls safe is one
## the real fighter survives. Run at every lip on the strip and, on each frame
## of the run-up, jump -- from a snapshot of the match, so every take-off is
## the same run up to that frame -- and compare what leap() said with what the
## physics did. A landing it calls safe that the body falls off is the bug
## that once put the easy opponent in the moat: a jump whose feet came down on
## a sliver of the far lip, which the grid counts as footing and the physics
## engine does not.
func test_a_predicted_landing_is_a_real_one() -> void:
	await wait_physics_frames(1)
	var wrong: Array[String] = []
	var safe := 0
	for lip: Vector2 in _lips():
		var dir := int(lip.y)
		var seat := 0 if dir < 0 else 1
		var fight := _open(seat)
		var me := fight.seats[seat].node as Fighter
		var x := lip.x - dir * 72.0
		me.respawn_at(Vector2(x, float(_strip.ground_row(floori(x / 16.0)) * 16)), dir)
		var run := PlayerInput.BIT_LEFT if dir < 0 else PlayerInput.BIT_RIGHT
		for frame: int in 40:
			var body := DuelView.Body.of(me)
			if (lip.x - me.position.x) * dir < 56.0 and body.grounded:
				var said := DuelFeet.leap(_strip, me.tuning, body, dir, true)
				var before := fight.write_state()
				var lived := _jump(fight, seat, run)
				fight.read_state(before)
				if bool(said["safe"]):
					safe += 1
					if not lived:
						wrong.append("x=%.1f toward %d" % [body.position.x, lip.x])
			fight.step(run if seat == 0 else 0, run if seat == 1 else 0)
		fight.free()
	assert_gt(safe, 40, "leap() called enough take-offs safe to test")
	assert_eq(wrong, [] as Array[String], "every one of them was")


## The landing rule itself, against an oracle that shares no code with it: a
## body coming down on the floor at any x near any lip counts as landed safe
## only if FOOTHOLD of its width is over something it can stand on. Swept in
## twentieths of a pixel, because the sliver the easy opponent once fell off
## was a tenth of a pixel wide -- too thin for a sampled run-up to find.
func test_a_landing_counts_only_with_a_foothold() -> void:
	var tuning := DuelTuning.new()
	var half := tuning.body_width * 0.5
	var bad: Array[String] = []
	var landings := 0
	for lip: Vector2 in _lips():
		var floor_y := float(_strip.ground_row(floori((lip.x - lip.y * 8.0) / 16.0)) * 16)
		var x := lip.x - 8.0
		while x <= lip.x + 8.0:
			var body := DuelView.Body.new()
			body.position = Vector2(x, floor_y - 0.5)
			body.velocity = Vector2(0.0, 60.0)
			body.grounded = false
			var said := DuelFeet.leap(_strip, tuning, body, 0, false)
			var under := _overlap(x - half, x + half, floori(floor_y / 16.0))
			if bool(said["safe"]):
				landings += 1
				if under < DuelFeet.FOOTHOLD - 0.01:
					bad.append("x=%.2f: %.2f px under the feet" % [x, under])
			x += 0.05
	assert_gt(landings, 500, "swept enough landings")
	assert_eq(bad, [] as Array[String], "none on less than a foothold")


## How much of [left, right] lies over tiles a foot can stand on in `row`.
func _overlap(left: float, right: float, row: int) -> float:
	var total := 0.0
	for column: int in range(floori(left / 16.0), floori(right / 16.0) + 1):
		var kind := _strip.kind_at(column, row)
		if kind != Tiles.Kind.SOLID and kind != Tiles.Kind.PLATFORM:
			continue
		total += maxf(0.0, minf(right, (column + 1) * 16.0) - maxf(left, column * 16.0))
	return total


## A full jump from where `seat` is, holding the run: alive and standing after?
func _jump(fight: DuelMatch, seat: int, run: int) -> bool:
	var me := fight.seats[seat].node as Fighter
	for frame: int in 50:
		var bits := run | (PlayerInput.BIT_JUMP if frame < DuelFeet.HOLD else 0)
		fight.step(bits if seat == 0 else 0, bits if seat == 1 else 0)
		if not fight.is_fighter_alive(seat):
			return false
		if frame > 2 and me.grounded:
			return true
	return false


## A match with the other seat dead and the initiative with `seat`, so the
## window opens toward its gate and nothing stands in the way.
func _open(seat: int) -> DuelMatch:
	var fight := Support.spawn_match(get_tree().root, _strip)
	while fight.phase == DuelMatch.Phase.COUNTDOWN:
		fight.step(0, 0)
	fight.seats[1 - seat].kill(seat)
	fight.step(0, 0)
	return fight


## Steers `seat` home with DuelFeet alone. Returns "home" at the gate, "past"
## once beyond `goal_x` (when given), "dead", or "stuck".
func _drive(fight: DuelMatch, seat: int, slop: int, limit: int, goal_x: float = NAN) -> String:
	var me := fight.seats[seat].node as Fighter
	var dir := ZoneStrip.goal_direction(seat)
	var held := 0
	for frame: int in limit:
		var body := DuelView.Body.of(me)
		var way := DuelFeet.steer(_strip, me.tuning, body, dir, held, slop)
		if bool(way["jump"]) and held == 0 and body.grounded:
			held = int(way["hold"])
		var bits := 0
		if held > 0:
			bits |= PlayerInput.BIT_JUMP
			held -= 1
		var d := int(way["dir"])
		bits |= PlayerInput.BIT_LEFT if d < 0 else (PlayerInput.BIT_RIGHT if d > 0 else 0)
		fight.step(bits if seat == 0 else 0, bits if seat == 1 else 0)
		if not fight.is_fighter_alive(seat):
			return "dead"
		if fight.phase == DuelMatch.Phase.CONSUMED or fight.phase == DuelMatch.Phase.MATCH_OVER:
			return "home"
		if not is_nan(goal_x) and (me.position.x - goal_x) * dir > 0.0 and me.grounded:
			return "past"
	return "stuck at x=%.0f" % me.position.x


## Every lip a running fighter can fall off on the floor of the strip, as
## (x of the edge, the direction you would be running to fall off it).
func _lips() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var floor_row := _strip.ground_row(0)
	for x: int in range(1, _strip.cols() - 1):
		var here := _strip.ground_row(x) >= 0
		var east := _strip.ground_row(x + 1) >= 0
		if here and not east:
			out.append(Vector2((x + 1) * 16.0, 1.0))
		if not here and east:
			out.append(Vector2((x + 1) * 16.0, -1.0))
	assert_gt(floor_row, 0, "the strip has a floor")
	return out
