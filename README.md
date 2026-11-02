# Swordknights

A mobile-first jump-and-run adventure in the spirit of *Prince of Persia*:
deliberate, weighty movement, ledge grabs, and a sun-bleached duotone city.

This repository holds the **foundation** — engine, physics, character,
rendering, mobile input and one complete level. It runs and it is playable
end to end; it is not yet a finished game.

![The Sun Terrace](docs/screenshot.png)

## Quick start

```bash
npm install
npm run dev          # http://localhost:5173 — also reachable from a phone on the LAN
```

| Script             | What it does                                     |
| ------------------ | ------------------------------------------------ |
| `npm run dev`      | Vite dev server with hot reload                  |
| `npm run build`    | Typecheck, then bundle to `dist/`                |
| `npm run preview`  | Serve the production bundle                      |
| `npm test`         | Run the Vitest suite                             |
| `npm run typecheck`| `tsc --noEmit`                                   |
| `npm run android`  | Build, `cap sync`, open the Android project      |
| `npm run ios`      | Build, `cap sync`, open the Xcode project        |

## Controls

| Action      | Keyboard              | Gamepad        | Touch                         |
| ----------- | --------------------- | -------------- | ----------------------------- |
| Move        | `←` `→` / `A` `D`     | Stick / D-pad  | Left half — floating stick    |
| Up / down   | `↑` `↓` / `W` `S`     | Stick / D-pad  | Push the stick up or down     |
| Jump        | `Space` / `K`         | A              | **JUMP**                      |
| Sword       | `J` / `E` / `Enter`   | X / B          | **SWORD**                     |
| Walk (slow) | `Shift`               | Left trigger   | Small stick deflection        |
| Pause       | `Esc` / `P`           | Start          | **II**                        |

Ledge grab happens automatically when you fall past a grabbable corner while
moving into it; press up (or jump) to mantle, down to let go. Hold down +
jump to drop through a one-way platform.

## Going native

[Capacitor](https://capacitorjs.com) wraps the same bundle for both stores.
The native projects are generated, not committed:

```bash
npm run build
npx cap add android      # once
npx cap add ios          # once, on macOS
npm run android          # or: npm run ios
```

`capacitor.config.ts` already sets the app id, the dark background that shows
behind the letterbox, and `contentInset: 'never'` so iOS does not pad the
canvas. The page uses `viewport-fit=cover` and the renderer reads
`env(safe-area-inset-*)`, so the HUD and buttons stay clear of notches and the
home indicator.

## Project layout

```
src/
  core/      loop, input, audio, storage, game shell  — no game rules here
  render/    renderer, camera, palette, parallax, tile and character painters
  game/      world, tiles, physics, player state machine, tuning, entities
  ui/        HUD and on-screen touch controls
  scenes/    scene contract and the play scene
  game/levels/   ASCII level definitions
tests/       Vitest suite (physics, world parsing, movement, level sanity)
legacy/      the original Python 2 / pygame prototype, kept for reference
```

The dependency direction is one-way: `game/` never imports from `render/` or
`ui/`, which is why the whole player state machine can be simulated headlessly
in tests with no DOM.

## Authoring a level

Levels are ASCII art. `src/game/levels/level01.ts` is the worked example.

```
 #  solid block        =  one-way platform     H  ladder
 ^  spikes             ~  water                :  background niche
 @  player spawn       *  relic                D  exit door
 t  torch (decor)      p  patrol guard         .  or space — empty
```

Vertical spacing is a design language, not a free choice:

| Rise      | How the player clears it   |
| --------- | -------------------------- |
| 2 tiles   | plain jump                 |
| 3 tiles   | needs a one-way platform   |
| 4 tiles   | needs a ledge grab         |

Those numbers come out of the jump arc in `src/game/tuning.ts`, and
`tests/movement.test.ts` asserts they still hold. Retune the character and the
tests tell you which level geometry just became unreachable.

## Art direction

No image assets. Everything — terrain, skyline, characters, effects — is drawn
from flat polygons out of one small palette in `src/render/palette.ts`:
lit surfaces in gold, everything facing away in crimson, a warm bevel on the
edge between them, and hard offset shadows. The total bundle is ~14 kB gzipped.

Swapping `PALETTE` and `SURFACE` re-lights the entire game, so night, interior
and storm variants are a table edit rather than an asset pass.

## Status

Working: fixed-timestep loop, swept AABB tile physics, one-way platforms,
ladders, the full ground/air/ledge state machine with coyote time and jump
buffering, sword and stomp attacks, hazards, relics, exits, patrol enemies,
follow camera with dead zone and look-ahead, parallax, HUD, touch/gamepad/
keyboard input, save data, and one complete level.

Not built yet: more levels, enemy AI beyond a patrol route, sword blocking and
parries, cutscenes, music, and a title/level-select menu.

## Credits

Earlier two-player sword-fighting prototype (Python 2 + pygame) by Andreas,
with support from Harald P. and Michael W. — preserved under `legacy/`.

## Licence

GPL-3.0-or-later. See [LICENSE](LICENSE).
