class_name DuelSim
extends Node2D
## The surface a networked duel is driven through, and nothing else.
##
## `scripts/net/session.gd` reconciles the tug-of-war match
## (`scripts/duel/match.gd`), and needs exactly six things from it, the six
## below, plus the bracket it puts around the frames it steps again. They
## were pulled out into a base class so the round duel the session was first
## written for and the match could coexist during the changeover;
## the round duel is retired, and the seam is kept because it is the whole of
## what the session is allowed to know about a duel.
##
## THE CONTRACT, which every subclass owes the session
##
##   step(bits_a, bits_b)  one frame, a pure function of this object's state and
##                         those two bytes. No wall clock, no Input singleton,
##                         no randomness, no reading of the real frame delta.
##                         Must be called from inside a physics frame.
##   write_state()         every byte `step` reads, so a frame can be replayed.
##   read_state(bytes)     the exact inverse.
##   checksum()            a quantised fingerprint of the same state.
##   arena_identity()      a hash of the geometry both peers must agree on,
##                         checked during the handshake so a mismatched level
##                         is refused in the lobby instead of surfacing as an
##                         unexplained desync in the third zone.
##   match_length()        the one integer the host dictates about the shape of
##                         the match — rounds to win, or zones in the strip.
##   arena_id(), set_arena(id)
##                         the arena's name, which the host dictates too: the
##                         guest loads the strip the host chose before the
##                         hashes are compared.
##
## REPLAYS, the other half of purity
##
##   begin_replay()        the session is about to step frames it has stepped
##                         before -- a rewind to the host's state and a replay
##                         of everything since. Nothing stepped from here on
##                         may ring a sound, shake the screen or spill blood.
##   end_replay()          the correction is over. The subclass now reconciles
##                         what it has shown with what its corrected history
##                         holds, once, in _replay_ended().
##
## NetSession brackets every frame it re-steps this way, and steps nothing else
## inside the bracket. A frame stepped inside it is still the same frame: the
## flag may silence signals and nothing more. It is not in write_state(), not in
## the checksum, and no step may read it to decide anything that is.

## Advances one frame. See the class docstring: pure, and inside a physics frame.
var frame: int = 0

## Set between begin_replay() and end_replay(). Read by the presentation half
## of a step; never by the simulation half.
var replaying := false

## What happened during the last step(). Cleared at the top of every step.
var events: Array[Dictionary] = []


func step(_bits_a: int, _bits_b: int) -> void:
	push_error("DuelSim.step is abstract")


func write_state() -> PackedByteArray:
	push_error("DuelSim.write_state is abstract")
	return PackedByteArray()


func read_state(_bytes: PackedByteArray) -> bool:
	push_error("DuelSim.read_state is abstract")
	return false


func checksum() -> int:
	push_error("DuelSim.checksum is abstract")
	return 0


func reset_match() -> void:
	push_error("DuelSim.reset_match is abstract")


## The session is about to step frames again. See the class docstring.
func begin_replay() -> void:
	replaying = true


## The re-stepping is over. Concrete, so a stand-in duel need not care; a duel
## that presents anything settles it in _replay_ended().
func end_replay() -> void:
	replaying = false
	_replay_ended()


func _replay_ended() -> void:
	pass


## How many bytes write_state() produces. The session does not need it; the
## tests and docs/duel-match.md do, because the snapshot is the bandwidth.
func snapshot_bytes() -> int:
	return write_state().size()


## The geometry hash exchanged in the handshake. Two peers whose levels differ
## must not start a match.
func arena_identity() -> int:
	return 0


## The name of the arena the host plays, carried in its WELCOME so the guest
## can load the same one. Empty for a duel with only one arena.
func arena_id() -> String:
	return ""


## Applied by the guest when the host's WELCOME names an arena: put this duel
## on it, or return false if this build has no such arena, which fails the
## handshake in the lobby with the arena's name in the sentence.
func set_arena(id: String) -> bool:
	return id == arena_id()


## The host's one dictate about the match's shape.
func match_length() -> int:
	return 1


## Applied by the client when the host's WELCOME names a different length.
## Returns false if this peer cannot play a match of that shape, which fails
## the handshake rather than desyncing later.
func set_match_length(_length: int) -> bool:
	return true


## FNV-1a over the little-endian bytes of each word. Chosen for being four
## lines long and identical on every platform, not for its collision behaviour.
## Lives here so the match, the strip and NetProtocol.arena_hash share one.
static func fnv1a(words: PackedInt32Array) -> int:
	var hash_value := 0x811c9dc5
	for word: int in words:
		for shift: int in [0, 8, 16, 24]:
			hash_value ^= (word >> shift) & 0xff
			hash_value = (hash_value * 16777619) & 0xffffffff
	return hash_value


const QUANTISE := 256.0


## 1/256 of a pixel and of a second: finer than anything that could be seen,
## and still coarse enough to absorb last-bit float noise, which is not a
## desync and must not be reported as one.
static func quantise(value: float) -> int:
	return int(roundf(value * QUANTISE))
