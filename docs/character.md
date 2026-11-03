# The character

How the prince is drawn, how he is posed, and what the tuning numbers behind
him are for.

![every state, before and after](character-states.png)

## The constraint

The figure is 22 px tall on a 180 px viewport. On a phone that is roughly a
fingernail. Everything in `scripts/player/player_art.gd` follows from that:

- **Silhouette first.** A pose that only reads from its interior does not read.
  Every state below is distinguishable with the colours thrown away.
- **Four tones, nine pixels.** Lit cloth, shade cloth, an ink edge down the
  shadow side, and a darker cloak behind. That is the entire value structure,
  and it is what makes a red figure legible against terrain that is itself red
  and gold.
- **Flat planes, hard edges, no gradients.** The concept art's language, and
  conveniently also the cheapest thing to draw.
- **No image assets.** Everything comes out of `Palette` through
  `draw_colored_polygon`, `draw_rect` and friends. That is deliberate: the
  whole look re-lights from one table.

The light is fixed in the **world**, not on the character: it comes from the
left, the same direction `AsciiLevel.atlas_for()` lights the terrain from. So
the lit plane is the world-left half of the body whichever way the character
faces, and the hard shadow edge runs down his middle.

## The pose vocabulary

`_posture()` turns `(state, state_time)` into a **pose**: a flat dictionary of
named quantities. A pose contains no coordinates. `_rig()` turns a pose into
points, applying squash, lean, sink and the mirror for `facing` exactly once,
and the `_draw_*` helpers read the rig and know nothing about state.

Poses are written in **forward space**: `+x` is the way the character faces,
and `_rig()` mirrors it. Angles are radians, `0` straight forward, positive
downward. `_pose()` lists every field with the value it takes when a state
does not care:

| Field | What it moves |
| --- | --- |
| `squash` | vertical scale; width compensates, so volume roughly holds |
| `sink` | folds the body down **without** shrinking the hood — a crouch, a dead hang |
| `bob` | whole-body vertical offset, for the run's footfall |
| `lean` | forward offset at the shoulders, tapering to nothing at the feet |
| `tilt` | rotation about the feet — only HURT and DEAD use it |
| `twist` | shoulder foreshortening; below 1 reads as turned away |
| `dangle` | how far **below** the origin the feet hang |
| `hem_lift` / `hem_spread` / `hem_fwd` | where the robe's bottom edge is |
| `hood_tilt` / `hood_face` / `hood_push` | where the cowl points; `hood_face` may go negative to look backwards |
| `glint` | alpha of the one eye light |
| `stride` / `stance` / `knee` | the legs |
| `arm_a` / `arm_b` (+ `_len`) | front and back arm |
| `cloak_sweep` / `cloak_rise` / `cloak_flare` | the cloak behind everything |
| `blade` / `blade_len` / `blade_hot` | the sword; `INF` hides it |

### What each state is supposed to read as

| State | The read |
| --- | --- |
| `IDLE` | a standing column; the robe breathes, the hem touches the floor |
| `WALK` | a short stride, hem just clear of the feet |
| `RUN` | deep stride, 3 px of forward lean, cloak streaming, hem swinging **against** the legs |
| `TURN` | narrow — the shoulders foreshorten, the heel digs in, the hood is already looking the new way while the cloak is still travelling the old way |
| `CROUCH` | folded to `CROUCH_HEIGHT` by `sink`, not by scale; hem pools on the floor |
| `JUMP` | stretched, legs tucked, cloth streaming straight down |
| `FALL` | arms up and reaching — the ledge-grab probe fires from here, so the pose has to look like it is asking for a ledge |
| `LAND` | squashed, knees out, hem splayed, dust |
| `HANG` | two ink knuckles above a narrow column. Nothing else in the game has that shape |
| `CLIMB_UP` | a knee driven onto the ledge, then standing up over it, interpolated by the climb's own progress |
| `LADDER` | foreshortened shoulders, hood nearly edge on, hands and feet alternating |
| `ATTACK` | wind up back, lunge through, recover; the blade's arc matches `Player.attack_rect()`'s active window |
| `HURT` | thrown back and tilted, hood knocked away, whole figure burned white for 0.14 s |
| `DEAD` | toppled: the robe keeps its shape, the figure does not |

## Adding a state

1. Add the case to `_posture()` and write a `_my_state()` function returning
   `_pose({...})` with only the fields that matter. Give it a docstring that
   says what the pose is supposed to **read** as, not what the numbers are.
