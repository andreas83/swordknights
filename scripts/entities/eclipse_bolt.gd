class_name EclipseBolt
extends FoeProjectile
## A sunbolt the King throws in his second phase: the kept sun's light, caught
## on the polished face of his disc and thrown along the floor at chest height
## (docs/campaign.md, "The Eclipse -- the boss").
##
## Everything that makes it fair is FoeProjectile's: it is a danger until a
## parry turns it, then it is the prince's, and the first foe it meets -- the
## King, whose disc faces the sun and not the prince -- takes it as
## `Foe.Blow.SHOT`. A backstep does not let it by; a crouch goes under it, and
## so does nothing but time. What is the King's is its size and its look, the
## Glassbearer's numbers: 8 x 2, chest height, at whatever speed the volley
## throws it.
##
## Chapter IV's Glassbearer throws a sunbolt of its own (scripts/entities/
## sunbolt.gd, built alongside this one). The two are the same light and may
## become one class; they were kept apart so that neither chapter waited on
## the other.
##
## ## The look
##
## A streak of the sun's own ramp along its flight -- PAPER at the head, then
## LIGHT_SOFT, then LIGHT -- and a one-pixel MID tail that steps behind it on a
## 12 fps clock like a torch's flame, so it reads as fire and not as a bar.
## Turned by a parry it is the prince's: the head goes to the other end, and a
## steel edge runs along it, the one cold colour, which is the blade's. A
## pixel of halo round it and a fading tail behind are drawn and never
## refereed: alone in the dark at 8 x 2 it is a speck on a phone.

## Its sound on stone, through Game's front door like a foe's.
signal cue(voice: StringName, options: Dictionary)

const LENGTH := 8.0
const THICKNESS := 2.0

var _time := 0.0


func _init() -> void:
	size = Vector2(LENGTH, THICKNESS)


func _physics_process(delta: float) -> void:
	_time += delta
	var was := is_spent()
	super(delta)
	if not was and is_spent() and level != null and level.is_solid_at(global_position):
		cue.emit(&"sword_hit", {"pitch": 1.9, "volume_db": -12.0})
	queue_redraw()


func _draw() -> void:
	var dir := signf(velocity.x) if velocity.x != 0.0 else 1.0
	var half := LENGTH * 0.5
	var top := -THICKNESS * 0.5
	# Head to tail along the flight: the brightest end leads.
	draw_rect(Rect2(-half, top, LENGTH, THICKNESS), Palette.LIGHT)
	var head := half - 3.0 if dir > 0.0 else -half
	draw_rect(Rect2(head, top, 3.0, THICKNESS), Palette.PAPER)
	var mid := head - 2.0 * dir if dir > 0.0 else head + 3.0
	draw_rect(Rect2(mid, top, 2.0, THICKNESS), Palette.LIGHT_SOFT)
	var flicker := int(_time * 12.0) % 2
	# A flat halo a pixel round it and a two-step tail behind: 8 x 2 is the
	# Glassbearer's size and the size it hits at, and alone at night on a phone
	# it is a speck. The halo is drawn, never refereed.
	draw_rect(Rect2(-half - 1.0, top - 1.0, LENGTH + 2.0, THICKNESS + 2.0),
		Palette.with_alpha(Palette.LIGHT_SOFT, 0.35))
	var trail := -half - 6.0 if dir > 0.0 else half
	draw_rect(Rect2(trail, top, 6.0, THICKNESS), Palette.with_alpha(Palette.LIGHT, 0.45))
	var tail := -half - 1.0 - float(flicker) if dir > 0.0 else half + float(flicker)
	draw_rect(Rect2(tail, top + 0.5, 1.0, 1.0), Palette.MID)
	if reflected:
		draw_rect(Rect2(-half, top - 1.0, LENGTH, 1.0), Palette.STEEL)
