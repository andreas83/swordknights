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

const BIT_LEFT := 1 << 0
const BIT_RIGHT := 1 << 1
const BIT_UP := 1 << 2
const BIT_DOWN := 1 << 3
const BIT_JUMP := 1 << 4
const BIT_ATTACK := 1 << 5
const BIT_WALK := 1 << 6
## --- duel (additive) --- the eighth and last bit: raise the sword to block.
const BIT_GUARD := 1 << 7

var left := false
var right := false
var up := false
var down := false
var jump := false
var attack := false
var walk := false
## --- duel (additive) ---
var guard := false

var just_pressed_jump := false
var just_pressed_attack := false
## --- duel (additive) --- a parry is a press edge, so the duel needs this one.
var just_pressed_guard := false

var _previous_bits := 0


var axis_x: int:
	get:
		return (1 if right else 0) - (1 if left else 0)

var axis_y: int:
	get:
		return (1 if down else 0) - (1 if up else 0)


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
	if guard: bits |= BIT_GUARD # --- duel (additive) ---
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
	guard = bits & BIT_GUARD != 0 # --- duel (additive) ---

	just_pressed_jump = jump and (_previous_bits & BIT_JUMP) == 0
	just_pressed_attack = attack and (_previous_bits & BIT_ATTACK) == 0
	just_pressed_guard = guard and (_previous_bits & BIT_GUARD) == 0 # --- duel ---
	_previous_bits = bits


func clear() -> void:
	apply_bits(0)
	_previous_bits = 0


## --- duel (additive) ------------------------------------------------------
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
## the duel uses, because it also reads the guard binding and because it has to
## produce the whole frame in one shot (applying bits twice would eat the press
## edges). `suffix` selects the binding set: "" for the shared actions, "_p1"
## and "_p2" for the two seats on one keyboard.
static func bits_from_actions(suffix: String = "") -> int:
	var bits := 0
	if Input.is_action_pressed("move_left" + suffix): bits |= BIT_LEFT
	if Input.is_action_pressed("move_right" + suffix): bits |= BIT_RIGHT
	if Input.is_action_pressed("move_up" + suffix): bits |= BIT_UP
	if Input.is_action_pressed("move_down" + suffix): bits |= BIT_DOWN
	if Input.is_action_pressed("jump" + suffix): bits |= BIT_JUMP
	if Input.is_action_pressed("attack" + suffix): bits |= BIT_ATTACK
	if Input.is_action_pressed("walk" + suffix): bits |= BIT_WALK
	if Input.is_action_pressed("guard" + suffix): bits |= BIT_GUARD
	return bits
