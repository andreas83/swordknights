extends SceneTree
## Is one frame of a duel really a function of its state and two input bytes?
##
##     godot --headless --script tests/duel_determinism_test.gd
##
## Everything in scripts/net rests on this file passing. Three claims:
##
## 1. TWO SIMS AGREE. Two separately built duels, same arena, same input
##    stream, hold the same checksum after every single frame. This is the
##    property the netplay desync detector measures, and the reason a host's
##    simulation can be called authoritative at all.
##
## 2. A SNAPSHOT IS LOSSLESS. write_state() then read_state() leaves a duel
##    with the checksum it had before. If it were not, a client could never
##    land exactly on the host's state and every snapshot would read as a
##    desync.
##
## 3. A REPLAYED FRAME IS THE SAME FRAME. Running the stream as a burst inside
##    one physics frame gives the same checksums as pacing it out one frame per
##    physics frame. Reconciliation replays frames in a burst, so if this were
##    false the client would drift away from the host every time it corrected.
##
## See tests/duel_support.gd for why only one duel exists at a time.

const Support := preload("res://tests/duel_support.gd")
const FRAMES := 360
const SNAPSHOT_AT := 150

enum Stage { RECORD, COMPARE, SNAPSHOT, PACED, DONE }

var _s := Support.new()
var _stream: Array[Vector2i]
var _record := PackedInt64Array()
var _warmup := 0
var _stage: Stage = Stage.RECORD
var _duel: Duel
var _cursor := 0


func _initialize() -> void:
	_stream = Support.input_stream(FRAMES, 0x51f0d)


func _physics_process(_delta: float) -> bool:
	# The physics space needs a frame to exist before a duellist can move, and
	# a freed arena needs one to leave it.
	_warmup += 1
	if _warmup < 3:
		return false

	match _stage:
		Stage.RECORD:
			_record = Support.checksums_of(root, _stream)
			_s.equal(_record.size(), FRAMES, "a checksum was recorded for every frame")
			_s.check(_record[0] != _record[FRAMES - 1], "the duel actually moved")
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
			if _duel == null:
				_duel = Support.spawn_duel(root)
				_cursor = 0
				return false
			if _cursor < FRAMES:
				var pair := _stream[_cursor]
				_duel.step(pair.x, pair.y)
				if not _s.check(
					_duel.checksum() == _record[_cursor],
					"frame %d paced out does not match the same frame replayed"
						% _cursor + _diff()
				):
					_stage = Stage.DONE
					return false
				_cursor += 1
				return false
			_s.check(
				_duel.phase != Duel.Phase.COUNTDOWN or _duel.round_index > 0,
				"%d frames is long enough to leave the opening countdown" % FRAMES
			)
			_stage = Stage.DONE

		Stage.DONE:
			quit(_s.report("duel_determinism"))
			return true

	return false


func _check_snapshot_round_trip() -> void:
	var duel := Support.spawn_duel(root)
	for i: int in SNAPSHOT_AT:
		var pair := _stream[i]
		duel.step(pair.x, pair.y)

	var before := duel.checksum()
	var blob := duel.write_state()
	_s.equal(blob.size(), Duel.SNAPSHOT_BYTES, "a snapshot is a fixed size")
	_s.equal(before, _record[SNAPSHOT_AT - 1], "the snapshot duel is on the recorded path")

	# Push it somewhere else entirely, then restore.
	for i: int in 23:
		duel.step(PlayerInput.BIT_RIGHT | PlayerInput.BIT_JUMP, PlayerInput.BIT_ATTACK)
	_s.check(duel.checksum() != before, "stepping on changes the checksum")

	_s.check(duel.read_state(blob), "a snapshot reads back")
	_s.equal(duel.checksum(), before, "write_state/read_state is lossless")

	# And a restored duel must carry on down the recorded path, not merely look
	# right for one frame — that is what reconciliation actually needs.
	for i: int in 40:
		var pair := _stream[SNAPSHOT_AT + i]
		duel.step(pair.x, pair.y)
	_s.equal(
		duel.checksum(), _record[SNAPSHOT_AT + 39],
		"a duel restored from a snapshot keeps simulating the same future"
	)
	duel.free()


static func _first_mismatch(a: PackedInt64Array, b: PackedInt64Array) -> int:
	if a.size() != b.size():
		return mini(a.size(), b.size())
	for i: int in a.size():
		if a[i] != b[i]:
			return i
	return -1


## Names the fields that differ, so a failure says what drifted.
func _diff() -> String:
	if _duel == null:
		return ""
	var out := ""
	var fresh := Support.spawn_duel(root)
	for i: int in _cursor + 1:
		var pair := _stream[i]
		fresh.step(pair.x, pair.y)
	var mine := PackedFloat32Array()
	var theirs := PackedFloat32Array()
	mine.resize(Player.DUEL_STATE_FLOATS)
	theirs.resize(Player.DUEL_STATE_FLOATS)
	for slot: int in 2:
		_duel.players[slot].duel_write_state(mine, 0)
		fresh.players[slot].duel_write_state(theirs, 0)
		for i: int in Player.DUEL_STATE_FLOATS:
			if mine[i] != theirs[i]:
				out += "\n      slot %d field %d: %.9f vs %.9f" % [slot, i, mine[i], theirs[i]]
	fresh.free()
	return out
