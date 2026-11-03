# Working on Swordknights

A mobile-first platform adventure (Prince of Persia cadence) plus a two-player
sword duel (Nidhogg tug-of-war), in **Godot 4.5.1 / GDScript**. No hand-drawn
assets: terrain, skyline, characters, effects and audio are generated from one
palette and one tuning table.

## The one command

```bash
.github/scripts/check_all.sh      # everything CI runs, in CI's order
```

Run it before every commit. It keeps going after a failing stage, so one run
reports everything that is wrong. Stages: `import` → `gdlint` → `parse-check` →
`boot smoke` → `tests`, plus `gdformat` as advisory.

Needs `godot` on `PATH` (or `GODOT_BIN`) and `pip install -r
.github/requirements-ci.txt`.

Other entry points:

```bash
godot --headless --path . --import                               # rebuild .godot/ and the class cache
godot --headless --path . --script tools/configure_project.gd    # regenerate project.godot
python3 tools/generate_tiles_png.py                              # assets/tiles.png from the palette
godot --headless --path . --script tools/build_tileset.gd        # assets/tiles.tres
xvfb-run -a godot --path . --rendering-driver opengl3 \
  --script tools/screenshot.gd -- --scene res://scenes/game.tscn --out /tmp/shots --shots 1,3,6
```

`tools/screenshot.gd` is how a visual change gets judged on rendered pixels
rather than on intent. Use it; the engine renders fine headless under xvfb.

## Invariants — do not quietly change these

**The tick is 60 Hz and fixed.** All simulation lives in `_physics_process`.
Frame counts in the duel spec are literally simulation steps. Nothing
gameplay-relevant may depend on `_process` or on `delta` varying.

**The viewport is 180 units tall, width derived from aspect**
(`canvas_items` / `keep_height`). One tile is 16 px. Authoring, tuning and
collision all use those units.

**`project.godot` is generated.** Edit `tools/configure_project.gd` and re-run
it. The same holds for the tile atlas and TileSet. A setting changed in the
editor is a setting that will be overwritten.

**`scripts/core/tuning.gd` is the single source of the traversal grammar.**
2-tile rise = hop, 3 = one-way step, 4 = ledge grab, `Tuning.gap_tiles()` =
widest flat gap. Those are *derived* from the jump arc, not chosen. Never add a
second derivation elsewhere — that bug has already happened twice. Retuning is
allowed; it must keep the tests in `tests/tuning_grammar_test.gd` and
`tests/level_envelope_test.gd` green.

**`;` is the only comment marker in ASCII levels.** `#` is a solid tile. A `#`
comment silently deletes a row of geometry and shifts everything below it.

**Audio goes through `GameAudio.cue(voice, options)`**, never
`AudioDirector.play()` directly. Autoload names do not resolve at compile time
under `godot --headless --script`, so a direct reference makes the script fail
to load — and a scene then instantiates *without* its script, which is how a
test once passed while measuring nothing.

**Simulated code must not call `move_and_slide()`.** It carries engine-internal
state that GDScript can neither read nor write, so it survives a snapshot
restore and desyncs the netplay rollback. The duel runs its own slide loop over
`move_and_collide()`.

**A `Resource` referenced from a `.tscn` is shared across all instances.** Set
`resource_local_to_scene = true` on anything mutated at runtime (collision
shapes above all), or one duellist crouches the other's hitbox.

**A hazard narrower than grab reach is not a hazard.** The ledge-grab probe
runs every falling frame, so a 2-tile spike pit is free passage. A pit must be
wider than `Tuning.grab_tiles()`, be roofed, or have nothing grabbable on the
far side.

## Tests

| Name | Harness | Runner |
| --- | --- | --- |
| `tests/**/test_*.gd` | `extends GutTest` | collected by GUT |
| `tests/*_test.gd` | `extends SceneTree`, asserts itself, `quit()`s | second phase of `run_tests.sh` |

**New tests should be GUT.** Both naming conventions are load-bearing: a file
matching neither is silently skipped, which loses the coverage *and* leaves the
build green. `tests/net_live.gd`, `tests/duel_support.gd`, `tests/level_asserts.gd`
and `tests/character_poses.gd` are helpers, deliberately not matching either.

A green suite is not evidence on its own. This repository has produced three
distinct "silently green" failures (GUT exiting 0 with zero tests; a script
failing to load so assertions never ran; suites named so the runner never found
them). Each is now a guard in `run_tests.sh` or in the test itself. **When you
find a fourth, add a guard — do not just fix the symptom.** A test that
measures nothing must fail.

## Style

Tabs. Statically typed GDScript (`:=` and explicit return types). Lines ≤ 100.
`gdlint .` from the repository root — it resolves `.gdlintrc` upwards from the
working directory. Two rules are disabled with written reasons; do not disable a
third to go green.

A docstring says what the file is responsible for and why it is built that way.
The repository's comments argue for decisions rather than restate the code —
match that.

## Map

| | |
| --- | --- |
| `docs/architecture.md` | layers, timestep, collision, the input seam |
| `docs/art-direction.md` | the look-and-feel thesis every visual change answers to |
| `docs/character.md` | pose vocabulary, secondary motion, the feel lab |
| `docs/duel-spec.md` | the Nidhogg duel spec, plus three engineering objections to it |
| `docs/level-generation.md` | segment grammar, reachability proof |
| `docs/netplay.md` | host-authoritative prediction and reconciliation over WebSocket |
| `docs/audio.md` | synthesis, buses, adding a voice |
| `docs/ci.md` | workflows, secrets, what the repository owner must enable |

`legacy/` holds the Python/pygame and TypeScript/Vite prototypes. Reference
only; `.gdignore`d and excluded from lint. `.claude/worktrees/` holds agent
copies of the whole project and is excluded from lint and the parse check —
without that, every finding is reported once per worktree and every fix looks
like it failed to apply.

## Git

Commit messages are imperative and say what changed and why ("Make `;` the only
comment marker in the ASCII level format"). No model identifiers in commits, PR
text, or code comments. Do not open a pull request unless asked.
