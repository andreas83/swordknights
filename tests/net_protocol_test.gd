extends SceneTree
## The wire format: every message round-trips, and nothing malformed gets through.
##
##     godot --headless --script tests/net_protocol_test.gd
##
## The second half matters as much as the first. A relay is a public endpoint
## and a decoder that reads past the end of a buffer is a crash someone else
## gets to trigger, so `decode` is fed every truncation of every message and
## has to answer "error" to all of them rather than returning nonsense.

const Support := preload("res://tests/duel_support.gd")

var _s := Support.new()


func _initialize() -> void:
	_messages_round_trip()
	_truncation_is_always_an_error()
	_a_different_protocol_version_is_refused()
	_unknown_types_and_runts_are_refused()
	_room_codes_are_unambiguous()
	_the_arena_hash_identifies_the_arena()

	quit(_s.report("net_protocol"))


## --- cases ------------------------------------------------------------------

func _messages_round_trip() -> void:
	var state := PackedByteArray()
	for i: int in 200:
		state.append(i & 0xff)
	var pairs: Array[Vector2i] = [Vector2i(0x11, 0x22), Vector2i(0xff, 0x00)]

	var hello := _decoded(NetProtocol.hello(7, "challenger"))
	_s.equal(hello.get("type"), NetProtocol.Type.HELLO, "HELLO decodes as HELLO")
	_s.equal(hello.get("build"), 7, "HELLO carries the build")
	_s.equal(hello.get("name"), "challenger", "HELLO carries the name")

	var welcome := _decoded(NetProtocol.welcome(1, 3, 0xdeadbeef))
	_s.equal(welcome.get("slot"), 1, "WELCOME carries the seat")
	_s.equal(welcome.get("rounds_to_win"), 3, "WELCOME carries the round target")
	_s.equal(welcome.get("arena_hash"), 0xdeadbeef, "WELCOME carries the arena hash")

	var input := _decoded(
		NetProtocol.input_window(1000, PackedByteArray([1, 2, 3, 255, 0]))
	)
	_s.equal(input.get("first_frame"), 1000, "INPUT carries the first frame")
	_s.equal(
		Array(input.get("bits") as PackedByteArray), [1, 2, 3, 255, 0],
		"INPUT carries every byte of the window"
	)

	var snapshot := _decoded(
		NetProtocol.snapshot(4242, 0xfeedface, state, pairs)
	)
	_s.equal(snapshot.get("frame"), 4242, "SNAPSHOT carries the frame")
	_s.equal(snapshot.get("checksum"), 0xfeedface, "SNAPSHOT carries the checksum")
	_s.equal(snapshot.get("pairs"), pairs, "SNAPSHOT carries the input history")
	_s.equal(snapshot.get("state"), state, "SNAPSHOT carries the state unchanged")

	# A checksum is a full 32 bits unsigned; it must not come back negative.
	var top := _decoded(NetProtocol.snapshot(1, 0xffffffff, state, []))
	_s.equal(top.get("checksum"), 0xffffffff, "a checksum with the top bit set survives")

	var ping := _decoded(NetProtocol.ping(9, 123456789012))
	_s.equal(ping.get("id"), 9, "PING carries the id")
	_s.equal(ping.get("sent_usec"), 123456789012, "PING carries the send time")
	var pong := _decoded(NetProtocol.pong(9, 123456789012))
	_s.equal(pong.get("type"), NetProtocol.Type.PONG, "PONG decodes as PONG")

	var bye := _decoded(NetProtocol.bye(NetProtocol.Bye.VERSION_MISMATCH))
	_s.equal(bye.get("reason"), NetProtocol.Bye.VERSION_MISMATCH, "BYE carries the reason")

	var desync := _decoded(NetProtocol.desync(77, 0xaabbccdd, 0x11223344))
	_s.equal(desync.get("frame"), 77, "DESYNC carries the frame")
	_s.equal(desync.get("mine"), 0xaabbccdd, "DESYNC carries our checksum")
	_s.equal(desync.get("theirs"), 0x11223344, "DESYNC carries theirs")

	_s.equal(
		_decoded(NetProtocol.room_open()).get("type"), NetProtocol.Type.ROOM_OPEN,
		"ROOM_OPEN decodes"
	)
	_s.equal(_decoded(NetProtocol.room_join("ab2x")).get("code"), "AB2X",
		"ROOM_JOIN upper-cases the code")
	var ok := _decoded(NetProtocol.room_ok("WXYZ", true))
	_s.equal(ok.get("code"), "WXYZ", "ROOM_OK carries the code")
	_s.equal(ok.get("as_host"), true, "ROOM_OK carries the seat")
	_s.equal(_decoded(NetProtocol.room_ok("WXYZ", false)).get("as_host"), false,
		"ROOM_OK carries the guest seat too")
	var room_error := _decoded(
		NetProtocol.room_error(NetProtocol.RoomError.ROOM_FULL, "room QRST is full")
	)
	_s.equal(room_error.get("code"), NetProtocol.RoomError.ROOM_FULL,
		"ROOM_ERROR carries the code")
	_s.equal(room_error.get("message"), "room QRST is full",
		"ROOM_ERROR carries the message")
	_s.equal(_decoded(NetProtocol.room_peer(true)).get("present"), true,
		"ROOM_PEER carries presence")


