extends SceneTree
## A match on the real fighter, not the placeholder.
##
## The match layer was built and tested against scripts/duel/match_stub_fighter.gd,
## as agreed when the duel work was split. Three things stood between it and
## the real fighter, all found by reading before wiring, none of which the
## stub-based suites could see:
##
##   1. The fighter's world was typed `Level`; the match hands it a ZoneStrip;
##      the typed assignment failed in silence and the world stayed null.
##   2. The fighter's state is 100 bytes of mixed doubles and int32s; the
##      match refused it, and its checksum would have read ints as doubles.
##   3. The fighter collides through the physics space, which the view streams.
##
## Each has a check below, and so does the thing the wiring is for: a sword
## kills through the match and moves the rope, a hazard kills, and a rewind to
## a snapshot replays the same frames byte for byte -- which is what netplay
## rests on.
##
##     godot --headless --path . --script res://tests/match_fighter_test.gd

const Support := preload("res://tests/duel_support.gd")
const MANIFEST := "res://levels/duel_zones.txt"
const FIGHTER_SCENE: PackedScene = preload("res://scenes/fighter.tscn")

## Frames of random play for the determinism checks. Long enough to see deaths,
## respawns and thrown swords; short enough to run in a second or two.
const RANDOM_FRAMES := 600

var _s := Support.new()
var _strip: ZoneStrip
var _warm := 0


func _initialize() -> void:
	_strip = ZoneStrip.from_manifest(MANIFEST)


func _physics_process(_delta: float) -> bool:
	_warm += 1
	if _warm < 3:
		return false
	if not _s.check(_strip != null, "the strip loads"):
		quit(_s.report("match_fighter"))
		return true

	_it_builds_on_the_real_fighter()
	_the_fighters_stand_on_the_ground()
	_a_thrust_kills_through_the_match()
	_a_hazard_kills_and_credits_the_other_seat()
	_two_runs_on_the_same_inputs_agree()
	_a_rewind_replays_the_same_frames()

	quit(_s.report("match_fighter"))
	return true


## --- 1 and 2: the seam ------------------------------------------------------

func _it_builds_on_the_real_fighter() -> void:
	var fight := _open_match()
	if fight == null:
		return
	for slot: int in 2:
		var fighter := fight.seats[slot].node as Fighter
		if not _s.check(fighter != null, "seat %d holds a real Fighter" % slot):
			continue
		_s.check(fighter.world == _strip,
			"seat %d's fighter was handed the strip as its world" % slot)
		_s.equal(fighter.id, slot, "seat %d's fighter knows its seat" % slot)
	_s.check(fight.seats[0].hashes_itself(), "the fighter hashes itself")
	_s.equal(fight.snapshot_bytes(), DuelMatch.HEADER_BYTES + 2 * Fighter.state_bytes(),
		"the snapshot is the header and two fighter blocks")
	fight.free()


## --- 3: the ground ----------------------------------------------------------

func _the_fighters_stand_on_the_ground() -> void:
	var fight := _open_match()
	if fight == null:
		return
	for i: int in 90:
		fight.step(0, 0)
	for slot: int in 2:
		var fighter := fight.seats[slot].node as Fighter
		_s.check(fighter.is_alive(), "seat %d is alive after standing still" % slot)
		_s.check(fighter.grounded, "seat %d is standing on something" % slot)
		var column := floori(fighter.position.x / ZoneStrip.TILE)
		var floor_y := float(_strip.ground_row(column) * ZoneStrip.TILE)
		_s.check(absf(fighter.position.y - floor_y) < 1.0,
			"seat %d stands on the strip's floor (y %.2f, floor %.2f)"
			% [slot, fighter.position.y, floor_y])
	fight.free()


## --- the point of wiring it -------------------------------------------------

## A walks in and thrusts MID; B holds HIGH. Off the diagonal of the matrix,
## so the cut lands.
func _a_thrust_kills_through_the_match() -> void:
	var fight := _open_match()
	if fight == null:
		return
	var a := fight.seats[0].node as Fighter
	var b := fight.seats[1].node as Fighter
	var reach := a.tuning.blade_reach

	var closed := false
	for i: int in 240:
		var gap := b.position.x - a.position.x
		if gap <= reach:
			closed = true
			break
		fight.step(PlayerInput.BIT_RIGHT, PlayerInput.BIT_UP)
	_s.check(closed, "A closes to within reach of B")
	fight.step(PlayerInput.BIT_ATTACK, PlayerInput.BIT_UP)
	for i: int in 20:
		fight.step(0, PlayerInput.BIT_UP)
		if not b.is_alive():
			break

	_s.check(not b.is_alive(), "B, holding HIGH against a MID thrust, is dead")
	_s.check(a.is_alive(), "A is not")
	_s.equal(fight.kills[0], 1, "the kill is A's")
	_s.equal(fight.leader_slot(), 0, "A takes the initiative")
	_s.check(fight.respawn[1] > 0.0, "B's respawn timer is running")
	fight.free()


