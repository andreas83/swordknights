# Duel combat

How a duel frame resolves: the fighter, the matrix, the clash, the disarm, the
catch.
The specification this implements is [`duel-spec.md`](duel-spec.md); this file
records what the code does and where it departs from the spec.

The numbers live in `scripts/duel/duel_tuning.gd`. The resolution lives in
`scripts/duel/combat.gd`. The fighter is `scripts/duel/fighter.gd`.

## One frame

The physics tick is a fixed 60 Hz, so every frame count below is a count of
simulation steps. The match owns the order:

```
a.input.apply_bits(bits_a); b.input.apply_bits(bits_b)
a.simulate(DT);             b.simulate(DT)
DuelCombat.resolve(a, b)
```

`simulate()` is a pure function of the fighter's state and one input byte. It
reads no clock, no device and no randomness, which is what lets a client replay
the host's frame and compare checksums. `resolve()` reads every hitbox before it
applies anything, so no outcome depends on which fighter is slot A.

## The thrust

| | Frames | Tuning field |
|---|---|---|
| Whole thrust | 14 | `thrust_frames` |
| Blade live | 1–4 | `thrust_active` |
| Recovery | 5–14 | — |
| Disarm read accepted | 1–5 | `disarm_window` |

Recovery frames cut nothing. A thrust that missed leaves its owner open for
ten frames, which is the price of committing.

## Resolving a blade against a body

`DuelCombat._probe()` asks what the attacker's blade does to the defender this
frame. It checks the **diagonal first**: equal stance against equal posture.

1. **Clash.** Both blades are committed at the same height. They bounce, and
   both fighters are knocked back (`clash_knockback`).
2. **Disarm.** The defender moved their blade *into* the height of a thrust
   that is still inside the disarm window. The attacker loses the sword.
3. **Parry.** The defender's blade was already at that height. The thrust is
   turned aside. Resolved as a clash.

Off the diagonal, the matrix in `duel-spec.md` decides, and the only question
is whether the blade reached the body. A matrix cell of *clash* assumes there is
a blade at that height to turn the thrust. Empty-handed, rolling, or recovering
from a missed thrust, there is nothing there, and the cut lands.

The diagonal gets slightly more reach than a body hit (`blade_reach` against the
guard rect as well as the hurt rect), because two blades meet before either
reaches a body.

### A departure from the spec: you can only parry what you face

The spec's matrix is keyed on heights alone. The code adds one condition: a
defender's blade only turns a thrust aside if the defender is **facing** the
attacker (`_faces()`). Without it, a fighter running away with a matching stance
would be immune to a stab in the back. A duel where the back is safe is not a
duel.

## The disarm window

This is the most important number in the combat system, because it decides
whether a disarm is a **read** or a **spam**.

**What the spec said, and why it changed.** The spec's pseudocode disarms the
attacker whenever the defender changes stance into the attacker's height and the
attacker does not. It never checks that the attacker is attacking. Written that
way, you disarm a motionless opponent by cycling your stance next to them, and
the dominant strategy is to stand close and wave. `duel-spec.md` flags this and
proposes gating the disarm on a thrust in its opening frames. That is what the
code does: `_probe()` only reaches the disarm branch while the attacker is
`THRUSTING` and `state_frame <= disarm_window`, and only when the defender's
`stance_changed` flag is set that frame.

**Why the window is wider than the blade's live phase.** The blade is live for
frames 1–4. The disarm read is accepted through frame 5, the first frame of
recovery. `tests/fighter_frames_test.gd` pins this frame by frame: a stance
change on thrust frames 1 to 5 disarms, on 6 to 8 it does not, and the measured
window is exactly five.

Two things follow from the numbers alone. Four frames is 67 ms and five is
83 ms. Both are well under human visual reaction time, so nobody *reacts* to a
thrust inside this window. A disarm is a prediction: the defender commits their
stance change before the thrust is visible, or as it appears. The one frame past
the live phase keeps a correct prediction that lands on the frame the blade
stops cutting from being scored as a miss.

**What is not recorded.** The fighter agent's own argument for five over four
or six was lost when its container restarted, before it wrote this file. The
two code comments that point here were written expecting that argument. What is
above is derived from the code and the tests, not recovered from the agent.
The spec's guidance stands: start at four to six, and **settle the number by
playing**, not by reasoning. If you change it, change
`tests/fighter_frames_test.gd`'s expected width with it, and write the reason
here.

