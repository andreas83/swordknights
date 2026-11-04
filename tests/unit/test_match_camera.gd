extends GutTest
## The duel camera on a match (scripts/duel/match_camera.gd), standing in front
## of a phone's screen through its seam: 2400 x 1080, six pixels a unit.
##
## Held here: through matches of biased random play -- runs, swings, kills,
## respawns ahead, the window dragged along the strip -- every living fighter
## inside the playable window is inside the view on every frame; while a
## fighter is down the frame stands back to the far level, and a fighter
## respawned ahead is on screen from the frame it is inside the window; and the
## camera is presentation: a match framed every frame and one never framed
## step to the same bytes.
##
## On the match's placeholder fighter, as the match's own suites are: these
## test the camera against the rope, and need no physics space.

const Support := preload("res://tests/duel_support.gd")
const DT := 1.0 / 60.0
const PHONE := Vector2(2400.0, 1080.0)

var _strip: ZoneStrip


func before_all() -> void:
	_strip = Support.load_strip()


func _match() -> DuelMatch:
	var fight := DuelMatch.new()
	add_child_autofree(fight)
	assert_true(fight.build(_strip), "the match builds")
	return fight


func _camera(fight: DuelMatch, screen: Vector2 = PHONE, per_unit: float = 6.0) -> MatchCamera:
	var camera := MatchCamera.new()
	camera.screen_pixels = screen
	camera.pixels_per_unit = per_unit
	add_child_autofree(camera)
	camera.setup(fight)
	return camera


## The fighters that must be on screen and are not, as text; empty when none.
func _lost(fight: DuelMatch, camera: MatchCamera) -> String:
	var view := camera.view_rect()
	var out := ""
	for slot: int in 2:
		if not fight.is_fighter_alive(slot):
			continue
		var at := fight.fighter_position(slot)
		if at.x < fight.scroll or at.x > fight.scroll + _strip.zone_width():
			continue # outside the window: a respawn ahead, not yet reachable
		var body := Rect2(at.x - 4.5, at.y - 22.0, 9.0, 22.0)
		if not view.encloses(body):
			out += "seat %d at %s outside %s; " % [slot, at, view]
	return out


func test_every_fighter_in_the_window_is_always_on_screen() -> void:
	for screen: Array in [[PHONE, 6.0], [Vector2(1920, 1080), 6.0], [Vector2(1280, 720), 4.0]]:
		for stream_seed: int in [5, 17]:
			var fight := _match()
			var camera := _camera(fight, screen[0], screen[1])
			var stream := Support.input_stream(3600, stream_seed)
			var first := ""
			var kills := 0
			var closest := 0
			for frame: int in stream.size():
				var deaths := fight.kills[0] + fight.kills[1]
				fight.step(stream[frame].x, stream[frame].y)
				if fight.kills[0] + fight.kills[1] > deaths:
					kills += 1
					camera.kill_beat(fight.fighter_position(1 if fight.respawn[1] > 0.0 else 0))
				camera._process(DT)
				closest = maxi(closest, camera.framing.level)
				var lost := _lost(fight, camera)
				if first == "" and lost != "":
					first = "frame %d: %s" % [frame, lost]
			assert_eq(first, "", "%s, seed %d: nobody framed out" % [screen[0], stream_seed])
			assert_gt(kills, 0, "%s, seed %d: the play had kills in it" % [screen[0],
				stream_seed])
			assert_gt(closest, camera.framing.far_level(),
				"%s, seed %d: and came in closer than far" % [screen[0], stream_seed])
			fight.queue_free()
			camera.queue_free()


func test_a_kill_stands_the_frame_back_and_a_respawn_ahead_comes_into_it() -> void:
	var fight := _match()
	while fight.phase == DuelMatch.Phase.COUNTDOWN:
		fight.step(0, 0)
	var camera := _camera(fight)
	var middle := fight.scroll + _strip.zone_width() * 0.5
	for slot: int in 2:
		var x := middle + (-16.0 if slot == 0 else 16.0)
		fight.seats[slot].respawn_at(Vector2(x, _strip.ground_row(floori(x / 16.0)) * 16.0),
			1 if slot == 0 else -1)
	for _frame: int in 240:
		fight.step(0, 0)
		camera._process(DT)
	assert_eq(camera.framing.level, camera.framing.close_level(), "close together: close")

	var fell := fight.fighter_position(1)
	fight.seats[1].kill(0)
	fight.step(0, 0)
	camera.kill_beat(fell)
	for _frame: int in roundi((MatchFraming.KILL_HOLD - 0.1) / DT):
		fight.step(0, 0)
		camera._process(DT)
	assert_eq(camera.framing.level, camera.framing.close_level(), "held on the kill")
	assert_true(camera.view_rect().has_point(fell), "with the body's spot in frame")
	for _frame: int in 60:
		fight.step(0, 0)
		camera._process(DT)
	assert_eq(camera.framing.level, camera.framing.far_level(),
		"then stood back while seat two is down")

	# Seat one, leading west, runs and hops at the respawn until it is in the
	# window: a hop on a held-and-released jump, as the demo's walker does.
	var seen_at := -1
	var entered_at := -1
	for frame: int in 60 * 12:
		var hop := PlayerInput.BIT_JUMP if frame % 20 < 14 else 0
		fight.step(PlayerInput.BIT_LEFT | hop, 0)
		camera._process(DT)
		if not fight.is_fighter_alive(1):
			continue
		var x := fight.fighter_position(1).x
		var inside := x >= fight.scroll and x <= fight.scroll + _strip.zone_width()
		if inside and entered_at < 0:
			entered_at = frame
		if camera.view_rect().has_point(fight.fighter_position(1) + Vector2(0.0, -11.0)) \
				and seen_at < 0:
			seen_at = frame
		if entered_at >= 0 and seen_at >= 0:
			break
	assert_gte(entered_at, 0, "the respawned fighter came into the window")
	assert_gte(seen_at, 0, "and onto the screen")
	assert_lte(seen_at, entered_at, "no later than it entered the window")


func test_the_camera_is_presentation() -> void:
	var plain := _match()
	var framed := _match()
	var camera := _camera(framed)
	var stream := Support.input_stream(1800, 5)
	var parted := -1
	var kills := 0
	for frame: int in stream.size():
		plain.step(stream[frame].x, stream[frame].y)
		var deaths := framed.kills[0] + framed.kills[1]
		framed.step(stream[frame].x, stream[frame].y)
		if framed.kills[0] + framed.kills[1] > deaths:
			kills += 1
			camera.kill_beat(framed.fighter_position(0))
		camera._process(DT)
		if parted < 0 and (plain.checksum() != framed.checksum()
				or plain.write_state() != framed.write_state()):
			parted = frame
	assert_gt(kills, 0, "through kills, holds and respawns")
	assert_eq(parted, -1, "framed every frame, the match steps to the same bytes")
