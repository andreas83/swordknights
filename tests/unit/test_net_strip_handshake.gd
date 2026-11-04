extends GutTest
## The host chooses the strip; the guest loads it, or says in the lobby why it
## cannot. The wire half (protocol version 3 and on, the strip's name on WELCOME, a
## name that is not a name refused) and the session half (a guest on another
## strip switched to the host's, a guest without it refused with the strip
## named, and the host told why rather than that the guest left).
##
## On the placeholder fighter: nothing here steps a body, and a match on it
## builds without a physics space. Each refusal below was seen to pass a guest
## through with its own strip before the WELCOME carried the host's.

const POLLS := 120


func test_welcome_carries_the_strip_by_name() -> void:
	assert_gte(NetProtocol.VERSION, 3, "the strips are protocol 3, and every one since")
	var bytes := NetProtocol.welcome(1, 5, 0x1234abcd, {"figure": "heroine"}, "well")
	var back := NetProtocol.decode(bytes)
	assert_false(back.has("error"), "it decodes: %s" % back.get("error", ""))
	assert_eq(String(back["arena_id"]), "well", "the strip's name")
	assert_eq(int(back["arena_hash"]), 0x1234abcd, "and its hash")
	assert_eq((back["look"] as Dictionary).get("figure"), "heroine", "and the look after it")
	var none := NetProtocol.decode(NetProtocol.welcome(1, 5, 7))
	assert_eq(String(none["arena_id"]), "", "a duel with one arena names none")
	var junk := NetProtocol.welcome(1, 5, 7, {}, "Not A Name!")
	assert_eq(String(NetProtocol.decode(junk)["arena_id"]), "",
		"a name that is not an id is sent as none, not sent to be refused")


func test_a_welcome_from_before_the_strips_is_refused_by_its_version() -> void:
	var bytes := NetProtocol.welcome(1, 5, 7, {}, "well")
	bytes[0] = 2
	var back := NetProtocol.decode(bytes)
	assert_true(back.has("error"), "a protocol-2 WELCOME is not read")
	assert_eq(int(back.get("version", -1)), 2, "and the session is told which version")


func test_a_strip_name_that_is_not_a_name_fails_the_message() -> void:
	var bytes := NetProtocol.welcome(1, 5, 7, {}, "well")
	# The name's bytes start after slot, length and hash: [ver, type, 1, 5, 4 x hash].
	bytes[9] = 0x57 # 'W', not lower case
	assert_string_contains(String(NetProtocol.decode(bytes).get("error", "")), "not a name")
	for cut: int in range(2, 12):
		var short := NetProtocol.welcome(1, 5, 7, {}, "aqueduct").slice(0, cut)
		assert_true(NetProtocol.decode(short).has("error"), "cut at %d is refused" % cut)


func test_the_guest_loads_the_strip_the_host_chose() -> void:
	var host := _match("well")
	var guest := _match(DuelStrips.TUG)
	var sessions := _seat(host, guest)
	assert_eq(sessions[1].stage, NetSession.Stage.RUNNING, "the guest is seated")
	assert_eq(guest.strip.id, "well", "on the host's strip")
	assert_eq(guest.arena_identity(), host.arena_identity(), "with the host's hash")
	_close(sessions, [host, guest])


func test_a_guest_without_the_strip_is_refused_and_the_host_told() -> void:
	var host := _match("well")
	var guest := _match(DuelStrips.TUG)
	guest.arena_switch = func(_id: String) -> bool: return false
	var sessions := _seat(host, guest)
	var guest_session: NetSession = sessions[1]
	var host_session: NetSession = sessions[0]
	assert_eq(guest_session.stage, NetSession.Stage.ENDED, "the guest is not seated")
	assert_string_contains(guest_session.status_detail, "CLOCKWORK WELL",
		"and the lobby names the strip")
	assert_eq(guest.strip.id, DuelStrips.TUG, "the guest's own strip is left as it was")
	assert_eq(host_session.stage, NetSession.Stage.ENDED, "the host stops waiting")
	assert_string_contains(host_session.status_detail, "cannot fight on this strip",
		"and says why, not that the guest left")
	_close(sessions, [host, guest])


func test_a_strip_of_the_right_name_and_the_wrong_beat_is_refused() -> void:
	var host := _match("well")
	var guest := _match(DuelStrips.TUG)
	var switch := guest.arena_switch
	guest.arena_switch = func(id: String) -> bool:
		var ok: bool = switch.call(id)
		guest.strip.hazards.blades[0]["phase"] = 25
		return ok
	var sessions := _seat(host, guest)
	assert_eq((sessions[1] as NetSession).stage, NetSession.Stage.ENDED, "refused")
	assert_string_contains((sessions[1] as NetSession).status_detail, "same arena",
		"by the hash, after the switch")
	_close(sessions, [host, guest])


## A match on the placeholder fighter on strip `id`, switchable the way the
## scene switches it: built again on the strip named.
func _match(id: String) -> DuelMatch:
	var fight := DuelMatch.new()
	add_child_autofree(fight)
	assert_true(fight.build(DuelStrips.open(id)), "%s builds" % id)
	fight.arena_switch = func(named: String) -> bool:
		var next := DuelStrips.open(named)
		return next != null and fight.build(next)
	return fight


func _seat(host: DuelMatch, guest: DuelMatch) -> Array[NetSession]:
	var ends := LoopbackTransport.pair(11)
	var host_session := NetSession.new()
	var guest_session := NetSession.new()
	host_session.start(ends[0], host, true)
	guest_session.start(ends[1], guest, false)
	for i: int in POLLS:
		if guest_session.stage == NetSession.Stage.RUNNING:
			break
		host_session.poll()
		guest_session.poll()
	# The host hears the guest's refusal a poll or two after it is sent.
	for i: int in 4:
		host_session.poll()
	return [host_session, guest_session]


func _close(sessions: Array[NetSession], _matches: Array) -> void:
	for session: NetSession in sessions:
		session.shutdown()
