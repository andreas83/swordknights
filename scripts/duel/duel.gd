class_name Duel
extends Node2D
## The duel simulation: two duellists, one arena, a round state machine.
##
## The whole point of this file is `step(bits_a, bits_b)`. One call is one frame,
## and that frame is a function of nothing but the duel's own state and those
## two input snapshots — no wall clock, no Input singleton, no randomness, no
## reading of the frame's real delta. Everything that makes a duel playable over
## a network falls out of that one property:
##
##   * local two-player is two local input sources feeding the same step
##   * the host's simulation is authoritative because it is reproducible
##   * a client can replay the frames it mispredicted and converge
##   * two instances fed the same input stream agree, which is what the
##     desync checksum measures and what tests/duel_determinism_test.gd asserts
##
## The one thing step() needs from its caller is to be inside a physics frame:
## the duellists are CharacterBody2D, and move_and_slide() queries the physics
## space, which only exists while the engine is stepping it. Call step() from
## _physics_process, as the scenes do.
##
## Presentation is kept strictly outside. step() records what happened in
## `events` and emits signals, and suppresses the signals while `replaying` is
## set, so a reconciled frame does not re-trigger a sound or a screen shake that
## already played.

signal round_started(index: int)
signal round_ended(winner: int)
signal match_ended(winner: int)
signal cut_landed(victim: int, at: Vector2)
signal cut_blocked(defender: int, parried: bool, at: Vector2)
signal swords_clashed(at: Vector2)

enum Phase {
	COUNTDOWN, ## On your marks. Inputs are ignored and the swords are cold.
	FIGHTING, ## The only phase in which a sword can land.
	ROUND_OVER, ## Someone is down, or the clock ran out. Scored already.
	MATCH_OVER, ## Somebody reached rounds_to_win.
}

const DT := DuelRules.DT

## --- state: everything step() reads and everything a snapshot carries ------

var frame: int = 0
var phase: Phase = Phase.COUNTDOWN
var phase_time: float = 0.0
var round_index: int = 0
var scores := PackedInt32Array([0, 0])
var rounds_to_win: int = DuelRules.ROUNDS_TO_WIN
var last_round_winner: int = DuelRules.DRAW
var match_winner: int = DuelRules.DRAW

## Set while frames are being replayed after a correction, so the presentation
## layer is not told about things it has already shown.
var replaying := false

## What happened during the last step(). Cleared at the top of every step.
var events: Array[Dictionary] = []

var players: Array[Player] = []
var level: Level

var _arena: AsciiLevel
var _spawns: Array[Vector2] = []
var _scratch := PackedFloat32Array()


## --- construction ----------------------------------------------------------

## Builds the arena and the two duellists. Call once, after the node is in the
## tree (the duellists need their collision shape, which is @onready).
func setup(arena: AsciiLevel, rounds: int = DuelRules.ROUNDS_TO_WIN) -> void:
	_arena = arena
	rounds_to_win = maxi(1, rounds)
	_scratch.resize(Player.DUEL_STATE_FLOATS)

	level = Level.new()
	level.name = "Arena"
	add_child(level)
	level.build(arena)
	# A TileMapLayer creates its collision bodies on a deferred internal update,
	# so for one frame after build() the arena is scenery with nothing solid in
	# it and the duellists fall through the floor. Forcing the update means
	# setup() and the first step() can happen in the same frame — which is what
	# lets a test, a replay and a reconciliation all start immediately.
	level.tilemap.update_internals()

	# The arena carries one spawn mark and the duel mirrors it. That is what
	# makes the two seats provably equal: a symmetric arena cannot be authored
	# with a better corner for one of them, because there is only one corner.
	var a_cell := arena.spawn_point
	var b_cell := Vector2i(arena.cols - 1 - a_cell.x, a_cell.y)
	_spawns = [level.entity_world_position(a_cell), level.entity_world_position(b_cell)]

	var packed := load(DuelRules.PLAYER_SCENE) as PackedScene
	for slot: int in 2:
		var duellist := packed.instantiate() as Player
		duellist.name = "Duellist%d" % slot
		duellist.level = level
		# Stepped by this file, not by the engine; blocks; dies in one cut.
		duellist.duel_driven = true
		duellist.guard_enabled = true
		duellist.kill_on_lethal_hit = true
		# A bare PlayerInput never polls a device: it holds whatever bits were
		# last applied, whether those came from a keyboard or off the wire.
		duellist.input = PlayerInput.new()
		add_child(duellist)
		duellist.duel_isolate_shape()
		players.append(duellist)

	reset_match()


func reset_match() -> void:
	frame = 0
	round_index = 0
	scores = PackedInt32Array([0, 0])
	last_round_winner = DuelRules.DRAW
	match_winner = DuelRules.DRAW
	events.clear()
	_begin_round()


func arena_size() -> Vector2:
	return level.world_size()


