class_name Tiles
extends RefCounted
## Tile vocabulary shared by the ASCII level format, the generated TileSet and
## the gameplay queries.
##
## Levels are authored as ASCII art; this is the legend. Keeping the atlas
## coordinates here too means tools/build_tileset.gd and the level builder can
## never drift apart.
##
## There are four kinds of glyph:
##
##   LEGEND         terrain — fills the cell, may collide, is queried by the
##                  character (solid, platform, spikes, water, ladder).
##   ENTITY_LEGEND  a thing that spawns in the cell; the cell stays empty.
##   DECOR_LEGEND   architecture — a cornice, an arch, a railing. Never
##                  collides and is never queried, so a level's difficulty
##                  cannot change by decorating it. The cell stays empty.
##   SEAL_LEGEND    masonry hiding a secret room (docs/world.md, "Secrets").
##                  The cell is terrain like any other; the value says what
##                  it does until the secret is found.
##   MECHANISM_LEGEND  a mechanism, placed per connected run and wired by the
##                  mason's marks (MASONS_MARKS, the digits) that touch it.
##                  Its cell is MECHANISM_TERRAIN's, empty by default.
##
## A level can also bind a glyph no legend uses for itself, with `;! mark`
## (scripts/world/ascii_level.gd).
##
## The atlas has a lit half and a shade half in register: the shade twin of a
## tile is SHADE_ROW_OFFSET rows below it, which is how the world shader picks
## between them. See tools/generate_tiles_png.py and docs/world.md.

enum Kind {
	EMPTY = 0,
	SOLID = 1,
	PLATFORM = 2, ## One-way: land on it from above, jump up through it.
	SPIKES = 3,
	WATER = 4,
	LADDER = 5,
	BACKDROP = 6, ## Visually solid background filler — never collides.
}

const LEGEND := {
	" ": Kind.EMPTY,
	".": Kind.EMPTY,
	"#": Kind.SOLID,
	"=": Kind.PLATFORM,
	"^": Kind.SPIKES,
	"~": Kind.WATER,
	"H": Kind.LADDER,
	":": Kind.BACKDROP,
}

## Characters that mark an entity and leave the tile itself empty.
const ENTITY_LEGEND := {
	"@": "spawn",
	"*": "relic",
	"D": "exit",
	"t": "torch",
	"p": "patrol",
	"E": "eclipse", ## the King, the finale's boss: scripts/entities/eclipse.gd
	"K": "kept_sun", ## the light he hoards, over his post: scripts/entities/kept_sun.gd
	"w": "bastion", ## a posted guard behind a tall shield (scripts/entities/bastion.gd)
	"L": "inscription", ## words cut into a wall; spawned by SecretKeeper
	"j": "caracal", ## the King's hunting cat (scripts/entities/caracal.gd)
	"v": "doves", ## a flock on a lit terrace (scripts/entities/dove_flock.gd)
}

## Masonry that seals a secret room. The cell parses to the Kind it has in
## play until the secret is found, and is remembered as a seal of this kind:
##
##   %  false    looks like the wall and is not there: BACKDROP. Walk into it
##               and it dissolves around you. The tell is a bricked-up doorway
##               with air moving through its joints.
##   &  cracked  a wall that is really there until a sword finds it: SOLID, so
##               it holds a guard, a ledge grab and the character's feet
##               exactly as stone does, and a swing or a plunge opens it. The
##               tell is the same doorway with a crack down it, shedding grit.
##
## Behind a seal, the room is the BACKDROP (and the entity marks) a flood from
## the seal reaches; AsciiLevel finds it. It is drawn as stone until found.
##   Q  sun      a doorway with a sun carved in it: SOLID, and blind to the
##               body and the blade alike. Light opens it -- a beam resting on
##               it, or a sunbolt -- through the sun-seal mechanism that the
##               same glyph places (MECHANISM_LEGEND, scripts/mechanisms/
##               sun_seal.gd). The carved sun is its tell.
const SEAL_LEGEND := {
	"%": "false",
	"&": "cracked",
	"Q": "sun",
}