## Every message, cut off at every possible length, must decode as an error and
## must not read past the end of the buffer.
func _truncation_is_always_an_error() -> void:
	var state := PackedByteArray()
	for i: int in 64:
		state.append(i)
	var whole: Array[PackedByteArray] = [
		NetProtocol.hello(1, "someone"),
		NetProtocol.welcome(0, 3, 12345),
		NetProtocol.input_window(10, PackedByteArray([1, 2, 3])),
		NetProtocol.snapshot(10, 999, state, [Vector2i(1, 2), Vector2i(3, 4)]),
		NetProtocol.ping(1, 2),
		NetProtocol.pong(1, 2),
		NetProtocol.bye(NetProtocol.Bye.QUIT),
		NetProtocol.desync(1, 2, 3),
		NetProtocol.room_join("AB2X"),
		NetProtocol.room_ok("AB2X", true),
		NetProtocol.room_error(NetProtocol.RoomError.BAD_CODE, "no"),
		NetProtocol.room_peer(false),
	]

	var leaked := 0
	for message: PackedByteArray in whole:
		for cut: int in range(0, message.size()):
			var decoded := NetProtocol.decode(message.slice(0, cut))
			if not decoded.has("error"):
				leaked += 1
	_s.equal(leaked, 0, "no truncation of any message decodes as valid")

	# And the whole message still does, so the loop above was not vacuous.
	var intact := 0
	for message: PackedByteArray in whole:
		if not NetProtocol.decode(message).has("error"):
			intact += 1
	_s.equal(intact, whole.size(), "every intact message still decodes")


func _a_different_protocol_version_is_refused() -> void:
	var message := NetProtocol.hello(1, "x")
	message[0] = NetProtocol.VERSION + 1
	var decoded := NetProtocol.decode(message)
	_s.check(decoded.has("error"), "a future protocol version is refused")
	_s.equal(decoded.get("version"), NetProtocol.VERSION + 1,
		"and reports the version it saw, so the lobby can say so")


func _unknown_types_and_runts_are_refused() -> void:
	_s.check(NetProtocol.decode(PackedByteArray()).has("error"), "no bytes is an error")
	_s.check(
		NetProtocol.decode(PackedByteArray([NetProtocol.VERSION])).has("error"),
		"a header with no type is an error"
	)
	_s.check(
		NetProtocol.decode(PackedByteArray([NetProtocol.VERSION, 200])).has("error"),
		"an unknown message type is an error"
	)
	# A seat number a duel does not have must not be accepted.
	var welcome := NetProtocol.welcome(7, 3, 1)
	_s.check(NetProtocol.decode(welcome).has("error"), "WELCOME naming seat 7 is refused")


func _room_codes_are_unambiguous() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var seen := {}
	for i: int in 500:
		var code := NetProtocol.make_room_code(rng)
		_s.check(NetProtocol.is_room_code(code), "generated code '%s' validates" % code)
		seen[code] = true
	_s.check(seen.size() > 400, "500 generated codes are mostly distinct")

	for bad: String in ["", "ABC", "ABCDE", "AB0X", "ABIX", "ABLX", "ab2x!", "AB X"]:
		_s.check(not NetProtocol.is_room_code(bad), "'%s' is not a room code" % bad)
	for ambiguous: String in ["O", "0", "I", "1", "L", "U", "V"]:
		_s.check(
			not NetProtocol.CODE_ALPHABET.contains(ambiguous),
			"'%s' is kept out of the alphabet — it gets misheard" % ambiguous
		)


func _the_arena_hash_identifies_the_arena() -> void:
	var arena := AsciiLevel.from_file("res://levels/zone_03.txt")
	var again := AsciiLevel.from_file("res://levels/zone_03.txt")
	_s.equal(
		NetProtocol.arena_hash(arena), NetProtocol.arena_hash(again),
		"the same level file hashes the same twice"
	)

	var other := AsciiLevel.new()
	other.parse("####\n#@ #\n####")
	_s.check(
		NetProtocol.arena_hash(arena) != NetProtocol.arena_hash(other),
		"a different arena hashes differently"
	)

	# One tile moved has to change the hash, or a mismatched level file would
	# sail past the handshake and show up as an unexplained desync.
	var nudged := AsciiLevel.new()
	nudged.parse("####\n#@# \n####")
	_s.check(
		NetProtocol.arena_hash(other) != NetProtocol.arena_hash(nudged),
		"moving a single tile changes the hash"
	)


func _decoded(bytes: PackedByteArray) -> Dictionary:
	var out := NetProtocol.decode(bytes)
	_s.check(not out.has("error"), "decoding %d bytes: %s" % [
		bytes.size(), out.get("error", "ok")])
	return out
