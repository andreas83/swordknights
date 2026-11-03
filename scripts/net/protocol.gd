class_name NetProtocol
extends RefCounted
## The wire format. Every byte that crosses between two duellists is built and
## read here, and nowhere else.
##
## Each message is [u8 version][u8 type][payload], little-endian throughout. The
## version is checked on arrival rather than assumed: two builds that disagree
## should say so in the lobby instead of desyncing in the third round. Bump
## VERSION whenever a payload changes shape.
##
## `decode` never trusts its input. A short, truncated or unknown message comes
## back as a dictionary carrying "error" and is dropped by the session — a
## relay is a public endpoint, and a malformed packet must not be able to crash
## a duel or read past the end of a buffer.
##
## Sizes, so the bandwidth is not a mystery (see docs/netplay.md):
##   INPUT     ~11 bytes   client -> host, every frame
##   SNAPSHOT  ~230 bytes  host -> client, every SNAPSHOT_INTERVAL frames
##   look      ~45 bytes   both ways, once, on the end of HELLO and WELCOME
##
## VERSION is still 1 although HELLO and WELCOME grew a look. That is the one
## kind of change that does not need a bump: the look is an optional block on
## the END of a message, and a version-1 decoder reads HELLO and WELCOME up to
## their last fixed field and never asks whether bytes follow. So an older
## build reads a newer HELLO exactly as it always did and plays on, showing
## its opponent in the seat's default; a newer build reads an older HELLO as
## one with no look, which is the same answer. A bump would have refused that
## match in the lobby, to protect a field neither side needs to duel. Anything
## that changes a field the duel does depend on still bumps VERSION.

const VERSION := 1

enum Type {
	## --- the duel ---
	HELLO = 1, ## first thing a peer says: who it is and what build it runs
	WELCOME = 2, ## the host answers with the seat it assigned
	INPUT = 3, ## client -> host, a window of recent input frames
	SNAPSHOT = 4, ## host -> client, authoritative state plus the input behind it
	PING = 5,
	PONG = 6,
	BYE = 7,
	DESYNC = 8, ## "your frame N and mine disagree" — reported both ways

	## --- the rendezvous relay (see scripts/net/rendezvous.gd) ---
	ROOM_OPEN = 16, ## give me a new room code
	ROOM_JOIN = 17, ## put me in this room
	ROOM_OK = 18, ## you are in; here is the code and whether you host
	ROOM_ERROR = 19,
	ROOM_PEER = 20, ## the other seat arrived or left
}

enum Bye {
	QUIT = 0,
	VERSION_MISMATCH = 1,
	ROOM_CLOSED = 2,
	ARENA_MISMATCH = 3,
}

enum RoomError {
	NO_SUCH_ROOM = 0,
	ROOM_FULL = 1,
	BAD_CODE = 2,
	TOO_MANY_ROOMS = 3,
}

## Room codes avoid the characters people mishear or mistype: no O/0, no I/1/L,
## no U/V confusion when spoken aloud.
const CODE_ALPHABET := "ABCDEFGHJKMNPQRSTWXYZ23456789"
const CODE_LENGTH := 4

## A short string field: one length byte then the bytes. Spelled out rather
## than using StreamPeer's own string helpers so the format is unambiguous and
## cannot shift under us between engine versions.
const MAX_TEXT := 64

## --- a player's look ---------------------------------------------------------
##
## The block HELLO and WELCOME may end with: the sender's figure and wardrobe
## colours, as CharacterLook ids, so each phone can draw the other player as
## they chose to be drawn. Presentation only. It is handed to the scene and to
## nothing else -- not the match, not a snapshot, not a checksum -- so two
## peers with different looks, or one with none, step identical duels.
##
##     [u8 LOOK_FORMAT][u8 count] then count x [u8 tag][u8 length][id bytes]
##
## Ids rather than option indices, for the reason the wardrobe's file uses
## them: two builds may list the options in a different order, and an index
## would then put a different colour on the other screen. An id the receiving
## build does not know names nothing and falls back. The tag is the field's
## position in LOOK_TAGS, which is therefore append-only: a tag past the end is
## a field from a newer build and is skipped, which its length prefix allows.
##
## Nothing here is trusted. The block is read by the rule the wardrobe's loader
## uses on its file: if the block cannot be read at all -- truncated, a count
## past MAX_LOOK_FIELDS, a format this build does not know -- the whole look is
## dropped; if it can, each field stands or falls alone, so an id that is too
## long, is not lower-case ASCII, or repeats a field costs that one field. What
## survives is still only a set of strings, and CharacterLook.take_ids() is
## what decides whether they name anything. A malformed look never fails the
## message it rides on: refusing a HELLO over a sash colour would stall the
## handshake, which is exactly what a peer must not be able to do with it.

