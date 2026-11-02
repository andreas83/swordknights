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

var left := false
var right := false
var up := false
var down := false
var jump := false
var attack := false
var walk := false

var just_pressed_jump := false
var just_pressed_attack := false

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

	just_pressed_jump = jump and (_previous_bits & BIT_JUMP) == 0
	just_pressed_attack = attack and (_previous_bits & BIT_ATTACK) == 0
	_previous_bits = bits


func clear() -> void:
	apply_bits(0)
	_previous_bits = 0
