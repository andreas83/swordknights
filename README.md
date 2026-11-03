# Swordknights

A mobile-first platform adventure in the spirit of *Prince of Persia*:
deliberate, weighty movement, ledge grabs, and a sun-bleached duotone city —
plus a two-player sword duel in the spirit of *Nidhogg*, playable on one
keyboard or over the network.

Built with **Godot 4.5.1**. There are no hand-drawn assets — terrain, skyline,
characters and effects are all generated or drawn from one small palette.

![The Sun Terrace](docs/screenshot.png)

## Running it

Open the project folder in Godot 4.5, or from a terminal:

```bash
godot --path .                 # play
godot --headless --path . --import   # import assets / rebuild the class cache
```

The engine binary is not vendored. Get 4.5.1 from the
[Godot releases page](https://github.com/godotengine/godot/releases/tag/4.5.1-stable).

## Controls

| Action      | Keyboard            | Gamepad       | Touch                      |
| ----------- | ------------------- | ------------- | -------------------------- |
| Move        | `←` `→` / `A` `D`   | Stick / D-pad | Left half — floating stick |
| Up / down   | `↑` `↓` / `W` `S`   | Stick / D-pad | Push the stick up or down  |
| Jump        | `Space` / `K`       | A             | **JUMP**                   |
| Sword       | `J` / `E` / `Enter` | X / B         | **SWORD**                  |
| Walk (slow) | `Shift`             | L1            | Small stick deflection     |
| Pause       | `Esc` / `P`         | Start         | **II**                     |
| Mute        | `M`                 | —             | —                          |

Ledge grabs happen automatically when you fall past a grabbable corner while
moving into it; press up (or jump) to mantle, down to let go. Hold down and
press jump to drop through a one-way platform.

In the local duel both players share one keyboard. A Godot action cannot tell
two gamepads apart, so these bindings are keyboard-only by design:

| Action       | Player one | Player two          |
| ------------ | ---------- | ------------------- |
| Move         | `W A S D`  | Arrows / numpad `8456` |
| Jump         | `Space` / `V` | `K` / numpad `0` |
| Sword        | `F`        | `J` / numpad `1`    |
| Guard        | `G`        | `L` / numpad `2`    |
| Walk (slow)  | `Shift`    | `;` / numpad `3`    |

The networked duel uses the single-player bindings above, plus `Q` / `L` or
R1 to guard.

## Project layout

```
project.godot          written by tools/configure_project.gd, not by hand
scripts/
  core/      palette, tuning, boot, game controller, mode registry
  world/     ASCII level parser, tilemap level node
  player/    character state machine, input seam, character art
  entities/  relic, exit door, torch, patrol guard
  render/    follow camera, procedural parallax skyline
  ui/        HUD, menu, touch controls
  audio/     synthesis, mixer autoload, character sounds, music
  levels/    segment grammar, generator, reachability verifier
  duel/      two-player duel: rules, camera, HUD, art, local and online hosts
  net/       transport, protocol, session, lobby, rendezvous server
scenes/      boot, menu, game, player, duel, rendezvous, touch controls
levels/      ASCII level and arena files
assets/      generated tile atlas + TileSet
tools/       project configuration, asset generation, screenshots
tests/       headless test scripts
legacy/      earlier prototypes (Python/pygame, TypeScript/Vite), .gdignore'd
```

## Configuration as code

Project settings and the whole input map live in `tools/configure_project.gd`
rather than in editor state, so every binding is reviewable in a diff and
reproducible on a fresh clone:

```bash
godot --headless --path . --script tools/configure_project.gd
```

The same applies to art. The terrain atlas and its TileSet are generated:

```bash
python3 tools/generate_tiles_png.py        # assets/tiles.png from the palette
godot --headless --path . --script tools/build_tileset.gd   # assets/tiles.tres
```

Re-lighting the world — night, interior, storm — is an edit to
`scripts/core/palette.gd` plus those two commands, not an art pass.

## Authoring a level

Levels are ASCII art. `levels/level_01.txt` is the worked example.

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

Horizontally, `Tuning.gap_tiles()` is the widest flat gap a running jump
crosses.

All four numbers come out of the jump arc in `scripts/core/tuning.gd`. Retune
the character and the grammar moves with it; `tests/tuning_grammar_test.gd`
and `tests/level_envelope_test.gd` fail if a level's geometry stops matching
what the character can do.

**A hazard narrower than grab reach is not a hazard.** The ledge-grab probe
runs every frame while falling, so a 2-tile spike pit is free passage: you
drop in, catch the far wall and mantle out. A pit has to be wider than
`Tuning.grab_tiles()` to cost anything — or be roofed, or have nothing
grabbable on the far side. This caught out the duelling arena, where both
fighters simply walked across the spikes.

## Screenshots without a screen

`tools/screenshot.gd` renders any scene off-screen and writes PNGs, which is
how visual changes get checked in CI and on headless machines:

```bash
xvfb-run -a godot --path . --rendering-driver opengl3 \
  --script tools/screenshot.gd -- \
  --scene res://scenes/game.tscn --out /tmp/shots --shots 1,3,6 --hold move_right
```

## Documentation

| | |
| --- | --- |
| [`docs/architecture.md`](docs/architecture.md) | layers, fixed timestep, collision, the input seam |
| [`docs/art-direction.md`](docs/art-direction.md) | the look-and-feel thesis: one low sun, cast shadows, hard edges |
| [`docs/world.md`](docs/world.md) | cast shadows, shade twins, architecture dressed onto terrain |
| [`docs/character.md`](docs/character.md) | pose vocabulary, secondary motion, the feel lab |
| [`docs/feel.md`](docs/feel.md) | camera beats, hitstop, the wipe, haptics |
| [`docs/ui.md`](docs/ui.md) | the Alcazar typeface, safe areas, variable width |
| [`docs/duel-spec.md`](docs/duel-spec.md) | the Nidhogg duel specification, with three engineering objections |
| [`docs/duel-combat.md`](docs/duel-combat.md) | how a duel frame resolves: matrix, clash, parry, disarm window |
| [`docs/duel-match.md`](docs/duel-match.md) | the tug-of-war: initiative, zones, respawn, gore, open items |
| [`docs/level-generation.md`](docs/level-generation.md) | segment grammar and the reachability proof |
| [`docs/netplay.md`](docs/netplay.md) | host-authoritative prediction and reconciliation |
| [`docs/audio.md`](docs/audio.md) | synthesis, buses, adding a voice |
| [`docs/ci.md`](docs/ci.md) | workflows, secrets, what the repository owner must enable |

Contributors — human or agent — should start at [`CLAUDE.md`](CLAUDE.md): one
command to run every check, and the invariants that are not safe to change
quietly.

## Status

Working: tilemap world with solid, one-way, ladder and hazard tiles; the full
ground/air/ledge character state machine with coyote time, jump buffering,
variable jump height and apex float; sword and stomp attacks; relics, exits
and patrol guards; dead-zone follow camera; procedural parallax skyline; HUD;
keyboard, gamepad and touch input; mode menu; build, test and release
pipeline; procedural level generation with a reachability proof; procedural
audio — synthesised sound effects, an Andalusian music loop with an intensity
parameter, and persisted volume and mute settings; a two-player duel, both on
one keyboard and over the network, with host-authoritative prediction,
reconciliation and a desync test.

In progress: rebuilding the duel on the *Nidhogg* model — one hit kills, three
sword stances that clash or kill, disarm, sword throw, and a tug-of-war over a
chain of zones instead of rounds and health bars. The specification and the
objections to it are in [`docs/duel-spec.md`](docs/duel-spec.md).

Not built yet: more hand-authored levels, enemy AI beyond a patrol route,
cutscenes.

## History

This repository started as a two-player sword-fighting prototype in Python 2
and pygame, and passed through a TypeScript/Vite/Capacitor foundation before
moving to Godot. Both are preserved under `legacy/` — the feel tuning, the
ASCII level format and the palette were carried across rather than reinvented.

## Credits

Original prototype by Andreas, with support from Harald P. and Michael W.

## Licence

GPL-3.0-or-later. See [LICENSE](LICENSE).
