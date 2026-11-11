extends GutTest
## Protocol 4: the duel's rules changed under every message -- down standing
## still guards LOW, WALK shuffles and ducks, a roll ends in recovery, a kick's
## knockdown is short, a double kill keeps the initiative, a passed fighter is
## put back ahead, a duel is a best of three -- and the match header grew by
## the trailing-edge counters and the series.
## A version-3 build would step the same inputs into another match, so the two
## must refuse each other in the lobby rather than desync in the second zone
## (scripts/net/protocol.gd, VERSION).
##
## Seen to fail with VERSION left at 3: the first test, and every version-3
## message below decoding as if it were current. Protocol 5 (the jump's
## forgiveness) kept every refusal here and has its own pin,
## tests/unit/test_net_jump_version.gd.

const POLLS := 60


func test_duel_fairness_is_protocol_four() -> void:
	assert_gte(NetProtocol.VERSION, 4, "duel fairness bumped the protocol to 4, or past it")
	assert_eq(DuelMatch.HEADER_BYTES, 52, "and the match header to 52 bytes")


## Every message a version-3 peer sends -- HELLO, WELCOME, INPUT, SNAPSHOT --
## is refused, and says which version it was, so the lobby can say so.
func test_every_version_three_message_is_refused() -> void:
	var messages := {
		"HELLO": NetProtocol.hello(NetProtocol.VERSION, "x"),
		"WELCOME": NetProtocol.welcome(1, 5, 7, {}, "tug"),
		"INPUT": NetProtocol.input_window(10, PackedByteArray([1, 2, 3])),
		"SNAPSHOT": NetProtocol.snapshot(10, 99, PackedByteArray([0, 0, 0, 0]),
			[Vector2i(1, 2)] as Array[Vector2i]),
	}
	for name: String in messages:
		var bytes: PackedByteArray = messages[name]
		assert_false(NetProtocol.decode(bytes).has("error"), "a current %s decodes" % name)
		bytes[0] = 3
		var back := NetProtocol.decode(bytes)
		assert_true(back.has("error"), "a protocol-3 %s is refused" % name)
		assert_eq(int(back.get("version", -1)), 3, "and reports version 3")


## A host of this build hearing a version-3 guest stops, and the reason it gives
## is the build, not a silence.
func test_a_version_three_guest_is_told_it_is_a_different_build() -> void:
	var host := DuelMatch.new()
	add_child_autofree(host)
	assert_true(host.build(DuelStrips.open(DuelStrips.TUG)), "the host's match builds")
	var ends := LoopbackTransport.pair(5)
	var session := NetSession.new()
	session.start(ends[0], host, true)
	var hello := NetProtocol.hello(NetProtocol.VERSION, "old")
	hello[0] = 3
	ends[1].send(hello)
	for i: int in POLLS:
		session.poll()
		ends[1].poll()
		if session.stage == NetSession.Stage.ENDED:
			break
	assert_eq(session.stage, NetSession.Stage.ENDED, "the host does not seat it")
	assert_string_contains(session.status_detail,
		"protocol 3, ours %d" % NetProtocol.VERSION, "and says why")
	session.shutdown()
