extends GutTest
## Every strip between two real NetSessions, and every gimmick through a
## rewind: the blades and the water are the frame's, the stones are the
## snapshot's, and neither may ever make two peers disagree.
##
## tests/match_net_test.gd plays the Tug of War between a host and a client
## over a loopback link, clean, laggy and lossy, and asks the corrected-outcome
## questions of it. This plays every other strip over the same three links
## with the same closing bots and holds each to zero desyncs with the detector
## actually verifying; then it rewinds a match on each strip to a snapshot
## taken just before its gimmick fires -- a scythe's cut, a basin's rise, a
## slab's fall -- replays the same inputs, and requires every byte of every
## frame to come back the same. Both were seen to fail with the stones left
## out of the snapshot: the client stood on a slab the host had dropped, and
## the replay put a fallen slab back.
##
## Inside one physics frame, as every match test is (tests/duel_support.gd).
##
## ## Two devices are two worlds
##
## Each match here is in a physics space of its own (a SubViewport with its
## own World2D), as a host and a guest are on two phones. tests/match_net_test.gd
## builds both in one space and gets away with it on the Tug of War, because a
## fighter collides with nothing of the other match's but an identical ground.
## On the Aqueduct it does not get away with it: with both matches' ground and
## slabs in one space, the laggy link parted a host and a client by 1.2e-4 px
## beside a slab on frame 140 -- across a 1/256 quantum -- and in separate
## spaces the same run, and every other link and strip, parts by nothing. The
## cross-talk was the test's, not the game's; a test of two devices now has two.

const Support := preload("res://tests/duel_support.gd")
const FIGHTER_SCENE: PackedScene = preload("res://scenes/fighter.tscn")
## Polls of both sessions per link: ten seconds, enough for the Floodgates'
## first sluice to open and the Aqueduct's middle to be worn.
const POLLS := 720
const HANDSHAKE_POLLS := 240
## [label, latency, jitter, loss] per link, as tests/match_net_test.gd has them.
const LINKS := [["clean", 0, 0, 0.0], ["laggy", 6, 2, 0.0], ["lossy", 3, 1, 0.15]]


func test_every_strip_plays_online_without_a_desync() -> void:
	await wait_physics_frames(1)
	for id: String in DuelStrips.IDS:
		if id == DuelStrips.TUG:
			continue # tests/match_net_test.gd plays it, and more besides
		var strip := DuelStrips.open(id)
		for link: Array in LINKS:
			_play_online(strip, link, 101 + LINKS.find(link) * 101)


func test_every_gimmick_rewinds_and_replays_byte_for_byte() -> void:
	await wait_physics_frames(1)
	# Where each strip's gimmick is about to act, and how to see that it did.
	# A cut begins inside the window: a blade not live one frame and live the next.
	_rewind("well", 300, 120, func(fight: DuelMatch, from: int, to: int) -> bool:
		for blade: Dictionary in fight.strip.hazards.blades:
			for f: int in range(from + 1, to + 1):
				if StripHazards.is_live(blade, f) and not StripHazards.is_live(blade, f - 1):
					return true
		return false)
	# The water moves inside the window.
	_rewind("floodgates", 600, 150, func(fight: DuelMatch, from: int, to: int) -> bool:
		var flood: Dictionary = fight.strip.hazards.floods[0]
		return StripHazards.fill_of(flood, to) != StripHazards.fill_of(flood, from))
	# The slab seat 0 was stood on drops inside the window.
	_rewind("aqueduct", 120, 160, func(fight: DuelMatch, _from: int, _to: int) -> bool:
		return StripHazards.has_fallen(fight.stones[int(fight.get_meta(&"stood", 0))]), true)
	# Static: there is nothing to act but the fight, which is there or not.
	_rewind("roofs", 120, 200, func(_fight: DuelMatch, from: int, to: int) -> bool:
		return to > from)


## A slab stood on drops after its fuse, the fighter on it falls through the
## collision it had, and a snapshot from before the drop puts it back under
## their feet: the bodies follow the bytes both ways.
func test_a_fallen_slab_is_gone_from_the_physics_and_comes_back_on_a_rewind() -> void:
	await wait_physics_frames(1)
	var strip := DuelStrips.open("aqueduct")
	var fight := Support.spawn_match(get_tree().root, strip)
	var cell: Vector2i = strip.hazards.stones[strip.hazards.stone_count() / 2]
	var on := Vector2(cell.x * 16.0 + 8.0, cell.y * 16.0)
	_skip_countdown(fight)
	fight.seats[0].respawn_at(on, 1)
	fight.step(0, 0)
	var index := strip.hazards.stone_index(cell)
	assert_true(StripHazards.is_burning(fight.stones[index]), "a foot lights the slab")
	var before := fight.write_state()
	for i: int in StripHazards.FUSE + 4:
		fight.step(0, 0)
	assert_true(StripHazards.has_fallen(fight.stones[index]), "and it drops after its fuse")
	for i: int in 30:
		fight.step(0, 0)
	assert_gt(fight.fighter_position(0).y, on.y + 8.0, "and the fighter on it went with it")
	assert_true(fight.read_state(before), "the snapshot from before reads back")
	for i: int in 10:
		fight.step(0, 0)
	assert_almost_eq(fight.fighter_position(0).y, on.y, 0.5,
		"and the slab is under their feet again")
	fight.free()


