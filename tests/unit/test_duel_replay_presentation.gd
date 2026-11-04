extends GutTest
## What the screen is told when NetSession corrects a client: the rule in
## scripts/duel/match_ledger.gd, docs/netplay.md "Corrected outcomes", played
## out on the match by hand.
##
## The corrections here are staged the way the session makes them --
## begin_replay(), read_state() back to an earlier frame, the frames stepped
## again, end_replay() -- with the kill moved, removed or added on the second
## pass. The kill is scripted (the placeholder fighter's slay(), between two
## steps, as the attract demo does it), because what is under test is what the
## match says about a changed outcome, not how a sword produces one. The
## placeholder fighter is not a physics body, so none of this needs a physics
## frame and it can be a GUT test. tests/match_net_test.gd asks the same
## questions of two real sessions on the real fighter, where the corrections
## are whatever lag and loss make of them.

const MANIFEST := "res://levels/duel_zones.txt"
## Frames between the snapshot a correction rewinds to and the kill.
const LEAD_IN := 4
## Frames the prediction ran on past the kill before the host's word arrived.
const AFTER := 8

var _strip: ZoneStrip


## Everything the scene would hear from one match.
class Ears:
	extends RefCounted

	var beats: Array[int] = [] # victims, one per fighter_died
	var blood := {} # Vector2i(frame, victim) -> at
	var recorded := 0
	var retracted := 0
	var others := 0 # every other beat: initiative, respawn, zone, catch...

	func _init(fight: DuelMatch) -> void:
		fight.fighter_died.connect(
			func(victim: int, _k: int, _at: Vector2) -> void: beats.append(victim))
		fight.death_recorded.connect(func(victim: int, at: Vector2, frame: int, _blow: int) -> void:
			recorded += 1
			blood[Vector2i(frame, victim)] = at)
		fight.death_retracted.connect(func(victim: int, frame: int) -> void:
			retracted += 1
			blood.erase(Vector2i(frame, victim)))
		fight.initiative_changed.connect(func(_l: int) -> void: others += 1)
		fight.fighter_respawned.connect(
			func(_s: int, _at: Vector2, _f: int) -> void: others += 1)
		fight.zone_changed.connect(func(_i: int) -> void: others += 1)
		fight.blade_caught.connect(func(_b: int, _f: int, _at: Vector2) -> void: others += 1)


func before_all() -> void:
	_strip = ZoneStrip.from_manifest(MANIFEST)


func _fight() -> DuelMatch:
	var fight := DuelMatch.new()
	add_child_autofree(fight)
	assert_true(fight.build(_strip), "the match builds on the placeholder fighter")
	var guard := 0
	while fight.phase == DuelMatch.Phase.COUNTDOWN and guard < 600:
		fight.step(0, 0)
		guard += 1
	return fight


## Steps `frames` frames, slaying seat 1 (by seat 0) before frame `kill_at` if
## it is one of them. Returns the frame the kill landed on, or -1.
func _run(fight: DuelMatch, frames: int, kill_at: int = -1) -> int:
	var landed := -1
	for i: int in frames:
		if fight.frame == kill_at:
			fight.seats[1].node.call("slay", 0)
			landed = fight.frame
		fight.step(PlayerInput.BIT_RIGHT, 0)
	return landed


## Rewinds to `snapshot` and steps up to `to` again inside the replay bracket,
## as NetSession does, with the kill (if any) at `kill_at`.
func _correct(fight: DuelMatch, snapshot: PackedByteArray, to: int, kill_at: int) -> void:
	fight.begin_replay()
	assert_true(fight.read_state(snapshot), "the snapshot reads back")
	_run(fight, to - fight.frame, kill_at)
	fight.end_replay()


func test_a_frame_stepped_again_rings_nothing() -> void:
	var fight := _fight()
	var ears := Ears.new(fight)
	var snapshot := fight.write_state()
	var kill_at := fight.frame + LEAD_IN
	_run(fight, LEAD_IN + AFTER, kill_at)
	var heard := [ears.beats.size(), ears.recorded, ears.others]
	assert_eq(ears.beats, [1] as Array[int], "the predicted kill rang once")

	_correct(fight, snapshot, fight.frame, kill_at)
	_correct(fight, snapshot, fight.frame, kill_at)
	assert_eq([ears.beats.size(), ears.recorded, ears.others], heard,
		"two corrections that changed nothing rang nothing: not the kill, not the "
			+ "initiative it won")
	assert_eq(ears.retracted, 0, "and took nothing back")


