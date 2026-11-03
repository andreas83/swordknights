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
##    receive it, and otherwise left alone. give_world() reads the value back,
##    because a typed property refuses a value of the wrong type in silence.
##
## 4. A referee. The fighter resolves its own frame; it does not resolve two
##    fighters against each other, and it does not die to spikes on its own.
##    referee() does both, after both fighters have stepped.
##
## The contract calls still go through call() and get(), because the match's
## own tests run on the placeholder in scripts/duel/match_stub_fighter.gd and
## the interface is what both fighters share. referee() is the exception and
## types the real Fighter directly: combat is defined on that class.

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
##
## Returns false if the fighter has a place for the world and refused it.
## Object.set() on a typed property silently does nothing when the type does
## not match, and the real fighter's first wiring failed exactly that way: its
## world stayed null and nothing said so. Reading the value back is the check.
func give_world(strip: ZoneStrip) -> bool:
	for property: String in WORLD_PROPERTIES:
		if property in node:
			node.set(property, strip)
			return node.get(property) == strip
	return true


func setup(profile: Resource) -> void:
	node.call("setup", slot, profile)


func on_died(handler: Callable) -> void:
	node.connect("died", handler)


## Passes the match's `replaying` on to a fighter that has presentation signals
## of its own (the real one: disarm, clash, throw, knockdown, catch). The
## placeholder has none and no such property, which is not an error. Set by
## name, so read back: a fighter that kept ringing through a replay would be
## exactly the bug the flag exists to prevent.
func set_replaying(on: bool) -> bool:
	if not ("replaying" in node):
		return true
	node.set("replaying", on)
	return bool(node.get("replaying")) == on


func simulate(delta: float) -> void:
	node.call("simulate", delta)


## Blade against blade, and body against the ground, for one frame.
##
## The order is the fighter's own, from scripts/duel/fighter.gd: both inputs
## applied, both fighters simulated, then this. Combat reads every hitbox before
## it applies anything, so the outcome does not depend on which seat is A.
## Hazards come after the blades, so a fighter cut down over the spikes is
## credited to the blade, not to the spikes.
##
## The placeholder resolves its own kills and its own hazards, so for it this
## does nothing. That is the one place this seam still branches on which
## fighter it holds.
static func referee(a: DuelSeat, b: DuelSeat, strip: ZoneStrip) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var first := a.node as Fighter
	var second := b.node as Fighter
	if first == null or second == null:
		return events
	events = DuelCombat.resolve(first, second)
	var floor_of_world := strip.world_size().y
	for fighter: Fighter in [first, second]:
		if not fighter.is_alive():
			continue
		if strip.rect_is_deadly(fighter.hurt_rect()) or fighter.position.y > floor_of_world:
			fighter.kill(-1)
	return events


## Whether the fighter supplies its own checksum words. The real fighter does,
## because its state mixes doubles and integers; the placeholder does not.
func hashes_itself() -> bool:
	return node.has_method("checksum_into")


func checksum_into(words: PackedInt32Array) -> void:
	node.call("checksum_into", words)


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


## Kills the fighter, credited to `killer` (-1 for a hazard). The real fighter
## calls it kill(); the placeholder calls it slay().
func kill(killer: int) -> void:
	node.call("kill" if node.has_method("kill") else "slay", killer)


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
