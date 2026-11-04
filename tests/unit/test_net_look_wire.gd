extends GutTest
## A player's look on the wire: the block HELLO and WELCOME may end with
## (scripts/net/protocol.gd, "a player's look").
##
## Three things are held here. Every look there is crosses intact. A HELLO
## and WELCOME that carry no look still read -- as the default -- and one with
## a look begins with exactly the lookless bytes. A build before the sword
## catch speaks protocol 1 and is refused outright (VERSION, protocol.gd).
## And nothing a peer can put in the block -- cut short, too long, too many
## fields, the wrong format, bytes that are not an id, plain noise -- fails the
## message it rides on, reaches past the buffer, or comes out as anything but
## known fields holding well-formed ids, with every other field the default.

const BUILD := 1
const NAME := "challenger"

## A lookless HELLO, written out by hand rather than by NetProtocol, so that
## the encoder changing shape cannot quietly change this too: the version, type
## HELLO, build 1 as a little-endian u32, then the name as one length byte and
## its bytes. This is what a peer that sends no look says.
const V1_HELLO_HEAD := [NetProtocol.VERSION, 1, 1, 0, 0, 0, 10]
## A lookless WELCOME: seat 1, five zones, arena hash 0x04030201, and no strip
## named -- one zero length byte, the field protocol 3 put before the look.
const V1_WELCOME := [NetProtocol.VERSION, 2, 1, 5, 1, 2, 3, 4, 0]
## What every build before the sword catch said hello with: protocol 1.
const PRE_CATCH_HELLO := [1, 1, 1, 0, 0, 0, 1, 0x78]


func _v1_hello() -> PackedByteArray:
	var bytes := PackedByteArray(V1_HELLO_HEAD)
	bytes.append_array(NAME.to_ascii_buffer())
	return bytes


## Every combination of every option: 2 x 4 x 4 x 4 x 4.
func _every_look() -> Array[CharacterLook]:
	var looks: Array[CharacterLook] = [CharacterLook.new()]
	for field: String in CharacterLook.FIELDS:
		var grown: Array[CharacterLook] = []
		for base: CharacterLook in looks:
			for i: int in CharacterLook.options(field).size():
				var look := base.duplicate_look()
				look.set_index(field, i)
				grown.append(look)
		looks = grown
	return looks


func _chosen() -> CharacterLook:
	return CharacterLook.from_ids({"figure": "heroine", "outfit": "wine",
		"accent": "ink", "hair": "henna", "skin": "umber"})


## A HELLO with `block` as its look, bypassing the encoder, which would never
## write most of what these tests need to send.
func _hello_with(block: Array) -> Dictionary:
	var bytes := _v1_hello()
	bytes.append_array(PackedByteArray(block))
	return NetProtocol.decode(bytes)


## One field as the wire spells it: tag, length, bytes.
func _field(tag: int, id: String) -> Array:
	var out := [tag, id.length()]
	out.append_array(Array(id.to_ascii_buffer()))
	return out


## --- round trip -------------------------------------------------------------

func test_every_look_crosses_hello_and_welcome_intact() -> void:
	var looks := _every_look()
	assert_eq(looks.size(), 2 * 4 * 4 * 4 * 4, "walked every look")
	var lost: Array[String] = []
	for look: CharacterLook in looks:
		var hello := NetProtocol.decode(NetProtocol.hello(BUILD, NAME, look.to_ids()))
		var welcome := NetProtocol.decode(NetProtocol.welcome(1, 5, 77, look.to_ids()))
		for message: Dictionary in [hello, welcome]:
			if message.has("error") or message.has("look_error"):
				lost.append("%s: %s" % [look.to_ids(), message])
			elif not CharacterLook.from_ids(message["look"]).equals(look):
				lost.append("%s came back as %s" % [look.to_ids(), message["look"]])
	assert_eq(lost, [] as Array[String], "\n".join(lost.slice(0, 6)))


func test_the_rest_of_the_message_is_unchanged_by_a_look() -> void:
	var hello := NetProtocol.decode(NetProtocol.hello(BUILD, NAME, _chosen().to_ids()))
	assert_eq(hello.get("build"), BUILD, "HELLO keeps its build")
	assert_eq(hello.get("name"), NAME, "and its name")
	var welcome := NetProtocol.decode(
		NetProtocol.welcome(1, 5, 0xdeadbeef, _chosen().to_ids()))
	assert_eq(welcome.get("slot"), 1, "WELCOME keeps its seat")
	assert_eq(welcome.get("rounds_to_win"), 5, "its match length")
	assert_eq(welcome.get("arena_hash"), 0xdeadbeef, "and its arena")


func test_every_wardrobe_field_has_a_wire_tag() -> void:
	for field: String in CharacterLook.FIELDS:
		assert_has(NetProtocol.LOOK_TAGS, field, "%s can be sent" % field)


