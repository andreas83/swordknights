class_name PlayerInput
extends RefCounted
## One frame of intent, decoupled from where it came from.
##
## The character never asks "which device?" — it reads these fields. A local
## device, a replay, an AI or a remote peer all drive the same code path, which
## is what makes the simulation reusable for lockstep netplay and for headless
## tests.
##
## The bitmask encoding is the wire format: eight bits per player per frame.
##
## THE DUEL'S SEVEN BUTTONS. Nidhogg needs left, right, up, down, jump, attack
## and throw — seven, and the byte has eight bits, so no widening is needed and
## none is allowed: the frame stays one byte because that is what the wire,
## the replays and the press-edge memory are built on.
##
## Bit 7 is the one that changed hands. It carried the duel's GUARD button when
## the duel had a guard state; the fighter replaced that state with the three
## sword stances, which are driven by up and down and cost no bit at all, so
## bit 7 now carries THROW. `BIT_GUARD`, `guard` and `just_pressed_guard`
## remain as aliases of the same bit, because scripts/player/player.gd still
## has the old guard state and the pre-fighter duel still drives it; retiring
## the names is a change to those files, not to this one.

const BIT_LEFT := 1 << 0
const BIT_RIGHT := 1 << 1
const BIT_UP := 1 << 2
const BIT_DOWN := 1 << 3
const BIT_JUMP := 1 << 4
const BIT_ATTACK := 1 << 5
const BIT_WALK := 1 << 6
## The eighth and last bit: let go of the sword.
const BIT_THROW := 1 << 7
## Deprecated alias of BIT_THROW. See the class docstring.
const BIT_GUARD := BIT_THROW

var left := false
var right := false
var up := false
var down := false
var jump := false
var attack := false
var walk := false
var throw := false

var just_pressed_jump := false
var just_pressed_attack := false
## A throw is a press edge: holding the button does not keep throwing swords.
var just_pressed_throw := false

var _previous_bits := 0


var axis_x: int:
	get:
		return (1 if right else 0) - (1 if left else 0)

var axis_y: int:
	get:
		return (1 if down else 0) - (1 if up else 0)

## Deprecated aliases of `throw` and `just_pressed_throw`, on the same bit.
var guard: bool:
	get:
		return throw

var just_pressed_guard: bool:
	get:
		return just_pressed_throw


## Refresh from the source. The base class holds whatever was last applied.
func poll() -> void:
	pass


func to_bits() -> int:
	var bits := 0
	if left: bits |= BIT_LEFT
	if right: bits |= BIT_RIGHT
	if up: bits |= BIT_UP
	if down: bits |= BIT_DOWN
	if jump: bits |= BIT_JUMP
	if attack: bits |= BIT_ATTACK
	if walk: bits |= BIT_WALK
	if throw: bits |= BIT_THROW
	return bits


## Applies a wire frame and derives the press edges from the previous one.
func apply_bits(bits: int) -> void:
	left = bits & BIT_LEFT != 0
	right = bits & BIT_RIGHT != 0
	up = bits & BIT_UP != 0
	down = bits & BIT_DOWN != 0
	jump = bits & BIT_JUMP != 0
	attack = bits & BIT_ATTACK != 0
	walk = bits & BIT_WALK != 0
	throw = bits & BIT_THROW != 0

	just_pressed_jump = jump and (_previous_bits & BIT_JUMP) == 0
	just_pressed_attack = attack and (_previous_bits & BIT_ATTACK) == 0
	just_pressed_throw = throw and (_previous_bits & BIT_THROW) == 0
	_previous_bits = bits


func clear() -> void:
	apply_bits(0)
	_previous_bits = 0


## --- duel -----------------------------------------------------------------
##
## The duel rewinds and replays frames, so the edge-detection memory has to be
## part of the saved state — otherwise a rolled-back frame would re-fire a press
## that already happened. These two expose it without making the field public.

func previous_bits() -> int:
	return _previous_bits


func restore_previous_bits(bits: int) -> void:
	_previous_bits = bits


## Reads one frame of intent straight off the input map for a given binding set.
##
## LocalInput keeps its own copy for the adventure actions; this is the version
## the duel uses, because it also reads the eighth bit and because it has to
## produce the whole frame in one shot (applying bits twice would eat the press
## edges). `suffix` selects the binding set: "" for the shared actions, "_p1"
## and "_p2" for the two seats on one keyboard.
##
## Bit 7 is read from BOTH bindings: `throw`, which is what the fighter wants,
## and `guard`, which the pre-fighter duel still binds. One bit, either key.
static func bits_from_actions(suffix: String = "") -> int:
	var bits := 0
	if Input.is_action_pressed("move_left" + suffix): bits |= BIT_LEFT
	if Input.is_action_pressed("move_right" + suffix): bits |= BIT_RIGHT
	if Input.is_action_pressed("move_up" + suffix): bits |= BIT_UP
	if Input.is_action_pressed("move_down" + suffix): bits |= BIT_DOWN
	if Input.is_action_pressed("jump" + suffix): bits |= BIT_JUMP
	if Input.is_action_pressed("attack" + suffix): bits |= BIT_ATTACK
	if Input.is_action_pressed("walk" + suffix): bits |= BIT_WALK
	if _pressed_any(["throw" + suffix, "guard" + suffix]): bits |= BIT_THROW
	return bits


## Any of these actions, skipping the ones this build has no binding for: a
## project.godot that predates the throw binding must not spam errors.
static func _pressed_any(actions: Array) -> bool:
	for action: String in actions:
		if InputMap.has_action(action) and Input.is_action_pressed(action):
			return true
	return false
