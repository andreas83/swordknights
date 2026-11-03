class_name DuelSim
extends Node2D
## The surface a networked duel is driven through, and nothing else.
##
## `scripts/net/session.gd` does not care whether it is reconciling a
## round-based duel (`scripts/duel/duel.gd`) or the tug-of-war match
## (`scripts/duel/match.gd`). It needs exactly six things, and they are the six
## below. Pulling them out into a base class is what lets the two simulations
## coexist during the changeover instead of one of them having to win first.
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
##
## `replaying` is the other half of purity: a reconciled frame must not
## re-trigger a sound, a screen shake or a blood splatter that already played,
## so subclasses record what happened in `events` and suppress their signals
## while it is set.

## Advances one frame. See the class docstring: pure, and inside a physics frame.
var frame: int = 0

## Set while frames are being replayed after a correction, so the presentation
## layer is not told about things it has already shown.
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


## How many bytes write_state() produces. The session does not need it; the
## tests and docs/duel-match.md do, because the snapshot is the bandwidth.
func snapshot_bytes() -> int:
	return write_state().size()


## The geometry hash exchanged in the handshake. Two peers whose levels differ
## must not start a match.
func arena_identity() -> int:
	return 0


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
## Lives here so both simulations and NetProtocol.arena_hash share one.
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