2. If the state needs a quantity no field expresses, add the field to
   `_pose()`'s defaults and consume it in `_rig()` or a `_draw_*` helper. Do
   not special-case a state inside a drawing helper: the helpers must stay
   state-blind, or the next pose has to fight them.
3. Add a row to `_pose_table()` in `tests/character_poses.gd` and re-render the
   contact sheet (below). If it does not read at 1:1 in the inset, it does not
   read.

## Secondary motion

The pose is a pure function of `(state, state_time, velocity, facing)` — which
is what keeps a replay or a network peer drawing the same frames. The *cloth*
is not:

- **`_sway`** chases the body's velocity with an exponential lag, in forward
  space. It reaches the cloak multiplied and the hem multiplied and negated, so
  running makes the cloak trail and the hem drag back, falling makes both
  stream upward, and both keep moving for a few frames after the body stops.
- **`_squash_impulse()`** is a damped ring kicked by the `landed` and `jumped`
  signals. A landing's depth is `Tuning.impact_weight(impact_speed)`, so the
  squash scales with the drop and then settles with a small overshoot instead
  of snapping back.
- **`_flash`** burns every plane of the figure toward `PAPER` for 0.14 s after
  a hit. It lives in the art rather than in the effects node so that the flash
  is exactly the character's own silhouette, not a rectangle laid over it.

That is the only state this node keeps, all of it cosmetic, all of it
self-correcting within a few frames.

## Effects

`scripts/player/player_fx.gd` draws landing dust, run scuffs, a ledge-grab
puff, a sword trail and hit sparks. It is driven entirely off `Player`'s
existing signals — `landed`, `grabbed_ledge`, `hurt`, `died` — plus the two
public fields `PlayerArt.blade_tip` / `blade_hot` for the trail, so the trail
cannot drift away from the sword it is following.

It **attaches itself**: `PlayerArt._ready()` calls `PlayerFx.attach()`, which
adds the node beside the art if it is not already there. Nothing has to be
wired into `scenes/player.tscn`, so every Player everywhere gets the effects
and the scene file stays a two-node file nobody has to merge.

Particles are a fixed-size `PackedFloat32Array` with a stride — no object per
particle, no timer, no tween, nothing allocated or freed while playing. The
node is `top_level`, so dust stays where it was kicked up instead of riding
along with the character.

## The tuning, and what changed

`scripts/core/tuning.gd` is the only place feel lives. The hard constraint on
any change is the traversal grammar:

```
Tuning.hop_tiles()            == 2
Tuning.platform_step_tiles()  == 3
Tuning.grab_tiles()           == 4
```

`tests/tuning_grammar_test.gd` pins those and must pass after every change.
Run `tests/tuning_feel_test.gd` and `tests/character_traversal_test.gd` too.

### What moved, and why

