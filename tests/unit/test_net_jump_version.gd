extends GutTest
## Protocol 5: the duel's jump forgives what a thumb does -- a press up to seven
## frames early is kept, one up to six frames past an edge still jumps, and a
## tap rises four frames before letting go can cut it (scripts/duel/fighter.gd,
## DuelTuning's jump windows; docs/duel-combat.md, "The jump"). No message
## changed shape, and the fighter's block is the same 100 bytes, so a
## version-4 build would decode every message and step the same inputs into a
## different arc: it has to be refused in the lobby, not found out by the
## desync detector in the second zone (scripts/net/protocol.gd, VERSION).
##
## Seen to fail with VERSION left at 4: the first test, and every version-4
## message below decoding as if it were current.

const POLLS := 60


func test_the_jump_is_protocol_five() -> void:
	assert_eq(NetProtocol.VERSION, 5, "the jump's forgiveness bumped the protocol to 5")
	assert_eq(Fighter.state_bytes(), 100, "in the same 100-byte fighter block")


## Every message a version-4 peer sends is refused, and says which version.
func test_every_version_four_message_is_refused() -> void:
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
		bytes[0] = 4
		var back := NetProtocol.decode(bytes)
		assert_true(back.has("error"), "a protocol-4 %s is refused" % name)
		assert_eq(int(back.get("version", -1)), 4, "and reports version 4")


## A host of this build hearing a version-4 guest stops and says it is a
## different build.
func test_a_version_four_guest_is_told_it_is_a_different_build() -> void:
	var host := DuelMatch.new()
	add_child_autofree(host)
	assert_true(host.build(DuelStrips.open(DuelStrips.TUG)), "the host's match builds")
	var ends := LoopbackTransport.pair(5)
	var session := NetSession.new()
	session.start(ends[0], host, true)
	var hello := NetProtocol.hello(NetProtocol.VERSION, "old")
	hello[0] = 4
	ends[1].send(hello)
	for i: int in POLLS:
		session.poll()
		ends[1].poll()
		if session.stage == NetSession.Stage.ENDED:
			break
	assert_eq(session.stage, NetSession.Stage.ENDED, "the host does not seat it")
	assert_string_contains(session.status_detail, "protocol 4, ours 5", "and says why")
	session.shutdown()
