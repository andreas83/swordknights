# The duel match: a tug-of-war

The match layer turns two fighters into a Nidhogg match: a strip of zones, an
initiative that decides which way the world scrolls, respawns, and two gates.
The specification is [`duel-spec.md`](duel-spec.md) §3. How a single exchange
of blades resolves is [`duel-combat.md`](duel-combat.md).

![Three frames of a demo match](duel-match.png)

*Rendered with `tools/screenshot.gd` from `scenes/duel_match.tscn --demo`. The
fighters in it are placeholders and are not drawn — see "Status" below. The
rings are respawn timers, the pools are gore, the track at the top is the zone
and initiative indicator.*

## The pieces

| File | Owns |
|---|---|
| `scripts/duel/match.gd` (`DuelMatch`) | initiative, scroll, respawn timers, win condition, snapshot, checksum |
| `scripts/duel/match_sim.gd` (`DuelSim`) | the surface the network session drives; both duels implement it |
| `scripts/duel/match_seat.gd` (`DuelSeat`) | the **only** place that touches a fighter |
| `scripts/duel/zones.gd` (`ZoneStrip`) | the zones as data, and every collision question |
| `scripts/duel/zones_view.gd` | streams tilemap cells near the camera |
| `scripts/duel/gore.gd` (`GoreField`) | decals, presentation only |
| `scripts/duel/match_camera.gd`, `match_hud.gd`, `match_gate.gd` | presentation |
| `levels/duel_zones.txt`, `levels/zone_0*.txt` | the strip: a manifest and five zones |

## One frame

`DuelMatch.step(bits_a, bits_b)` is one frame, and the frame is a function of
nothing but the match's state and those two input bytes. That is the promise
the round duel made and the network session relies on: a client replays the
host's frames and compares checksums. `docs/netplay.md` explains what it buys.

## Simulation and presentation

The line is drawn on purpose, and tests hold it.

**Simulation** — in `write_state()` and the checksum: the frame, phase,
initiative, zone index, winner, kill counts, phase time, both respawn timers,
the scroll, and both fighters' state. Initiative computed separately on each
peer is initiative that eventually disagrees, and the disagreement is a match
where one screen scrolls and the other does not.

**Presentation** — never in the snapshot: gore, the camera, the HUD. A
presentation field inside the snapshot is as bad as a simulation field outside
it; it would make a blood spot something two peers could diverge over.
`tests/match_gore_test.gd` proves gore never touches state.

**Geometry is never streamed.** `ZoneStrip` answers every collision question for
every zone from the level text, always. Only the *tilemap cells* — and so the
engine's physics bodies built from them — are streamed, three zones around the
view plus wherever a fighter stands or is about to respawn. A simulation whose
answers depended on what had finished loading would be one two peers could
disagree about.

## The snapshot is the bandwidth

`snapshot_bytes()` is `HEADER_BYTES` (44) plus two fighter blocks. The four
time-and-distance values in the header are doubles, not floats: they are
compared against thresholds, and rounding a threshold comparison to 32 bits
moves a transition by a whole frame.

The checksum quantises every float to 1/256 before hashing, so noise in the
last bit cannot fire it. It reads each fighter block as a run of float64s, so a
fighter's state must be a whole number of doubles; `build()` refuses one that
is not.

## Initiative and the window

The spec's `LeaderState`, kept to its names. A match opens `NEUTRAL`; nothing
scrolls until someone has died. **Every death hands the initiative to the other
fighter**, whatever did the killing: a fall onto spikes is credited to the
opponent. A death reported twice scores once.

The playable window is one zone wide and **slides continuously**. The leader
drags it, and it only ever moves in the leader's goal direction. That one-way
ratchet *is* "the screen opens only in the leader's direction": running the
wrong way walks you into the trailing wall instead of scrolling the world back.
Because the window slides rather than snapping zone to zone, crossing a seam is
not an event anywhere in the code, and there is nothing at a seam to stutter.

