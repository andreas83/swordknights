extends SceneTree
## Is one frame of the duel really a function of its state and two input bytes?
##
##     godot --headless --path . --script tests/duel_determinism_test.gd
##
## Everything in scripts/net rests on this file passing. The duel is the
## tug-of-war match on the real fighter (scripts/duel/match.gd); the round duel
## these claims were first made against is retired, and the claims moved here
## unchanged. Three of them:
##
## 1. TWO SIMS AGREE. Two separately built matches, same strip, same input
##    stream, hold the same checksum after every single frame. This is the
##    property the netplay desync detector measures, and the reason a host's
##    simulation can be called authoritative at all.
##
## 2. A SNAPSHOT IS LOSSLESS. write_state() then read_state() puts a match back
##    exactly: the same checksum, the same bytes when written again, and the
##    same future. If it were not, a client could never land exactly on the
##    host's state and every snapshot would read as a desync.
##
## 3. A REPLAYED FRAME IS THE SAME FRAME, to within float noise. Running the
##    stream as a burst inside one physics frame and pacing it out one frame per
##    physics frame give the same match: every discrete field identical, every
##    position and velocity within 1/256 of a pixel -- the checksum's quantum.
##    Reconciliation replays frames in a burst while the live game paces them,
##    so if this were false the client would drift away from the host every
##    time it corrected. tests/match_fighter_test.gd replays from a snapshot,
##    but always in a burst; this is the only paced run.
##
##    "To within float noise" is weaker than the round duel managed, which was
##    bit-exact, and the weakening is measured rather than assumed. On the real
##    fighter a paced run and a burst run part in the last bits of a standing
##    fighter's y -- about 1e-4 px, two hundred frames in -- while two paced runs
##    agree exactly and so do two bursts. Which bits move depends on what the
##    physics space held before, so it reads as the engine's collision recovery
##    visiting the ground's tile shapes in a different order. The quantised
##    checksum absorbs it unless a value sits on a rounding boundary, where it
##    would show up as a false desync. docs/duel-match.md lists it as open; the
##    first bitwise divergence is printed on every run so the number can be
##    watched, and the tolerance below is what fails if it ever grows.
##
## Run in a SceneTree rather than as a GUT test because the match has to be
## stepped from inside a physics frame, one per physics frame for claim 3. See
## tests/duel_support.gd.

const Support := preload("res://tests/duel_support.gd")
const FRAMES := 360
const SNAPSHOT_AT := 150
## The checksum's quantum, in pixels and pixels per second.
const NOISE := 1.0 / 256.0

enum Stage { RECORD, COMPARE, SNAPSHOT, PACED, DONE }

var _s := Support.new()
var _strip: ZoneStrip
var _stream: Array[Vector2i]
var _record := PackedInt64Array()
var _record_states: Array[PackedByteArray] = []
var _first_bitwise := -1
var _worst_noise := 0.0
var _warmup := 0
var _stage: Stage = Stage.RECORD
var _fight: DuelMatch
var _cursor := 0


func _initialize() -> void:
	_strip = Support.load_strip()
	_stream = Support.input_stream(FRAMES, 0x51f0d)


func _physics_process(_delta: float) -> bool:
	# The physics space needs a frame to exist before a fighter can move.
	_warmup += 1
	if _warmup < 3:
		return false

	match _stage:
		Stage.RECORD:
			_record = _burst_record()
			_s.equal(_record.size(), FRAMES, "a checksum was recorded for every frame")
			if _record.size() == FRAMES:
				_s.check(_record[0] != _record[FRAMES - 1], "the match actually moved")
			_stage = Stage.COMPARE

		Stage.COMPARE:
			var second := Support.checksums_of(root, _stream)
			var drift := _first_mismatch(_record, second)
			_s.equal(drift, -1, "two independent sims agree on every frame")
			_stage = Stage.SNAPSHOT

		Stage.SNAPSHOT:
			_check_snapshot_round_trip()
			_stage = Stage.PACED

		Stage.PACED:
			if _fight == null:
				_fight = Support.spawn_match(root, _strip)
				_cursor = 0
				if not _s.check(_fight != null, "the paced match builds"):
					_stage = Stage.DONE
				return false
			if _cursor < FRAMES and _cursor < _record_states.size():
				var pair := _stream[_cursor]
				_fight.step(pair.x, pair.y)
				var paced := _fight.write_state()
				var burst := _record_states[_cursor]
				if _first_bitwise < 0 and paced != burst:
					_first_bitwise = _cursor
				var apart := _apart(burst, paced)
				if not _s.check(
					apart <= NOISE,
					"frame %d paced out is not the same frame run as a burst (%s)"
						% [_cursor, "a discrete field differs" if apart > 1.0e9
							else "%.6f px apart" % apart]
				):
					_stage = Stage.DONE
					return false
				_worst_noise = maxf(_worst_noise, apart)
				_cursor += 1
				return false
			print("  paced vs burst: first bitwise difference at frame %d, worst %.6f px"
				% [_first_bitwise, _worst_noise])
			_s.check(
				_fight.phase != DuelMatch.Phase.COUNTDOWN,
				"%d frames is long enough to leave the opening countdown" % FRAMES
			)
			_s.check(
				_fight.kills[0] + _fight.kills[1] > 0,
				"the paced run included a death (%d, %d)" % [_fight.kills[0], _fight.kills[1]]
			)
			_fight.free()
			_fight = null
			_stage = Stage.DONE

		Stage.DONE:
			quit(_s.report("duel_determinism"))
			return true

	return false