## The catch

An empty hand can take a thrown sword out of the air, as in Nidhogg. The owner
asked for it. The code is `Fighter._snatch()`, `Fighter.catch_blade()`,
`DuelCombat._catches()` and `_catch()`. The numbers are in `DuelTuning`, under
*the catch*.

### Who catches

Only a fighter with nothing in hand: one who was disarmed, or one who threw and
missed. An armed fighter keeps the deflect: a live thrust bats the blade away,
exactly as before. A sword arriving at an armed fighter who does nothing kills
them. They are not handed a second sword.

### How: a timed snatch, not a catch on contact

THROW with an empty hand is a **snatch**. Until now that press did nothing.
Both hands open in front of the chest, and a blade flying into them while they
are open is caught.

| | Frames | Tuning field |
|---|---|---|
| Whole snatch | 18 | `snatch_frames` |
| Hands open | 1–6 | `catch_window` |
| Recovery | 7–18, standing, no duck, roll or jump | — |
| Taking the blade in hand | 6 | `catch_settle` |
| Reach of the hands | 8 px past the body, top of HIGH to bottom of MID | `catch_reach` |

The brief offered other rules. Each was rejected for what it does to the
throw:

- **Automatic on contact.** Every empty-handed fighter would be immune to a
  chest-high throw for free. The throw at an unarmed opponent, and the throw
  back of a sword you have just picked up, would stop being an attack and
  become a gift. Nobody on either side would have a decision to make.
- **Facing the blade.** This is automatic with one condition, and in a duel
  that condition almost always holds. It is kept as part of the geometry: the
  hands are only on the front of the body. It is not enough as the rule.
- **The blade at body height, not low.** This is kept too, as geometry: the
  hands reach from the face to the bottom of MID, so a LOW throw goes under them
  into the legs. On its own it is automatic again.

A snatch that must be timed makes the catch a read on both sides. That is the
mind game:

- **The thrower picks the height.** A LOW throw cannot be caught; it has to be
  jumped. A HIGH throw can be ducked, and a MID one rolled under. So open hands
  are the right answer to two heights out of three, and the wrong one to LOW.
  The empty-handed fighter has to read the height as well as the moment.
- **The thrower picks the moment.** A snatch at nothing leaves the fighter
  standing for twelve frames, unable to duck, roll or jump. The thrower can
  hold the throw, bait the hands open, and throw into the recovery. That is the
  same price a missed thrust pays, and it is what stops a player from mashing
  the snatch.
- **The thrower picks the distance.** Across 40 px the blade reaches the body
  four frames after it leaves the hand. That is 67 ms, well under reaction
  time, so up close a catch is a prediction. From a quarter of a screen away a
  throw is in the air for twenty frames, and an alert player can react to it.
  The long throw is the one that gets caught. That is the risk of throwing from
  safety.

Why throwing is still worth it:

- The catch does not touch the armed opponent at all, and that is the opponent
  you usually throw at.
- Against an empty hand, a LOW throw, a baited snatch or a close throw still
  kills.
- A catch makes the catcher wait out `catch_settle` before the sword is any use.

**The window, measured.** `tests/fighter_frames_test.gd` plays the edges
instead of assuming them. It throws across 40 px and tries every snatch from
too early to too late, each in a fresh stage. The blade enters the hands' rect
on frame 2 after the throw and reaches the body on frame 4. Snatches pressed on
frames −3 to 4 catch: eight presses. That is `catch_window` plus the two frames
the blade spends in the hands before it reaches the body. One press earlier
dies in the recovery. Every later one is already dead.

Six frames is not chosen the way the disarm window was. That window is
measured from a thrust you cannot see coming. This one is opened by a press
against a blade in flight. Like the disarm window, it wants playtesting rather
than argument. If you change it, the frames test re-derives its edges from the
new number.

### What a catch does

- **The records swap.** The catcher takes the record that was flying; the
  thrower gets the catcher's old record. This is how a pickup works, so there
  are still exactly two swords and both live in the two snapshots. The thrower
  stays empty-handed. The sword they now "own" is the one the catcher lost
  earlier, lying wherever it fell.
