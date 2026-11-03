# Duel specification

The duel mode is a Nidhogg-style tug-of-war. This document is the design
owner's specification, transcribed, followed by engineering notes where the
specification and the engine disagree.

The adventure mode is unaffected by everything here.

## 1. Fighter state machine

```
                  +-----------------------------------+
                  |               IDLE                |
                  +-----------------------------------+
                    |         |             |       |
            Run-Input |   Jump-Input |   Duck-Input |   | Attack-Input
                    v         v             v       |
              +---------+ +--------+   +----------+ |
              | RUNNING | | JUMPING|   | DUCKING  | |
              +---------+ +--------+   +----------+ |
                    |         |             |       |
              Roll-Input  Divekick-Input Roll-Input |
                    v         v             v       v
               +--------------------------------------+
               |  ROLLING  | DIVEKICK |   THRUSTING   |
               +--------------------------------------+
                                  |
                           Weapon Lose / Throw
                                  v
                        +--------------------+
                        | UNARMED_COMBAT_FSM |
                        +--------------------+
```

Transitions are **prioritised**: `DEAD` overrides every other state.

| State | Rule |
| --- | --- |
| IDLE / RUNNING | Stance may change freely between HIGH, MID and LOW. **Zero frames of animation lock.** |
| THRUSTING | 12–15 frames total. Frames 1–4 the blade hitbox extends forward (active). Frames 5–15 are recovery and the fighter is vulnerable if the thrust missed. The fighter drifts slightly forward during the thrust. |
| ROLLING | 25 frames. Hurtbox compressed to ~30% of standing height, which passes under HIGH and MID attacks and under thrown swords. **No invulnerability** — a LOW thrust kills a rolling fighter. |
| DISARMED / UNARMED | Its own sub-machine. Leg sweep knocks the opponent down; ground pound finishes a downed opponent. Standing over a dropped sword and pressing down picks it up in one frame. Throw with an empty hand snatches a thrown sword out of the air (implemented; see the sword throw below). |

## 2. Combat matrix

Resolution is between the attacker's blade hitbox and the defender's hurtbox,
keyed on the two stances.

| Attacker ↓ \ Defender → | HIGH | MID | LOW | DUCKING |
| --- | --- | --- | --- | --- |
| **HIGH** | clash / parry | kill (head, torso) | kill (head, torso) | miss — passes over the head |
| **MID** | kill (torso) | clash / parry | kill (torso) | kill (head) |
| **LOW** | kill (legs) | kill (legs) | clash / parry | kill (torso) |

A body hit is an instant kill. There is no health.

### Clash and disarm

```
function resolveSwordCollision(p1, p2) {
  if (p1.stance === p2.stance) {
    if (p1.isAttacking && p2.isAttacking) {
      // Both thrust at the same height: the blades bounce off each other
      triggerParryEffect(p1.swordTip, p2.swordTip);
      applyKnockback(p1, -2.0);
      applyKnockback(p2, -2.0);
    }
    else if (p1.isStanceChanging && !p2.isStanceChanging) {
      // P1 changes stance into the level of P2's active blade: disarm
      disarmPlayer(p2);
    }
  }
}
```

### Sword throw

- Trajectory is a straight line parallel to the ground, angled slightly up
  with `up` + throw.
