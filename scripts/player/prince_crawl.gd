class_name PrinceCrawl
extends RefCounted
## The crawl: on hands and knees under a ceiling one tile high
## (docs/character.md, "The crawl").
##
## Its own file, beside PrinceMoves, so Player carries two hooks and no more
## of it: one asks whether the prince is hemmed in under a ceiling (no sword,
## no standing up), the other takes the frame when a crawl is what the stick
## asks for. Everything else a crawl is, Player already is: the crouch's 13-px
## body (`Player._set_crouched()`), which every floor, ceiling, hazard and foe
## sees, so nothing reaches a crawl that does not reach a crouch.
##
## Two rules make it safe on a touch stick:
##
## - **Chosen, never fallen into.** From a crouch or from standing still with
##   down held. A run or a walk with the stick drifted low -- which a thumb on
##   a stick does all the time -- stays upright.
## - **Under a ceiling he stays down** whatever the stick says, and comes up
##   as a crouch does, the moment there is room.
##
## It is slow -- Tuning.CRAWL_SPEED is a little over half a walk -- so no
## passage it opens is a quicker way anywhere, and the proof charges it by
## that clock (ReachCrawl, ReachRace.CRAWL_TILE).


## Whether the standing body would fit where `player`'s feet are now.
static func room_to_stand(player: Player) -> bool:
	if player.level == null:
		return true
	return not player.level.rect_hits_solid(Rect2(
		player.position.x - Tuning.BODY_WIDTH * 0.5, player.position.y - Tuning.BODY_HEIGHT,
		Tuning.BODY_WIDTH, Tuning.BODY_HEIGHT
	))


## Down on the floor under a ceiling too low to stand in: he stays down, and
## no sword comes out -- there is no room to swing one. The press stays in
## the buffer for when there is.
static func hemmed(player: Player, grounded: bool) -> bool:
	return grounded and player._crouched and not room_to_stand(player)


## The frame, if it is a crawl's: true when it took it. One frame on hands and
## knees toward `want_x`, at CRAWL_SPEED, turning on the spot -- too slow to
## need the run's planted turn. Off the end of a floor he falls as anything
## does, and stands when there is room.
static func take(player: Player, delta: float, want_x: int, grounded: bool,
		is_hemmed: bool) -> bool:
	var at_rest := player._crouched or absf(player.velocity.x) < 1.0
	if not grounded or want_x == 0 or not (is_hemmed or (player.input.down and at_rest)):
		return false
	player._set_crouched(true)
	player.facing = want_x
	player.velocity.x = move_toward(player.velocity.x, float(want_x) * Tuning.CRAWL_SPEED,
		Tuning.GROUND_ACCEL * delta)
	player._enter(Player.State.CRAWL)
	return true