const LOOK_FORMAT := 1
## Wire tags. Append only; see above.
const LOOK_TAGS: Array[String] = ["figure", "outfit", "accent", "hair", "skin"]
## More entries than a look could need, so a newer build has room to grow and
## a hostile one cannot make the reader loop for long.
const MAX_LOOK_FIELDS := 16
## Longer than any option id, short enough that a look stays tens of bytes.
const MAX_LOOK_ID := 16


## --- encoding ---------------------------------------------------------------

static func _open(type: Type) -> StreamPeerBuffer:
	var buf := StreamPeerBuffer.new()
	buf.big_endian = false
	buf.put_u8(VERSION)
	buf.put_u8(int(type))
	return buf


static func _put_text(buf: StreamPeerBuffer, text: String) -> void:
	var raw := text.substr(0, MAX_TEXT).to_utf8_buffer()
	buf.put_u8(raw.size())
	if raw.size() > 0:
		buf.put_data(raw)


## `look` is the sender's CharacterLook ids (CharacterLook.to_ids()). Empty
## sends no look block at all, which is byte for byte a version-1 HELLO.
static func hello(build: int, name: String, look: Dictionary = {}) -> PackedByteArray:
	var buf := _open(Type.HELLO)
	buf.put_u32(build)
	_put_text(buf, name)
	_put_look(buf, look)
	return buf.data_array


## The host's look rides on its WELCOME, as the guest's rides on its HELLO.
static func welcome(
	slot: int, rounds_to_win: int, arena_hash: int, look: Dictionary = {}
) -> PackedByteArray:
	var buf := _open(Type.WELCOME)
	buf.put_u8(slot)
	buf.put_u8(rounds_to_win)
	buf.put_u32(arena_hash)
	_put_look(buf, look)
	return buf.data_array


## Writes the fields of `look` that this build has a tag for and whose ids
## would be accepted on the other side; anything else is left out rather than
## sent to be refused. Writes nothing for an empty look.
static func _put_look(buf: StreamPeerBuffer, look: Dictionary) -> void:
	var fields: Array[PackedByteArray] = []
	for tag: int in LOOK_TAGS.size():
		var value: Variant = look.get(LOOK_TAGS[tag])
		if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:
			continue
		var raw := String(value).to_ascii_buffer()
		if not is_look_id(raw):
			continue
		var field := PackedByteArray([tag, raw.size()])
		field.append_array(raw)
		fields.append(field)
	if fields.is_empty():
		return
	buf.put_u8(LOOK_FORMAT)
	buf.put_u8(fields.size())
	for field: PackedByteArray in fields:
		buf.put_data(field)


## A window of consecutive input frames, oldest first, starting at `first_frame`.
##
## Sent every frame and deliberately redundant: the same frame goes out several
## times, so one lost or late datagram does not starve the host of input. Over
## WebSocket (TCP) nothing is lost and the redundancy is nearly free; it is here
## because the transport is meant to be swappable for an unreliable one.
static func input_window(first_frame: int, bits: PackedByteArray) -> PackedByteArray:
	var buf := _open(Type.INPUT)
	buf.put_u32(first_frame)
	buf.put_u8(bits.size())
	if bits.size() > 0:
		buf.put_data(bits)
	return buf.data_array


## The authoritative state at `frame`, its checksum, and the input the host
## applied over the `pairs` frames leading up to it.
##
## The input history is what makes divergence detectable rather than merely
## suspected: given the previous snapshot's state and these bytes, the client
## can recompute this exact frame with no prediction involved, so a checksum
## that still disagrees is a real desync and not a mispredicted remote input.
## `pairs` is [bits_a, bits_b] per frame, oldest first, for frames
## (frame - pairs.size()) .. (frame - 1).
static func snapshot(
	frame: int, checksum: int, state: PackedByteArray, pairs: Array[Vector2i]
) -> PackedByteArray:
	var buf := _open(Type.SNAPSHOT)
	buf.put_u32(frame)
	buf.put_u32(checksum)
	buf.put_u8(pairs.size())
	for pair: Vector2i in pairs:
		buf.put_u8(pair.x & 0xff)
		buf.put_u8(pair.y & 0xff)
	buf.put_u16(state.size())
	if state.size() > 0:
		buf.put_data(state)
	return buf.data_array


