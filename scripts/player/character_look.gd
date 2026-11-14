class_name CharacterLook
extends RefCounted
## One player's look: which figure, and which few palette colours it wears.
##
## Purely presentation. A look changes what PlayerArt draws and nothing that
## the body, the hitbox, the tuning or the networked simulation can see --
## both figures stand on the same rig, so the heroine is exactly as tall, as
## wide and as long in the reach as the prince. Online, the ids travel once in
## the handshake so the other phone can draw them too, and go no further than
## its scene (scripts/net/protocol.gd).
##
## ## Every option is a Palette colour
##
## There is no colour picker, on purpose. The art direction is a duotone lit by
## one low sun (docs/art-direction.md), and a figure that pops against gold and
## crimson terrain needs four tones in a fixed relationship: lit cloth, shade
## cloth, an ink edge and a darker plane behind. So an option is a whole ramp
## of palette steps that already stand in that relationship, not a hue.
##
## The skin and hair ramps are steps of the same gold-to-crimson scale the
## world is built from. A face under this sun is gold or ember like every
## other surface; a "natural" skin tone imported from outside the palette would
## be the one thing in the frame that is not lit by it.
##
## ## The duel's two seats
##
## Teal is player two's and nobody else's. In a duel the robe's three planes
## always take the seat's team colour (FighterArt.seat), whatever outfit was
## chosen -- the outfit row is the adventure's. Every other option is drawn
## from colours that belong to *neither* team, so a customised seat one can
## never carry sea-green and a customised seat two can never carry crimson.
## tests/unit/test_duel_seats_distinct.gd walks every look to hold that.
##
## On disk a look is a set of ids rather than indices (see Wardrobe), so the
## lists below may be reordered or extended without changing anyone's choice.

enum Figure { PRINCE, HEROINE, STICK, PRINCESS }

## The prince and the heroine are drawn in flat planes; STICK is the pose with
## the clothes taken off (StickCostume); PRINCESS is a 3D warrior princess
## rendered onto the same rig (PrincessCostume). All four stand on one skeleton.
const FIGURES: Array[Dictionary] = [
	{"id": "prince", "name": "PRINCE"},
	{"id": "heroine", "name": "HEROINE"},
	{"id": "stick", "name": "STICK"},
	{"id": "princess", "name": "PRINCESS",
		"defaults": {"outfit": "royal", "hair": "brown", "skin": "fair"}},
]

## The robe or tunic: lit plane, shade plane, and the darker plane behind (the
## prince's cloak; the heroine's legs). The adventure's choice; the duel swaps
## in the seat's team colour.
const OUTFITS: Array[Dictionary] = [
	{"id": "crimson", "name": "CRIMSON",
		"cloth": Palette.CLOTH, "dark": Palette.CLOTH_DARK, "back": Palette.SHADOW_DEEP},
	{"id": "ember", "name": "EMBER",
		"cloth": Palette.SHADOW_WARM, "dark": Palette.SHADOW, "back": Palette.SHADOW_PIT},
	{"id": "saffron", "name": "SAFFRON",
		"cloth": Palette.MID, "dark": Palette.SHADOW_WARM, "back": Palette.SHADOW_PIT},
	{"id": "wine", "name": "WINE",
		"cloth": Palette.SHADOW, "dark": Palette.SHADOW_PIT, "back": Palette.INK},
	{"id": "royal", "name": "ROYAL",
		"cloth": Palette.ROYAL, "dark": Palette.ROYAL_DARK, "back": Palette.ROYAL_DEEP},
]

## The sash, the hood's crest, the headband and the ribbons. One flat colour.
const ACCENTS: Array[Dictionary] = [
	{"id": "gold", "name": "GOLD", "colour": Palette.LIGHT_WARM},
	{"id": "pale", "name": "PALE", "colour": Palette.LIGHT_SOFT},
	{"id": "fire", "name": "FIRE", "colour": Palette.MID},
	{"id": "ink", "name": "INK", "colour": Palette.INK},
]

## Hair, lit and shaded. The prince's is under his hood.
const HAIRS: Array[Dictionary] = [
	{"id": "raven", "name": "RAVEN", "lit": Palette.SHADOW_PIT, "shade": Palette.INK},
	{"id": "chestnut", "name": "CHESTNUT", "lit": Palette.SHADOW, "shade": Palette.SHADOW_PIT},
	{"id": "henna", "name": "HENNA", "lit": Palette.SHADOW_WARM, "shade": Palette.SHADOW},
	{"id": "gold", "name": "GOLD", "lit": Palette.LIGHT_WARM, "shade": Palette.MID},
	{"id": "brown", "name": "BROWN", "lit": Palette.UMBER, "shade": Palette.UMBER_DARK},
]