func _check_snapshot_round_trip() -> void:
	var fight := Support.spawn_match(root, _strip)
	if not _s.check(fight != null, "the snapshot match builds"):
		return
	for i: int in SNAPSHOT_AT:
		var pair := _stream[i]
		fight.step(pair.x, pair.y)

	var before := fight.checksum()
	var blob := fight.write_state()
	_s.equal(blob.size(), fight.snapshot_bytes(), "a snapshot is a fixed size")
	_s.equal(before, _record[SNAPSHOT_AT - 1], "the snapshot match is on the recorded path")

	# Push it somewhere else entirely, then restore.
	for i: int in 23:
		fight.step(PlayerInput.BIT_RIGHT | PlayerInput.BIT_JUMP, PlayerInput.BIT_ATTACK)
	_s.check(fight.checksum() != before, "stepping on changes the checksum")

	_s.check(fight.read_state(blob), "a snapshot reads back")
	_s.equal(fight.checksum(), before, "write_state/read_state keeps the checksum")

	# Checksums are quantised, so matching ones prove less than they look. A
	# snapshot that rounded a timer would sail through the line above and then
	# move a state transition by a frame somewhere downstream, which is exactly
	# the kind of thing the desync detector would later report as a divergence.
	# The snapshot IS the raw state, so compare it byte for byte.
	var again := fight.write_state()
	_s.equal(_first_byte_mismatch(blob, again), -1,
		"a snapshot round trip is exact to the last bit")

	# And a restored match must carry on down the recorded path, not merely
	# look right for one frame -- that is what reconciliation actually needs.
	for i: int in 40:
		var pair := _stream[SNAPSHOT_AT + i]
		fight.step(pair.x, pair.y)
	_s.equal(
		fight.checksum(), _record[SNAPSHOT_AT + 39],
		"a match restored from a snapshot keeps simulating the same future"
	)
	fight.free()


## Steps one match through the stream inside this physics frame, keeping the
## state after every frame as well as the checksum.
func _burst_record() -> PackedInt64Array:
	var out := PackedInt64Array()
	var fight := Support.spawn_match(root, _strip)
	if fight == null:
		return out
	for pair: Vector2i in _stream:
		fight.step(pair.x, pair.y)
		out.append(fight.checksum())
		_record_states.append(fight.write_state())
	fight.free()
	return out


## How far apart two snapshots of the same frame are: the largest difference
## in any position or velocity, or INF if any discrete field differs. Reads the
## layout the match and the fighter publish (DuelMatch.HEADER_BYTES, Fighter's
## offsets, DuelBlade.BYTES) rather than restating it.
static func _apart(a: PackedByteArray, b: PackedByteArray) -> float:
	if a.size() != b.size():
		return INF
	# The match header: everything up to the scroll is discrete or a timer that
	# no collision touches; the scroll follows the fighters.
	var scroll_at := DuelMatch.HEADER_BYTES - 8
	if a.slice(0, scroll_at) != b.slice(0, scroll_at):
		return INF
	var worst := absf(a.decode_double(scroll_at) - b.decode_double(scroll_at))
	var block := Fighter.state_bytes()
	for seat: int in 2:
		var base := DuelMatch.HEADER_BYTES + seat * block
		# [floats, discrete) for the body, then the same again for the blade.
		var spans := [
			[base + Fighter.OFF_POSITION, base + Fighter.OFF_STATE, base + Fighter.OFF_BLADE],
			[base + Fighter.OFF_BLADE, base + Fighter.OFF_BLADE + 32,
				base + Fighter.OFF_BLADE + DuelBlade.BYTES],
		]
		for span: Array in spans:
			var floats_from: int = span[0]
			var discrete_from: int = span[1]
			var end: int = span[2]
			for at: int in range(floats_from, discrete_from, 8):
				worst = maxf(worst, absf(a.decode_double(at) - b.decode_double(at)))
			if a.slice(discrete_from, end) != b.slice(discrete_from, end):
				return INF
	return worst


static func _first_mismatch(a: PackedInt64Array, b: PackedInt64Array) -> int:
	if a.size() != b.size():
		return mini(a.size(), b.size())
	for i: int in a.size():
		if a[i] != b[i]:
			return i
	return -1


static func _first_byte_mismatch(a: PackedByteArray, b: PackedByteArray) -> int:
	if a.size() != b.size():
		return mini(a.size(), b.size())
	for i: int in a.size():
		if a[i] != b[i]:
			return i
	return -1
