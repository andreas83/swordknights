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
`Tiles.SHADE_ROW_OFFSET` (2) rows below it. The shader reads the mask and, where
it says shadow, samples the twin instead: one extra texture fetch, and no second
pass over the tilemap. The current atlas is 256 × 64 px — 32 tiles and 32 twins.

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

## Tests

- `tests/world_shadow_test.gd` — the shadow model: the sun's direction, what
  casts, the two sparing rules, that shipping levels are neither blank nor
  black, and that the mask fits a texture. The shade-twin lookup itself has no
  dedicated test; it is checked by eye in screenshots.
- `tests/world_dressing_test.gd` — decoration cannot collide, marks leave
  their cell empty, every shipping and generated level gets architecture, and a
  symmetric level is dressed symmetrically.
- `tools/world_debug.gd` — not a test. Dumps a level's dressing and shadow mask
  for inspection.
