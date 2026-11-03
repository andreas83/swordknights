class_name LocalInput
extends PlayerInput
## Reads the Godot input map. The action suffix lets a second local player use
## a parallel set of bindings ("move_left_p2" and so on) without duplicating
## any logic.
##
## The reading itself is PlayerInput.bits_from_actions(), so a local player, a
## duel seat and a remote peer cannot drift apart over which key is which bit —
## there is one table and it is there.

var suffix: String = ""


func _init(action_suffix: String = "") -> void:
	suffix = action_suffix


func poll() -> void:
	apply_bits(bits_from_actions(suffix))