func test_a_look_is_tens_of_bytes() -> void:
	var widest := 0
	for look: CharacterLook in _every_look():
		var bytes := NetProtocol.hello(BUILD, NAME, look.to_ids())
		widest = maxi(widest, bytes.size() - _v1_hello().size())
	assert_gt(widest, 0, "a look adds bytes at all")
	assert_lt(widest, 64, "the longest look is %d bytes, sent once" % widest)


## --- a peer without the field, and a build before the catch -----------------

func test_without_a_look_hello_is_byte_for_byte_the_lookless_message() -> void:
	assert_eq(NetProtocol.hello(BUILD, NAME), _v1_hello(), "no look, no block")
	assert_eq(NetProtocol.welcome(1, 5, 0x04030201), PackedByteArray(V1_WELCOME),
		"and WELCOME likewise")


## The catch changed what an empty hand's THROW does, so a protocol-1 build
## would step the same inputs into a different match. It must be refused.
func test_a_build_from_before_the_catch_is_refused() -> void:
	assert_gte(NetProtocol.VERSION, 2, "the catch bumped the protocol (and the strips again)")
	var hello := NetProtocol.decode(PackedByteArray(PRE_CATCH_HELLO))
	assert_true(hello.has("error"), "a protocol-1 HELLO does not read")
	assert_eq(hello.get("version"), 1, "and says which version it was")


## A decoder reads HELLO and WELCOME up to their last fixed field and only
## then asks whether a look follows. A message with a look has to begin with
## exactly the lookless bytes, so the look stays an optional tail.
func test_a_look_rides_after_everything_a_lookless_message_holds() -> void:
	var hello := NetProtocol.hello(BUILD, NAME, _chosen().to_ids())
	var welcome := NetProtocol.welcome(1, 5, 0x04030201, _chosen().to_ids())
	assert_gt(hello.size(), _v1_hello().size(), "the HELLO carries more")
	assert_eq(hello.slice(0, _v1_hello().size()), _v1_hello(),
		"and begins with the lookless HELLO")
	assert_gt(welcome.size(), V1_WELCOME.size(), "the WELCOME carries more")
	assert_eq(welcome.slice(0, V1_WELCOME.size()), PackedByteArray(V1_WELCOME),
		"and begins with the lookless WELCOME")


func test_a_lookless_peers_messages_read_as_the_default_look() -> void:
	var hello := NetProtocol.decode(_v1_hello())
	assert_false(hello.has("error"), "a lookless HELLO still reads")
	assert_false(hello.has("look_error"), "and is not a bad look, just none")
	assert_eq(hello.get("look"), {}, "with no look")
	var welcome := NetProtocol.decode(PackedByteArray(V1_WELCOME))
	assert_false(welcome.has("error"), "a lookless WELCOME still reads")
	assert_eq(welcome.get("look"), {}, "with no look")
	assert_true(CharacterLook.from_ids(hello["look"]).equals(CharacterLook.new()),
		"which is the prince")


## --- what a peer must not be able to do with it -------------------------------

## Cut anywhere before the look and it is the truncated message it always was;
## cut anywhere inside the look and the message stands with the look dropped.
func test_a_truncated_look_drops_the_look_and_keeps_the_message() -> void:
	var whole := NetProtocol.hello(BUILD, NAME, _chosen().to_ids())
	var fixed := _v1_hello().size()
	var leaked := 0
	var dropped := 0
	for cut: int in range(0, whole.size()):
		var message := NetProtocol.decode(whole.slice(0, cut))
		if cut < fixed:
			leaked += 0 if message.has("error") else 1
		elif cut == fixed:
			assert_eq(message.get("look"), {}, "cut at the look: a lookless HELLO")
		else:
			assert_false(message.has("error"), "cut at %d still a HELLO" % cut)
			assert_eq(message.get("look"), {}, "cut at %d drops the whole look" % cut)
			dropped += 1 if message.has("look_error") else 0
	assert_eq(leaked, 0, "no cut short of the fixed fields reads as a HELLO")
	assert_eq(dropped, whole.size() - fixed - 1, "every cut inside the look is said to be")

	var welcome := NetProtocol.welcome(0, 5, 1, _chosen().to_ids())
	for cut: int in range(V1_WELCOME.size() + 1, welcome.size()):
		var message := NetProtocol.decode(welcome.slice(0, cut))
		assert_false(message.has("error"), "WELCOME cut at %d still a WELCOME" % cut)
		assert_eq(message.get("look"), {}, "and without the look")


func test_a_format_this_build_does_not_know_drops_the_look() -> void:
	var block := [NetProtocol.LOOK_FORMAT + 1, 1]
	block.append_array(_field(0, "heroine"))
	var message := _hello_with(block)
	assert_false(message.has("error"), "the HELLO stands")
	assert_eq(message.get("look"), {}, "the look does not")
	assert_true(message.has("look_error"), "and says why")


func test_too_many_fields_drops_the_look() -> void:
	var block := [NetProtocol.LOOK_FORMAT, NetProtocol.MAX_LOOK_FIELDS + 1]
	for i: int in NetProtocol.MAX_LOOK_FIELDS + 1:
		block.append_array(_field(0, "heroine"))
	var message := _hello_with(block)
	assert_false(message.has("error"), "the HELLO stands")
	assert_eq(message.get("look"), {}, "a look past MAX_LOOK_FIELDS is not read")


