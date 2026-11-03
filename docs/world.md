# The world: light and architecture

Two systems turn a level's terrain into the city in the reference art. Both are
built against [`art-direction.md`](art-direction.md), and both run over every
level the game plays — hand-authored, generated, and duelling zones — without
any of them being rewritten.

| | File |
|---|---|
| Cast shadows | `scripts/render/sun_shadow.gd`, `assets/world_shadow.gdshader` |
| Shade twins in the atlas | `tools/generate_tiles_png.py`, `scripts/world/tiles.gd` |
| Architecture from terrain | `scripts/world/dresser.gd` |
| Secret rooms | `scripts/world/secret_view.gd`, `scripts/world/secret_keeper.gd` |

The docstrings in those files carry the full argument. This page is the map,
plus the facts that do not belong to any one file.

## One sun

The sun is fixed in the world and rakes low from the left at the integer vector
`(RUN, RISE) = (2, 1)`: two pixels across for every one down.

The integer slope is what makes the solve cheap. Index each pixel by its lane,
`lane = x − 2y`. The lanes partition the grid exactly, and stepping
`(x + 2, y + 1)` walks one lane. So casting a shadow is one sweep per lane with
a countdown, not a ray-march per pixel. The whole world is static once a level
is built, so the mask is solved **once**, into one bit per pixel, and after that
a shadow costs one texture fetch per fragment. Nothing is re-solved while the
game runs, and there is no render target and no light pass.

### What casts, and what is spared

A pixel casts if it is opaque in the atlas: terrain and mid-ground architecture
alike. No decoration declares its own silhouette, so a new one casts correctly
the moment it is drawn. Background filler, water and the foreground plane do not
cast.

Two rules decide what is spared. The picture is wrong without either.

1. **A body does not shadow itself.** Without this, a wall's own cap eats the
   gold off the wall below it.
2. **What counts as one body is declared, not inferred.** Terrain and the
   cornices and friezes carved into it are one body. A column, balustrade or
   planter *standing on* a surface is its own body, and throws its shadow across
   that surface. `Tiles.STANDING_DECOR` is the list. It is the difference
   between a terrace of flat gold and one banded by its colonnade.

### Why thin casters are two pixels wide

A one-pixel-wide vertical caster at column `x` covers lanes `x − 2y` for each
row `y`. Stepping down one row moves the lane by two, so a one-pixel post only
ever touches lanes of one parity. Its shadow lands on every other lane, and
reads as a dotted line instead of a shadow. A two-pixel post covers both
parities. That is why balustrade posts in `tools/generate_tiles_png.py` are two
pixels wide, and why any new thin standing decoration should be too.

## Shade twins

A surface going into shadow is not that surface darkened. It is the next tone
down the duotone ramp, which is the art direction's central idea.

The atlas is two halves in register. Every tile has a shade twin
`Tiles.SHADE_ROW_OFFSET` (4) rows below it. The shader reads the mask and, where
it says shadow, samples the twin instead: one extra texture fetch, and no second
pass over the tilemap. The current atlas is 256 × 128 px — 53 tiles and 53 twins.

The atlas and the TileSet are generated:

```bash
python3 tools/generate_tiles_png.py
godot --headless --path . --script tools/build_tileset.gd
```

Both are byte-for-byte reproducible; that was checked when this work merged.

## Cost

`SunShadow.timings` records each phase of the last build, so the numbers here
can be checked rather than believed. Measured at merge, six builds each, in a
cloud container with no GPU on a shared CPU:

| Level | Mask | Typical build | Range |
|---|---|---|---|
| `level_01` | 1264 × 352 px | 92 ms | 91–149 ms |
| generated | 688 × 336 px | 42 ms | 41–49 ms |

Both are about 0.2 µs per mask pixel, linear in area, as the lane sweep
promises. The phases split roughly a quarter rasterise, a third depth, the rest
the sweep; the upload is negligible. Per-tile opacity bitmaps are cached across
levels: 1.7 ms on the first build, about 0.01 ms after.

This is a **one-off cost at level load**, paid behind the scene wipe
(`docs/feel.md`). It is not per frame. A phone may be several times slower than
the figures above; nobody has measured one yet. If a level load ever shows a
hitch, the sweep is the phase to look at first.

Above 2048 px in either dimension (`SunShadow.MAX_MASK_PX`, the GL ES3
guaranteed texture size), the mask is solved and stored at half resolution. A
long generated level reaches that.

## Architecture from terrain