func _play_online(strip: ZoneStrip, link: Array, seed_value: int) -> void:
	var label := "%s %s" % [strip.id, link[0]]
	var host_match := _open_match(strip, "Host")
	var client_match := _open_match(strip, "Client")
	var ends := LoopbackTransport.pair(seed_value)
	var host_end: LoopbackTransport = ends[0]
	var client_end: LoopbackTransport = ends[1]
	host_end.latency_frames = int(link[1])
	host_end.jitter_frames = int(link[2])
	host_end.drop_rate = float(link[3])
	client_end.latency_frames = int(link[1])
	client_end.jitter_frames = int(link[2])
	var host := NetSession.new()
	var client := NetSession.new()
	host.local_input = _bot(host_match, 0, seed_value)
	client.local_input = _bot(client_match, 1, seed_value)
	host.start(host_end, host_match, true)
	client.start(client_end, client_match, false)
	var shaken := 0
	while shaken < HANDSHAKE_POLLS and not (host.is_running() and client.is_running()):
		host.poll()
		client.poll()
		shaken += 1
	assert_lt(shaken, HANDSHAKE_POLLS, "%s: both sessions reach RUNNING" % label)
	var start := host_match.frame
	for i: int in POLLS:
		host.poll()
		client.poll()
	assert_gt(host_match.frame - start, POLLS * 9 / 10, "%s: the host kept stepping" % label)
	assert_gt(client.verifications, 0, "%s: the client verified (%d)" % [label,
		client.verifications])
	assert_eq(client.desync_count, 0, "%s: no desync" % label)
	assert_eq(host.desync_count, 0, "%s: none on the host either" % label)
	gut.p("  %-18s frames=%d corrections=%d verifications=%d kills=%d/%d desync=%d" % [
		label, host_match.frame - start, client.corrections, client.verifications,
		host_match.kills[0], host_match.kills[1], client.desync_count])
	host.shutdown()
	client.shutdown()
	host_match.get_parent().free()
	client_match.get_parent().free()


## Steps `id` to `at` on a seeded input stream, snapshots, steps `span` frames
## recording every state, rewinds, replays, and compares. `acted` says whether
## the gimmick did something inside the window, so a window that missed it
## proves nothing and fails. With `on_stones`, seat 0 is stood on a slab
## whole until then, just before the snapshot; both stand still throughout, so
## no thrown sword cuts the one standing on it down before it goes, and
## the slab lights, burns and drops inside the window.
func _rewind(id: String, at: int, span: int, acted: Callable, on_stones: bool = false) -> void:
	var strip := DuelStrips.open(id)
	var fight := Support.spawn_match(get_tree().root, strip)
	var stream := Support.input_stream(at + span, 77)
	for f: int in at:
		fight.step(0 if on_stones else stream[f].x, 0 if on_stones else stream[f].y)
	if on_stones:
		for i: int in strip.hazards.stone_count():
			var cell: Vector2i = strip.hazards.stones[i]
			var inside := fight.window_rect().grow(-32.0).has_point(Vector2(cell * 16))
			if StripHazards.is_whole(fight.stones[i]) and inside:
				fight.seats[0].respawn_at(Vector2(cell.x * 16.0 + 8.0, cell.y * 16.0), 1)
				fight.set_meta(&"stood", i)
				break
	assert_false(acted.call(fight, at, at), "%s: the gimmick had not yet acted" % id)
	var snapshot := fight.write_state()
	var first: Array[PackedByteArray] = []
	var sums := PackedInt64Array()
	for f: int in range(at, at + span):
		fight.step(0 if on_stones else stream[f].x, 0 if on_stones else stream[f].y)
		first.append(fight.write_state())
		sums.append(fight.checksum())
	assert_true(acted.call(fight, at, at + span), "%s: the gimmick acted in the window" % id)
	assert_true(fight.read_state(snapshot), "%s: the snapshot reads back" % id)
	var differ := 0
	for f: int in range(at, at + span):
		fight.step(0 if on_stones else stream[f].x, 0 if on_stones else stream[f].y)
		if fight.write_state() != first[f - at] or fight.checksum() != sums[f - at]:
			differ += 1
	assert_eq(differ, 0, "%s: %d frames replayed byte for byte" % [id, span])
	fight.free()


func _skip_countdown(fight: DuelMatch) -> void:
	while fight.phase == DuelMatch.Phase.COUNTDOWN:
		fight.step(0, 0)


## A match in a physics world of its own: one device. Free it with its world,
## `fight.get_parent().free()`.
func _open_match(strip: ZoneStrip, label: String) -> DuelMatch:
	var device := SubViewport.new()
	device.name = label + "Device"
	device.world_2d = World2D.new()
	add_child(device)
	var fight := DuelMatch.new()
	fight.name = label
	fight.fighter_scene = FIGHTER_SCENE
	device.add_child(fight)
	assert_true(fight.build(strip), "%s match builds on %s" % [label, strip.id])
	return fight


## tests/match_net_test.gd's closing duellist: noise on every button but the
## direction, which closes. A hash of the frame and the seat, never a running
## generator, so the session may ask for a frame twice.
func _bot(fight: DuelMatch, seat: int, seed_value: int) -> Callable:
	var chance := PlayerInput.BIT_UP | PlayerInput.BIT_DOWN | PlayerInput.BIT_JUMP \
		| PlayerInput.BIT_ATTACK | PlayerInput.BIT_THROW
	return func() -> int:
		var me := fight.fighter_position(seat)
		var them := fight.fighter_position(1 - seat)
		var bits := hash(Vector3i(fight.frame, seat, seed_value)) & chance
		if fight.frame % 7 != 0:
			bits &= ~PlayerInput.BIT_THROW
		if absf(them.x - me.x) > 6.0:
			bits |= PlayerInput.BIT_RIGHT if them.x > me.x else PlayerInput.BIT_LEFT
		return bits
