# Architecture

A map of the foundation and the reasoning behind the parts that are easy to
get wrong later.

## Layers

```
scenes/boot.tscn
  └─ scripts/core/boot.gd ........ thin entry point; platform setup belongs here
       └─ scenes/menu.tscn ....... mode select, driven by core/mode_registry.gd
            └─ scenes/game.tscn
                 ├─ core/game.gd ......... owns a level's actors and arbitrates them
                 ├─ world/level.gd ....... TileMapLayer + geometry queries
                 ├─ player/player.gd ..... state machine on a CharacterBody2D
                 ├─ entities/* ........... relic, exit, torch, patrol
                 ├─ render/game_camera.gd  dead-zone follow
                 └─ ui/hud.gd, ui/touch_controls.gd
```

The dependency direction is one-way. `player/`, `world/` and `entities/` never
reach into `render/` or `ui/`, which is what lets the whole simulation run
headlessly in tests and under a network session.

## Fixed timestep

All gameplay runs in `_physics_process`, which Godot steps at a constant
60 Hz (`physics/common/physics_ticks_per_second`). Without that, a 120 Hz
tablet and a 60 Hz phone produce different jump heights, every piece of level
geometry becomes device-dependent, and networked play cannot agree on
anything. `max_physics_steps_per_frame` is capped at 5 so a stalled frame
cannot trigger a catch-up spiral.

`default_gravity` is set to zero on purpose: the character applies its own
gravity, including the reduced pull near the apex of a jump.

## Virtual resolution

The viewport is **180 units tall with an aspect-derived width**
(`stretch/mode = canvas_items`, `stretch/aspect = keep_height`). Fixed height
keeps the character the same apparent size on every device; flexible width
means a 20:9 phone sees more of the room instead of black bars. One tile is
16 px, so the whole game is authored in the same units the tuning uses.

## Collision

Tiles carry their collision in the generated TileSet, across two physics
layers:

| Layer | Mask bit | Contents |
| --- | --- | --- |
| 0 | 1 | solid blocks |
| 1 | 2 | one-way platforms |

Separating them is what makes dropping through a platform trivial: the
character clears mask bit 2 for a quarter of a second instead of needing any
special case in the movement code.

Hazards, ladders and backdrop tiles carry **no** collision. They are read
through the TileSet's custom `kind` data (`Level.rect_has_kind`), which means
a level hand-edited in the Godot editor behaves exactly like a parsed or
generated one.

## Character state machine

`scripts/player/player.gd` keeps every transition in one `match` block. The
feel comes from four forgiveness mechanisms, all tunable in
`scripts/core/tuning.gd`:

- **Coyote time** — a jump is accepted for 0.1 s after walking off an edge.
- **Jump buffering** — a jump pressed up to 0.14 s before landing still fires.
- **Variable height** — releasing the button mid-rise cuts upward velocity.
- **Apex float** — reduced gravity near the top of the arc, so mid-air
  steering reads clearly.

The node's origin is at the character's **feet**, which makes spawning, ledge
snapping and drawing all read straight off `position`.

Ledge grabbing is a geometry probe, not a trigger volume: while falling, the
hand position in the facing direction is tested for a solid tile with empty
space directly above it. Any corner in any level is therefore grabbable
without authoring markers — and it is why the level grammar's 4-tile rule is a
derived number rather than an arbitrary one.

## The input seam

`scripts/player/player_input.gd` is one frame of intent: seven bits of held
state plus derived press edges, with `to_bits()` / `apply_bits()` as the wire
format. The character reads those fields and never asks which device produced
them.

That indirection is load-bearing. A local device (`LocalInput`, with an action
suffix so a second local player needs no duplicated logic), a replay, an AI or
a remote peer all drive the character through the identical code path.

## Rendering

No image assets. `scripts/core/palette.gd` holds the duotone ramp and names
surfaces by how they face the light rather than by hue, so re-lighting is a
table edit. The terrain atlas is generated from that same palette by
`tools/generate_tiles_png.py`, and `tools/build_tileset.gd` turns it into a
TileSet with the collision shapes and custom data above.

One subtlety worth knowing if you edit the atlas generator: PIL's `fill`
**replaces** a pixel including its alpha rather than compositing onto it, so
painting a translucent tint directly would punch a transparent hole in the
tile and let the sky show through. Use the `over()` helper.

The character is drawn as a posed cloak silhouette in
`scripts/player/player_art.gd`, derived from state and `state_time`. Swapping
in real sprites later means replacing that one file.

## Configuration as code

`project.godot` is written by `tools/configure_project.gd`. Settings and input
bindings therefore show up as readable diffs instead of as editor state, and a
fresh clone can regenerate them. Add a setting to that script, not to the
editor.

## Extending

- **New level** — add an ASCII file under `levels/`, point a scene's
  `level_path` at it. `Game.level_source` takes an `AsciiLevel` directly for
  levels that are generated rather than stored.
- **New entity** — add a class under `scripts/entities/`, a legend character
  in `scripts/world/tiles.gd`, and a case in `Game._spawn_entities`.
- **New mode** — add one entry to `scripts/core/mode_registry.gd` and it
  appears in the menu. The scene is loaded only when the mode is chosen.