`scripts/world/dresser.gd` reads terrain and adds what a builder would have:
arcades cut into wall faces, cornices and balustrades along terrace lips,
colonnades down wide terraces, friezes, niches, planters, hanging cloth, and
foreground archways that put the third depth plane in front of the player.

**It cannot change a level's difficulty.** Decoration tiles carry no collision
and no queried kind (`tools/build_tileset.gd`), and every mark sits in a cell
the terrain left empty. A level can be dressed, undressed or re-dressed and the
character's reachable set is identical. That is what makes it safe to run over
levels it has never seen. `tests/world_dressing_test.gd` checks the two
conditions that make it true — no decoration tile can collide, and every mark
leaves its own cell empty — rather than recomputing the reachable set.

**Restraint is a rule.** Every dressing rule has a minimum run width and a
spacing (the constants at the top of `dresser.gd`), because the failure of
automatic decoration is ornament on every surface. Three arches and one long
shadow beat a wall of carving.

**Authors can override.** Marks written in the ASCII win over rules. The
glyphs are documented in the header of `levels/level_01.txt` and defined in
`Tiles.DECOR_LEGEND`. Most of level 1 is deliberately *not* marked up: a level
that needed hand marking would mean generated levels could never look like it.

## Room moods: wear, growth and the things people leave about

Architecture alone made every room the same room. The end of `dresser.gd`
cuts a level into rooms `ROOM_COLS` (20) wide and gives each **one** mood, in an
order shuffled per level from its name so that neighbours never repeat:

| Mood | What it adds |
| --- | --- |
| garden | ivy over the parapets and down the faces, grass along the lips, a potted palm, the planters in flower |
| store | urns and jars, against the walls and stacked in the open |
| ruin | cracked and spalled stone, rubble at the foot of the walls |
| court | latticed windows, lanterns under overhangs, a rug airing over a railing |

Two things happen everywhere regardless of mood: stone standing in water grows
moss, and a wall tall enough to be a building (`TALL_WALL` courses of sheer
face) gets storeys of windows — a sheer face that high with nothing in it is
the placeholder `art-direction.md` warns about.

One mood per room rather than a little of everything everywhere is the
restraint rule applied to life: a room reads as *the garden* the way a street
does. The sixteen tiles are the atlas's third row; their shade twins come from
the same `SHADE_MAP`, which is why the atlas grew to three lit rows and
`SHADE_ROW_OFFSET` to 3.

These go on a fourth layer, **Props**, drawn over Decor on the same plane, so
an urn can stand in front of a cornice and ivy can hang over a frieze without
taking either's cell. `SunShadow.build()` stamps both planes, so a palm or an
urn casts its own shadow without erasing the cornice behind it. The safety
argument is unchanged: no collision, no queried kind, never on a reserved
cell, and every prop either lies over stone the terrain already has or stands
in a cell it left empty. `tests/unit/test_room_moods.gd` checks those, that
neighbouring rooms differ, and that a mirrored arena is dressed as a mirror.

## The air

`scripts/render/ambience.gd`, one node per level. Dust is one pixel of
`LIGHT_SOFT`, drawn **only where the shadow mask says the air is lit**
(`SunShadow.last_mask`, the CPU copy of the mask solved at build). A mote
drifting into a cast shadow vanishes and reappears on the far side, so with a
few dozen of them moving the shadow's edge is visible in the air at exactly the
slope the sun throws it — a shaft of light with no haze, no gradient and no
extra pass. Leaves come down off the ivy, palms and planters, a handful of
sources per level. Everything is a pure function of the clock: nothing is
spawned or freed, and none of it is gameplay.

A flock of birds crosses the far sky every thirty-one seconds
(`ParallaxSky._draw_flock()`), in the sky's own crimson, a step darker.

## The duel's zones

The tug-of-war strip (`levels/duel_zones.txt`) is drawn by the same path, a
zone at a time, by `scripts/duel/zones_view.gd`. Two things differ from a
level, both because the strip is streamed and wider than one texture:

- **Dressed once, whole.** `ZoneStrip.as_level()` stitches the five zones into
  one `AsciiLevel`, and `WorldDresser` runs over that at setup. A terrace
  across a seam gets one colonnade rather than two halves, and since the strip
  mirrors about its centre, so does its dressing.
- **Lit per zone.** The strip is 2400 px wide, over `MAX_MASK_PX`, so one mask
  would be half resolution. Each zone's mask is solved over the zone plus
  `ZoneView.SHADOW_LEAD` (8) columns to its west — shadows fall east and stop
  after `REACH_TILES` — and the shader's `mask_origin` places it.
  `tests/unit/test_zone_dressing.gd` compares each against a solve over
  everything west of it, pixel for pixel; with no lead, two zones disagree.

