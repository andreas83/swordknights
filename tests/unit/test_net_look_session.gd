extends GutTest
## The looks crossing a real NetSession handshake (scripts/net/session.gd),
## over a loopback pair, against a stand-in duel.
##
## The handshake is all that is driven here, so the duel is a stub: the looks
## must arrive before anyone is seated, and they must arrive whatever the other
## side is -- this build, a peer of this version that sends none, or one sending a
## look that will not read, which must not stall the handshake it rides on.
## That the looks leave the simulation alone is tests/match_net_test.gd's
## question, asked with the real match: two different looks, no desync.

## Steps a frame counter and nothing else, so a session that reaches RUNNING
## and polls on does not trip DuelSim's abstract methods.
class StubSim:
	extends DuelSim

	func step(_bits_a: int, _bits_b: int) -> void:
		frame += 1

	func write_state() -> PackedByteArray:
		var bytes := PackedByteArray()
		bytes.resize(4)
		bytes.encode_u32(0, frame)
		return bytes

	func read_state(bytes: PackedByteArray) -> bool:
		if bytes.size() < 4:
			return false
		frame = bytes.decode_u32(0)
		return true

	func checksum() -> int:
		return frame

	func reset_match() -> void:
		frame = 0


const POLLS := 20

## The literal bytes a guest that sends no look says hello with; see
## tests/unit/test_net_look_wire.gd for how they are spelled.
const V1_HELLO := [NetProtocol.VERSION, 1, 1, 0, 0, 0, 1, 0x78]
## And a lookless host's welcome: seat 1, a match length of 1, arena hash 0,
## which is what StubSim answers to, and no strip named: a zero length byte,
## the field protocol 3 added (scripts/net/protocol.gd).
const V1_WELCOME := [NetProtocol.VERSION, 2, 1, 1, 0, 0, 0, 0, 0]
## A build from before the sword catch: protocol 1.
const PRE_CATCH_HELLO := [1, 1, 1, 0, 0, 0, 1, 0x78]

var _host_look := {"figure": "heroine", "outfit": "saffron", "accent": "pale",
	"hair": "gold", "skin": "sand"}
var _guest_look := {"figure": "prince", "outfit": "wine", "accent": "ink",
	"hair": "raven", "skin": "umber"}


func _sim() -> StubSim:
	var sim := StubSim.new()
	autofree(sim)
	return sim


func _session(look: Dictionary) -> NetSession:
	var session := NetSession.new()
	session.local_look = look
	return session


func _poll(sessions: Array, ends: Array) -> void:
	for i: int in POLLS:
		for session: NetSession in sessions:
			session.poll()
		for end: LoopbackTransport in ends:
			end.poll()


## Everything one raw end of the pair was sent, decoded.
func _record(end: LoopbackTransport) -> Array[Dictionary]:
	var heard: Array[Dictionary] = []
	end.received.connect(func(bytes: PackedByteArray) -> void:
		heard.append(NetProtocol.decode(bytes)))
	return heard


func test_each_side_gets_the_others_look_before_it_is_seated() -> void:
	var ends := LoopbackTransport.pair()
	var host := _session(_host_look)
	var guest := _session(_guest_look)
	var seen_when_seated := [null, null]
	host.handshake_complete.connect(
		func(_slot: int) -> void: seen_when_seated[0] = host.remote_look.duplicate())
	guest.handshake_complete.connect(
		func(_slot: int) -> void: seen_when_seated[1] = guest.remote_look.duplicate())
	host.start(ends[0], _sim(), true)
	guest.start(ends[1], _sim(), false)
	_poll([host, guest], [])

	assert_true(host.is_running() and guest.is_running(), "both seated")
	assert_eq(seen_when_seated[0], _guest_look, "the host had the guest's look when seated")
	assert_eq(seen_when_seated[1], _host_look, "the guest had the host's look when seated")
	assert_eq(host.remote_look_error, "", "and neither look was refused")
	assert_eq(guest.remote_look_error, "", "on either side")
	host.shutdown()
	guest.shutdown()