| Was | Now | Why |
| --- | --- | --- |
| `GROUND_ACCEL 520` | `900` | 0 → top speed took 10 frames. Deliberate is in the wind-up of a turn, not in a tenth of a second of nothing happening. Now 6 frames. |
| `GROUND_FRICTION 760` | `1100` | Stopping was slower than a human expects, so the character skated. It now plants. It also makes `TURN` (which runs friction × 1.4) actually stop rather than drift. |
| `AIR_ACCEL 340` | `480` | 0.26 s to steer to full speed mid-air was too slow to thread a gap you had already committed to. 0.18 s now — enough to adjust, not enough to fly. |
| `AIR_FRICTION 150` | `260` | Letting go in the air did almost nothing. Now it shortens a jump, which is a real choice. |
| `TURN_TIME 0.09` | `0.1` | Six frames. The turn pose has something to say now, and the stronger friction means those frames read as weight rather than as lag. |
| `SOFT_LAND_SPEED 190` | `265` | **The big one.** A jump from flat ground lands at exactly `JUMP_SPEED` = 252, so at 190 *every single jump* ended in a recovery lockout. Running and jumping felt like wading. Both thresholds now sit above `flat_jump_land_speed()`. |
| `HARD_LAND_SPEED 300` | `330` | Re-spaced with the above: flat jump clean, +1 tile soft, +2 tiles hard. |
| `LAND_RECOVER_TIME 0.18` | `0.12` | The hardest landing now costs 11 frames instead of 17. |
| `MAX_FALL_SPEED 330` | `360` | Headroom so terminal velocity still counts as a hard landing. |
| `APEX_THRESHOLD 36` → `52`, `APEX_GRAVITY_SCALE 0.72` → `0.62` | | The apex float was worth 0.3 px and 0.12 s — invisible. It is now worth 0.9 px and 0.17 s, so the top of the arc is somewhere you can actually aim from. Still inside the grammar: the rise goes 35.6 → 36.2 px, which is between 2 and 3 tiles either way. |
| `JUMP_CUT_MULTIPLIER 0.42` | `0.38` | A crisper short hop. |
| `CLIMB_UP_TIME 0.34` | `0.27`, `HANG_HOLD_TIME 0.08` → `0.06` | The mantle was long enough to feel like a cutscene. |
| `MAX_GRAB_FALL_SPEED 260` | `310` | Above `flat_jump_land_speed()`, so a ledge is still grabbable at the speed a jump actually falls past it. Strictly more forgiving; it can never make geometry unreachable. |
| `ATTACK_TIME 0.28` | `0.24`, `INVULNERABLE_TIME 1.1` → `0.9` | Both were long enough to notice. |
| *(none — the cut applied from frame 1)* | `MIN_JUMP_HOLD 0.1` | **For thumbs.** A one-frame tap rose 6 px, and a jump buffered before landing and released before it fired rose 2 px — a jump that did not happen. Releasing jump now cuts the rise only after six frames in the air, so the shortest jump is a ~21 px hop: over a tile, still well short of a held jump. No apex moves, so the grammar cannot. |
| *(none — a press outside IDLE/WALK/RUN was dropped)* | `ATTACK_BUFFER 0.12` | A sword press in the last frames of a fall, in a turn, in a landing or in the tail of a swing did nothing. It is now kept like a jump press and swings on the first frame it can. |

**Nothing that defines reach moved.** `GRAVITY`, `JUMP_SPEED`, `RUN_SPEED`,
`WALK_SPEED`, `BODY_WIDTH`, `BODY_HEIGHT` and `GRAB_PROBE_Y` are untouched, so
every existing level's distances are exactly as they were.

Four derived numbers were added — `flat_jump_land_speed()`,
`land_speed_after_drop()`, `impact_weight()` and `gap_tiles()`. They are
consequences, not knobs: the landing thresholds are set relative to the first,
the art and the dust both scale off `impact_weight()` so they cannot disagree
about how hard a landing was, and `gap_tiles()` is the horizontal half of the
grammar — the widest flat gap a running jump crosses, currently 3 — which is
what the feel lab's long-gap station is built to.

## The feel lab

`scenes/feel_lab.tscn` + `levels/feel_lab.txt` is the A/B bench: every
canonical obstacle side by side, in the order the grammar introduces them —
open run-up, 2-tile hop, 3-tile platform step, 4-tile grab wall, 3-tile gap,
a four-tile drop, a ladder onto a terrace with a seven-tile drop off it, and a
one-way platform to hop through and fall back down through. It is registered
in `mode_registry.gd`, so it is one entry in the menu.

Change a number in `tuning.gd`, play the lab, and you can see in one screen
which distances still work.

## Looking at it

The only honest test of this art is the pixels. Two tools:

```bash
# Every pose, one frame each, as a labelled contact sheet with 1:1 insets.
xvfb-run -a godot --path . --rendering-driver opengl3 \
  --script tests/character_poses.gd -- --out /tmp/poses/after
python3 tests/character_contact_sheet.py docs/character-states.png \
  "after=/tmp/poses/after" "before=/tmp/poses/before"

# The character in the real game, in motion, against real terrain.
xvfb-run -a godot --path . --rendering-driver opengl3 \
  --script tools/screenshot.gd -- --scene res://scenes/feel_lab.tscn \
  --out /tmp/lab --shots 0.6,1.6,2.4,3.2 --hold move_right
```

`tests/character_poses.gd` exists because `tools/screenshot.gd` walks a live
scene and cannot reach `HANG`, `CLIMB_UP`, `ATTACK` or `DEAD` on demand. The
harness freezes a player into each pose in turn — re-pinning it every idle
frame, because the state machine keeps running underneath — and captures a
frame with the feet on a fixed mark, so a fixed crop lands on the character
every time.

## The duel fighter wears the same figure