Measured at setup in the same container as the table above: about 15 ms to
dress the strip and 130–180 ms to solve the five masks, once per match, before
the countdown. Streaming a zone in writes cells and nothing else.

In a duel the foreground plane is drawn at 55% (`ZoneView.FORE_ALPHA`): a
column in front of the prince costs nothing, a column in front of the other
fighter hides the stance you are reading.

The room moods are **not** run on the duel's zones: `ZoneView` draws the
architecture and the foreground the dresser returns and leaves its `props`
plane out, as the art pass intended for the duelling ground.

## Secrets

A secret room is a seal and the room behind it. The ASCII marks only the seal
(`Tiles.SEAL_LEGEND`); the room is the `:` masonry a flood from the seal
reaches, with the entity marks inside it, so it is drawn the way a niche is
drawn and cannot be forgotten. `AsciiLevel._find_secrets()` does the flood.

| Seal | In play | Opens to | Tell |
| --- | --- | --- | --- |
| `%` false | `BACKDROP`: there is no wall | the body walking into it | a bricked-up doorway, air drifting out of its joints |
| `&` cracked | `SOLID`: a wall, a ledge, a floor | the sword: a swing, an air slash, or a plunge onto a cracked floor | the same doorway with a crack, shedding grit; on a floor, a hairline across the cap |

A fall does not open a cracked floor, however hard: luck is not looking.

### The tell is architecture

The tell is the mason's one, because architecture is the subject: a doorway
that was filled in. Coursed ashlar never lets a vertical joint run through two
courses; an opening bricked up afterwards always does, down both jambs, and
the fill is laid in smaller stones whose beds never meet the wall's. The fill
is drawn in the wall's own tones, so the doorway is there for whoever looks
and nothing to whoever runs. The motion — a mote, a grain — is the half that
catches the corner of the eye, one pixel at a time. Ruin rooms crack walls
too, so the doorway's shape is the part that cannot be confused, and the
dresser's marks are cleared off every secret and the cells in front of it.

### Drawing a lie, and taking it back

`Level.build()` paints the terrain as it really is and takes everything that
decides the *look* — caps, lit edges, dressing, the shadow — from the facade
(`AsciiLevel.facade()`), the level with every unfound room solid. Over each
room `SecretView` lays a cover of the facade's own tiles. Finding one:

- repaints the terrain around it from the level as it now is, which is also
  what removes a cracked seal's collision (at once: a plunge that opened a
  floor this frame falls through it this frame);
- drops the cover out in an ordered dither spreading from the point of entry
  (`dissolve` in `assets/world_shadow.gdshader`) — hard pixels the whole way;
- swaps in the room's light. The shadow is solved twice at build, sealed and
  with every room open; each differing mask pixel belongs to its nearest
  secret, and finding it copies those pixels into the live mask. A found room
  is in its own shade with a shaft through the doorway, and nothing is solved
  in play. The second solve costs what the first does, behind the same wipe,
  and only in a level that has secrets.

What a room holds is hidden until it is found; found secrets stay found
through deaths, and a restart seals them all again (`SecretKeeper`).

### Never required, never a trap

`LevelReachability.audit_secrets()` proves it for every combination of found
and unfound secrets; `docs/level-generation.md` has the details.
`tests/unit/test_secret_proof.gd` runs it on the Sun Terrace and refuses one
broken level per clause.

### The Sun Terrace's three

| | Where | Seal | Prize |
| --- | --- | --- | --- |
| A | the cistern's far wall, at the bottom of the pit | false | a relic |
| B | the high block's face, over the basin's run-up | cracked | a relic, and an inscription |
| C | the guard's floor, under the low platform | cracked floor | a relic, in a cellar you climb out of by a ledge grab |

One per act, each teaching the next: walk through, cut through, plunge
through.

## Directives and wiring

A level file can say things about itself that are not rows of it. A comment
that starts `;!` is a **directive**:

```
;! time dusk
;! mark 1 plate channel=west_gate
;! mark 2 gate channel=west_gate
; The Cistern Gate
```

A directive is a comment first. The geometry parser skips it like any `;`
line, so it can never move a tile — the failure the format has been burned by
twice — and it is never taken for the title, which is still the first plain
comment. `;` stays the only comment marker; `#` is still a solid tile.

| Directive | Means | Read by |
| --- | --- | --- |
| `time <stop>` | the hour the level is set at | the time-of-day grade |
| `mark <glyph> <kind> [key=value …]` | `glyph` places an entity of `kind` here, with these parameters | `AsciiLevel` |

