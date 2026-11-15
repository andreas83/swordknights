# Art direction

One idea, held consistently. Everything below is in service of it.

## The idea: a low sun

It is late afternoon in a stone city and the sun is nearly on the horizon.
Every surface is either **lit gold** or **lost in crimson shadow**, and the
line between them is hard. There is no third value, no gradient, no haze
softening the edge.

That is the whole look. It is not a palette choice — it is a *lighting*
choice, and the palette follows from it.

### What this means in practice

- **One sun, fixed in the world.** It rakes in low from the left. It does not
  rotate with the camera and it does not follow the player. When the
  character turns around, the shadow edge down their body does not move.
- **Shadows are cast, not painted.** A balustrade throws a hard black diagonal
  across a gold floor. An arch cuts a shape of light onto the wall behind it.
  A ledge drops a band of shade on the stone below. If a shadow in a frame
  could not be traced back to the thing casting it, it is decoration and it is
  wrong.
- **Hard edges only.** No soft shadows, no bloom, no blur, no post-processing
  that muddies the boundary. The engine is on the GL compatibility renderer
  and the game must hold 60 fps on a phone; the restraint is both an art
  decision and a performance one.
- **Long shadows.** The sun is low, so shadows are long enough to become
  composition — often longer than the thing casting them.

## The second idea: architecture is the subject

The reference is not a platform game's blocks. It is a *city*: horseshoe
arches, balustrades, stepped terraces, onion domes, colonnades, planters,
fountains, carved wall reliefs, awnings, stairs that go somewhere.

A wall that is a rectangle with a joint line painted on it is a placeholder.
A wall should have an arch cut into it, a cornice along its top, a niche with
something in it. The player should run *under* arches, *behind* railings,
*past* columns.

## Depth: three planes, always

| Plane | What lives there | How it reads |
| --- | --- | --- |
| Background | the parallax city, domes, the sun | desaturated, hazed toward the horizon colour, never crisp |
| Mid-ground | everything the player touches | full contrast, hardest edges, where the eye goes |
| Foreground | railings, column bases, arch soffits, hanging cloth | darker than the mid-ground, often near-silhouette, occludes the player |

Foreground occlusion is the cheapest depth there is and we currently have
none. The player passing *behind* a balustrade is worth more than any number
of particles.

## Colour discipline

The duotone is the rule; accents are the exception and they are rationed:

- **Teal** — water, and player two. Nothing else.
- **Green** — living things only: palms, planters, moss in a cistern.
- **Steel** — blades and spikes. Cold against everything else, which is why a
  sword reads instantly.
- **Paper white** — reserved for the brightest specular and for text. If
  white appears anywhere else it steals the eye.
- **Blood red** — blood, and nothing else. See below.
- **Royal blue, umber and fair** — what a figure wears: an outfit, hair,
  leather, a fair skin. Never stone, never a team. See below.

### The sixth and seventh accents: royal blue and umber

The owner's concept sheet for the 3D princess wears a royal-blue tunic and
cape, brown hair and brown leather, and asked for her to be close to it. The
duotone has no blue and its "browns" are crimsons, so `Palette.ROYAL*` and
`Palette.UMBER*` were added -- and `Palette.FAIR`, a peach skin, since the
gold ramp's lightest step made a fair face yellow -- each standing in the same
lit / shade / back relationship as the cloth ramp. They are rationed by use:
the wardrobe's ROYAL outfit and BROWN hair, and the princess's leather. They
never colour stone, and never a team: a duel re-dresses every robe in its
seat's crimson or sea-green, and the blue sits about fifty degrees of hue away
from player two's teal.

### The one imported asset: the princess's model

Everything else on screen is generated from the palette and the tuning
table. The owner's rigged princess (`assets/characters/princess.glb`,
generated from the concept sheet with Tripo -- its rigged, animated export
with the colour textures of its textured one grafted on by
tools/merge_glb.py -- and the textures the importer extracts beside it) is the single exception,
sanctioned by the owner: a professionally made, animated character is not
something the primitives can match. It is held to the rest of this document
as far as a texture can be:

- **Lit by the world's sun**, through the same 3D stage as the primitives:
  the key from the left, the warm rim, a dark of the palette for the ambient,
  and the ink silhouette round it. Its texture is its albedo, not its
  lighting; the stage is exposed brighter for it, since a dark albedo under a
  light tuned for painted palette steps went black at play size.