## What a seal of each kind is, in play, until its secret is found.
const SEAL_KIND := {
	"false": Kind.BACKDROP,
	"cracked": Kind.SOLID,
	"sun": Kind.SOLID,
}

## Mechanisms: plates, gates, lifts, crumbling stone (docs/world.md,
## "Directives and wiring"). A glyph here places its kind like an entity mark,
## with three differences: every connected run of glyphs of one kind is ONE
## mechanism (a portcullis three cells tall is one gate, and `[` `]` can be one
## lift); it is wired by the mason's marks it touches; and its cell parses as
## MECHANISM_TERRAIN says, empty unless listed. Each builder adds its own,
## one line each -- the campaign proposes `o ! [ ] ' , x O z i`.
const MECHANISM_LEGEND := {
	"[": "lift", ## a lift's platform at its home stop (scripts/mechanisms/lift.gd)
	"]": "lift",
	"'": "lift", ## the lift's travel: air, until the slab passes through it
	"o": "plate", ## a pressure plate: a floor stone (scripts/mechanisms/plate.gd)
	"!": "gate", ## a portcullis, hung from a lintel (scripts/mechanisms/gate.gd)
	",": "crumbling", ## scripts/mechanisms/crumbling_stone.gd
	"h": "hatch", ## an iron grate in a floor: a one-way floor, drawn as iron (hatch.gd)
	"x": "sun_mirror", ## turned a quarter by the sword; starts facing up
	"O": "sun_seal", ## a door with a sun carved in it: opens when lit
	"Q": "sun_secret", ## the same seal guarding a secret room (SEAL_LEGEND)
}
## The terrain a mechanism glyph's cell is in the grid. Only for something
## that IS terrain and stays it, like a plate, which is a floor stone: the
## tilemap draws and collides what is listed, so anything that stops being
## stone in play (crumbling stone, a seal) must be EMPTY here and bring its
## own collision (Mechanism.set_kind()).
##
## `Q` is the one exception, and it is the secrets' rule rather than this
## one's: a secret's seal is terrain that the secret keeper un-makes when the
## room is found (SEAL_KIND, scripts/world/secret_keeper.gd), exactly as it
## un-makes a cracked wall, so it is SOLID here like `&` is.
const MECHANISM_TERRAIN := {
	"o": Kind.SOLID, ## a plate is the floor's own stone, and stays it
	"h": Kind.PLATFORM, ## a hatch is a one-way floor, and stays one
	"Q": Kind.SOLID,
}
## Mason's marks: stone carved with a channel number. A mark wires the one
## mechanism it touches, up, down, left or right -- same mark, same channel --
## and the cell is solid stone, so an edit that inserts a row cannot detach a
## wire and the mark collides like the wall it is cut in.
const MASONS_MARKS := "123456789"

## Mechanisms a test registered for itself; see add_mechanism_for_test().
static var _test_mechanisms: Dictionary = {}

## Architecture marks. The value is the decoration id WorldDresser plants.
## Each leaves the tile empty, so marking a level up cannot change what the
## character can and cannot reach.
const DECOR_LEGEND := {
	"A": "arch", ## anchor: bottom-left cell of a 2x3 opening
	"n": "niche",
	"|": "column", ## a vertical run; the ends become capital and base
	"_": "cornice",
	"b": "balustrade",
	"V": "planter",
	"f": "fountain", ## anchor: left cell of a 2-wide basin
	"F": "frieze",
	"B": "banner",
	"r": "fore_rail",
	"I": "fore_column",
	"S": "fore_soffit_l",
	"s": "fore_soffit_r",
	"c": "fore_cloth", ## a vertical run; the last cell becomes the fringe
}

## Decorations that STAND ON a surface rather than being carved into it.
## scripts/render/sun_shadow.gd treats these as their own body, so a column
## throws a shadow across the terrace it is standing on. Everything not listed
## is part of the stone it is drawn over — a cornice or a frieze must not
## shade the floor it belongs to, or every gold cap in the game goes crimson.
const STANDING_DECOR := [
	"column_shaft", "column_cap", "column_base",
	"balustrade", "planter", "fountain_l", "fountain_r", "banner",
	"urn", "jars", "rubble", "planter_bloom", "palm_top", "palm_pot", "lantern",
	"balustrade_rug",
]

