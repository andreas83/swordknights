# Level generation

A seeded generator that chains hand-shaped beats into an ASCII level and then
*proves* the exit can be reached before handing it over.

```
godot --headless --path . --script tools/generate_level.gd -- \
  --seed 51759241 --length 150 --difficulty 0.9
```

Three files do the work, and they are layered so each one can be read on its
own:

| File | Responsibility |
|---|---|
| `scripts/levels/grammar.gd` | the segment vocabulary and the ASCII stamps |
| `scripts/levels/generator.gd` | chaining, entity placement, retries, rendering |
| `scripts/levels/reachability.gd` | the solvability proof |

Plus `tools/generate_level.gd` (CLI), `scenes/generated_game.tscn` with
`scripts/levels/generated_game.gd` (the Endless mode), and the `level_*`
suites in `tests/`.

## The one rule everything else follows

Level geometry is **derived from the jump arc, not chosen**. Three vertical
distances make up the whole design language:

| Rise | Cleared by | Comes from |
|---|---|---|
| 2 tiles | a plain hop | `Tuning.hop_tiles()` |
| 3 tiles | a one-way platform used as a step | `Tuning.platform_step_tiles()` |
| 4 tiles | a ledge grab | `Tuning.grab_tiles()` |

`LevelGrammar.hop_rise()`, `step_rise()` and `grab_rise()` are thin wrappers
over those helpers and nothing in the generator writes 2, 3 or 4 by hand.
Retune the character and the grammar moves with it: a slower `JUMP_SPEED`
turns today's hop into tomorrow's platform step, and the segments stamp
themselves one tile taller or shorter without anyone editing them.