- Lethal on contact with any unguarded hurtbox.
- Countered by ducking, rolling, or a thrust that deflects the flying blade.
- **Caught out of the air by an empty hand, as in Nidhogg.** *Added at the
  owner's request; implemented.* Only an unarmed fighter catches, and only
  with a timed snatch: THROW with nothing to throw opens the hands for six
  frames, and a HIGH or MID blade flying into them is caught. A LOW throw
  cannot be. The catcher is armed with that blade at once and the thrower stays
  unarmed. When the hands and the body are touched on the same frame, the hands
  win. The rule, the numbers, the ties and why it is a timed snatch rather than
  a catch on contact are in [`duel-combat.md`](duel-combat.md#the-catch).

## 3. Initiative and zones

```
enum LeaderState { NEUTRAL, PLAYER_1, PLAYER_2 }

class TugOfWarManager {
  currentLeader = NEUTRAL;
  currentZoneIndex = 0;
  totalZones = 5;

  onPlayerKilled(killer, victim) {
    currentLeader = killer.id === 1 ? PLAYER_1 : PLAYER_2;
    showArrowUI(currentLeader);
  }

  canScrollToZone(direction) {
    if (currentLeader === PLAYER_1 && direction === -1) return true;
    if (currentLeader === PLAYER_2 && direction === 1) return true;
    return false;
  }
}
```

Player one pushes left toward zone 0; player two pushes right toward zone N.
Running the wrong way does not scroll the world.

### Respawn

1. Victim dies.
2. A 2.0 second timer starts.
3. The spawn point is computed from the **leader's** current position, placed
   roughly 1.5 screen widths ahead in the leader's direction of travel.
4. The respawning fighter faces the leader, to intercept them.
5. Edge case: if the leader is already at the edge of the final zone, the
   opponent spawns directly in front of the exit.

## 4. Feel, physics and visual rules

- **Gravity:** very high. No floaty moon jumps.
- **Acceleration:** maximum speed within 1–2 frames.
- **Friction:** high — releasing the input stops the fighter within 2–3 frames.
- **Collision:** AABB for bodies, rectangles for blades. No circles.
- **Persistent gore:** every kill sprays particles in the dead fighter's
  colour, and those stains stay on the wall and floor for the rest of the
  match.

---

# Engineering notes

Three places where the specification as written will not survive contact with
the engine or with a competitive player. These are flagged, not silently
changed — the design calls stay with the design owner.

## The disarm rule disarms idle opponents

The pseudocode gates disarm on `p1.isStanceChanging && !p2.isStanceChanging`
inside the same-stance branch. It never checks that **p2 is attacking**. As
written, moving your blade to the height of a motionless opponent's resting
blade disarms them, so the dominant strategy is to stand next to someone
cycling stances until their sword falls out.

The prose above the pseudocode says the opposite — *"while player B attacks"*
— so this reads as an omission rather than an intent. Proposed:

```
else if (p1.justChangedStanceInto(p2.stance) && p2.isAttacking
         && p2.attackFrame <= DISARM_WINDOW) {
  disarmPlayer(p2);
}
```

A window measured in frames from the start of the opponent's thrust is what
makes disarm a read rather than a spam. The window length is the single
most important number in the combat system and wants playtesting, not a
guess; start around 4–6 frames, i.e. the active phase of the thrust.

## Render-to-texture gore is expensive on the target

The specification asks for stains baked into the wall and floor textures. On
a phone, with the GL compatibility renderer, a render target covering five
zones is tens of megabytes of VRAM that exists only to hold splatter.

Cheaper and visually identical at this resolution: keep a bounded,
per-zone list of decals — position,colour, a few polygon points — and draw them
in one pass beneath the actors. A few hundred per zone is far more than a
match produces, costs kilobytes, survives a zone revisit, and needs no render
target at all. It also keeps the duel's checksum clean, because decals are
presentation and must never enter the snapshot.

If the stains must physically accumulate into the tiles later, that is a
render-target optimisation to add once it is proven necessary.

## Blades do not need oriented rectangles

The specification asks for "oriented rectangles for the sword". In a 2D side
view with exactly three discrete stances, a thrust is horizontal at one of
three heights — the rectangle is always axis-aligned. An AABB per stance is
cheaper, exactly as precise here, and strictly more deterministic, which
matters because the duel is host-authoritative and verified by checksum.

Oriented rectangles become necessary only if a diagonal or arcing attack is
added later.

## Two notes that are not objections

- **The frame counts map 1:1.** The engine's physics tick is fixed at 60 Hz
  (`docs/architecture.md`), so "12–15 frames" is literally 12–15 simulation
  steps. This is the payoff for the fixed timestep.
- **Everything here is simulation state.** Stances, thrown blades, dropped
  blades, disarm timers, initiative, zone index and respawn timers all go in
  the network snapshot; gore, dust and camera do not. See `docs/netplay.md`,
  and note that a single field hiding outside the snapshot is what produced
  the one desync we have had so far.