## Skin, lit and shaded. The prince's face is a void under the hood.
const SKINS: Array[Dictionary] = [
	{"id": "sand", "name": "SAND", "lit": Palette.LIGHT_SOFT, "shade": Palette.LIGHT_WARM},
	{"id": "amber", "name": "AMBER", "lit": Palette.LIGHT_WARM, "shade": Palette.MID},
	{"id": "copper", "name": "COPPER", "lit": Palette.MID, "shade": Palette.SHADOW_WARM},
	{"id": "umber", "name": "UMBER", "lit": Palette.SHADOW_WARM, "shade": Palette.SHADOW},
	{"id": "fair", "name": "FAIR", "lit": Palette.FAIR, "shade": Palette.FAIR_SHADE},
]

## The keys a look is saved under, in the order the editor lists them.
const FIELDS: Array[String] = ["figure", "outfit", "accent", "hair", "skin"]

var figure: int = Figure.PRINCE
var outfit := 0
var accent := 0
var hair := 0
var skin := 1


## The option table behind a field, so the editor and the loader walk the same
## lists.
static func options(field: String) -> Array[Dictionary]:
	match field:
		"figure":
			return FIGURES
		"outfit":
			return OUTFITS
		"accent":
			return ACCENTS
		"hair":
			return HAIRS
		"skin":
			return SKINS
	return []


func duplicate_look() -> CharacterLook:
	var copy := CharacterLook.new()
	for field: String in FIELDS:
		copy.set_index(field, index_of(field))
	return copy


func index_of(field: String) -> int:
	match field:
		"figure":
			return figure
		"outfit":
			return outfit
		"accent":
			return accent
		"hair":
			return hair
		"skin":
			return skin
	return 0


## Out-of-range values wrap, so stepping past either end of a list cycles.
func set_index(field: String, value: int) -> void:
	var count := options(field).size()
	if count == 0:
		return
	var wrapped := wrapi(value, 0, count)
	match field:
		"figure":
			figure = wrapped
		"outfit":
			outfit = wrapped
		"accent":
			accent = wrapped
		"hair":
			hair = wrapped
		"skin":
			skin = wrapped


func option(field: String) -> Dictionary:
	return options(field)[index_of(field)]


func is_heroine() -> bool:
	return figure == Figure.HEROINE


## Whether the figure shows a face and hair, so the hair and skin rows mean
## something: the prince's are under his hood and the stick avatar has none.
func shows_face() -> bool:
	return figure == Figure.HEROINE or figure == Figure.PRINCESS


func equals(other: CharacterLook) -> bool:
	return other != null and to_ids() == other.to_ids()


## The look as ids, for the file.
func to_ids() -> Dictionary:
	var out := {}
	for field: String in FIELDS:
		out[field] = String(option(field)["id"])
	return out


## Reads ids back. A field that is missing, of the wrong type or names nothing
## keeps its default: a hand-edited or half-written file costs one choice, not
## the whole look. Returns how many fields were taken from `ids`.
func take_ids(ids: Dictionary) -> int:
	var taken := 0
	# FIELDS starts with the figure, so a figure's own defaults go on first and
	# every field the ids do name is taken over them.
	for field: String in FIELDS:
		var value: Variant = ids.get(field)
		if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:
			continue
		var table := options(field)
		for i: int in table.size():
			if String(table[i]["id"]) == String(value):
				set_index(field, i)
				taken += 1
				if field == "figure":
					wear_defaults()
				break
	return taken


## Puts on the figure's own defaults, if it has any: the princess comes in the
## royal blue, brown hair and fair skin of her concept sheet. Only the colours
## change; the figure stays. The wardrobe calls this when a player steps onto
## a figure, take_ids() when a set of ids names one.
func wear_defaults() -> void:
	var defaults: Dictionary = FIGURES[figure].get("defaults", {})
	for field: String in defaults:
		var table := options(field)
		for i: int in table.size():
			if String(table[i]["id"]) == String(defaults[field]):
				set_index(field, i)


## A new look read from ids by take_ids(): the default, with each field that
## names an option replaced. For ids from anywhere not trusted -- the other
## player's handshake above all (scripts/net/protocol.gd).
static func from_ids(ids: Dictionary) -> CharacterLook:
	var look := CharacterLook.new()
	look.take_ids(ids)
	return look


## Puts this look on a figure. Colours first, then the costume, so a costume
## built here sees the colours it is dressed in. A FighterArt re-imposes its
## seat's team colour after this (FighterArt.dress), which is the half of the
## seat guarantee that lives in the duel.
func dress(art: PlayerArt) -> void:
	var robe := option("outfit")
	art.cloth = robe["cloth"]
	art.cloth_dark = robe["dark"]
	art.cloak_shade = robe["back"]
	art.accent = option("accent")["colour"]
	var locks := option("hair")
	var face := option("skin")
	match figure:
		Figure.HEROINE:
			art.costume = HeroineCostume.new(
				locks["lit"], locks["shade"], face["lit"], face["shade"])
		Figure.STICK:
			art.costume = StickCostume.new()
		Figure.PRINCESS:
			art.costume = PrincessCostume.new(locks["lit"], locks["shade"], face["lit"])
		_:
			art.costume = Costume.new()
	art.queue_redraw()
