extends SceneTree
## The tug-of-war match, played between two real NetSessions.
##
## NetSession was built and tested against the round duel, since retired; the
## match is what the online duel runs. This puts a host session and a client session, each
## with its own DuelMatch on the real fighter, on the two ends of a loopback
## transport and plays random input for both seats -- with and without latency,
## jitter and dropped snapshots -- and asks the questions netplay rests on:
## does the client converge on the host every time it is told the truth, and
## does the detector stay quiet while it does.
##
## Unlike tests/net_desync_test.gd, the host here is live rather than recorded.
## Two matches can share a physics world because a fighter collides with the
## ground and never with another fighter, and both matches build the same
## ground in the same place.
##
##     godot --headless --path . --script res://tests/match_net_test.gd

const Support := preload("res://tests/duel_support.gd")
const MANIFEST := "res://levels/duel_zones.txt"
const FIGHTER_SCENE: PackedScene = preload("res://scenes/fighter.tscn")

## Polls of both sessions per scenario: twenty seconds of a match, long enough
## that deaths happen under any of the three links, not only by luck.
const POLLS := 1200
## A handshake that has not completed after this many polls has failed.
const HANDSHAKE_POLLS := 240

var _s := Support.new()
var _strip: ZoneStrip
var _warm := 0


func _initialize() -> void:
	_strip = ZoneStrip.from_manifest(MANIFEST)


func _physics_process(_delta: float) -> bool:
	_warm += 1
	if _warm < 3:
		return false
	if not _s.check(_strip != null, "the strip loads"):
		quit(_s.report("match_net"))
		return true

	_scenario("clean", 0, 0, 0.0, 101)
	_scenario("laggy", 6, 2, 0.0, 202)
	_scenario("lossy", 3, 1, 0.15, 303)

	quit(_s.report("match_net"))
	return true


func _scenario(label: String, latency: int, jitter: int, loss: float, seed_value: int) -> void:
	var host_match := _open_match("Host")
	var client_match := _open_match("Client")
	if host_match == null or client_match == null:
		return

	var ends := LoopbackTransport.pair(seed_value)
	var host_end: LoopbackTransport = ends[0]
	var client_end: LoopbackTransport = ends[1]
	host_end.latency_frames = latency
	host_end.jitter_frames = jitter
	# Snapshots are what the host sends; dropping them is the loss that a
	# reconciling client has to survive.
	host_end.drop_rate = loss
	client_end.latency_frames = latency
	client_end.jitter_frames = jitter

	var host := NetSession.new()
	var client := NetSession.new()
	# The host sits in seat 0 and the client in seat 1; checked below.
	host.local_input = _bot(host_match, 0, seed_value)
	client.local_input = _bot(client_match, 1, seed_value)
	var seats := [-1, -1]
	host.handshake_complete.connect(func(slot: int) -> void: seats[0] = slot)
	client.handshake_complete.connect(func(slot: int) -> void: seats[1] = slot)
	host.start(host_end, host_match, true)
	client.start(client_end, client_match, false)

	var shaken := 0
	while shaken < HANDSHAKE_POLLS and not (
			host.stage == NetSession.Stage.RUNNING and client.stage == NetSession.Stage.RUNNING):
		host.poll()
		client.poll()
		shaken += 1
	if not _s.check(shaken < HANDSHAKE_POLLS, "%s: both sessions reach RUNNING" % label):
		_close([host, client], [host_match, client_match])
		return

	_s.equal(seats, [0, 1], "%s: the host is seat 0 and the client seat 1" % label)
	var start := host_match.frame
	for i: int in POLLS:
		host.poll()
		client.poll()

	_s.check(host_match.frame - start > POLLS * 9 / 10,
		"%s: the host kept stepping (%d frames)" % [label, host_match.frame - start])
	_s.check(client.verifications > 0,
		"%s: the client verified against the host (%d times)" % [label, client.verifications])
	_s.equal(client.desync_count, 0, "%s: no desync" % label)
	_s.check(host_match.kills[0] + host_match.kills[1] > 0,
		"%s: the play included deaths (%d, %d)" % [label, host_match.kills[0], host_match.kills[1]])
	print("  %-6s frames=%d corrections=%d verifications=%d kills=%d/%d desync=%d" % [
		label, host_match.frame - start, client.corrections, client.verifications,
		host_match.kills[0], host_match.kills[1], client.desync_count,
	])
	_close([host, client], [host_match, client_match])


## A crude duellist for one seat: always closing on the other fighter, with
## stance, jump, thrust and throw left to chance.
##
## Pure noise rarely brings two fighters together -- they walk past each other
## and face away -- and then nobody dies and the network path for death,
## respawn and initiative goes untested. The chance is a hash of the frame and
## the seat, not a random generator's running state, so whatever the session
## asks for a frame it is always given the same answer.
func _bot(fight: DuelMatch, seat: int, seed_value: int) -> Callable:
	var chance := PlayerInput.BIT_UP | PlayerInput.BIT_DOWN | PlayerInput.BIT_JUMP \
		| PlayerInput.BIT_ATTACK | PlayerInput.BIT_THROW
	return func() -> int:
		var me := fight.fighter_position(seat)
		var them := fight.fighter_position(1 - seat)
		var bits := hash(Vector3i(fight.frame, seat, seed_value)) & chance
		# A sword thrown every few frames would leave both of them unarmed for
		# the whole run; keep the throws rare.
		if fight.frame % 7 != 0:
			bits &= ~PlayerInput.BIT_THROW
		if absf(them.x - me.x) > 6.0:
			bits |= PlayerInput.BIT_RIGHT if them.x > me.x else PlayerInput.BIT_LEFT
		return bits


func _open_match(label: String) -> DuelMatch:
	var fight := DuelMatch.new()
	fight.name = label
	fight.fighter_scene = FIGHTER_SCENE
	root.add_child(fight)
	if not _s.check(fight.build(_strip), "%s match builds" % label):
		fight.free()
		return null
	return fight


func _close(sessions: Array, matches: Array) -> void:
	for session: NetSession in sessions:
		session.shutdown()
	for fight: DuelMatch in matches:
		fight.free()
