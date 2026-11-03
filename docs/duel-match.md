# The duel match: a tug-of-war

The match layer turns two fighters into a Nidhogg match: a strip of zones, an
initiative that decides which way the world scrolls, respawns, and two gates.
The specification is [`duel-spec.md`](duel-spec.md) §3. How a single exchange
of blades resolves is [`duel-combat.md`](duel-combat.md).

![Three frames of a demo match](duel-match.png)

*Rendered with `tools/screenshot.gd` from `scenes/duel_match.tscn --demo`, on
the real fighter, in the prince's figure (`scripts/duel/fighter_art.gd`). The demo's
kills are scripted so a screenshot at a given second is always the same one.
Rings are respawn timers, the track at the top is zone and initiative.*

## The pieces

| File | Owns |
|---|---|
| `scripts/duel/match.gd` (`DuelMatch`) | initiative, scroll, respawn timers, win condition, snapshot, checksum |
| `scripts/duel/match_sim.gd` (`DuelSim`) | the surface the network session drives; the match implements it |
| `scripts/duel/match_seat.gd` (`DuelSeat`) | the **only** place that touches a fighter |
| `scripts/duel/match_ledger.gd` (`MatchLedger`) | what the scene has been told, against what the history holds; presentation only |
| `scripts/duel/zones.gd` (`ZoneStrip`) | the zones as data, and every collision question |
| `scripts/duel/zones_view.gd` | streams the zones' drawn layers near the camera, dressed and lit |
| `scripts/duel/gore.gd` (`GoreField`) | decals, presentation only |
| `scripts/duel/match_camera.gd`, `match_hud.gd`, `match_gate.gd` | presentation |
| `scripts/duel/duel_brain.gd` (`DuelBrain`) | the computer opponent: one input byte a frame from a `DuelView` |
| `scripts/duel/duel_view.gd`, `duel_eyes.gd`, `duel_cpu.gd` | what it may see, how late, and the order that keeps it honest |
| `scripts/duel/duel_feet.gd` (`DuelFeet`) | where its jumps land: the moat, the pit and the benches |
| `scripts/duel/match_cpu.gd`, `scenes/duel_match_cpu.tscn` | Duel vs CPU: the match with seat two's byte from the computer |
| `levels/duel_zones.txt`, `levels/zone_0*.txt` | the strip: a manifest and five zones |

## One frame

`DuelMatch.step(bits_a, bits_b)` is one frame, and the frame is a function of
nothing but the match's state and those two input bytes. That is the promise
the round duel made and the network session relies on: a client replays the
host's frames and compares checksums. `docs/netplay.md` explains what it buys.

Inside the frame, in this order: both inputs applied, both fighters simulated,
then `DuelSeat.referee()` — blade against blade through `DuelCombat.resolve()`,
then each body against the ground's hazards (spikes, water, falling out of the
world). Blades go first, so a fighter cut down over the spikes is credited to
the blade. The fighter resolves its own frame and nothing else; refereeing two
of them is the match's job.

The real fighter moves with `move_and_collide()`, so it needs ground in the
physics space. The match builds that itself, once per match: a hidden tilemap
of every solid and one-way cell of the whole strip (`_build_ground()`). The
view's tilemap is streamed and only draws — its collision is off — because a
streamed floor is one two peers could hold differently.

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
every zone from the level text, always, and the physics a fighter moves against
is the match's own ground layer, built whole. Only the *drawing* is streamed —
each zone's tile layers, dressed and lit — three zones around the view plus
wherever a fighter stands or is about to respawn. A simulation whose
answers depended on what had finished loading would be one two peers could
disagree about.

## The snapshot is the bandwidth

`snapshot_bytes()` is `HEADER_BYTES` (44) plus two fighter blocks. The four
time-and-distance values in the header are doubles, not floats: they are
compared against thresholds, and rounding a threshold comparison to 32 bits
moves a transition by a whole frame.

The checksum quantises every float to 1/256 before hashing, so noise in the
last bit cannot fire it. The real fighter supplies its own share
(`Fighter.checksum_into()`), because its 100-byte state mixes doubles and
int32s and only it knows which bytes are which. A fighter that does not hash
itself — the placeholder — is read back as a run of float64s, so its state must
be a whole number of them; `build()` refuses one that is neither.

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

## The zones