func _a_hazard_kills_and_credits_the_other_seat() -> void:
	var fight := _open_match()
	if fight == null:
		return
	var spikes := _find_kind(Tiles.Kind.SPIKES)
	if not _s.check(spikes.x >= 0, "the strip has spikes somewhere"):
		fight.free()
		return
	var b := fight.seats[1].node as Fighter
	fight.seats[1].set_position(Vector2(
		(spikes.x + 0.5) * ZoneStrip.TILE, (spikes.y + 1) * ZoneStrip.TILE))
	fight.step(0, 0)
	_s.check(not b.is_alive(), "B, standing in the spikes, is dead")
	_s.equal(fight.kills[0], 1, "a hazard death is credited to the other seat")
	_s.equal(fight.leader_slot(), 0, "and the other seat takes the initiative")
	fight.free()


## --- determinism ------------------------------------------------------------

func _two_runs_on_the_same_inputs_agree() -> void:
	var first := _random_run(11)
	var second := _random_run(11)
	_s.equal(first.size(), RANDOM_FRAMES, "the first run produced a checksum per frame")
	var differ := -1
	for i: int in mini(first.size(), second.size()):
		if first[i] != second[i]:
			differ = i
			break
	_s.equal(differ, -1, "%d frames of random play, twice: identical checksums"
		% RANDOM_FRAMES)
	var distinct := {}
	for value: int in first:
		distinct[value] = true
	_s.check(distinct.size() > RANDOM_FRAMES / 2,
		"the checksum moves with the play (%d distinct of %d)" % [distinct.size(), first.size()])


## The netplay property. Run, take a snapshot, run on; rewind to the snapshot
## and run the same inputs again. Every frame after the rewind must match the
## first pass in state and checksum. This is what a client does every time a
## correction arrives.
func _a_rewind_replays_the_same_frames() -> void:
	var fight := _open_match()
	if fight == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	for i: int in 200:
		fight.step(rng.randi() & 0xff, rng.randi() & 0xff)

	var snapshot := fight.write_state()
	var inputs: Array[Vector2i] = []
	var states: Array[PackedByteArray] = []
	var sums: Array[int] = []
	for i: int in 300:
		var bits := Vector2i(rng.randi() & 0xff, rng.randi() & 0xff)
		inputs.append(bits)
		fight.step(bits.x, bits.y)
		states.append(fight.write_state())
		sums.append(fight.checksum())

	_s.check(fight.read_state(snapshot), "the snapshot reads back")
	var first_bad := -1
	for i: int in inputs.size():
		fight.step(inputs[i].x, inputs[i].y)
		if fight.write_state() != states[i] or fight.checksum() != sums[i]:
			first_bad = i
			break
	_s.equal(first_bad, -1, "300 frames replayed from a snapshot: identical state")
	_s.check(fight.kills[0] + fight.kills[1] > 0,
		"the replayed stretch included at least one death")
	fight.free()


func _random_run(seed_value: int) -> PackedInt64Array:
	var sums := PackedInt64Array()
	var fight := _open_match()
	if fight == null:
		return sums
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i: int in RANDOM_FRAMES:
		fight.step(rng.randi() & 0xff, rng.randi() & 0xff)
		sums.append(fight.checksum())
	fight.free()
	return sums


## --- helpers ----------------------------------------------------------------

func _open_match() -> DuelMatch:
	var fight := DuelMatch.new()
	fight.name = "Match"
	fight.fighter_scene = FIGHTER_SCENE
	root.add_child(fight)
	if not _s.check(fight.build(_strip), "the match builds on the real fighter"):
		fight.free()
		return null
	while fight.phase == DuelMatch.Phase.COUNTDOWN:
		fight.step(0, 0)
	return fight


## The first cell of `kind` with an empty cell above it, or (-1, -1).
func _find_kind(kind: Tiles.Kind) -> Vector2i:
	for y: int in range(1, _strip.rows()):
		for x: int in _strip.cols():
			if _strip.kind_at(x, y) == kind and _strip.kind_at(x, y - 1) == Tiles.Kind.EMPTY:
				return Vector2i(x, y)
	return Vector2i(-1, -1)