Horizontal distance works the same way. `LevelGrammar.max_gap_tiles()` is the
widest chasm a running jump crosses, and it is derived, not guessed — see
[The 60 Hz detail](#the-60-hz-detail) for why it is integrated frame by frame
rather than solved in closed form.

## The grammar

A **segment** is a parameterised ASCII stamp modelled on one of level 01's
beats. Every segment declares:

- `entry` and `exit` height, in tiles above the lowest ground the generator
  emits;
- `width`, in columns;
- `difficulty`, its intrinsic hardness on the same 0..1 scale the caller asks
  for;
- `params`, everything the stamp needs, resolved up front.

| Segment | Rise | Difficulty | What it is |
|---|---|---|---|
| `terrace` | 0 or down | 0.00 | flat ground, optionally stepping down — the connective tissue, and the grammar's only descent |
| `relic_alcove` | 0 | 0.15 | a pedestal a hop high with a relic on it and a backdrop niche behind |
| `cistern` | 0 | 0.20 | a pit with a ladder out of it: a safe failure that teaches climbing |
| `gap` | 0 | 0.30 | a bottomless chasm to jump |
| `platform_stair` | +3 per step | 0.35 | a one-way platform floating a hop above the ground, then a step up to the next level |
| `guard_post` | 0 | 0.45 | a wide ledge with a patrolling guard |
| `spike_pit` | 0 | 0.55 | a narrow notch with spikes at the bottom |
| `water_basin` | 0 | 0.65 | a brim-full basin — no lip to scramble onto |
| `grab_wall` | +4 | 0.75 | a vertical face exactly `grab_rise()` tall |

### Why chaining cannot leave a seam

Two properties do it, and neither depends on the generator being careful:

1. The next segment's `entry` *is* the previous segment's `exit`. The chainer
   carries one `height` variable and never invents one.
2. Every segment fills its own ground — `_ground()` writes solid from the
   segment's surface row all the way down to the bedrock, for every column it
   owns. Nothing is left to a neighbour, so adjacent segments at the same
   height are indistinguishable from one terrace and adjacent segments at
   different heights meet as a clean vertical face.

There are no overhangs anywhere in the grammar: the terrain is a heightfield
with pits carved into it. That is what makes headroom automatic — the only
thing that is ever above walkable ground is sky or a one-way platform.

### Adding a segment

Five steps, all in `scripts/levels/grammar.gd`:

1. **Add it to `templates()`** with an `id`, a `difficulty` and an `ascent`
   hint. The hint is for the chainer's weighting, not a promise.
2. **Teach `fits(id, entry)` about it** if it needs headroom. This is
   consulted *before* any random draw, so the rng stream never depends on
   which candidates were rejected — which is what keeps seeds stable when you
   add a segment that does not apply everywhere.
3. **Add a branch to `instantiate()`** that resolves `width`, `exit` and
   `params`. Every random choice the segment makes happens here and nowhere
   else. Use `_pick(rng, lo, hi, difficulty)` so the parameter widens with
   difficulty, and derive distances from `hop_rise()` / `step_rise()` /
   `grab_rise()` / `gap_limit(difficulty)` rather than from literals.
4. **Add a `_stamp_<id>()`** and wire it into `stamp()`. It receives the
   resolved spec and no rng at all, so a stamp is replayable and testable on
   its own. Return entity anchors — `{kind, cell}` for `relic`, `patrol` or
   `torch` — and let `_torch_marks()` handle torches, because it re-checks
   that the cell it was given is empty with ground under it.
5. **Run the suites.** `level_solvability_test.gd` will tell you immediately
   if the new segment is sometimes impassable: it shows up as a jump in the
   retry rate, not as a mysterious failure.

Keep landing zones at least two columns wide. A jump holding a direction
travels about 24 px horizontally before the feet come back down, so a
one-column perch is routinely overshot — the verifier is right to refuse it,
and the segment will simply never be chosen.

### Difficulty

Difficulty does three things, and `tests/level_difficulty_test.gd` pins each:

- **Gates the vocabulary.** A segment harder than `difficulty +
  DIFFICULTY_TOLERANCE` never appears. At 0.1 there are no grab walls and no
  water; at 0.95 there are plenty of both.
- **Widens parameters.** `_pick()` biases toward the wide end, and
  `gap_limit()` only opens up to the full `max_gap_tiles()` at 0.85 and above.
- **Sets entity budgets.** More guards, more relics.

It also ramps across the level: the effective difficulty runs from 55% of the
request at the spawn to 100% at the exit, so a level opens on a terrace and
earns its ledge-grab wall rather than starting with one.

## The reachability proof

`LevelReachability.verify(level)` returns `{ok, reason, explored, ...}`. It is
the reason a generated level can be trusted, so it is worth being precise
about what it does and does not claim.

### It is a simulation, not a heuristic

Nothing in it hardcodes a jump height or a gap width. It steps the same
arithmetic `scripts/player/player.gd` steps, at the same fixed 60 Hz:

- the two-phase gravity of `_apply_gravity()`, reduced near the apex;
- the `move_toward()` ground and air control of `_free_movement()`;
- per-axis collision against the tile grid, sliding along walls the way
  `move_and_slide()` does;
- the one-way platform layer — ignored going up, landed on coming down, and
  switched off entirely during the 0.25 s drop-through window;
- `_try_grab_ledge()` step for step, including the hand probe position, the
  "solid tile with nothing solid on top" test, the hang-rect clearance check
  and the stand-rect check that decides whether the mantle has room to finish.

Because it is a simulation, the reach envelope is an *output*, not an input.
`LevelReachability.measure_reach()` asks the simulation directly — it builds
synthetic probes and reports what they clear:

| Probe | Isolates | Result |
|---|---|---|
| a one-way platform `n` tiles up | the plain hop (a platform is not solid, so it cannot be grabbed) | `hop` |
| a solid wall `n` tiles tall | the ledge grab | `grab` |
| two terraces `n` columns apart | the running jump | `gap` |

`tests/level_envelope_test.gd` asserts those measurements equal
`Tuning.hop_tiles()`, `Tuning.grab_tiles()` and
`LevelGrammar.max_gap_tiles()`. That is the link that makes the whole thing
tamper-evident: change a tuning constant and either the measured envelope
follows or the suite fails.

### The search

States are `(cell, mode)` where mode is standing or on a ladder. Standing in
cell (x, y) means the body fits there — cells (x, y) and (x, y-1) free of
solid and of hazards — and something holds it up at (x, y+1).

From a standing state the search offers, per direction:

- **walk** one cell, same row (a one-tile step needs a hop, so this is flat
  only);
- **jump** at full run speed, and again from a standing start — the short arc
  is what reaches a narrow ledge the running jump sails over;
- **jump straight up** while facing that way, the only arc that grabs a wall
  you are already pressed against;
- **jump from the lip** and **walk off the edge**, when there is a drop ahead.

Plus **drop-through** when the floor is a one-way platform, and **ladder**
entry whenever the body overlaps one — including mid-arc, which is how falling
into a cistern and climbing out works.

Each arc is stepped frame by frame and records everything it proves: where it
lands, every ledge it could grab on the way down, every ladder it passes
through. An arc that touches spikes or water stops there and contributes
nothing beyond that point, because the player would be dead.

The queue is bucketed by manhattan distance to the exit — greedy best-first.
A solvable level is usually settled in a few dozen expansions (level 01 takes
31) instead of flooding the map, while an unsolvable one still explores
exhaustively and reports unreachable rather than timing out.

### It is deliberately conservative

Where the real character has an option this model does not reproduce, the edge
is simply not offered:

- coyote-time jumps after walking off a ledge;
- releasing or reversing the stick mid-arc;
- jumping off a ladder;
- wall-sliding down to a lower ledge;
- crouch-walking under a one-tile ceiling;
- leaning the last ~4 px out over a drop before jumping — the lip takeoff is
  modelled at the tile boundary, where half the body is still over solid
  ground, and the genuine overhang past that is given up.

So **"verified" means "reachable even by this reduced character"**, never
"reachable if you play perfectly". Erring the other way would make the proof
worthless, which is why the right response to a generator that fails too often
is a change to the grammar, never a loosening here.

The counterweight — the thing that stops conservatism becoming uselessness —
is that `tests/level_envelope_test.gd` verifies `levels/level_01.txt`, a level
a person designed and played. A model that could not route through it would be
too strict to generate anything good.

### From somewhere other than the spawn

`verify_from(level, start, proved)` runs the same proof from any standing
cell, and treats arriving at any cell in `proved` as arriving at the door.
`Game.checkpoint_cells()` uses it to decide which torches are checkpoints
(see `docs/feel.md`): a place the player has stood is reachable by
definition, but the exit is not necessarily reachable *from* it, and a
checkpoint in a dead end would be a soft lock. Torches are proved from the
door backwards, each one only as far as the last one proved.

### Retries

`LevelGenerator.build()` verifies every candidate. A rejected one is retried
under a fresh sub-seed from `LevelGenerator.sub_seed(seed, attempt)`, a hash
of the original — so a retry is exactly as reproducible as a first attempt,
and all `MAX_ATTEMPTS` sub-seeds for a seed are distinct, so no attempt is
wasted regenerating a candidate that was already rejected. After 24 attempts
it pushes an error and returns `null` rather than a broken level.

In practice the retry path is cold: across the 240 seeds in
`level_solvability_test.gd`, every one verified on the first attempt. That is
the grammar and the verifier agreeing, and the suite fails if more than a
quarter of seeds ever need a retry.

## The 60 Hz detail

Worth knowing about, because it bit this code and will bite the next change.

The game is a fixed-timestep simulation, and semi-implicit Euler at 60 Hz does
not agree with the closed-form arc. The continuous solution says a jump rises
35.56 px over 0.5911 s; the engine actually rises 33.36 px over 0.5833 s.

That 0.7 px of lost reach is the difference between a 3-tile gap being
crossable and not. `LevelGrammar.jump_airtime()` therefore integrates the arc
frame by frame instead of solving it, and `max_gap_tiles()` measures between
positions the character can really occupy — taking off from the ledge lip and
landing as soon as the far edge of the body is over the landing tile.

The tier integers survive the discrepancy (33.36 px still clears two tiles,
and the hand probe still reaches into the fourth row), which is why
`Tuning`'s closed-form helpers remain correct — but a future retune could
easily land somewhere the two disagree, and `measure_reach()` is what would
catch it.

## A trap in the ASCII format

`AsciiLevel.is_comment()` treats a line of exactly `#`, or one beginning
`"# "`, as a comment. A grid row whose first tile is solid and whose second is
blank therefore **disappears when the level is parsed back**, silently, taking
its row with it and shifting everything below.

`LevelGrammar.Canvas.to_lines()` guards against this: such a row gets its one
blank written as `.`, which the legend also maps to empty. At most one glyph
changes and the row stays hand-editable.
`tests/level_determinism_test.gd` checks every generated level still has
`LevelGrammar.ROWS` rows after a round trip, which is what would catch a
regression.

## Playing one

**Endless** in the main menu (`scripts/core/mode_registry.gd`) runs
`scenes/generated_game.tscn`. It does not duplicate the game scene — it
instantiates `res://scenes/game.tscn` and hands the generated level over
through `Game.level_source`, which must be set **before** `add_child()`
because `Game._ready()` is what reads it. Endless and Adventure therefore
always run the identical playable scene.

A fresh seed is rolled each entry and shown top-right for the whole level, so
a good roll can be written down and replayed:

```
godot --headless --path . --script tools/generate_level.gd -- --seed <that one>
```

Set `seed_override` on the scene to pin one from the editor.

Some seeds worth looking at, all at the default length 170:

| Seed | Difficulty | Why |
|---|---|---|
| 51759241 | 0.90 | *Gilded Gallery* — opens straight onto a 4-tile grab wall with a guard posted on top of it; three grab walls, climbing to height 8 |
| 51759241 | 0.55 | *Old Reservoir* — the same seed read gently: platform stairs instead of grab walls, climbing to 9 past basins and spike pits |
| 225741179 | 0.55 | *Shifting Causeway* — a cistern and its ladder as the second beat, then stairs up, a long drop back to 2, and stairs up again |
| 2024 | 0.60 | *Drowned Catacomb* — a double platform stair lifting 3 → 9 early, then a four-tile drop into the middle of the level |
| 1 | 0.50 | *Gilded Catacomb* — stairs all the way to the ceiling height of 9 and back down; a good gentle smoke test |

The same seed at two difficulties is the clearest way to see the dial work:
51759241 is the same chain of ideas at 0.55 and 0.90, built out of different
beats.

## Running the tests

No framework; each suite is a standalone headless script that exits non-zero
on failure.

```
godot --headless --path . --script tests/level_envelope_test.gd
godot --headless --path . --script tests/level_determinism_test.gd
godot --headless --path . --script tests/level_placement_test.gd
godot --headless --path . --script tests/level_difficulty_test.gd
godot --headless --path . --script tests/level_solvability_test.gd
```

| Suite | Covers |
|---|---|
| `level_envelope_test` | measured reach vs `Tuning`; glyphs vs the tile legend; each primitive proved necessary by a probe that fails without it; level 01 verifies |
| `level_determinism_test` | same seed to the byte, independence from the global RNG and from call order, round-trip through the parser, sub-seed distinctness |
| `level_placement_test` | spawn and exit on solid ground with headroom, no entity in a wall or a hazard or sharing a cell, and that the verifier refuses broken levels |
| `level_difficulty_test` | the vocabulary gate, hazard and guard density, gap and rise sizes, both ends of the dial playable |
| `level_solvability_test` | 240 seeds across four lengths and six difficulties, independently re-verified |

`tests/level_asserts.gd` is the shared helper. It is `preload`ed rather than
registered with `class_name`, so it cannot collide with a real test framework
landing in `tests/` later.