- **The team owns the cloth.** Her blue -- the ROYAL accent her texture is
  made in -- is dyed per pixel to the seat's crimson or sea-green in a duel
  (assets/cloth_tint.gdshader), leaving her trim, emblem, leather, steel and
  skin as made; the rest of her texture keeps clear of both teams' hues. An
  export without colour textures wears the team on its ink edge instead.
- **No modelled sword.** The sword on screen is the shared 2D one, coloured
  hers, because it is the rect the duel fights with; her clips' sword hand
  is where it starts.
- **The flash** burns it toward paper white like every figure.
- **No blood red** in the texture: the blood ramp stays gore's alone.

Without the file the princess is the primitives, and nothing else changes:
`CharacterLook.princess()` decides, and docs/character.md says what the file
must be and how it is drawn.

### The fifth accent: blood

Blood was the cloth crimson, which is the architecture's crimson: it read on
a gold floor and went out against every wall, arcade and shaded floor it was
spilled on. The owner approved a dedicated blood colour as a deliberate
exception to the two-tone rule, and it is rationed like the other four:
**the blood ramp is drawn by `scripts/duel/gore.gd` and
`scripts/world/bloodshed.gd` and by nothing else.** A banner, a sky or a HUD
mark that borrowed it would make a death harder to read everywhere it hung.
`tests/unit/test_blood_ramp.gd` scans the project for the names and the hex
values and fails on any other file.

| Tone | Hex | OKLab L | Chroma | Hue | Used for |
| --- | --- | --- | --- | --- | --- |
| `Palette.BLOOD` | `c80810` | 0.526 | 0.212 | 28.1° | a drop in the air, a fresh splat, a wet pool, the blob where a drop hits a wall |
| `Palette.BLOOD_DRIED` | `3a0406` | 0.226 | 0.083 | 25.0° | a dried pool, a pool's heart, a smear's lower row, a wall run |
| `Palette.BLOOD_WET` | `ff6a55` | 0.707 | 0.186 | 30.4° | the glint: the sunward pixel of a drop, the sunward end of a wet pool. Never a fill |

**What sets it apart is chroma.** The world spends the whole red ramp, from
`INK` to `SHADOW_WARM`, so any red sits near some stone tone in lightness.
What no stone tone has is `BLOOD`'s saturation (0.212, against 0.188 for the
most saturated stone) at the hue of red rather than crimson's pink (13 to 19°
of hue from `SHADOW`, `SHADOW_DEEP` and `SHADOW_PIT`; the cloth crimson it
replaces was 1.5 to 4°). That is why it reads as blood and not as more wall.

**Two tones in every mark.** `BLOOD` alone is weakest on the mid crimson
`SHADOW` (OKLab distance 6.0), and `BLOOD_DRIED` alone on the darkest stone
(`INK` 4.2, `SHADOW_PIT` 5.6). Each is far from what the other is near, so no
mark is one tone: a drop has its glint, a smear is fresh over dried, a wall
hit is a fresh blob over a dried run, a wet pool has a dried heart and a
glint. Measured in OKLab distance × 100 (about 2 is just noticeable, 10
plainly different, 20 a glance) and WCAG luminance contrast ratio:

| Surface | Hex | `BLOOD` ΔE | `BLOOD` CR | `BLOOD_DRIED` ΔE | `BLOOD_DRIED` CR | `BLOOD_WET` ΔE | better of the two |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `INK` | `2b0a14` | 35.9 | 3.03 | 4.2 | 1.04 | 52.0 | 35.9 |
| `SHADOW_PIT` | `4a0d1e` | 28.1 | 2.56 | 5.6 | 1.14 | 44.4 | 28.1 |
| `SHADOW_DEEP` | `7a1230` | 17.1 | 1.79 | 16.6 | 1.63 | 33.4 | 17.1 |
| `SHADOW` | `b32142` | 6.0 | 1.09 | 29.4 | 2.68 | 21.0 | 29.4 |
| `SHADOW_WARM` | `d8452c` | 7.6 | 1.37 | 38.6 | 4.01 | 11.0 | 38.6 |
| `MID` | `e8702a` | 16.9 | 1.94 | 46.2 | 5.65 | 6.1 | 46.2 |
| `LIGHT_WARM` | `f2a829` | 30.1 | 2.98 | 57.1 | 8.67 | 15.3 | 57.1 |
| `LIGHT` | `f7ce2e` | 39.5 | 3.95 | 65.6 | 11.52 | 24.1 | 65.6 |
| `LIGHT_SOFT` | `ffe873` | 45.3 | 4.87 | 71.5 | 14.20 | 28.8 | 71.5 |