func spawn_of(slot: int) -> Vector2:
	return _spawns[slot]


## --- the step --------------------------------------------------------------

## Advance the duel exactly one frame. See the file header: pure in the state
## and the two input snapshots, and must be called inside a physics frame.
func step(bits_a: int, bits_b: int) -> void:
	events.clear()

	# Outside the fight the duellists stand on their marks. Zeroing the input
	# rather than skipping the simulation keeps the step uniform — gravity,
	# landing and a corpse falling off a ledge all still run — and stops a
	# button held through the countdown from firing the instant it ends.
	var fighting := phase == Phase.FIGHTING
	players[DuelRules.SLOT_A].input.apply_bits(bits_a if fighting else 0)
	players[DuelRules.SLOT_B].input.apply_bits(bits_b if fighting else 0)

	players[DuelRules.SLOT_A].simulate(DT)
	players[DuelRules.SLOT_B].simulate(DT)

	if fighting:
		_resolve_swords()
		_resolve_arena()

	_advance_phase()
	frame += 1


## --- combat ----------------------------------------------------------------

## Sword against sword and sword against body.
##
## Both hitboxes are read before anything is applied, so the outcome does not
## depend on which duellist is resolved first — a simultaneous exchange is a
## clash for both of them rather than a kill for whoever happens to be slot A.
func _resolve_swords() -> void:
	var a := players[DuelRules.SLOT_A]
	var b := players[DuelRules.SLOT_B]
	if not (a.is_alive() and b.is_alive()):
		return

	var a_cuts := a.is_swinging() and a.attack_rect().intersects(b.body_rect())
	var b_cuts := b.is_swinging() and b.attack_rect().intersects(a.body_rect())

	if a_cuts and b_cuts:
		var middle := (a.position + b.position) * 0.5
		a.stagger(Player.CLASH_STAGGER, b.position.x)
		b.stagger(Player.CLASH_STAGGER, a.position.x)
		events.append({"kind": "clash", "at": middle})
		if not replaying:
			swords_clashed.emit(middle)
		return

	if a_cuts:
		_resolve_cut(DuelRules.SLOT_A, DuelRules.SLOT_B)
	elif b_cuts:
		_resolve_cut(DuelRules.SLOT_B, DuelRules.SLOT_A)


func _resolve_cut(attacker_slot: int, defender_slot: int) -> void:
	var attacker := players[attacker_slot]
	var defender := players[defender_slot]

	# A raised guard only covers the side it faces. Blocking is a decision
	# about where the danger is, not a button that makes you invulnerable.
	if defender.guard_covers(attacker.position.x):
		var parried := defender.guard_time <= Player.PARRY_WINDOW
		attacker.stagger(
			Player.PARRY_STAGGER if parried else Player.BLOCK_STAGGER, defender.position.x
		)
		defender.absorb_block(attacker.position.x, parried)
		events.append({
			"kind": "parry" if parried else "block",
			"defender": defender_slot, "at": defender.position,
		})
		if not replaying:
			cut_blocked.emit(defender_slot, parried, defender.position)
		return

	defender.take_lethal_hit(attacker.position.x)
	events.append({"kind": "cut", "victim": defender_slot, "at": defender.position})
	if not replaying:
		cut_landed.emit(defender_slot, defender.position)


## Spikes, water, and the long drop past the bottom of the arena.
func _resolve_arena() -> void:
	var below := level.world_size().y + 48.0
	for slot: int in 2:
		var duellist := players[slot]
		if not duellist.is_alive():
			continue
		if level.rect_is_deadly(duellist.body_rect()) or duellist.position.y > below:
			duellist.kill()
			events.append({"kind": "fell", "victim": slot, "at": duellist.position})
			if not replaying:
				cut_landed.emit(slot, duellist.position)


## --- rounds ----------------------------------------------------------------

func _advance_phase() -> void:
	phase_time += DT

	match phase:
		Phase.COUNTDOWN:
			if phase_time >= DuelRules.COUNTDOWN_TIME:
				_set_phase(Phase.FIGHTING)
				if not replaying:
					round_started.emit(round_index)

		Phase.FIGHTING:
			var a_down := not players[DuelRules.SLOT_A].is_alive()
			var b_down := not players[DuelRules.SLOT_B].is_alive()
			if a_down or b_down:
				# Both down on the same frame is a double kill: a draw, and
				# neither duellist is any closer to the match.
				last_round_winner = (
					DuelRules.DRAW if a_down == b_down
					else (DuelRules.SLOT_B if a_down else DuelRules.SLOT_A)
				)
				if last_round_winner != DuelRules.DRAW:
					scores[last_round_winner] += 1
				_set_phase(Phase.ROUND_OVER)
				if not replaying:
					round_ended.emit(last_round_winner)
			elif phase_time >= DuelRules.ROUND_TIME_LIMIT:
				last_round_winner = DuelRules.DRAW
				_set_phase(Phase.ROUND_OVER)
				if not replaying:
					round_ended.emit(DuelRules.DRAW)

		Phase.ROUND_OVER:
			if phase_time >= DuelRules.ROUND_OVER_TIME:
				var decided := _match_winner_or_none()
				if decided != DuelRules.DRAW:
					match_winner = decided
					_set_phase(Phase.MATCH_OVER)
					if not replaying:
						match_ended.emit(match_winner)
				else:
					round_index += 1
					_begin_round()

		Phase.MATCH_OVER:
			pass


