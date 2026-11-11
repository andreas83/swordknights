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

## Stance, footwork and the duck

Up is HIGH, nothing is MID, and **down is LOW**, standing still as much as
running. **WALK** is footwork: held with a direction, the fighter shuffles that
way at `walk_speed` (48 px/s, against a run's 120) and does *not* turn round,
so a guard can give ground with the blade still toward the opponent. **The
duck is down with WALK**: planted, 13 px tall, under a HIGH blade and a HIGH
throw.

| Input | Standing | With a direction |
|---|---|---|
| nothing | MID guard | run, turning that way, MID |
| up | HIGH guard | run, HIGH |
| down | **LOW guard** | run, LOW |
| WALK + direction | -- | shuffle, keeping the facing, at the held stance |
| down + WALK | **duck** | duck (planted; the direction is ignored) |
| down + jump | roll | roll |

### What was wrong

Down standing still used to *be* the duck, and the duck is the matrix's fourth
column, which LOW kills. The only way to hold a LOW guard was down and a
direction together: running into the blade. Backing off turned the fighter
round, so a LOW thrust could be guarded only by walking into it. A bot that
thrust nothing but LOW beat EASY 24 times in 24, and finished 17 of 18 against
MEDIUM. The computer's own "LOW guard" and its LOW flick were ducks too, so the
read `duel-match.md` describes did not exist at LOW.

The duck also leaked into the thrust. Nothing cleared it on the way into
`THRUSTING`, so a thrust from a duck kept the 13 px body under a HIGH blade
while its own LOW blade killed, and two of them met as a double kill instead
of a clash.

### Why down is the guard and down + WALK the duck, not the other way round

The choice is made for the phone stick. The adventure's stick
(`scripts/ui/touch_controls.gd`) presses a direction past a 7-unit dead zone,
up or down past 14, and WALK when the push is sideways and small (between 7
and 16.5 units of a 30-unit stick). The duel's now reads the same push by its
angle; see *The stick*, below, for why and for the numbers.

- **The guard is held; the duck is a moment.** A fencer holds a stance for
  seconds at the edge of reach. The duck is a dodge for the frames a HIGH blade
  or a throw takes to pass. The steadiest thing a thumb can hold on a stick is
  a straight push, so the straight push is the stance. It is LOW, as up is
  HIGH: one rule for all three heights, standing or running.
- **The other way round, the LOW guard could not stand still on a phone.**
  Down + WALK as the guard needs a sideways push to press WALK, and a sideways
  push moves the fighter. Every LOW guard would shuffle, which is the bug
  again in a new form.
- **The duck stays reachable.** On a phone it is the stick pushed down and a
  little to either side; on a keyboard, `S` with `Shift` (seat two, `↓` with
  `;`). Whichever side the stick leans, the duck is planted, so a lean the
  wrong way costs nothing.
- **It is a smaller move than it was.** The roll goes under HIGH and MID
  blades and throws, and needs no diagonal. The duck is kept for what only it
  does: stay where you are, under a HIGH blade, with the blade coming back to
  you.

### A thrust is made standing

Out of a duck the body comes up into the thrust (`Fighter._begin_attack`). The
duck is a dodge, never a stance to stab from. So a thrust from a duck against a
HIGH thrust on the same frame is two thrusts at different heights, and both
land. Two thrusts from ducks are two LOW thrusts, and they clash. The punish
from a duck is timed: wait under the HIGH blade until its four live frames are
over, then come up into its recovery.

### The read is the posture, not the button

`stance_changed`, which the disarm read is built on, is now "the posture moved
this frame" rather than "the stance moved". Standing up out of a duck into LOW,
or out of a knockdown into MID, moves the blade into that height as surely as
pressing down does: a duck holds no height at all. So both are reads.

`tests/combat_matrix_test.gd` holds every defender posture standing still, LOW
included. `tests/unit/test_duel_fair_fencing.gd` holds the stationary LOW
parry, the LOW disarm from a standstill and from a duck, WALK backing off with
the guard still up (and a run turning the back), the duck planted under HIGH,
and the thrust from a duck as designed. Each was seen to fail with the old
rule put back.

### The stick

The owner, after the build above: *ducking works well; the LOW guard is not
quite clear*. Asked whether he could tell he was in a LOW guard, and tell it
from the duck, he said no. Two things were wrong, one in the thumb and one in
the picture.

**The thumb.** On the adventure's stick, straight down was the guard only while
the thumb stayed within the 7-unit dead zone of the vertical: under 3 mm on a
phone. A thumb pulled down to hold a guard wanders more than that, and past it
the stick pressed a direction and WALK as well, which is the duck, which every
LOW thrust kills. The guard flickered into ducks, and every flicker moved the
posture. So the scenes that duel on a phone set `TouchControls.stance_stick`,
and below the stick's middle the push is read by its angle
(`TouchControls.stance_actions()`):

| Push, below the middle | Pressed | The fighter |
|---|---|---|
| within 22.5° of straight down (`STANCE_CONE`, the eight-way stick's own sector) | down | **LOW guard**, standing still |
| leaning further, or any sideways push short of a run | down, the direction, WALK | **duck**, planted |
| flatter than 45° with a run's push (16.5 units or more aside) | the direction | **run**, no down |

- **The lane widens with the push.** It is an angle, not a width: at a 30-unit
  push the thumb may wander 12 units either side and still hold LOW. The
  further a player pulls to say "guard", the more room the guard gets.
- **The duck stays a lean away.** It is still down and a little sideways, as
  the owner liked it; it now starts at 22.5° rather than at 7 units, which at a
  20-unit push is 8 units instead of 7, and a full diagonal push -- which used
  to be a run at LOW -- is a duck too. The duck plants, so which way it leans
  costs nothing.
- **A sagging run holds no down.** A running thumb that drifts below the
  horizontal used to press down past 14 units, which held LOW and turned the
  next JUMP into a roll. Flatter than 45° at a run's push, the stick is a run
  and nothing else. Down + JUMP is still the roll, from straight down or a
  lean, standing or running.
- **Up is the same lane.** Straight up holds HIGH standing still; a lean up
  shuffles at HIGH and a run up runs at HIGH, as before.
- **The adventure keeps its stick.** The prince crawls on down and a direction,
  and a crouch that needed a 22.5° lean to crawl would change a game that was
  not broken. `tests/unit/test_duel_stick.gd` holds the adventure's mapping push
  for push.

On the stick's base the two guard lanes are scored, and over it -- above the
thumb, which covers the knob -- the stick says what it holds: **HIGH**, **LOW**,
**DUCK**, or a dim **MID**. Read off the actions the stick is pressing, so the
word and the fighter cannot disagree about the buttons.

**Where it is said.** Every round opens with a plate in the band (MatchHud,
THE ROUND): ROUND n, or FINAL ROUND, the score, and how the guard and the duck
are held on this screen -- *STICK STRAIGHT DOWN: LOW GUARD · DOWN AND ASIDE:
DUCK* on a phone, *S OR DOWN: LOW GUARD · WITH SHIFT: DUCK* on a keyboard,
both seats' keys on one keyboard. It shows over the countdown, when the
fighters are held on their marks and the band is free.

### Seeing the guard

**The picture.** The LOW guard was the MID figure with its level blade seven
pixels lower: at phone scale, a blade at the knee of the same figure. The duck
was a folded figure holding the *same* level blade at the *same* height, since
the duck is down with WALK and down is LOW. Two pictures with a low blade in
them, one a guard and one the posture LOW kills. Now each height has a body of
its own (`FighterArt.GUARDS`, a table) and the blade a slant (`BLADE_SLOPE`):

| | Body | Blade |
|---|---|---|
| HIGH | back on the heels, free hand before the chest | point up |
| MID | the square stance it always had | level |
| LOW | the tallest of the three, feet planted wide, hood down the blade, the free arm thrown up and back | point down at the other's shins |
| duck | folded to 13 px | none along the guard: the sword is pulled up behind the shoulder |

The slant is drawn inside the simulation's blade rect, a pixel in from its top
and bottom, so the rule that the picture of the sword *is* what parries still
holds. A duck parries nothing, so it no longer draws a blade where a guard
would be. A thrust keeps its height's slant, so a LOW thrust is seen aimed at
the shins, and the rise out of a roll carries the sword trailing behind.

**The parry.** When blades meet, each fighter's blade strikes a spark where it
is (`FighterArt._on_clashed()`): at the shins for a LOW parry. The height that
turned the thrust is the height that lights up.

Judged on rendered pixels, at a phone's scale, on both figures and in the
Well's night as well as the Tug's afternoon: `docs/fighter-poses.png` and
`docs/heroine-fighter-poses.png` set HIGH, MID, LOW, the duck and a LOW parry
side by side. `tests/unit/test_duel_guard_poses.gd` holds the slants, LOW's
height and arm, the duck's empty guard and the spark on the rig's own points,
and was seen to fail against the art as it was.

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

## The roll and the dive kick: moves that cost

Both were free, and both decided matches on their own.

### The roll ends in recovery

| | Frames | Tuning field |
|---|---|---|
| Rolling, 7 px tall | 1–25 | `roll_frames` |
| Rising (`RISING`): standing height, no blade up, no input | 26–32 | `roll_recover` |

A roll had no recovery, so two chained kept a fighter 7 px tall for 116 frames
in 120, under every HIGH and MID blade and every throw above LOW. Now chained
rolls spend 99 frames in 120 low at most, and every rise is seven frames of
standing body with no blade up. The matrix reads a rising fighter's stance,
but with no blade up, so any height cuts it. Seven is inside the six to eight
asked for. It is enough for a fighter standing where the roll ends to thrust
into it, since a thrust is live on its first frame. It is short enough that a
roll past a blade from outside its reach is still the way past.

`RISING` is appended after `CATCH`, so every older state keeps its number on
the wire. The fighter's block is still 100 bytes. Under a low ceiling the rise
is at duck height, as the end of a roll always was.

### The dive kick buys a reset, not a kill

| | Before | Now | Tuning field |
|---|---|---|---|
| Kicker planted after landing | 10 | 16 | `divekick_recover` |
| Kicked fighter down | 45 (the sweep's) | 12 | `kick_downed_frames` |
| Swept fighter down | 45 | 45 | `downed_frames` |

The kick knocked its target down for the sweep's 45 frames while the kicker got
up in 10. A LOW thrust kills a fighter on the floor, so the kick was a kill
with extra steps: 12 kicks, 12 kills against a standing guard, and a bot that
did nothing else beat EASY 12 times in 12.

Now the kicked fighter is up first. The knockdown runs from the moment the kick
lands, in the air, and the kicker still has the rest of the dive and 16 frames
on the ground. A thrust on the kicker's first free frame meets a fighter who
has had a few frames to choose a height. Rising into the thrust's height is a
read (above), so the kicker can lose the sword. The probe that killed 12 times
in 12 now kills 0 times. What the kick still does is end whatever the target
was doing, put them on the floor for 12 frames and knock them back. It breaks a
turtle and opens a path past them. It no longer decides the exchange.

**Why not make the kick disarm instead?** A disarm is the read the whole
matrix is built to reward: a stance moved into a thrust inside five frames.
Handing it out for a jump would make the cheap move pay the skill ceiling's
price. A disarmed fighter is ten frames from free, with the sword on the floor
in front of the kicker, and an armed fighter against an empty hand wins most
exchanges. A short knockdown keeps the kick as a tool and the disarm as the
read.

The sweep keeps its 45 frames. It is the empty hand's way back into a fight,
and the spec gives its finisher to the ground pound. The fighter remembers how
long this knockdown is in the commitment counter, which was already in the
snapshot, so no bytes were added. `tests/unit/test_duel_fair_fencing.gd` plays a
kick and the LOW thrust after it, and was seen to fail with the sweep's 45
frames put back.

## The jump

The owner, on a phone: jumping felt better in the adventure than in the duel.
Measured frame by frame on the real bodies (the prince in `scenes/game.tscn`,
the fighter on a ledge of tiles, stepped one 60 Hz frame at a time):

| | Adventure (prince) | Duel, before | Duel, now |
|---|---|---|---|
| Held jump: apex | 38.1 px, frame 19 | 33.4 px, frame 10 | 33.4 px, frame 10 |
| Held jump: airtime | 39 frames | 21 frames | 21 frames |
| Running jump: reach | 57.2 px at 88 px/s | 42.0 px at 120 px/s | 42.0 px |
| Gravity | 900 px/s², 0.62 of it while \|vy\| < 52 | 2400 px/s², no float | unchanged |
| Terminal fall | 360 px/s | 660 px/s | unchanged |
| Air accel / friction | 480 / 260 px/s² | 2400 / 900 px/s² | unchanged |
| Jump cut on release | ×0.38 a frame, from frame 6 | ×0.35 a frame, from frame 1 | ×0.35 a frame, from frame 4 |
| Tap of 1 / 2 / 3 / 4 frames | 25.5 px each | 8.0 / 13.4 / 18.2 / 22.3 px | 22.3 px each |
| Coyote: presses off an edge that jump | 6 | 0 | 6 |
| Buffer: presses before landing that jump on it | 8 | 0 | 8 |
| Landing | no lockout below 265 px/s; a flat jump lands at 252 | none | none |
| Press to feet off the ground | the press frame | the press frame | the press frame |
| Input delay added locally | none | none: VS CPU and one keyboard step the press on the frame it is read, and an online client predicts its own with none | none |
| What a thumb's down does to JUMP | down + JUMP rolls only standing, not at a run | down + JUMP rolls; a run sagging 14 units down held down | the duel's stick: a sagging run holds no down (*The stick*) |

The held arcs were not the difference. The duel's is the spec's: high gravity,
two tiles in 21 frames, no float, and `tests/fighter_profile_test.gd` holds it
there. Its reach and height are what every strip's moat, alley and bench was
cut for. What differed was everything at the edges of a press, which is where a
thumb lives:

- **A tap was a twitch.** The cut multiplied the rise by 0.35 on every frame
  JUMP was up, from the first, and a tap on glass is one to four frames. Most
  phone jumps were 8 to 22 px hops. Now the cut waits `jump_min_hold` (4)
  frames, so a tap of one to four frames is the four-frame hop, 22 px: two
  thirds of a held jump, the same share the prince's tap gets. Holding is still
  the only way up two tiles.
- **A late press was eaten.** No coyote time: a press on the first frame after
  the feet left an edge did nothing. Now `coyote_frames` (7) lets a press on
  any of the first six frames off an edge jump, as many as the prince's 0.1 s.
  Six frames of fall is 14 px, so the jump still clears the ledge it left by
  19. Down + JUMP in the air is the dive kick, coyote or not.
- **An early press was eaten.** No buffer: a press a frame before landing, or
  in the last frames of a thrust, a roll's rise or a dive kick's landing, did
  nothing. Now a plain JUMP is kept `jump_buffer` (9) frames, the press's own
  frame included, and fires on the first frame a jump can: a press up to seven
  frames before the feet land jumps on landing, as the prince's does. Down +
  JUMP is never kept: a roll or a dive kick is a commitment chosen on its
  frame, and one queued from the air or from a recovery would be a roll the
  player did not choose.
- **A run's thumb rolled.** See *The stick*.

**Why the arc was not matched.** The prince's arc is longer (39 frames against
21) and floats at the apex; the duel's is quick on purpose, and a longer jump
would stretch every gap on every strip -- a three-tile moat would become a
jump, and the alley under a clash's knock-back a step -- and slow the fighting.
`tests/fighter_profile_test.gd` still asserts a jump under 0.4 s, about two
tiles high, shorter than the adventure's. The forgiveness changes no held arc,
so no strip needed re-proving; `tests/unit/test_duel_cpu_feet.gd` still crosses
every hazard from a run and a standstill, and `tests/match_fighter_test.gd`
still crosses the moat and dies walking into it.

**Snapshot and wire.** The three windows are frame counters, four bits each, in
the fighter's flags word above the input's press-edge memory, so the block is
still 100 bytes and the checksum covers them. `DuelFeet.leap()` flies a hold
shorter than the minimum as the minimum, as the fighter does, so the computer
plans the hop it will get. The inputs now do something on frames they did not,
so the protocol is version 5 and a version-4 build is refused in the lobby
(`tests/unit/test_net_jump_version.gd`).

`tests/unit/test_duel_jump_feel.gd` measures the coyote and buffer windows on
both characters the same way and holds them equal, holds the tap, the held arc,
the feet's prediction, a press kept through a roll's rise, down + JUMP never
queued, and a restore from a snapshot taken with a press in the buffer. With
the three windows set to nothing -- the old fighter exactly -- six of its
eight tests fail, and with the buffer left out of the flags word the snapshot
test does.

## Where else the duel is decided

Not covered here, and documented in the code:

- Sword throw, flight and pickup: `DuelCombat._resolve_flight()`,
  `_resolve_pickups()`, and `scripts/duel/combat_blade.gd`. The catch is above.
- Sweep and ground pound: `DuelCombat._apply_strike()` and the fighter's state
  machine. The roll and the dive kick are above.
- The movement profile: `DuelTuning`, which the match hands to each fighter in
  `setup()`. The fighter never reads `scripts/core/tuning.gd`; the duel is not
  the adventure.