## Which plane a decoration is drawn on. Anything not listed here is
## mid-ground: behind the character, in front of the terrain.
const FOREGROUND_DECOR := [
	"fore_rail", "fore_column", "fore_soffit_l", "fore_soffit_r",
	"fore_cloth", "fore_cloth_tail",
]

## --- atlas -----------------------------------------------------------------
## Must match the NAMES order in tools/generate_tiles_png.py.

const ATLAS_COLUMNS := 16
## The shade twin of a tile is this many rows further down the atlas.
const SHADE_ROW_OFFSET := 4

const ATLAS_SOLID_CAPPED := Vector2i(0, 0)
const ATLAS_SOLID_CAPPED_LIT := Vector2i(1, 0)
const ATLAS_SOLID_BURIED := Vector2i(2, 0)
const ATLAS_SOLID_BURIED_LIT := Vector2i(3, 0)
const ATLAS_PLATFORM := Vector2i(4, 0)
const ATLAS_SPIKES := Vector2i(5, 0)
const ATLAS_WATER := Vector2i(6, 0)
const ATLAS_LADDER := Vector2i(7, 0)
const ATLAS_BACKDROP := Vector2i(8, 0)

## Architecture. Never collides, so these never appear in kind_of_atlas().
const DECOR_ATLAS := {
	"cornice": Vector2i(9, 0),
	"balustrade": Vector2i(10, 0),
	"column_shaft": Vector2i(11, 0),
	"column_cap": Vector2i(12, 0),
	"column_base": Vector2i(13, 0),
	"planter": Vector2i(14, 0),
	"niche": Vector2i(15, 0),
	"arch_top_l": Vector2i(0, 1),
	"arch_top_r": Vector2i(1, 1),
	"arch_mid_l": Vector2i(2, 1),
	"arch_mid_r": Vector2i(3, 1),
	"arch_leg_l": Vector2i(4, 1),
	"arch_leg_r": Vector2i(5, 1),
	"fountain_l": Vector2i(6, 1),
	"fountain_r": Vector2i(7, 1),
	"frieze": Vector2i(8, 1),
	"banner": Vector2i(9, 1),
	"fore_rail": Vector2i(10, 1),
	"fore_column": Vector2i(11, 1),
	"fore_soffit_l": Vector2i(12, 1),
	"fore_soffit_r": Vector2i(13, 1),
	"fore_cloth": Vector2i(14, 1),
	"fore_cloth_tail": Vector2i(15, 1),
	# Wear, growth and the things people leave about. Placed only by the
	# dresser's room moods, on the props plane (see WorldDresser).
	"crack": Vector2i(0, 2),
	"worn": Vector2i(1, 2),
	"ivy_top": Vector2i(2, 2),
	"ivy": Vector2i(3, 2),
	"ivy_end": Vector2i(4, 2),
	"moss": Vector2i(5, 2),
	"window": Vector2i(6, 2),
	"urn": Vector2i(7, 2),
	"jars": Vector2i(8, 2),
	"rubble": Vector2i(9, 2),
	"grass": Vector2i(10, 2),
	"planter_bloom": Vector2i(11, 2),
	"palm_top": Vector2i(12, 2),
	"palm_pot": Vector2i(13, 2),
	"lantern": Vector2i(14, 2),
	"balustrade_rug": Vector2i(15, 2),
	# The tells of a secret, drawn over the seal's own stone by
	# scripts/world/secret_view.gd and nowhere else.
	"seal_top": Vector2i(0, 3),
	"seal_foot": Vector2i(1, 3),
	"crack_top": Vector2i(2, 3),
	"crack_foot": Vector2i(3, 3),
	"crack_cap": Vector2i(4, 3),
}