func test_a_too_long_id_costs_only_its_own_field() -> void:
	var block := [NetProtocol.LOOK_FORMAT, 3]
	block.append_array(_field(0, "heroine"))
	block.append_array(_field(1, "w".repeat(NetProtocol.MAX_LOOK_ID + 1)))
	block.append_array(_field(2, "ink"))
	var message := _hello_with(block)
	assert_eq(message.get("look"), {"figure": "heroine", "accent": "ink"},
		"the long one is skipped by its length, the others stand")
	# 255 is as long as a length byte goes; one that long, with nothing after.
	block = [NetProtocol.LOOK_FORMAT, 1, 1, 255]
	for i: int in 255:
		block.append(0x61)
	assert_eq(_hello_with(block).get("look"), {}, "a 255-byte id is no id")


func test_bytes_that_are_not_an_id_cost_only_their_field() -> void:
	var bad: Array = [
		[0, 0], # empty
		[1, 7, 0x43, 0x52, 0x49, 0x4d, 0x53, 0x4f, 0x4e], # CRIMSON
		[1, 4, 0xff, 0xfe, 0x00, 0x80], # not text at all
		[1, 3, 0x77, 0x00, 0x77], # a NUL inside
	]
	for field: Array in bad:
		var block := [NetProtocol.LOOK_FORMAT, 2]
		block.append_array(field)
		block.append_array(_field(3, "gold"))
		var message := _hello_with(block)
		assert_false(message.has("error"), "%s: the HELLO stands" % [field])
		assert_eq(message.get("look"), {"hair": "gold"}, "%s: only its field goes" % [field])


func test_a_field_from_a_newer_build_is_skipped() -> void:
	var block := [NetProtocol.LOOK_FORMAT, 3]
	block.append_array(_field(0, "heroine"))
	block.append_array(_field(NetProtocol.LOOK_TAGS.size() + 3, "boots"))
	block.append_array(_field(4, "copper"))
	assert_eq(_hello_with(block).get("look"), {"figure": "heroine", "skin": "copper"},
		"an unknown tag is stepped over, and the field after it still read")


func test_a_repeated_field_keeps_the_first() -> void:
	var block := [NetProtocol.LOOK_FORMAT, 2]
	block.append_array(_field(2, "ink"))
	block.append_array(_field(2, "pale"))
	assert_eq(_hello_with(block).get("look"), {"accent": "ink"}, "the first one stands")


## Well formed on the wire is not the same as meaning something: an id this
## build has no option for falls back, alone, as the wardrobe's file does.
func test_an_id_that_names_nothing_falls_back_field_by_field() -> void:
	var block := [NetProtocol.LOOK_FORMAT, 3]
	block.append_array(_field(0, "dragon"))
	block.append_array(_field(1, "wine"))
	block.append_array(_field(3, "teal"))
	var message := _hello_with(block)
	var look := CharacterLook.from_ids(message["look"])
	var expected := CharacterLook.new()
	expected.take_ids({"outfit": "wine"})
	assert_true(look.equals(expected), "only the outfit is taken: %s" % look.to_ids())


func test_the_encoder_sends_only_what_would_be_taken() -> void:
	var sent := NetProtocol.hello(BUILD, NAME, {
		"figure": "heroine", "outfit": 3, "accent": "Not An Id",
		"hair": "x".repeat(40), "skin": "amber", "cape": "long",
	})
	assert_eq(NetProtocol.decode(sent).get("look"), {"figure": "heroine", "skin": "amber"},
		"a number, a bad id, an overlong id and an unknown field all stay home")


## Noise after a valid HELLO: whatever it is, the HELLO reads, nothing is read
## past the end, and what comes out is only known fields holding ids.
func test_noise_after_a_hello_never_fails_it_or_escapes_the_rules() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x10c4
	var broken: Array[String] = []
	for trial: int in 3000:
		var noise := PackedByteArray()
		var length := rng.randi_range(1, 80)
		for i: int in length:
			noise.append(rng.randi_range(0, 255))
		# Half the time start like a real block, so the reader gets past the
		# header and into the fields instead of stopping at the format byte.
		if trial % 2 == 0:
			noise[0] = NetProtocol.LOOK_FORMAT
		var bytes := _v1_hello()
		bytes.append_array(noise)
		var message := NetProtocol.decode(bytes)
		if message.has("error") or message.get("name") != NAME:
			broken.append("trial %d: %s" % [trial, message])
			continue
		var look: Dictionary = message["look"]
		for field: Variant in look:
			var raw := String(look[field]).to_ascii_buffer()
			if not NetProtocol.LOOK_TAGS.has(field) or not NetProtocol.is_look_id(raw):
				broken.append("trial %d: %s=%s" % [trial, field, look[field]])
	assert_eq(broken, [] as Array[String], "\n".join(broken.slice(0, 6)))