`AsciiLevel.DIRECTIVES` lists the names something reads. A name that is not
there is a *problem*, like a malformed line or a glyph in no legend; problems
are collected in `AsciiLevel.problems`, `Game` warns about them when the
level loads, and `tests/unit/test_level_directives.gd` refuses a shipping
level that has any. Nothing about a problem stops a level from playing.

### Declared marks

`mark` binds a glyph no legend uses to a registered entity kind for this level
only. Digits are the natural choice, and there are plenty of free letters.
Every **connected run** of the glyph (up, down, left, right) is *one* entity,
anchored at the run's bottom-left cell — where a thing that stands, stands —
with the whole run in its `cells`. So a gate three cells tall is

```
;! mark 2 gate channel=a
      2
      2
  @   2     D
```

one gate. Like every entity mark, a declared cell is left empty in the grid:
whatever is there in play is the entity's to say (below). The marks join the
legend's in reading order, which is the order `Game` places and meets them.

### Wiring

Mechanisms are wired by naming the same channel: every mark with
`channel=west_gate` shares one wire on the level's `ChannelBus`
(`scripts/mechanisms/channel_bus.gd`). A trigger turns its wire on; a
receiver acts when it changes. A wire is on while any trigger **holds** it —
two plates on one channel are an OR — or for good once one **latches** it.
Wiring is data in the level text; there is nothing to connect in code.

### What a mechanism is in play

A mechanism (`scripts/mechanisms/mechanism.gd`) changes what its cells are
with `set_kind()`: stone, a one-way platform, spikes, a ladder, or air. It
never repaints the tilemap. It brings its own `StaticBody2D` on the solid or
one-way collision layer, which the prince's own `move_and_slide()` meets like
terrain — so dropping through a one-way mechanism works the way it does
through a platform, by clearing the one-way bit — and it writes the cell's
kind into the level's **overlay** (`Level.set_overlay()`), which every tile
query reads first: the ledge grab, the footing check, the stand-up room, the
hazard check, a guard's turn at a wall. Both halves are needed, and a test
breaks each one: with only the overlay the prince walks through a shut gate;
with only the body he could grab it and stand up inside it.

The tilemap, the dressing and the cast shadow are built from the level as
authored, so a mechanism draws itself and casts no sun shadow. Mechanisms
are props in the light, like a torch.

### Restarts and respawns

A restart rebuilds the level, mechanisms included. **A checkpoint respawn
also puts every mechanism back as the level text placed it**, on a fresh bus,
while relics, found secrets and fallen foes stay as the prince left them.
The reason is the checkpoint proof: a torch is proved to reach the door with
every wire off, so a respawn into any other mechanism state is one the proof
says nothing about — and keeping "the gate he opened" means also keeping "the
floor he broke", which is a soft lock. `Game._respawn()` carries the full
argument.

### Proving a level with mechanisms

Each mechanism kind tells the reachability proof how it changes passability
(`static func reach(mark, model)`), and the proof searches over a channel mask
as well as cells: see `docs/level-generation.md`, *Mechanisms*. A level with
no mechanism is proved exactly as it always was.

## Tests

- `tests/unit/test_level_directives.gd` — directives move no tile and are
  never the title; declared runs, anchors, parameters and reading order; every
  malformed line is a problem; shipping levels have none.
- `tests/unit/test_mechanisms.gd` — the bus, the overlay, a toy plate and gate
  in the game scene, and the restart and respawn rule.
- `tests/unit/test_secret_walls.gd`, `tests/unit/test_secret_count.gd` — the
  seals played through the real game scene, and the count.
- `tests/unit/test_zone_dressing.gd` — the duel's zones: the stitched strip is
  the strip, every zone is dressed, the dressing mirrors, each zone's shadow
  matches the whole strip's, and none of it reaches the simulation.
- `tests/world_shadow_test.gd` — the shadow model: the sun's direction, what
  casts, the two sparing rules, that shipping levels are neither blank nor
  black, and that the mask fits a texture. The shade-twin lookup itself has no
  dedicated test; it is checked by eye in screenshots.
- `tests/world_dressing_test.gd` — decoration cannot collide, marks leave
  their cell empty, every shipping and generated level gets architecture, and a
  symmetric level is dressed symmetrically.
- `tests/unit/test_room_moods.gd` — the props plane: where a prop may sit,
  that rooms differ, determinism, and mirrored arenas.
- `tools/world_debug.gd` — not a test. Dumps a level's dressing and shadow mask
  for inspection.
