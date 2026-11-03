class_name DuelSeat
extends RefCounted
## One seat of the match, and the ONLY place that touches a fighter.
##
## The match owns the match; the fighter owns the fighter. This file is the seam
## between them, so that scripts/duel/match.gd reads as ordinary typed code and
## every assumption about the other half of the duel is in one thirty-line
## place that can be checked against the agreed interface at a glance.
##
## THE AGREED INTERFACE
##     signal died(victim_id: int, killer_id: int)   # killer_id -1 for a hazard
##     func setup(id: int, profile: Resource) -> void
##     func respawn_at(position: Vector2, facing: int) -> void
##     func is_alive() -> bool
##     func write_state(into: PackedByteArray, at: int) -> void
##     func read_state(from: PackedByteArray, at: int) -> void
##     static func state_bytes() -> int
##     var input: PlayerInput
##
## WHAT THE MATCH NEEDS ON TOP OF IT, and why
##
## 1. `simulate(delta)` — advance the fighter exactly one frame on the input
##    already applied. Not optional: the whole netplay design rests on one
##    frame being a function the match calls, which is what lets a mispredicted
##    frame be replayed. If the fighter stepped itself from _physics_process
##    the match could neither replay nor reconcile. `died` must be emitted
##    synchronously inside it, not deferred, for the same reason.
##
## 2. The fighter's position, for the leader's position in the respawn
##    algorithm, for the window's trailing edge, and for the camera. Read
##    through Node2D, not through the fighter: `position`, feet at the origin,
##    as every other character in this project has it. `body_rect()` would be
##    better and is asked for in the report.
##
## 3. Somewhere to put the world. The interface has no way to hand a fighter
##    the level it is standing in, and a fighter needs one for hazards and
##    ladders at least. Injected by name if the fighter has somewhere to
##    receive it, and otherwise left alone — a fighter that gets its collision
##    from the tilemap in the scene needs nothing from us.
##
## Everything goes through call() and get() on purpose. The real Fighter class
## does not exist on this branch, so there is nothing to type against; writing
## the reflection out makes the contract visible instead of pretending to a
## type-safety that is not there. At merge these become direct calls.

## Where a fighter will accept the world, in the order tried.
const WORLD_PROPERTIES: Array[String] = ["strip", "level", "world"]

var slot: int = 0
var node: Node2D


func bind(at_slot: int, fighter: Node2D) -> void:
	slot = at_slot
	node = fighter


## True if this fighter answers the whole interface. Checked once, at build, so
## a fighter that is missing a method says so there rather than as a null
## halfway through a match.
func is_complete() -> bool:
	if node == null:
		return false
	for method: String in [
		"setup", "respawn_at", "is_alive", "write_state", "read_state",
		"state_bytes", "simulate",
	]:
		if not node.has_method(method):
			return false
	return node.has_signal("died") and ("input" in node)


func missing() -> String:
	if node == null:
		return "no fighter"
	var gaps := PackedStringArray()
	for method: String in [
		"setup", "respawn_at", "is_alive", "write_state", "read_state",
		"state_bytes", "simulate",
	]:
		if not node.has_method(method):
			gaps.append(method + "()")
	if not node.has_signal("died"):
		gaps.append("died signal")
	if not ("input" in node):
		gaps.append("input")
	return ", ".join(gaps)


## Hands the fighter the strip, if it has anywhere to put it. See note 3.
func give_world(strip: ZoneStrip) -> void:
	for property: String in WORLD_PROPERTIES:
		if property in node:
			node.set(property, strip)
			return


func setup(profile: Resource) -> void:
	node.call("setup", slot, profile)


func on_died(handler: Callable) -> void:
	node.connect("died", handler)


func simulate(delta: float) -> void:
	node.call("simulate", delta)


func is_alive() -> bool:
	return bool(node.call("is_alive"))


func input() -> PlayerInput:
	return node.get("input") as PlayerInput


func apply_bits(bits: int) -> void:
	var intent := input()
	if intent != null:
		intent.apply_bits(bits)


## Feet, in strip coordinates.
func position() -> Vector2:
	return node.position


func set_x(x: float) -> void:
	node.position.x = x


func set_position(at: Vector2) -> void:
	node.position = at


func respawn_at(at: Vector2, facing: int) -> void:
	node.call("respawn_at", at, facing)


## Bytes this fighter's state occupies. Must be a whole number of float64s: the
## checksum quantises the block to 1/256 before hashing it, exactly as the round
## duel does, because a float that differs in its last bit is noise and a
## checksum that fired on noise would be ignored within a minute of play.
func state_bytes() -> int:
	return int(node.call("state_bytes"))


func write_state(into: PackedByteArray, at: int) -> void:
	node.call("write_state", into, at)


func read_state(from: PackedByteArray, at: int) -> void:
	node.call("read_state", from, at)
