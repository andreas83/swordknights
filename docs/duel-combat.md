# Duel combat

How a duel frame resolves: the fighter, the matrix, the clash, the disarm.
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

## Where else the duel is decided

Not covered here, and documented in the code:

- Sword throw, flight and pickup: `DuelCombat._resolve_flight()`,
  `_resolve_pickups()`, and `scripts/duel/combat_blade.gd`.
- Roll, dive kick, sweep and ground pound: `DuelCombat._apply_strike()` and the
  fighter's state machine.
- The movement profile: `DuelTuning`, which the match hands to each fighter in
  `setup()`. The fighter never reads `scripts/core/tuning.gd`; the duel is not
  the adventure.