func _match_winner_or_none() -> int:
	if scores[DuelRules.SLOT_A] >= rounds_to_win:
		return DuelRules.SLOT_A
	if scores[DuelRules.SLOT_B] >= rounds_to_win:
		return DuelRules.SLOT_B
	return DuelRules.DRAW


func _begin_round() -> void:
	for slot: int in players.size():
		players[slot].duel_reset(_spawns[slot], 1 if slot == DuelRules.SLOT_A else -1)
	_set_phase(Phase.COUNTDOWN)


func _set_phase(next: Phase) -> void:
	phase = next
	phase_time = 0.0


## --- snapshots and the desync checksum -------------------------------------
##
## The duel's own scalars, then both duellists' full state. `read_state` has to
## restore everything `step` reads, which is why Player writes out its private
## timers and its input's press-edge memory too: a replayed frame that forgot
## the coyote window or re-fired a press would never converge on the host.

const HEADER_BYTES := 16
const SNAPSHOT_BYTES := HEADER_BYTES + 2 * Player.DUEL_STATE_FLOATS * 4


func write_state() -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.big_endian = false
	buf.put_u32(frame)
	buf.put_u8(int(phase))
	buf.put_u8(round_index)
	buf.put_u8(scores[DuelRules.SLOT_A])
	buf.put_u8(scores[DuelRules.SLOT_B])
	buf.put_8(last_round_winner)
	buf.put_8(match_winner)
	buf.put_u8(rounds_to_win)
	buf.put_u8(0) # padding, keeps the float block 4-byte aligned
	buf.put_float(phase_time)
	for slot: int in 2:
		players[slot].duel_write_state(_scratch, 0)
		for i: int in Player.DUEL_STATE_FLOATS:
			buf.put_float(_scratch[i])
	return buf.data_array


func read_state(bytes: PackedByteArray) -> bool:
	if bytes.size() < SNAPSHOT_BYTES:
		push_error("duel snapshot too short: %d of %d" % [bytes.size(), SNAPSHOT_BYTES])
		return false
	var buf := StreamPeerBuffer.new()
	buf.big_endian = false
	buf.data_array = bytes

	frame = buf.get_u32()
	phase = buf.get_u8() as Phase
	round_index = buf.get_u8()
	scores[DuelRules.SLOT_A] = buf.get_u8()
	scores[DuelRules.SLOT_B] = buf.get_u8()
	last_round_winner = buf.get_8()
	match_winner = buf.get_8()
	rounds_to_win = buf.get_u8()
	buf.get_u8()
	phase_time = buf.get_float()
	for slot: int in 2:
		for i: int in Player.DUEL_STATE_FLOATS:
			_scratch[i] = buf.get_float()
		players[slot].duel_read_state(_scratch, 0)
	return true


## A cheap fingerprint of the whole duel, for comparing two simulations.
##
## Quantised before hashing: a float that differs in its last bit is not a
## desync, it is noise, and a checksum that fired on noise would be ignored
## within a minute of play. 1/256 of a pixel and of a second is far finer than
## anything that could be seen, and still absorbs that noise.
func checksum() -> int:
	var words := PackedInt32Array()
	words.append(frame)
	words.append(int(phase))
	words.append(_quantise(phase_time))
	words.append(round_index)
	words.append(scores[DuelRules.SLOT_A])
	words.append(scores[DuelRules.SLOT_B])
	words.append(last_round_winner)
	words.append(match_winner)
	for slot: int in 2:
		players[slot].duel_write_state(_scratch, 0)
		for i: int in Player.DUEL_STATE_FLOATS:
			words.append(_quantise(_scratch[i]))
	return fnv1a(words)


const QUANTISE := 256.0


static func _quantise(value: float) -> int:
	return int(roundf(value * QUANTISE))


## FNV-1a over the little-endian bytes of each word. Chosen for being four
## lines long and identical on every platform, not for its collision behaviour.
static func fnv1a(words: PackedInt32Array) -> int:
	var hash_value := 0x811c9dc5
	for word: int in words:
		for shift: int in [0, 8, 16, 24]:
			hash_value ^= (word >> shift) & 0xff
			hash_value = (hash_value * 16777619) & 0xffffffff
	return hash_value