One screen each, one set piece each, and the stake rises toward either end
(`levels/duel_zones.txt` lists them):

| Zone | | Set piece | Stake |
| --- | --- | --- | --- |
| 3 | the Mirror Court | flat floor wall to wall, a low gallery in the middle | none: the start |
| 2, 4 | the Cistern Court | a spike pit three tiles wide, a stepping stone over it | a hazard with help |
| 1, 5 | the Gates | the arch, the crowd, and a moat of open water one jump out | a hazard with none, at dusk |

**The moat is two tiles, not three.** The duel fighter has no ledge grab, so
any gap is a hazard, and its running jump carries about 42 px. Over a
three-tile (48 px) moat exactly one press frame gets across; over two tiles a
run gets across if jump is pressed anywhere in a window of about eight frames
(16 px), and walking in still kills. `tests/match_fighter_test.gd` runs at the
moat from both gates and holds the window to at least four frames, and fails
with a three-tile moat. The pyramid of steps that stood there before came out
to make room, which raised the gate zones' open ground from 14 to 18 of 30
columns; the strip is 86 of 150, a little over half.

A respawn's zone is streamed in when its timer **starts**, not when the fighter
appears, so the only stream not triggered by travel has two seconds' warning.

## Gore

A bounded list per zone (`GoreField.MAX_PER_ZONE`, 192), not a render target.
Five zones are about fifty kilobytes and no VRAM, against tens of megabytes for
a render target on a phone. The list survives a zone being streamed out and
back because it is not in the tilemap. Shapes are seeded from the frame and the
seat, so both screens show the same splatter — without it being simulation.
The blood is fed by `death_recorded` and `death_retracted`, not by the beat
(`fighter_died`): a reconciling client paints each death once, takes back the
blood of a predicted kill the host never had, and moves a kill the correction
moved to the host's frame and place. `docs/netplay.md`, "Corrected outcomes",
has the rule and the argument for it.

## The computer opponent

**Duel vs CPU** (`scenes/duel_match_cpu.tscn`) is the one-keyboard match with
seat two's input byte taken from the computer instead of the keyboard
(`_step()` in `scripts/duel/match_cpu.gd`; the rest of that file is names and
seeds). It is the only way to duel on one phone. The player is seat one,
crimson, on the shared actions — the stick, JUMP, SWORD and THROW on a phone,
the single-player keys or a gamepad on a desktop — and the computer wears the
wardrobe's second look, in sea-green.

### What it may know

The opponent is a `DuelBrain`, and all it is ever handed is a `DuelView`, one
per frame. It answers with one byte of `PlayerInput`, the same eight bits a
keyboard, a replay or the network produce, and the match steps it exactly as
it steps a person. It holds no match, fighter, seat or input object, so it
cannot touch a rule and cannot read the player's buttons. That is checked on
the scripts themselves, not promised (`tests/unit/test_duel_cpu_seat.gd`).

| In the view | As of |
| --- | --- |
| its own fighter | the last frame stepped |
| the other fighter, the swords out of hand, the initiative, the other's respawn timer | `reaction` frames before the frame being decided |
| the level and the fighter's numbers | always: they never change, and both are on the screen |

**The order of a frame** is `DuelCpu`'s: the computer's bits are chosen from
frames already stepped, then the frame is stepped with the player's bits —
read off the input map there, for the first time — then the frame is looked
at. `DuelEyes` keeps a copy of what each frame showed, so "acts on what it saw
N frames ago" is literally a picture N frames old; subtracting N frames of
motion from the live match would be a guess at the past made with the present
in hand. The seat test changes the player's input on one frame and holds the
computer to the same bytes for its whole reaction time, and to different ones
after it. Hand the brain the newest picture instead and the test fails: the
computer answers one frame later.

**Why its own fighter is not late.** A player knows what their own thumbs are
doing without waiting to see it, and a jump over the moat timed off a picture
of yourself a third of a second old is a suicide, not a reaction. Everything
the other player did reaches it late; nothing they are doing reaches it at all.

### How it plays

Range is most of Nidhogg. A thrust reaches a body at 27 px between the feet
(`body_width + blade_reach`) and a resting blade at 34. Between the two — the
edge — a thrust can be parried or read but cannot kill, so the computer fences
from there:

- **Guard.** It holds the other fighter's height, which parries, as often as
  its level guards, reconsidered every 8 to 24 frames rather than every frame.
- **Read.** From the edge it flicks into the other's height one frame in four.
  Four is inside the five-frame disarm window
  ([`duel-combat.md`](duel-combat.md#the-disarm-window)), so a thrust from the
  edge always meets a flick on its way in. Inside the edge it stops flicking:
  a mismatched stance there is a dead one.
- **Attack.** It picks an open line — a height the other is not holding, and
  of those the one they hold least, from a running count of their stances —
  shows it for `tell` frames, steps in and thrusts. If they moved into it
  during the tell, a `feint` takes the other open line on the thrust frame;
  without one the thrust goes where it was shown, and is parried. A thrust
  that missed, a snatch at nothing, a disarmed or downed fighter is punished
  at once, with no tell. The longer two fighters stand at the edge the likelier
  an attack, so two careful fighters do not stand there forever.
- **Throw.** At a back running away, low by preference, because a low throw
  cannot be caught and has to be jumped; at range now and then. A throw coming
  at it is ducked if high, rolled under if middle and jumped if low, and the
  dodge is held until the blade is out the other side of the body. Empty-handed
  it snatches a high or middle throw instead, then fetches the nearest sword it
  can reach — never one in the water — and sweeps and stamps if there is none.
- **With the initiative** it runs for its gate and does not fight. A respawn
  in its way is vaulted: jumped if its blade is low, and otherwise rolled under
  seven times in ten and jumped the rest, so the vault is not a certainty to
  wait for. A jump comes down inside the other's reach, so once past, with them
  following, it rolls, which is faster than they can run. Near the end of the
  strip it stops short of the spot in front of the gate where the other is
  about to reappear: the rule (`DuelMatch.respawn_plan`) and the ring counting
  it down are both on the screen.
- **Without it**, it waits on the open ground a respawn puts it on, blade up,
  and meets the runner where it stands rather than running at them (two
  fighters closing at once close faster than either can see); thrusts low at a
  roller; chases, and throws at, one who got past; and goes and gets one who
  stops coming rather than waiting for a runner who will not run.

**The ground.** Every step goes through `DuelFeet`, which integrates the
fighter's own motion — the acceleration, gravity, jump cut and terminal speed
from `DuelTuning`, in the order `Fighter.simulate()` applies them — against the
tiles the referee kills on, and says where a jump lands. It tries a full jump
and two hops and takes the best on the first frame one lands well onto its
footing; at the lip it takes any safe one; with none it stops. A jump, roll,
thrust or throw the brain asks for is refused if it would come down in a
hazard. The prediction is the grid's and the fighter's motion is the physics
engine's, and the two part at corners: a one-way platform's corner does not
reliably catch a body falling past it, so a landing counts only with three
pixels of the body over footing (`DuelFeet.FOOTHOLD`). The easy opponent once
drowned off a landing with six hundredths of a pixel of the moat's far lip
under it, so `tests/unit/test_duel_cpu_feet.gd` sweeps every lip in twentieths
of a pixel against an oracle that shares no code with the rule.

### The levels

`DuelBrain.PROFILES`, one dictionary per level. Every knob is one a player can
feel; none of them is how much it is allowed to know.

| | EASY | MEDIUM | HARD |
| --- | --- | --- | --- |
| reaction: frames late it sees the other | 20 | 13 | 8 |
| anticipate: how far it leads a moving fighter | 0.4 | 0.5 | 1.0 |
| tell: frames it shows a thrust's height first | 22 | 10 | 4 |
| feint: chance to switch line on the thrust | 0 | 0.15 | 0.4 |
| guard: chance to hold the other's height | 0.3 | 0.65 | 0.9 |
| flick: chance to fish for a disarm at the edge | 0 | 0.25 | 0.5 |
| blunder: chance a thrust, vault or dodge goes wrong | 0.35 | 0.12 | 0.04 |
| aggression: attacks a second at the edge | 0.45 | 1.0 | 1.8 |
| throw: chance a second at a back running away | 0.2 | 0.5 | 0.9 |
| slop: frames late it jumps a hazard, never past the lip | 2 | 1 | 0 |

EASY is built to be beaten by someone who has just picked the game up: it sees
a third of a second late, shows every thrust's height for a third of a second
before it comes, guards one time in three and gets one thing in three wrong.
HARD sees in eight frames, which is quicker than a person, and is kept a fight
rather than a wall by its blunders and by the fact that it, too, cannot see a
thrust coming inside the disarm window: it guesses, as a person does.

### Seeds

All its chance comes from one `RandomNumberGenerator`, seeded in `reset()` and
drawn only inside `decide()`. The same seed and the same player inputs are the
same match, every checksum equal; a different seed is a different match
(`tests/unit/test_duel_cpu_bouts.gd`). The scene prints the level and the seed
when a match starts, takes `--seed=N` and `--cpu=easy|medium|hard` in the user
arguments, and takes the next seed for a rematch. The player's inputs are not
recorded, so a printed seed alone does not yet replay a match someone played;
see the open items.

### Measured

Headless, on the real fighter, at most three minutes a match:

| Against | Result |
| --- | --- |
| the closing bot of `tests/match_net_test.gd`, made to run for its gate when it leads; 20 seeds a level | EASY won 7, MEDIUM 17, HARD 20 |
| the same in the suite, 10 seeds a level | EASY 5, MEDIUM 8, HARD 10 |
| itself, 10 seeds a pairing | every match finished: EASY–EASY in 1,004 frames on average, MEDIUM–MEDIUM in 2,057 (longest 4,988), HARD–HARD in 3,145 (longest 8,917); HARD beat EASY 10 times in 10 and MEDIUM 8 |
| a scripted human (the determinism suites' input stream), 12 seeds a level | the computer won every match; the hands killed EASY 6 times, MEDIUM 8, HARD 2 |
| the ground, across all of the above | no deaths |

The suite holds HARD to eight wins in ten against the bot, EASY to losing some
and winning some, MEDIUM between them, every computer-against-computer match to
an end, and hazard deaths to one in twenty; each of those was seen to fail with
the behaviour behind it broken.

### Open

- **The numbers are measured against scripts, not people.** Whether EASY is
  beatable by a newcomer on a phone, and whether HARD is a fight rather than a
  wall, wants playing on a phone, as the disarm window did. The knobs are in
  one table for that.
- **The level is not saved.** The menu remembers it for the session
  (`ModeRegistry.choose`) and opens every launch on EASY.
- **A real match cannot be replayed from its seed alone** until the player's
  inputs are recorded with it.
- **Moves it does not use:** the dive kick, the thrust in the air, and turning
  a throw aside with a thrust.

## Tests

- `tests/match_initiative_test.gd` — leader state, the ratchet, the window.
- `tests/match_respawn_test.gd` — every leader position on the strip at 4 px
  intervals: timer, lead distance, facing, open ground, final zone, the
  pacifist line.
- `tests/zone_strip_test.gd` — loading, seams, spawn columns, and that no cell
  is written on a frame a fight crosses a seam.
- `tests/unit/test_zone_dressing.gd` — the zones are dressed and lit as one
  world, and none of it reaches the simulation.
- `tests/match_fighter_test.gd` — the match on the real fighter, including the
  gate moat: walking in kills, a running jump crosses.
- `tests/unit/test_duel_cpu_seat.gd` — the computer holds nothing it could
  peek through, presses only bytes a person could, and answers the player's
  input no sooner than its reaction time.
- `tests/unit/test_duel_cpu_bouts.gd` — replay from a seed, the win rates by
  level, computer against computer always finishing, and a leader who will not
  run being fetched.
- `tests/unit/test_duel_cpu_feet.gd` — every hazard crossed by the real fighter
  from a run and from a standstill, and the landing rule against an oracle.
- `tests/unit/test_duel_cpu_mode.gd` — the menu's row and levels, and the scene
  stepping both seats.
- `tests/match_gore_test.gd` — gore never reaches state or checksum, and the
  list is bounded.

## Status

**The match runs on the real fighter.** `scenes/duel_match.tscn` builds it,
and `tests/match_fighter_test.gd` plays matches on it: the seam hands over the
world and the checksum, the fighters stand on the ground, a thrust kills
through the match and moves the initiative, a hazard kills, two runs on the
same inputs agree frame by frame, and a rewind to a snapshot replays 300 frames
byte for byte. Each of those checks was seen to fail with its fix removed.

The match's own suites still run on the placeholder in `match_stub_fighter.gd`,
on purpose: they test the rope, and do not need a physics space.

All three menu entries run the match — Duel, Duel vs CPU and Duel Online —
and **the round duel is retired**: its
simulation, scenes, camera, HUD and art are gone, and so is the duel-only code
it needed in `scripts/player/player.gd` (guard, stagger, first-blood and its own
slide loop — the prince is the adventure's again). What its tests proved about
netplay now runs on the match: `tests/net_desync_test.gd` (a recorded host,
prediction, reconciliation, a detector that fires on a tampered snapshot and
stays quiet through loss and lag) and `tests/duel_determinism_test.gd` (two
sims agree, a snapshot round trip is exact, and a burst equals a paced run).
`tests/net_live.sh` plays the match between two processes. The tests of the
round duel's own rules and arena went with it.

Moving the paced-run check onto the real fighter found one thing the round
duel did not have: a burst and a paced run part by about 1e-4 px. It is inside
the checksum's quantum, and the test now holds it there and prints it; see
the last item in [`netplay.md`](netplay.md#not-handled-yet).

The five items that stood between the match and replacing the round duel:

1. ~~Zone width.~~ **Decided: a fighter stands 8–9% of the screen's height**,
   and the strip follows from that. The camera scales by height
   (`MatchCamera.FIGHTER_SHARE`, 0.085) at a whole number of screen pixels per
   texel — 8.1% at 1080 px tall, 9.2–9.4% at 1170–1440 — and snaps to the pixel
   grid, so texels are all one size on any aspect. At that scale phones show
   506–600 px of world, so a zone is 480 px (30 tiles,
   `ZoneStrip.SCREEN_WIDTH`) and always fits across: both fighters are on
   screen at every moment, as the mode needs. On narrower screens — a 16:9
   720p device, a 4:3 tablet — the camera follows the pair. The five zones were
   cut from 40 columns to 30 by removing only columns identical to their
   neighbour, chosen to keep the most open ground, so every gate, ladder,
   ledge and mark survived and the share of respawnable floor held at about
   half. The respawn lead is 1.5 × 480 = 720 px. `--framing=<px>` still frames
   a fixed width, for comparisons.
2. ~~The fighter is drawn as its hitboxes.~~ **The fighter wears the
   prince's figure** (`fighter_art.gd` extends `PlayerArt`), with the sword
   drawn exactly on the simulation's blade rect. See
   [`character.md`](character.md#the-duel-fighter-wears-the-same-figure) and
   `docs/fighter-poses.png`.
3. ~~The zones are bare.~~ **The zones are dressed and lit by the level
   path** ([`world.md`](world.md#the-duels-zones)). `ZoneView` dresses the
   whole strip once with `WorldDresser`, solves a full-resolution shadow mask
   per zone with `SunShadow`, and draws each streamed zone with `Level`'s own
   layers and shader material. Presentation only: every layer has collision
   off, the strip's identity does not change, and
   `tests/unit/test_zone_dressing.gd` holds both, plus a per-zone shadow
   that matches a solve over everything to its west pixel for pixel. In a
   duel the foreground plane is drawn at 55% so it never hides a fighter.
4. ~~The HUD is on the fallback font.~~ **The HUD is set in Alcazar**, on
   `UiFont`, `UiLayout` and `UiMarks` like every other screen
   ([`ui.md`](ui.md#duel-hud)): chrome at the top of the safe area, words for
   events and the result only in the reserved band, and a second, shorter
   phrasing for a 320-unit screen. `tests/ui_screens.gd` renders it as
   `match`, `match_flash` and `match_over`.
5. ~~The menu and the network session.~~ The menu's **Duel** is the match on
   one keyboard, and **Duel Online** is the match between two devices
   (`scenes/duel_match_online.tscn`, `scripts/duel/match_online.gd`): the lobby,
   transport and session of the round duel around the match's own scene, with
   touch controls and a THROW button. Phones on one Wi-Fi pair with a
   one-number code (`scripts/net/lan_code.gd`). `tests/match_net_test.gd` plays
   it between two sessions under latency, jitter and loss, and
   `tests/net_live.sh` between two processes, direct and relayed.

Task 14, the zone design, is done to the extent above: a set piece per zone and
a rising stake. Left for a designer's eye rather than a test: whether the
middle court should be flatter still, and whether the gate zones want a second
feature between the moat and the arch.