static func ping(id: int, sent_usec: int) -> PackedByteArray:
	var buf := _open(Type.PING)
	buf.put_u32(id)
	buf.put_u64(sent_usec)
	return buf.data_array


static func pong(id: int, sent_usec: int) -> PackedByteArray:
	var buf := _open(Type.PONG)
	buf.put_u32(id)
	buf.put_u64(sent_usec)
	return buf.data_array


static func bye(reason: Bye) -> PackedByteArray:
	var buf := _open(Type.BYE)
	buf.put_u8(int(reason))
	return buf.data_array


static func desync(frame: int, mine: int, theirs: int) -> PackedByteArray:
	var buf := _open(Type.DESYNC)
	buf.put_u32(frame)
	buf.put_u32(mine)
	buf.put_u32(theirs)
	return buf.data_array


static func room_open() -> PackedByteArray:
	return _open(Type.ROOM_OPEN).data_array


static func room_join(code: String) -> PackedByteArray:
	var buf := _open(Type.ROOM_JOIN)
	_put_text(buf, code.to_upper())
	return buf.data_array


static func room_ok(code: String, as_host: bool) -> PackedByteArray:
	var buf := _open(Type.ROOM_OK)
	_put_text(buf, code)
	buf.put_u8(1 if as_host else 0)
	return buf.data_array


static func room_error(code: RoomError, message: String) -> PackedByteArray:
	var buf := _open(Type.ROOM_ERROR)
	buf.put_u8(int(code))
	_put_text(buf, message)
	return buf.data_array


static func room_peer(present: bool) -> PackedByteArray:
	var buf := _open(Type.ROOM_PEER)
	buf.put_u8(1 if present else 0)
	return buf.data_array


## --- decoding ---------------------------------------------------------------

## Returns a dictionary with "type" and the payload's fields, or one carrying
## "error" if the bytes are not a message this build understands. Callers must
## check for "error" before reading anything else.
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 2:
		return {"error": "runt (%d bytes)" % bytes.size()}
	var version := bytes[0]
	if version != VERSION:
		return {"error": "protocol version %d, expected %d" % [version, VERSION],
			"version": version}

	var type := bytes[1] as Type
	var buf := StreamPeerBuffer.new()
	buf.big_endian = false
	buf.data_array = bytes
	buf.seek(2)
	var left := bytes.size() - 2
	var out := {"type": type}

	match type:
		Type.HELLO:
			if left < 5:
				return _short(type)
			out["build"] = buf.get_u32()
			out["name"] = _get_text(buf)
			if out["name"] == null:
				return _short(type)
			_get_look(buf, out)

		Type.WELCOME:
			if left < 6:
				return _short(type)
			out["slot"] = buf.get_u8()
			out["rounds_to_win"] = buf.get_u8()
			out["arena_hash"] = buf.get_u32()
			if out["slot"] > 1:
				return {"error": "WELCOME names seat %d" % out["slot"]}
			_get_look(buf, out)

		Type.INPUT:
			if left < 5:
				return _short(type)
			out["first_frame"] = buf.get_u32()
			var count: int = buf.get_u8()
			if left < 5 + count:
				return _short(type)
			out["bits"] = buf.get_data(count)[1] as PackedByteArray

		Type.SNAPSHOT:
			if left < 11:
				return _short(type)
			out["frame"] = buf.get_u32()
			out["checksum"] = buf.get_u32()
			var pair_count: int = buf.get_u8()
			if left < 11 + pair_count * 2:
				return _short(type)
			var pairs: Array[Vector2i] = []
			for i: int in pair_count:
				var a := buf.get_u8()
				var b := buf.get_u8()
				pairs.append(Vector2i(a, b))
			out["pairs"] = pairs
			var state_len := buf.get_u16()
			if left < 11 + pair_count * 2 + state_len:
				return _short(type)
			out["state"] = buf.get_data(state_len)[1] as PackedByteArray

		Type.PING, Type.PONG:
			if left < 12:
				return _short(type)
			out["id"] = buf.get_u32()
			out["sent_usec"] = buf.get_u64()

		Type.BYE:
			if left < 1:
				return _short(type)
			out["reason"] = buf.get_u8()

		Type.DESYNC:
			if left < 12:
				return _short(type)
			out["frame"] = buf.get_u32()
			out["mine"] = buf.get_u32()
			out["theirs"] = buf.get_u32()

		Type.ROOM_OPEN:
			pass

		Type.ROOM_JOIN:
			out["code"] = _get_text(buf)
			if out["code"] == null:
				return _short(type)

		Type.ROOM_OK:
			out["code"] = _get_text(buf)
			if out["code"] == null or bytes.size() - buf.get_position() < 1:
				return _short(type)
			out["as_host"] = buf.get_u8() != 0

		Type.ROOM_ERROR:
			if left < 1:
				return _short(type)
			out["code"] = buf.get_u8()
			out["message"] = _get_text(buf)
			if out["message"] == null:
				return _short(type)

		Type.ROOM_PEER:
			if left < 1:
				return _short(type)
			out["present"] = buf.get_u8() != 0

		_:
			return {"error": "unknown message type %d" % int(type)}

	return out


