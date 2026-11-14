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
## One tone below SHADOW_DEEP: the darkest a lit-world SURFACE may go, so that
## stone in deep shade stays crimson. INK is for voids, joints and silhouettes.
## tools/generate_tiles_png.py and tools/generate_icon.py carry the same value.
const SHADOW_PIT := Color("4a0d1e")
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

## Blood, and nothing else: the fifth rationed accent (docs/art-direction.md,
## "Colour discipline"). The architecture is crimson, so a crimson death
## vanished into it. This ramp is set apart by chroma, the one axis nothing
## else in the palette spends: a scarlet past the most saturated stone, at the
## hue of red rather than crimson's pink. Its tones still sit close in
## lightness to one of the stone's, so every mark carries two: the body reads
## on gold, dark stone and the night, and the dried tone reads where the body
## is weakest, on mid crimson. The numbers are in docs/art-direction.md and
## tests/unit/test_blood_ramp.gd holds them, and holds that only
## scripts/duel/gore.gd and scripts/world/bloodshed.gd ever draw with it.
const BLOOD := Color("c80810")
## Old blood: a pool after it has dried, the heart of a stain. Darker than
## SHADOW_PIT and turned toward brown, away from the stone's pink.
const BLOOD_DRIED := Color("3a0406")
## The wet glint: a pixel on a flying drop and the sunward edge of a fresh
## pool. A highlight only -- never a fill.
const BLOOD_WET := Color("ff6a55")

## The princess's concept colours: royal blue for cloth and umber for hair and
## leather, the sixth and seventh rationed accents (docs/art-direction.md,
## "Colour discipline"). The owner's concept sheet for the 3D princess wears
## both and the duotone has neither. Each is a ramp of three in the same
## lit/shade/back relationship as CLOTH, CLOTH_DARK and SHADOW_DEEP, and each
## is for what a figure wears, never for stone and never for a team: blue sits
## fifty degrees of hue from player two's teal, and a duel re-dresses every
## robe in its seat's colour whatever was chosen (FighterArt.dress).
const ROYAL := Color("3a6ccc")
const ROYAL_DARK := Color("244a99")
const ROYAL_DEEP := Color("16306a")
const UMBER := Color("8a5532")
const UMBER_DARK := Color("5a341f")
const UMBER_DEEP := Color("33200f")
## The princess's blade: a blue-white steel and the glow round it. The blade
## keeps steel's lightness, so a sword still reads as a sword first.
const ROYAL_STEEL := Color("a9c4f5")
const ROYAL_GLOW := Color("6fa2ff")

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
## The same bands at the last room's dusk: ink overhead, fire at the horizon.
const DUSK_SKY_STOPS: Array[Color] = [INK, INK, SHADOW_DEEP, SHADOW_WARM]
## And at night: ink all the way down to the last of the glow on the horizon
## (TimeOfDay, docs/campaign.md "Time of day").
const NIGHT_SKY_STOPS: Array[Color] = [INK, INK, INK, SHADOW_PIT]


static func with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)