The duel's `Fighter` is a different character with a different state machine,
but it is drawn by the same rig. `scripts/duel/fighter_art.gd` extends
`PlayerArt` and overrides the eight methods through which `PlayerArt` reads the
body it dresses — `_bind()`, `_has_body()`, `_body_facing()`, `_body_motion()`,
`_speed_share()`, `_skip_frame()`, `_blade_in_front()`, `_show_grip()` — plus
`_grounded()` and `_posture()`. For the prince those methods read the `Player`
exactly as before; a pixel comparison of level 1 before and after the change
showed no difference anywhere on him.

![every duel state](fighter-poses.png)

What the fighter adds is one rule: **the sword is drawn where the simulation's
blade rect is.** Same height as the stance band, same reach, the front hand
moved onto its hilt in `_rig()`. The duel is decided by where that rectangle
is, so the picture of the sword *is* the rectangle, and HIGH, MID and LOW read
at a glance. When the blade is held but not up — a roll, a dive, the recovery
of a thrust that missed — it is carried on the pose's angle instead, visibly
lowered, because a fighter who missed has to be seen to be open.

The same honesty applies to the body. Each pose was checked against the
fighter's hurtbox with the overlay on, and three were changed to fit it: the
roll pitches forward rather than folding down (the hood keeps its size, so a
deep fold pushed the hips through the floor); the sweep stays half upright,
because a sweeping fighter keeps its full-height hurtbox; and a downed fighter
sits back inside its small box instead of lying full length past it.

Seat two wears `Palette.WATER_DEEP`, `WATER_SHADE` and `WATER_NIGHT` in place of
the prince's crimson steps.

```bash
xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x720 \
  --script tests/fighter_poses.gd -- --out docs/fighter-poses.png [--hitboxes]
```

## The sentinel

The guards on the terraces are drawn by `scripts/entities/patrol_art.gd`, a
rig of the same kind as the prince's — a pose dictionary from
`(state, state_time)`, a rig, state-blind drawing helpers — and built to be his
opposite at every point the eye uses at this size: near-black where he is mid
red, a dome helm with a gold spike where he has a pointed cowl, pauldrons
where he is narrowest, legs and boots under a knee-length coat where his robe
reaches the floor, and a curved sabre on the shoulder where his blade hangs
low. The sun-facing edge of the coat, helm, pauldrons and helm-cloth carries a
one-pixel rim, so a dark figure does not vanish into the ink of an arch.

![every sentinel state, with the prince for scale](enemy-poses.png)

What the guard *does* changed with it, deliberately and narrowly. It used to
hurt on contact, which made it a moving spike: nothing to read and nothing to
fence with. Now it is harmless to touch and dangerous in one state only:

| State | Frames | What it is for |
| --- | --- | --- |
| `WINDUP` | 27 | the telegraph — sabre cocked overhead, eye slit burning white, a star of light up the blade, a cloth cue |
| `STRIKE` | 9 | the only frames `Patrol.strike_rect()` is non-empty |
| `RECOVER` | 33 | point on the floor, bent over: the opening |

The raise starts when the prince is `ENGAGE_GAP` in front of the guard, which
is already inside the prince's own sword reach, and his sword is live six
frames into a swing. So a player who acts on the raise wins the exchange, and
a hit during it staggers the guard out of its cut; a player who backs off one
tile is out of `REACH`. `tests/unit/test_patrol.gd` pins those relationships
against `Tuning`, so a retune of the prince cannot quietly make guards unfair.
The stomp is unchanged. A guard that dies kneels, topples and flickers out
over 1.3 s while its sabre spins away; it is neither dangerous nor hittable
from the killing blow on.

```bash
xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x720 \
  --script tools/enemy_poses.gd -- --out docs/enemy-poses.png [--silhouette]
```

`--silhouette` paints every figure black: the two-tone check from
`docs/art-direction.md`, and the quickest way to see that the guard and the
prince are different shapes.

## Tests

```bash
godot --headless --path . --script tests/tuning_grammar_test.gd     # the grammar
godot --headless --path . --script tests/tuning_feel_test.gd        # the feel relationships
godot --headless --path . --script tests/character_traversal_test.gd # the lab, played
```

The traversal test drives the real `Player` through the real feel lab with a
deliberately stupid bot — hold right, jump at a wall, jump at a gap, climb what
cannot be jumped, mantle a ledge — and asserts every station is cleared. It
runs in real time (the engine steps physics at wall-clock 60 Hz), so give it
about a minute. If a station needs more cleverness than that bot has, the
station is too fiddly to be canonical.
