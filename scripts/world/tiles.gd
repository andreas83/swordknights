class_name Tiles
extends RefCounted
## Tile vocabulary shared by the ASCII level format, the generated TileSet and
## the gameplay queries.
##
## Levels are authored as ASCII art; this is the legend. Keeping the atlas
## coordinates here too means tools/build_tileset.gd and the level builder can
## never drift apart.

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
}

## Atlas coordinates — must match the NAMES order in generate_tiles_png.py.
const ATLAS_SOLID_CAPPED := Vector2i(0, 0)
const ATLAS_SOLID_CAPPED_LIT := Vector2i(1, 0)
const ATLAS_SOLID_BURIED := Vector2i(2, 0)
const ATLAS_SOLID_BURIED_LIT := Vector2i(3, 0)
const ATLAS_PLATFORM := Vector2i(4, 0)
const ATLAS_SPIKES := Vector2i(5, 0)
const ATLAS_WATER := Vector2i(6, 0)
const ATLAS_LADDER := Vector2i(7, 0)
const ATLAS_BACKDROP := Vector2i(0, 1)

const ALL_ATLAS_COORDS: Array[Vector2i] = [
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