func test_a_lookless_guest_is_seated_and_shown_as_the_default() -> void:
	var ends := LoopbackTransport.pair()
	var old_guest: LoopbackTransport = ends[1]
	var heard := _record(old_guest)
	var host := _session(_host_look)
	host.start(ends[0], _sim(), true)
	old_guest.send(PackedByteArray(V1_HELLO))
	_poll([host], [old_guest])

	assert_true(host.is_running(), "the host seats a guest that sent no look")
	assert_eq(host.remote_look, {}, "and has no look for it")
	assert_eq(host.remote_look_error, "", "which is not an error")
	assert_true(CharacterLook.from_ids(host.remote_look).equals(CharacterLook.new()),
		"so it shows the default")

	var welcomes := heard.filter(
		func(m: Dictionary) -> bool: return m.get("type") == NetProtocol.Type.WELCOME)
	assert_gt(welcomes.size(), 0, "the lookless guest was welcomed")
	host.shutdown()


func test_a_lookless_host_seats_the_guest_and_is_shown_as_the_default() -> void:
	var ends := LoopbackTransport.pair()
	var old_host: LoopbackTransport = ends[0]
	var heard := _record(old_host)
	var guest := _session(_guest_look)
	guest.start(ends[1], _sim(), false)
	old_host.poll()
	var hellos := heard.filter(
		func(m: Dictionary) -> bool: return m.get("type") == NetProtocol.Type.HELLO)
	assert_gt(hellos.size(), 0, "the guest said hello")
	old_host.send(PackedByteArray(V1_WELCOME))
	_poll([guest], [old_host])

	assert_true(guest.is_running(), "the guest plays on against a host that sent no look")
	assert_eq(guest.local_slot, 1, "in the seat it was given")
	assert_eq(guest.remote_look, {}, "and draws the host as the default")
	guest.shutdown()


## A protocol-1 guest would step an empty hand's THROW differently. The host
## must refuse it in the lobby rather than seat it and desync later.
func test_a_guest_from_before_the_catch_is_refused() -> void:
	var ends := LoopbackTransport.pair()
	var old_guest: LoopbackTransport = ends[1]
	var host := _session(_host_look)
	host.start(ends[0], _sim(), true)
	old_guest.send(PackedByteArray(PRE_CATCH_HELLO))
	_poll([host], [old_guest])
	assert_false(host.is_running(), "the host does not seat a protocol-1 guest")
	assert_string_contains(host.status_detail, "different build")
	host.shutdown()


func test_a_look_that_will_not_read_does_not_stall_the_handshake() -> void:
	var ends := LoopbackTransport.pair()
	var rogue: LoopbackTransport = ends[1]
	var host := _session(_host_look)
	host.start(ends[0], _sim(), true)
	var hello := PackedByteArray(V1_HELLO)
	# A look block that claims 200 fields and then stops.
	hello.append_array(PackedByteArray([NetProtocol.LOOK_FORMAT, 200, 0, 7]))
	rogue.send(hello)
	_poll([host], [rogue])

	assert_true(host.is_running(), "the guest is seated anyway")
	assert_eq(host.remote_look, {}, "in the default look")
	assert_ne(host.remote_look_error, "", "and the reason is kept for the log")
	host.shutdown()


func test_a_repeated_hello_cannot_change_a_look_once_seated() -> void:
	var ends := LoopbackTransport.pair()
	var guest_end: LoopbackTransport = ends[1]
	var host := _session(_host_look)
	host.start(ends[0], _sim(), true)
	guest_end.send(NetProtocol.hello(NetProtocol.VERSION, "x", _guest_look))
	_poll([host], [guest_end])
	assert_eq(host.remote_look, _guest_look, "the first HELLO's look is taken")

	guest_end.send(NetProtocol.hello(NetProtocol.VERSION, "x", _host_look))
	_poll([host], [guest_end])
	assert_eq(host.remote_look, _guest_look, "a later one changes nothing")
	host.shutdown()