Over the stone and every stone tone under every hour's multiply (the duel's
dusk, golden, sunset, night) the worst case for the better of the two tones
is 17.0, against `SHADOW` under the dusk. The old pair, cloth crimson over
`SHADOW_PIT`, was 9.0 at its worst. The test holds these floors: the better
tone at least 15 from every surface, `BLOOD`'s chroma 0.02 above the stone's
most, 12° of hue from the crimson stone, and the glint 15 from `SHADOW` and
`SHADOW_DEEP`, which is where `BLOOD` is weakest.

**Lit like the stone it lies on.** The stone is drawn by an unshaded shader,
which no canvas multiply reaches. In the duel the dusk never touches it, so
the duel's field joins `MatchDusk.LIT` and a kill in the last room is as red
as one at noon. In the adventure the chapter's hour is laid on the stone by
hand, through the shader's tint (`WorldGrade`), so blood on the canvas takes
the same multiply as the stone under it and needs nothing of its own: graded
alike, the better of its two tones still stands off every stone at every hour,
scaled by the light the hour leaves (`tests/unit/test_blood_ramp.gd`).

**Not cartoonish.** The rest of the art direction still holds: opaque, hard
edged, one to three pixels, on the grid. The glint is a single pixel and is
never a fill. A pool dries from the rim inward as a hard edge moving, not a
fade, and ends a near-black red, which is what old blood is.

Everything is drawn from `scripts/core/palette.gd`. There are no image assets
in this project and there will not be: the tile atlas is generated from the
palette, the skyline from a seed, the character from polygons. Re-lighting the
world for night or interior must stay a palette edit plus a re-run.

## Composition

- **Negative space is not empty space.** A wide lit floor with one figure and
  one long shadow is the reference's strongest frame. Resist filling it.
- **Lead the eye with light.** The lit path should be the path. Where the
  player is meant to go, put the gold. The converse is the rule that bites:
  **a band of gold across the top of something is a promise that it holds
  you up.** Terrain caps, platforms, lifts and plates make it; decoration
  never does. A balustrade with a lit rail hanging over a terrace is a ledge
  to anyone holding a phone, and a frieze of slots between two gold rails is
  a ladder lying on its side -- both were jumped at by a player. So a
  railing is dark and stands on the floor behind the prince, shorter than
  he is; a frieze is blind arches in the wall's own shade; a capital, a rim
  or a kerb is lit on its west edge and never across its top. And the same
  holds for shape: nothing at the prince's feet may read as a hole a tile
  high unless it is one he can crawl through. `docs/world.md`, *Lit caps are
  a promise*, has the table and the test.
- **Silhouette first.** At 22 px the character is a shape before it is
  anything else; the same goes for every hazard and every ledge. If a frame
  does not read in two tones, no amount of detail will save it.

## Restraint

The failure mode for a game that looks like this is *clutter*: too many
particles, too much decoration, a shader on everything. The reference images
are striking because they are almost bare. Three well-placed arches and one
long shadow beat a screen full of ornament.

When in doubt, remove something.

## The icon

The icon is this page in one frame: a horseshoe arch, the low sun on the
horizon inside it, and the prince against the sun with his sword up, throwing
a long shadow down the floor towards you. Backlit, he is a silhouette, and a
silhouette against gold is the strongest two-tone read the palette has — the
only thing that survives at 48 px on a home screen. The blade is the one cold
colour in it.

It is generated like everything else, by `tools/generate_icon.py`, which
rasterises the same shapes **at each output's own pixel grid** (48 for the
favicon, 108 for Android's adaptive layers) with hard edges, rather than
shrinking one large image and smearing it. Sky and sun are the adaptive
icon's back layer; arch, floor and figure are the front, so a launcher's
parallax slides the sun behind the arch. `tests/unit/test_app_icon.gd` reads
the files back and fails if a preset names a missing file, a layer has lost its
alpha, or a colour has crept in from outside `Palette`.

```bash
python3 tools/generate_icon.py
godot --headless --path . --import
```