## Respawn

From the spec, with its numbers:

- `RESPAWN_DELAY` — 2.0 s.
- `RESPAWN_LEAD` — 1.5 screen widths ahead of the leader, in the leader's
  direction of travel, facing the leader.
- Only on **open ground**: `FLAT_RUN` cells of unbroken floor either side and
  `HEADROOM` clear rows above, so the leader can always jump over or roll past
  the respawned fighter. That keeps the pacifist line open: a leader is never
  forced to fight.
- At the final zone the respawn goes in front of the gate, with a standoff
  (`GATE_STANDOFF`). The gate's lintel in `zone_01.txt` sits high for exactly
  this reason: the leader has to be able to go over the top.

A respawn's zone is streamed in when its timer **starts**, not when the fighter
appears, so the only stream not triggered by travel has two seconds' warning.

## Gore

A bounded list per zone (`GoreField.MAX_PER_ZONE`, 192), not a render target.
Five zones are about fifty kilobytes and no VRAM, against tens of megabytes for
a render target on a phone. The list survives a zone being streamed out and
back because it is not in the tilemap. Shapes are seeded from the frame and the
seat, so both screens show the same splatter — without it being simulation.
The match does not emit `fighter_died` while replaying a corrected frame, so a
reconciling client does not paint the same death twice.

## Tests

- `tests/match_initiative_test.gd` — leader state, the ratchet, the window.
- `tests/match_respawn_test.gd` — every leader position on the strip at 4 px
  intervals: timer, lead distance, facing, open ground, final zone, the
  pacifist line.
- `tests/zone_strip_test.gd` — loading, seams, spawn columns, and that no cell
  is written on a frame a fight crosses a seam.
- `tests/match_gore_test.gd` — gore never reaches state or checksum, and the
  list is bounded.

## Status

The match is **built against a placeholder fighter** (`match_stub_fighter.gd`),
as agreed when the work was split, and **nothing in the game loads it yet**:
the menu's DUEL still starts the round-based duel in `scripts/duel/duel.gd`.
Both duels implement `DuelSim`, which is why they can coexist.

Open before the match replaces the round duel:

1. **The real fighter does not fit the seat yet.** `Fighter.level` is typed
   `Level`, but the seat hands it a `ZoneStrip`; `Fighter.state_bytes()` is 100,
   not a whole number of doubles; and the fighter collides through the physics
   space, which is the part that is streamed.
2. **The zones are bare.** `zones_view.gd` builds its own tilemap, so the
   architecture and cast shadows in [`world.md`](world.md) do not run on them.
3. **The HUD is on the fallback font**, not the game's typeface ([`ui.md`](ui.md)).
4. **A zone is 640 px wide and the view is 320.** `ZoneStrip.SCREEN_WIDTH` is a
   640 px "design screen", so the camera zooms to 0.5 to fit a zone — and to
   about 0.63–0.69 on wider phones. The game is landscape-only already, so the
   view is 320–440 units wide whatever the device.

   No pixels are lost: the stretch mode is `canvas_items`, which draws 2D at
   the screen's native resolution, so at 0.5 every texel is a clean 2×2 block
   at 720p (measured on `duel-match.png`'s source frames). Two real costs
   remain. **Size:** a fighter is half its adventure size, about 6% of the
   screen's height, and whether the three blade heights still read at that
   size is a question for a phone in hand. **Uneven texels:** at 20:9 and
   1080p the scale is 3.75 screen pixels per texel, so texels alternate 3 and
   4 pixels wide and shimmer when the view scrolls; the frames also show a
   slight vertical unevenness, because the camera is not snapped to the texel
   grid. The second is fixed by snapping the zoom to a whole number of screen
   pixels per texel and showing a little more than one zone, whatever width a
   zone is. The first is a design decision, not a bug, and it is not made
   yet.