func test_a_predicted_kill_the_host_never_had_is_taken_back() -> void:
	var fight := _fight()
	var ears := Ears.new(fight)
	var snapshot := fight.write_state()
	var kill_at := fight.frame + LEAD_IN
	_run(fight, LEAD_IN + AFTER, kill_at)
	assert_eq(ears.blood.size(), 1, "the predicted kill spilled blood")

	_correct(fight, snapshot, fight.frame, -1)
	assert_true(fight.is_fighter_alive(1), "the host says seat 1 never fell")
	assert_eq(ears.blood.size(), 1,
		"inside SAME_BEAT the blood waits: the corrected history may yet produce it")

	_run(fight, MatchLedger.SAME_BEAT)
	assert_eq(ears.blood.size(), 0, "past it, the blood is taken back")
	assert_eq(ears.retracted, 1, "by exactly one retraction")
	assert_eq(ears.beats, [1] as Array[int], "and no second beat, of any kind")


func test_a_kill_only_the_host_had_rings_late_once() -> void:
	var fight := _fight()
	var ears := Ears.new(fight)
	var snapshot := fight.write_state()
	_run(fight, LEAD_IN + AFTER)
	assert_eq(ears.beats.size(), 0, "the prediction had no kill")

	var kill_at := snapshot.decode_u32(0) + LEAD_IN
	_correct(fight, snapshot, fight.frame, kill_at)
	assert_eq(ears.beats, [1] as Array[int], "the host's kill rings, late, once")
	assert_eq(ears.blood.keys(), [Vector2i(kill_at, 1)],
		"with its blood on the host's frame, which seeds the same splatter on both")

	_run(fight, MatchLedger.SAME_BEAT * 2)
	_correct(fight, snapshot, fight.frame, kill_at)
	assert_eq(ears.beats.size(), 1, "and never again, however often it is replayed")
	assert_eq(ears.retracted, 0, "and it stays")


func test_a_kill_a_correction_moves_is_moved_without_a_beat() -> void:
	var fight := _fight()
	var ears := Ears.new(fight)
	var snapshot := fight.write_state()
	var predicted := fight.frame + LEAD_IN
	_run(fight, LEAD_IN + AFTER, predicted)

	var real := predicted + 3
	_correct(fight, snapshot, fight.frame, real)
	assert_eq(ears.beats, [1] as Array[int], "one death, one beat")
	assert_eq(ears.blood.keys(), [Vector2i(real, 1)], "the blood moved to the host's frame")
	assert_eq([ears.retracted, ears.recorded], [1, 2], "by taking it up and putting it down")


## Blood for a death the timeline lost track of -- the frames behind a snapshot
## could not be stepped again -- is kept, because the respawn timer in the
## state says the death happened, and on which frame.
func test_the_state_outranks_a_stale_timeline() -> void:
	var fight := _fight()
	var ears := Ears.new(fight)
	var snapshot := fight.write_state()
	var kill_at := fight.frame + LEAD_IN
	_run(fight, LEAD_IN + AFTER, kill_at)
	var dead := fight.write_state()

	# A correction that loses the kill from the timeline: back to before it, on
	# to just short of it, and then the host's state from after it, loaded
	# without the frames between being stepped.
	fight.begin_replay()
	fight.read_state(snapshot)
	_run(fight, LEAD_IN - 1)
	fight.read_state(dead)
	fight.end_replay()
	_run(fight, MatchLedger.SAME_BEAT * 2)
	assert_eq(ears.blood.keys(), [Vector2i(kill_at, 1)], "the blood stays where it was")
	assert_eq(ears.retracted, 0, "nothing was taken back")
	assert_eq(ears.beats.size(), 1, "and nothing rang twice")


## The flag is presentation's alone. A match stepped wholly inside the replay
## bracket and one stepped outside it must be the same match, byte for byte.
func test_replaying_does_not_touch_the_simulation() -> void:
	var plain := _fight()
	var quiet := _fight()
	quiet.begin_replay()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var parted := -1
	for i: int in 600:
		var a := rng.randi() & 0xff
		var b := rng.randi() & 0xff
		if i % 150 == 40:
			plain.seats[i % 2].node.call("slay", 1 - i % 2)
			quiet.seats[i % 2].node.call("slay", 1 - i % 2)
		plain.step(a, b)
		quiet.step(a, b)
		if parted < 0 and (plain.checksum() != quiet.checksum()
				or plain.write_state() != quiet.write_state()):
			parted = i
	quiet.end_replay()
	assert_true(plain.kills[0] + plain.kills[1] > 0, "the run had deaths in it")
	assert_eq(parted, -1, "600 frames, replaying or not: identical state and checksum")


func test_gore_takes_back_one_death_and_only_that_one() -> void:
	var field := GoreField.new()
	add_child_autofree(field)
	field.setup(_strip)
	var at := Vector2(_strip.zone_width() * 2.5, 64.0)
	field.spill(at, 1, 300)
	field.spill(at + Vector2(40.0, 0.0), 0, 310)
	var both := field.total()
	assert_gt(both, 0, "two deaths spilled")
	assert_eq(field.wipe(1, 999), 0, "a death that never spilled takes nothing")
	var taken := field.wipe(1, 300)
	assert_gt(taken, 0, "the retracted death's blood comes up")
	assert_eq(field.total(), both - taken, "and none of the other's")
	assert_eq(field.wipe(1, 300), 0, "twice is nothing more")
