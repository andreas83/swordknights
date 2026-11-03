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

Everything is drawn from `scripts/core/palette.gd`. There are no image assets
in this project and there will not be: the tile atlas is generated from the
palette, the skyline from a seed, the character from polygons. Re-lighting the
world for night or interior must stay a palette edit plus a re-run.

## Composition

- **Negative space is not empty space.** A wide lit floor with one figure and
  one long shadow is the reference's strongest frame. Resist filling it.
- **Lead the eye with light.** The lit path should be the path. Where the
  player is meant to go, put the gold.
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
