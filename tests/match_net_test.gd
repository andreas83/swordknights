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
## AND WHAT THE CLIENT'S SCREEN IS TOLD
## A client steps every frame on its guess and then steps it again, often
## twice, when the host corrects it. The screen must hear of each thing that
## happened once, not once per pass. So each scenario also watches the
## client's presentation, as the scene would, and asks:
##   - no frame is stepped twice outside NetSession's replay bracket (the
##     session's half: every re-stepped frame is marked as one);
##   - every death the host had rang exactly one beat on the client, and no
##     beat rang twice for one death (the whole of it: beats once per kill);
##   - the client's floor ends up with blood for exactly the host's deaths, at
##     the host's frame and place (the record follows the corrected history);
##   - and the host, which never replays, retracts nothing.
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
const HOST_LOOK := {"figure": "heroine", "outfit": "saffron", "accent": "pale",
	"hair": "gold", "skin": "copper"}
const CLIENT_LOOK := {"figure": "prince", "outfit": "wine", "accent": "ink",
	"hair": "raven", "skin": "umber"}

var _s := Support.new()
var _strip: ZoneStrip
var _warm := 0


## The real match, with a note of every frame it was asked to step outside a
## replay. A frame stepped there twice is a frame whose presentation rang twice.
class WatchedMatch:
	extends DuelMatch

	var fresh := {} # frame -> times stepped outside a replay

	func step(bits_a: int, bits_b: int) -> void:
		if not replaying:
			fresh[frame] = int(fresh.get(frame, 0)) + 1
		super.step(bits_a, bits_b)

	func stepped_twice() -> int:
		var twice := 0
		for at: int in fresh.keys():
			if int(fresh[at]) > 1:
				twice += 1
		return twice


## Listens to one match as the scene does: the beats, and the blood.
class Witness:
	extends RefCounted

	var fight: DuelMatch
	## {victim, frame}: each beat, and the match frame it rang on.
	var beats: Array[Dictionary] = []
	## Vector2i(death frame, victim) -> where: the blood on the floor now.
	var blood := {}
	var retractions := 0
	## Retractions that were half of a move: put straight back down elsewhere.
	var moves := 0
	var _just_taken := Vector2i(-1, -1) # (match frame, victim) of the last one

	func _init(watched: DuelMatch) -> void:
		fight = watched
		fight.fighter_died.connect(func(victim: int, _k: int, _at: Vector2) -> void:
			beats.append({"victim": victim, "frame": fight.frame}))
		fight.death_recorded.connect(func(victim: int, at: Vector2, frame: int) -> void:
			if _just_taken == Vector2i(fight.frame, victim):
				moves += 1
			_just_taken = Vector2i(-1, -1)
			blood[Vector2i(frame, victim)] = at)
		fight.death_retracted.connect(func(victim: int, frame: int) -> void:
			retractions += 1
			_just_taken = Vector2i(fight.frame, victim)
			blood.erase(Vector2i(frame, victim)))

	## Deaths told and then taken back for good: a kill the prediction showed
	## and the host never had.
	func phantoms() -> int:
		return retractions - moves

	## The blood of deaths up to `last`, as sorted [key, place] pairs.
	func floor_until(last: int) -> Array:
		var out := []
		var keys := blood.keys()
		keys.sort()
		for key: Vector2i in keys:
			if key.x <= last:
				out.append([key, blood[key]])
		return out


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
	var host_saw := Witness.new(host_match)
	var client_saw := Witness.new(client_match)

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
	# Two different looks, as two phones send. They are presentation and must
	# change nothing below: the same zero desyncs, with them crossing.
	host.local_look = HOST_LOOK
	client.local_look = CLIENT_LOOK
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
	_s.equal(host.remote_look, CLIENT_LOOK, "%s: the host has the client's look" % label)
	_s.equal(client.remote_look, HOST_LOOK, "%s: the client has the host's look" % label)
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
	_presentation(label, host_match, client_match, host_saw, client_saw, client)
	_close([host, client], [host_match, client_match])


## The client's screen against the host's history. See the docstring.
func _presentation(label: String, host_match: WatchedMatch, client_match: WatchedMatch,
		host_saw: Witness, client_saw: Witness, client: NetSession) -> void:
	_s.equal(client_match.stepped_twice(), 0,
		"%s: no frame was stepped twice outside a replay (%d stepped fresh)"
			% [label, client_match.fresh.size()])
	_s.equal(host_match.stepped_twice(), 0, "%s: nor on the host" % label)
	_s.equal(host_saw.retractions, 0, "%s: the host retracts nothing" % label)

	# Deaths the client has had every chance to settle: older than the newest
	# snapshot by more than the ledger waits before it retracts.
	var settled := client_match.frame - client.predicted_ahead - MatchLedger.SAME_BEAT - 1
	var real := host_saw.floor_until(settled)
	_s.check(real.size() > 0, "%s: the host had deaths to compare (%d)" % [label, real.size()])
	_s.equal(client_saw.floor_until(settled), real,
		"%s: the client's blood is the host's deaths, frame and place" % label)

	for death: Array in real:
		var key: Vector2i = death[0]
		var rang := 0
		for beat: Dictionary in client_saw.beats:
			var after := int(beat["frame"]) - key.x
			if int(beat["victim"]) == key.y and after >= -MatchLedger.SAME_BEAT \
					and after <= 2 * MatchLedger.SAME_BEAT:
				rang += 1
		_s.equal(rang, 1, "%s: seat %d's death on frame %d rang once on the client"
			% [label, key.y, key.x])
	var echoes := 0
	for i: int in client_saw.beats.size():
		for j: int in range(i + 1, client_saw.beats.size()):
			var a: Dictionary = client_saw.beats[i]
			var b: Dictionary = client_saw.beats[j]
			if a["victim"] == b["victim"] \
					and absi(int(b["frame"]) - int(a["frame"])) <= MatchLedger.SAME_BEAT:
				echoes += 1
	_s.equal(echoes, 0, "%s: no death rang twice on the client" % label)
	# And every beat is accounted for: a host death the client has, a predicted
	# death since taken back for good, or one still on the client's floor that
	# the host has not ruled on yet. Nothing rang that is in none of those.
	var shared := 0
	var unconfirmed := 0
	for key: Vector2i in client_saw.blood.keys():
		if host_saw.blood.has(key):
			shared += 1
		else:
			unconfirmed += 1
	_s.equal(client_saw.beats.size(), shared + client_saw.phantoms() + unconfirmed,
		"%s: beats = %d shared deaths + %d taken back + %d unconfirmed" % [
			label, shared, client_saw.phantoms(), unconfirmed])
	print("  %-6s beats=%d host deaths=%d taken back=%d moved=%d fresh frames=%d" % [
		label, client_saw.beats.size(), host_saw.blood.size(), client_saw.phantoms(),
		client_saw.moves, client_match.fresh.size(),
	])


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


func _open_match(label: String) -> WatchedMatch:
	var fight := WatchedMatch.new()
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