static func _short(type: Type) -> Dictionary:
	return {"error": "truncated %s" % type_name(type)}


## Returns null rather than "" when the field runs past the end, so a caller can
## tell an empty string from a malformed one.
static func _get_text(buf: StreamPeerBuffer) -> Variant:
	var total := buf.get_size()
	if buf.get_position() >= total:
		return null
	var length := buf.get_u8()
	if length > MAX_TEXT or buf.get_position() + length > total:
		return null
	if length == 0:
		return ""
	var raw: PackedByteArray = buf.get_data(length)[1]
	return raw.get_string_from_utf8()


## Reads the optional look block from where `buf` stands into out["look"], as
## {field: id}. Always sets it: empty when there was no block, which is an
## older peer, or when the block could not be read, which also sets
## out["look_error"] for the log. Never touches out["error"] -- see the note on
## LOOK_FORMAT for why a bad look does not fail its message.
static func _get_look(buf: StreamPeerBuffer, out: Dictionary) -> void:
	out["look"] = {}
	var total := buf.get_size()
	if buf.get_position() >= total:
		return
	if total - buf.get_position() < 2:
		out["look_error"] = "truncated look"
		return
	var look_format := buf.get_u8()
	var count := buf.get_u8()
	if look_format != LOOK_FORMAT:
		out["look_error"] = "look format %d, expected %d" % [look_format, LOOK_FORMAT]
		return
	if count > MAX_LOOK_FIELDS:
		out["look_error"] = "a look of %d fields" % count
		return
	var look := {}
	for i: int in count:
		if total - buf.get_position() < 2:
			out["look_error"] = "truncated look"
			return
		var tag := buf.get_u8()
		var length := buf.get_u8()
		if total - buf.get_position() < length:
			out["look_error"] = "truncated look"
			return
		var raw := PackedByteArray()
		if length > 0:
			raw = buf.get_data(length)[1]
		if tag >= LOOK_TAGS.size() or look.has(LOOK_TAGS[tag]) or not is_look_id(raw):
			continue # a newer build's field, a repeat, or not an id: this field only
		look[LOOK_TAGS[tag]] = raw.get_string_from_ascii()
	out["look"] = look


## True for 1..MAX_LOOK_ID bytes of lower-case ASCII, digits and underscores,
## which is every CharacterLook id. Checked as bytes, before anything is made a
## String of them: a hostile peer's invalid UTF-8 never reaches a decoder that
## would log about it.
static func is_look_id(raw: PackedByteArray) -> bool:
	if raw.is_empty() or raw.size() > MAX_LOOK_ID:
		return false
	for byte: int in raw:
		var lower := byte >= 0x61 and byte <= 0x7a
		var digit := byte >= 0x30 and byte <= 0x39
		if not (lower or digit or byte == 0x5f):
			return false
	return true


static func type_name(type: Type) -> String:
	return Type.keys()[Type.values().find(int(type))] if Type.values().has(int(type)) \
		else "TYPE_%d" % int(type)


## --- room codes -------------------------------------------------------------

static func make_room_code(rng: RandomNumberGenerator) -> String:
	var out := ""
	for i: int in CODE_LENGTH:
		out += CODE_ALPHABET[rng.randi_range(0, CODE_ALPHABET.length() - 1)]
	return out


static func is_room_code(code: String) -> bool:
	if code.length() != CODE_LENGTH:
		return false
	for i: int in code.length():
		if not CODE_ALPHABET.contains(code[i]):
			return false
	return true


## Identifies the arena both sides think they are fighting in, so a mismatched
## level file is caught in the lobby rather than as an unexplained desync.
static func arena_hash(arena: AsciiLevel) -> int:
	var words := PackedInt32Array()
	words.append(arena.cols)
	words.append(arena.rows)
	words.append(arena.spawn_point.x)
	words.append(arena.spawn_point.y)
	for y: int in arena.rows:
		for x: int in arena.cols:
			words.append(int(arena.kind_at(x, y)))
	return DuelSim.fnv1a(words)
