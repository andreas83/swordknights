class_name DuelCpu
extends RefCounted
## A seat played by the computer: a brain and the eyes it sees through.
##
## The only object a scene or a test drives the computer opponent through, and
## it keeps the order that makes the opponent honest:
##
##     var cpu_bits := cpu.next_bits()   # decided from what has been seen
##     fight.step(human_bits, cpu_bits)  # then the frame happens
##     cpu.watch(fight)                  # and is seen
##
## next_bits() hands the brain a DuelView built from frames already stepped, so
## the human's buttons for the frame being decided are not anywhere the brain
## could look. watch() is the only thing here that touches the match, and what
## it keeps is a copy of what is on the screen (DuelEyes).
##
## Runs in _physics_process at the fixed 60 Hz like everything else in the
## duel: one call each per simulation step, never per rendered frame.

var seat := 1
var brain: DuelBrain
var _eyes := DuelEyes.new()


func _init(at_seat: int = 1, level: DuelBrain.Difficulty = DuelBrain.Difficulty.MEDIUM,
		seed_value: int = 0) -> void:
	seat = at_seat
	brain = DuelBrain.new(at_seat, level, seed_value)


## The bits for the next frame, from what has been seen of the frames before it.
func next_bits() -> int:
	return brain.decide(_eyes.view(seat, brain.reaction()))


## Look at the frame just stepped. Call it after every step, and once after the
## match is built or reset, so the first decision has something to go on.
func watch(fight: DuelMatch) -> void:
	_eyes.record(fight)


## A rematch: nothing seen, nothing learned, the dice reseeded.
func reset(seed_value: int) -> void:
	_eyes.forget()
	brain.reset(seed_value)