## Decorations that have a handed twin. Mirroring a level's dressing has to
## swap these or the arches come out inside-out.
const MIRROR_PAIRS := {
	"arch_top_l": "arch_top_r",
	"arch_mid_l": "arch_mid_r",
	"arch_leg_l": "arch_leg_r",
	"fountain_l": "fountain_r",
	"fore_soffit_l": "fore_soffit_r",
}

const TERRAIN_ATLAS_COORDS: Array[Vector2i] = [
	ATLAS_SOLID_CAPPED,
	ATLAS_SOLID_CAPPED_LIT,
	ATLAS_SOLID_BURIED,
	ATLAS_SOLID_BURIED_LIT,
	ATLAS_PLATFORM,
	ATLAS_SPIKES,
	ATLAS_WATER,
	ATLAS_LADDER,
	ATLAS_BACKDROP,
]

## Physics layer indices inside the TileSet.
const PHYSICS_SOLID := 0
const PHYSICS_ONE_WAY := 1

## Matching collision_mask bits on the player.
const MASK_SOLID := 1
const MASK_ONE_WAY := 2

const CUSTOM_DATA_KIND := "kind"


## Every tile the TileSet must carry: terrain first, then architecture.
static func all_atlas_coords() -> Array[Vector2i]:
	var out: Array[Vector2i] = TERRAIN_ATLAS_COORDS.duplicate()
	for name: String in DECOR_ATLAS:
		out.append(DECOR_ATLAS[name])
	return out


static func kind_of_atlas(coords: Vector2i) -> Kind:
	match coords:
		ATLAS_SOLID_CAPPED, ATLAS_SOLID_CAPPED_LIT, ATLAS_SOLID_BURIED, ATLAS_SOLID_BURIED_LIT:
			return Kind.SOLID
		ATLAS_PLATFORM:
			return Kind.PLATFORM
		ATLAS_SPIKES:
			return Kind.SPIKES
		ATLAS_WATER:
			return Kind.WATER
		ATLAS_LADDER:
			return Kind.LADDER
		ATLAS_BACKDROP:
			return Kind.BACKDROP
		_:
			return Kind.EMPTY


static func is_deadly(kind: Kind) -> bool:
	return kind == Kind.SPIKES or kind == Kind.WATER


## The kind a mechanism glyph places, or "" when it is not one.
static func mechanism_kind(glyph: String) -> String:
	if _test_mechanisms.has(glyph):
		return String((_test_mechanisms[glyph] as Dictionary)["kind"])
	return String(MECHANISM_LEGEND.get(glyph, ""))


## The terrain a mechanism glyph's cell parses as.
static func mechanism_terrain(glyph: String) -> Kind:
	if _test_mechanisms.has(glyph):
		return (_test_mechanisms[glyph] as Dictionary)["terrain"] as Kind
	return MECHANISM_TERRAIN.get(glyph, Kind.EMPTY) as Kind


static func is_masons_mark(glyph: String) -> bool:
	return glyph.length() == 1 and MASONS_MARKS.contains(glyph)


## Test seam: a mechanism glyph that exists only in a test. Pair every call
## with remove_mechanism_for_test().
static func add_mechanism_for_test(glyph: String, kind: String,
		terrain: Kind = Kind.EMPTY) -> void:
	_test_mechanisms[glyph] = {"kind": kind, "terrain": terrain}


static func remove_mechanism_for_test(glyph: String) -> void:
	_test_mechanisms.erase(glyph)


static func is_foreground(decor_id: String) -> bool:
	return FOREGROUND_DECOR.has(decor_id)


## The atlas tile that is this one seen in a mirror, or the tile itself.
static func mirror_atlas(coords: Vector2i) -> Vector2i:
	for left: String in MIRROR_PAIRS:
		var right: String = MIRROR_PAIRS[left]
		if DECOR_ATLAS[left] == coords:
			return DECOR_ATLAS[right]
		if DECOR_ATLAS[right] == coords:
			return DECOR_ATLAS[left]
	return coords


static func standing_atlas_coords() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for id: String in STANDING_DECOR:
		if DECOR_ATLAS.has(id):
			out.append(DECOR_ATLAS[id])
	return out
