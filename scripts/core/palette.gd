class_name Palette
extends RefCounted
## The duotone palette taken from the concept art.
##
## Everything in the world is either lit gold or dropped into crimson shadow,
## with a small set of accents (water, foliage, cloth, steel) allowed to break
## the two-tone rule. The look comes from flat planes of colour and hard shadow
## edges, so keep the ramp small on purpose.
##
## SURFACE names colours by how they face the light rather than by hue —
## swapping that table re-lights the whole game.

const INK := Color("2b0a14")
const SHADOW_DEEP := Color("7a1230")
const SHADOW := Color("b32142")
const SHADOW_WARM := Color("d8452c")
const MID := Color("e8702a")
const LIGHT_WARM := Color("f2a829")
const LIGHT := Color("f7ce2e")
const LIGHT_SOFT := Color("ffe873")
const PAPER := Color("fff4c2")

const WATER := Color("46c7b0")
const WATER_DEEP := Color("1f8f86")
## Player two's cloth in shade and its cloak: the same two steps down from
## WATER_DEEP that CLOTH_DARK and SHADOW_DEEP are from CLOTH. Teal is water's and
## player two's, nobody else's (docs/art-direction.md).
const WATER_SHADE := Color("12605d")
const WATER_NIGHT := Color("0b3a3c")
const FOLIAGE := Color("5fbf7a")
const CLOTH := Color("c6354f")
const CLOTH_DARK := Color("8e1f38")
const STEEL := Color("8c8fa3")
const STEEL_DARK := Color("5a5d70")

## Surfaces, named by how they face the sun.
const SURFACE_LIT := LIGHT
const SURFACE_LIT_SOFT := LIGHT_SOFT
const SURFACE_SHADE := SHADOW
const SURFACE_SHADE_DEEP := SHADOW_DEEP
const SURFACE_BEVEL := LIGHT_WARM
const SURFACE_EDGE := SHADOW_WARM

## Sky gradient, top to bottom.
const SKY_STOPS: Array[Color] = [SHADOW_DEEP, SHADOW, MID, LIGHT_WARM]
const SKY_OFFSETS: Array[float] = [0.0, 0.45, 0.78, 1.0]


static func with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)