- **The catcher is armed at once**, in the `CATCH` state, for `catch_settle`
  frames. The blade is held at the height it came in at: `HIGH` if its centre
  was above the MID band, otherwise `MID`, never `LOW`
  (`DuelTuning.catch_stance()`). While the hands close on it the blade is not up
  to parry with and the fighter cannot act. That is the thrower's one chance to
  run or to sweep. After that the fighter is free, and the stance follows the
  buttons again with zero frames of lock.

### Ties, all resolved the same way on every machine

1. **The same blade would catch and kill on the same frame.** It touches the
   open hands and the body together. **The catch wins**, provided the blade is
   flying into the front of the body. A frame is a sample of continuous motion.
   The hands stand in front of the body on the blade's path, so on that frame
   the blade met the hands first. This is the same rule as a parry beating a cut
   on the diagonal of the matrix, where two blades meet before either reaches a
   body. A blade overtaking a fighter from behind reaches the back first and
   kills, open hands or not.

   `catch_reach` (8 px) is never less than a throw's travel in one frame
   (5.5 px), and `tests/unit/test_duel_catch.gd` holds that. So a throw from
   range is always in the hands on a frame before it reaches the body. The tie
   only decides two cases: a point-blank throw, and a snatch opened on the very
   frame of arrival. Giving those to the kill would make a point-blank throw
   unanswerable and the window's last frame a lie. The snatch already pays for
   its window with twelve frames of recovery, and the thrower already has LOW
   and the bait.
2. **A cut and a catch on the same frame.** The fighter is killed by a thrust or
   finished by a pound on the frame their hands would take a blade. **The cut
   wins.** `resolve()` settles blades and feet against bodies before blades in
   flight, and a dead fighter has no hands.
3. **A deflect and a catch.** A live thrust in the blade's path deflects it
   before any hands are asked.
4. **Two blades on one frame.** Both fighters threw and both snatched. Both
   catches land, in either seat order. The blades in flight are listed before
   any is resolved and found again by identity, because a catch moves records
   between the seats. Walking the seats instead would skip a blade that had just
   moved into a seat already visited, and the outcome would depend on who is
   seat A. `tests/unit/test_duel_catch.gd` resolves the crossing both ways
   round.

### What it looks like

- `FighterArt._snatch()`: both arms out, two open palms on the live frames, and
  the arms sagging over the recovery. A fighter who snatched at nothing is
  *seen* to have done so, as a missed thrust is.
- `FighterArt._catch()`: the blade pulled in point-up before the face (or the
  chest, for a MID catch), the body rocked back, and the edge flashing on the
  first two frames. The pose lasts exactly as long as `catch_settle`, so the
  pose is the window. All of this is in `docs/fighter-poses.png`.
- `match_scene.gd` adds a short camera shake, `GameAudio.cue("catch")` (the
  guard's steel-on-steel, pitched up) and the word **CAUGHT** in the HUD band.
- **There is no frozen frame.** In a duel that would be a correctness bug, not a
  taste; see `docs/feel.md`. The beat is presentation only.
- A catch rings once, however often `NetSession` re-steps its frame: the
  session marks every re-stepped frame as a replay, and the match tells the
  scene of each catch once, through the ledger every presented event goes
  through (`docs/netplay.md`, "Corrected outcomes"). The scene's own
  `CATCH_ECHO` guard that stood in for this is gone.

### Netplay

The catch adds no bytes. The two new states, `SNATCH` and `CATCH`, are appended
after `DEAD`, so every older state keeps its number on the wire. The snatch
window is `state_frame`. The caught blade is a record that was already in a
snapshot. The fighter's block is still 100 bytes, and the checksum already
covers state, frame, stance and both blade records.
`tests/match_fighter_test.gd` writes, reads back and rewrites every frame of a
catch. It replays the catch from before the throw and again from mid-flight,
and checks every frame byte for byte. It also checks that the checksum changes
with the catch state.

## Where else the duel is decided

Not covered here, and documented in the code:

- Sword throw, flight and pickup: `DuelCombat._resolve_flight()`,
  `_resolve_pickups()`, and `scripts/duel/combat_blade.gd`. The catch is above.
- Roll, dive kick, sweep and ground pound: `DuelCombat._apply_strike()` and the
  fighter's state machine.
- The movement profile: `DuelTuning`, which the match hands to each fighter in
  `setup()`. The fighter never reads `scripts/core/tuning.gd`; the duel is not
  the adventure.
