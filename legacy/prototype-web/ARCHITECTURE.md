# Architecture

A map of the foundation and the reasoning behind the parts that are easy to
get wrong later.

## Layers

```
main.ts
  └─ core/game.ts ........ owns canvas, renderer, input, audio, loop, scene
       ├─ core/loop.ts ... fixed timestep
       ├─ core/input.ts .. keyboard + gamepad + touch -> abstract actions
       ├─ render/* ....... stateless painters, driven by game state
       └─ scenes/playscene.ts
            ├─ game/world.ts .... parsed ASCII level + collision queries
            ├─ game/player.ts ... state machine on an AABB body
            ├─ game/entities/* .. relic, exit, torch, patrol
            └─ render/camera.ts . dead zone follow
```

Rule: `game/` must not import from `render/` or `ui/`. Gameplay is pure
simulation over numbers, which is what makes `tests/movement.test.ts` able to
play the game headlessly in Node.

## Fixed timestep

`core/loop.ts` advances simulation in exact 1/60 s slices and renders once per
animation frame. Without this, a 120 Hz tablet and a 60 Hz phone produce
different jump heights, and every piece of level geometry becomes device
dependent. The accumulator is capped at five steps so a backgrounded tab
cannot cause a catch-up death spiral on resume.

Rendering does not currently interpolate between steps — at 60 Hz simulation
on a 120 Hz display you get pairs of identical frames. If that becomes
visible, `render(alpha)` already carries the sub-step progress needed to
interpolate positions.

## Virtual resolution

The game draws into a virtual view that is **180 units tall** with a width
derived from the display's aspect ratio, clamped to 264–440 units
(`render/renderer.ts`). Fixed height keeps the character the same apparent
size on every device; flexible width means a 20:9 phone sees more of the room
instead of black bars. Device pixel ratio, letterboxing and safe-area insets
are all resolved inside the renderer, so no gameplay or UI code ever sees a
device pixel.

## Collision

`game/physics.ts` moves bodies one axis at a time, in sub-steps no larger than
a tile, binary-searching onto the contact point. Axis separation is what gives
platformers their predictable wall-slide behaviour; the sub-stepping is what
stops a fast fall from tunnelling through a floor.

One-way platforms collide only when the body was fully above the platform's
top edge on the previous sub-step, which is why `moveY` tracks
`previousBottom` rather than just testing overlap.

## Character state machine

`game/player.ts` holds every transition in one switch. The feel comes from
four forgiveness mechanisms, all tunable in `game/tuning.ts`:

- **Coyote time** — a jump is accepted for 0.1 s after walking off an edge.
- **Jump buffering** — a jump pressed up to 0.14 s before landing still fires.
- **Variable height** — releasing the button mid-rise cuts upward velocity.
- **Apex float** — reduced gravity near the top of the arc, so mid-air steering
  reads clearly.

Ledge grabbing is a geometry probe, not a trigger volume: while falling, the
hand position in the facing direction is tested for a solid tile with empty
space directly above it. That means any corner in any level is grabbable
without authoring markers, and it is why the level's vertical spacing rules
are derived values rather than arbitrary ones.

## Input

Keyboard, gamepad and touch each own a private state set; the public state is
their union (`core/input.ts`). This is deliberate — a single shared set means
releasing a key clears a direction the thumbstick is still holding. Gameplay
depends only on the structural `InputReader` interface, which is what lets
tests drive the player with a scripted stub.

## Rendering

No image assets. `render/palette.ts` defines the duotone ramp and a `SURFACE`
table that names colours by how they face the light rather than by hue, so
re-lighting the game is a table edit. Tile, character, parallax and entity
painters are separate files; replacing the character painter with real sprites
later touches nothing else.

## Extending

- **New level** — add an ASCII file under `game/levels/`, pass it to
  `PlayScene`. Nothing else changes.
- **New entity** — implement `Entity` in `game/entities/`, add a legend
  character in `game/tiles.ts`, and a case in `PlayScene.spawnEntities`.
- **New scene** (title, level select) — implement `Scene` and call
  `ctx.setScene`. Scene swaps are deferred to the start of the next update, so
  a scene may replace itself from inside its own `update`.
