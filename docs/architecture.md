# Architecture

A map of the foundation and the reasoning behind the parts that are easy to
get wrong later.

## Layers

```
scenes/boot.tscn
  └─ scripts/core/boot.gd ........ thin entry point; platform setup belongs here
       └─ scenes/menu.tscn ....... mode select, driven by core/mode_registry.gd
            └─ scenes/game.tscn
                 ├─ core/game.gd ......... owns a level's actors and arbitrates them
                 ├─ world/level.gd ....... TileMapLayer + geometry queries
                 ├─ player/player.gd ..... state machine on a CharacterBody2D
                 ├─ entities/* ........... placed through entities/entity_registry.gd
                 ├─ mechanisms/* ......... plates, gates: own collision, wired by channel
                 ├─ render/game_camera.gd  dead-zone follow
                 ├─ ui/hud.gd, ui/touch_controls.gd
                 └─ audio/player_audio.gd  maps the character to sound
```

Plus two systems that stand beside the scene tree rather than inside it:

```
audio/audio_director.gd ... autoload: buses, voice pool, music, settings
levels/generator.gd ....... seeded level generation, proved reachable
                            by levels/reachability.gd before it is played
```

The dependency direction is one-way. `player/`, `world/` and `entities/` never
reach into `render/` or `ui/`, which is what lets the whole simulation run
headlessly in tests and under a network session.

## Fixed timestep

All gameplay runs in `_physics_process`, which Godot steps at a constant
60 Hz (`physics/common/physics_ticks_per_second`). Without that, a 120 Hz
tablet and a 60 Hz phone produce different jump heights, every piece of level
geometry becomes device-dependent, and networked play cannot agree on
anything. `max_physics_steps_per_frame` is capped at 5 so a stalled frame
cannot trigger a catch-up spiral.

`default_gravity` is set to zero on purpose: the character applies its own
gravity, including the reduced pull near the apex of a jump.

## Virtual resolution

The viewport is **180 units tall with an aspect-derived width**
(`stretch/mode = canvas_items`, `stretch/aspect = keep_height`). Fixed height
keeps the character the same apparent size on every device; flexible width
means a 20:9 phone sees more of the room instead of black bars. One tile is
16 px, so the whole game is authored in the same units the tuning uses.

## Collision

Tiles carry their collision in the generated TileSet, across two physics
layers:

| Layer | Mask bit | Contents |
| --- | --- | --- |
| 0 | 1 | solid blocks |
| 1 | 2 | one-way platforms |

Separating them is what makes dropping through a platform trivial: the
character clears mask bit 2 for a quarter of a second instead of needing any
special case in the movement code.

Hazards, ladders and backdrop tiles carry **no** collision. They are read
through the TileSet's custom `kind` data (`Level.rect_has_kind`), which means
a level hand-edited in the Godot editor behaves exactly like a parsed or
generated one.

## Character state machine

`scripts/player/player.gd` keeps every transition in one `match` block. The
feel comes from five forgiveness mechanisms, all tunable in
`scripts/core/tuning.gd`:

- **Coyote time** — a jump is accepted for 0.1 s after walking off an edge.
- **Jump buffering** — a jump pressed up to 0.14 s before landing still fires.
- **Sword buffering** — a sword press is kept for 0.12 s, so one made at the
  end of a fall, in a turn or in a landing swings as soon as it can.
- **Variable height** — releasing the button mid-rise cuts upward velocity,
  but not in the first 0.1 s, so a tap is a hop rather than a twitch.
- **Apex float** — reduced gravity near the top of the arc, so mid-air
  steering reads clearly.

The node's origin is at the character's **feet**, which makes spawning, ledge
snapping and drawing all read straight off `position`.

Ledge grabbing is a geometry probe, not a trigger volume: while falling, the
hand position in the facing direction is tested for a solid tile with empty
space directly above it. Any corner in any level is therefore grabbable
without authoring markers — and it is why the level grammar's 4-tile rule is a
derived number rather than an arbitrary one.

## The input seam

`scripts/player/player_input.gd` is one frame of intent: seven bits of held
state plus derived press edges, with `to_bits()` / `apply_bits()` as the wire
format. The character reads those fields and never asks which device produced
them.

That indirection is load-bearing. A local device (`LocalInput`, with an action
suffix so a second local player needs no duplicated logic), a replay, an AI or
a remote peer all drive the character through the identical code path.

## Rendering

No image assets. `scripts/core/palette.gd` holds the duotone ramp and names
surfaces by how they face the light rather than by hue, so re-lighting is a
table edit. The terrain atlas is generated from that same palette by
`tools/generate_tiles_png.py`, and `tools/build_tileset.gd` turns it into a
TileSet with the collision shapes and custom data above.

One subtlety worth knowing if you edit the atlas generator: PIL's `fill`
**replaces** a pixel including its alpha rather than compositing onto it, so
painting a translucent tint directly would punch a transparent hole in the
tile and let the sky show through. Use the `over()` helper.

The character is drawn as a posed cloak silhouette in
`scripts/player/player_art.gd`, derived from state and `state_time`. Swapping
in real sprites later means replacing that one file.

## Audio

No audio files either. `scripts/audio/synth.gd` builds every voice from four
primitives — swept oscillators, resonant-filtered noise, Karplus-Strong
plucks and envelopes — and bakes them into `AudioStreamWAV` held in memory at
load time. Baking rather than streaming is cheaper on a phone, and
synthesising rather than shipping samples keeps the download tiny and the
licensing trivial.

The baking costs a couple of seconds of GDScript, so it runs on a thread and
`play()` no-ops for a voice that is not ready yet. If that ever shows on a
low-end phone, the fix is caching the baked PCM to `user://` keyed by a
synthesis version.

Noise comes from a seeded generator rather than `randf()`, so a voice is
byte-identical run to run and can be pinned by a test. Variation happens at
playback — pitch and level — not at bake, so repeated footsteps do not
machine-gun.

## Entities: one registry, one protocol, one referee

Everything a level places — relics, torches, the door, guards, and whatever
the campaign adds — goes through the same three pieces, so `Game` never names
a kind of thing:

| Piece | File | Job |
| --- | --- | --- |
| registry | `scripts/entities/entity_registry.gd` | kind name → script; one line per kind |
| site | `scripts/entities/entity_site.gd` | where a mark put the entity, and what the level knows there |
| contact | `scripts/entities/contact.gd` | the prince as entities see him for one frame, and the consequences they may ask for |

`Game._spawn_entities()` walks the level's marks in order and asks the
registry for each; the script's `place(site)` takes it from there.
`Game._resolve_interactions()` calls `meet(contact)` on every entity, in the
same order, once a playing frame. A relic decides that a touching body takes
it; a torch decides what "reaching it on your feet" means and *offers* itself
as a checkpoint, which Game takes only if it is further on; a door says it was
reached, and Game ends the level after the pass. A kind that declares
`signal cue(voice, options)` or `signal impact(at, frames, shake, weight)` has
them wired to `GameAudio.cue` and to Game's one impact budget.

Kinds that are glyphs but placed by someone else are listed in
`EntityRegistry.ELSEWHERE` (the spawn point; inscriptions, which the secret
keeper furnishes). `tests/unit/test_entity_registry.gd` fails on a legend
glyph that is in neither table — the glyph would otherwise spawn nothing, in
silence.

At a checkpoint respawn, what happens to an entity follows from what it *is*:
a foe goes back to its post unless it was cut down, a foe's projectile is
gone, and everything else stays as the prince left it.

### Adding a foe

A foe is a script that `extends Foe` (`scripts/entities/foe.gd`) and one line
in `EntityRegistry.kinds()`, plus its glyph in `Tiles.ENTITY_LEGEND`. Game
referees every foe against that contract, with no branch for any one of them:

| Game asks | Default | Override it to |
| --- | --- | --- |
| `bounds()` | — | give the body a stomp lands on (required) |
| `hurt_rect()` | `bounds()` | wound somewhere other than the whole body |
| `is_alive()` / `is_dangerous()` | alive, harmless | — |
| `is_engaged()` | `is_dangerous()` | hold the prince's idle while it fights |
| `dangers()` | none | list what can hurt him this frame (`FoeDanger`) |
| `hit(from_x)` | — | take one wound; true when it killed (emit `defeated`) |
| `take_blow(blow, from_x)` | every blow is `hit()` | block a sword from the front, refuse a stomp |
| `wound_voice()` | `guard_hit` | sound different when wounded |

The rules Game applies, once a frame per foe, in this order:

1. `target_rect` is set to the prince's body (empty when he is dead). A foe
   never reaches for the Player.
2. A foe that is not `is_alive()` is scenery: nothing more happens.
3. **Blade.** The sword's live rect against `hurt_rect()`, **once per swing
   per foe** (`tests/unit/test_one_swing.gd`): `Blow.SWORD`, or `Blow.PLUNGE`,
   which springs the prince back off whatever it hit.
4. **Stomp.** Falling onto `bounds()` from above is `Blow.STOMP` and bounces
   him — unless the foe answers `Outcome.NONE`, and then it never was one.
5. **Danger.** While `is_dangerous()`, the first of `dangers()` that touches
   his body is resolved: *parried* if his parry is up, he faces it and the
   danger has a `parry` (the guard's cut does; a slam need not), *evaded* in a
   backstep's window if it is `evadable`, otherwise *landed*. A danger with
   no `damage` and a `push` is a **shove**: landed, it throws the prince back
   and staggers him (`Player.shove()`) with no heart lost and no grace given
   -- the Bastion's shove, and his shield's face, which pushes back like a
   wall because foes have no collision of their own.

`take_blow()` answers an `Outcome`, and Game presents it: a wound or a kill
gets the wound sound and the impact, `BLOCKED` the clang and a small held
beat, `NONE` nothing. A foe asks for presentation rather than making it —
`cue` for a sound, `impact` for weight — so audio keeps its one front door
and hitstop its one budget.

**Down stays down.** A foe placed from a mark has a `post` (`patrol@38,11`)
that survives restarts; `defeated` makes Game remember it, and a respawn puts
back every foe whose post it does not remember, whole, at its post. A foe
brought in at runtime with `summon()` has no post: a respawn clears it.

**A post can remember.** Everything placed at a post is handed the same
dictionary every time, `EntitySite.memory`, which Game keeps across a respawn
and empties on a restart. A guard ignores it; a boss writes into it what must
outlive his body — the Eclipse, the phase he is in, so phases already won
stay won through a death (`scripts/entities/eclipse.gd`).

**A foe can hold the way out.** Anything in `ExitDoor.HELD_SHUT` keeps every
door in the level shut, drawn closed and deaf to the prince. The proof never
sees a holder: the door is open to it, and the holder stands in the arena it
proves reachable.

**Warnings go through `warn()`.** Every tell — a raise, a draw, a crouch
before a pounce — and every timed window that stands between the prince and
a death is read as `warn(seconds)`, never as the bare constant. That is the
LONGER WARNINGS assist (`scripts/core/assist.gd`, an owner decision in
`docs/campaign.md`): off, `warn()` returns what it was given, exactly; on, the
one factor the player chose. The cut, the opening after it and everything
else keep their own timing. A foe that compares a tell against its own
constant has forgotten the assist, so its tests should drive the tell with
the assist on, as `tests/unit/test_longer_warnings.gd` does the sentinel's
raise (`Patrol.windup_time()`). A mechanism with a clock in it has the same
`warn()`.

**Projectiles.** `launch(FoeProjectile)` hands an arrow, a knife or a stone
to the level (`scripts/entities/foe_projectile.gd`). It is a danger to the
prince until a parry sends it back, faster, at which point it is his: the
first foe it meets takes it as `Blow.SHOT` — its own archer included. It is
spent on the prince, on stone, out of the level, or when `LIFE` runs out, and
a respawn clears whatever is in the air.

The guard (`scripts/entities/patrol.gd`) is the reference foe. Its refactor
onto the contract was proved to change nothing by `tools/trace_level.gd`,
which plays the Sun Terrace end to end and an arena of every guard
interaction under scripted input and records every physics frame — prince,
entities and every sound cued. The traces before and after are byte for byte
the same; the tool is how the next refactor of `Game` should be checked too.
`tests/unit/test_foe_contract.gd` and `tests/unit/test_foe_projectile.gd`
hold the contract with toy foes that answer it differently from the guard.

### Adding a mechanism

Plates, gates, crumbling floors, timed traps and lifts are mechanisms: a
script that `extends Mechanism` (`scripts/mechanisms/mechanism.gd`), one line
in `EntityRegistry.kinds()`, and its glyph in `Tiles.MECHANISM_LEGEND` — plus
`Tiles.MECHANISM_TERRAIN` if its cell is stone that stays stone, as a plate's
is. Levels wire it with mason's marks and say what each wire does with a
`;! channel` line (`docs/world.md`, *Directives and wiring*):

```
;! channel 1 latch
#######1#######
       !
  @    !     D
###o###########
###1###########
```

What the base gives a mechanism, and what it overrides:

| | |
| --- | --- |
| `cells`, `params`, `channel` | every cell of its glyph's connected run, its parameters, and its wire: the digit of the mason's mark it touches |
| `_setup()` | override: its collision and look as the level text has it, *in its wire's state* — read `bus.is_on(channel)`, because a respawn can bring it back on a latched wire |
| `meet(contact)` | override, for a trigger: sense the prince (`feet_on()`, `body_in()`) and `bus.press()` / `bus.release()` its channel; `bus.latch()` for a deed that is never undone |
| `_on_channel(on)` | override, for a receiver: its wire changed |
| `static func wired() -> bool` | override to return true if it is nothing without a wire (a gate): placed without a mark, it is a level problem |
| `set_kind(kind)` | make its cells stone, a one-way platform, spikes, a ladder or air — its own `StaticBody2D` on `Tiles.MASK_SOLID` / `MASK_ONE_WAY` for the prince's physics *and* the level's overlay for his probes; never the tilemap |
| `contact.harm(hearts, from_x)` | hurt the prince without being a foe (a crusher); something that kills outright is `set_kind(SPIKES)` |
| `contact.reveal_secret(cell, at)` | find the secret whose seal or room holds `cell`, through the secret keeper (count, chime, reveal): for a seal the prince's body and blade cannot open, as light opens a sun-seal |
| `cue` / `impact` | presentation, through `GameAudio.cue` and Game's impact budget |
| `static func reach(mark, model)` | override: how it changes passability, for the proof |

A trigger never decides what its press means. Momentary, latched, held for
seconds or on a beat is the channel's mode, set by the level, and kept by
`ChannelBus` — which `Game` steps once per playing physics frame, so a hold
counts down and a beat turns in simulation steps, frozen by a hitstop like
everything else.

Three rules:

1. **All state lives in the node, and `_setup()` is the only reset.** A
   restart rebuilds every mechanism from its mark on a new bus; a checkpoint
   respawn does too, on a bus that keeps what was latched — a trap resets, a
   deed does not. The rule and its proof obligation are argued in Game's
   checkpoint notes.
2. **Change collision through `set_kind()`, never through the TileMap.** The
   body and the overlay must agree, or the prince can walk through a gate he
   can grab, or grab one he walks through.
3. **Tell the proof.** In `reach()`, describe the mechanism to the
   `ReachModel` (`scripts/levels/reach_model.gd`) with `switch_cells()`,
   `latch_on_stand()` (with `needs`, a latch that waits for other wires: a
   sun-seal behind another door) and `fixed_cells()`, and ask `model.channel_mode()`
   what a press means: a plate's press is a latch to the proof only on a
   `latch` wire. Say the conservative thing for anything with a clock in it:
   a held gate the proof treats as shut; a crumbling floor, a transient stand
   (`fuse_on_stand()`) on a wire that is a trap (`resets_on_respawn()`), as
   `CrumblingStone` does. A mechanism that says nothing is
   treated as never changing anything. A bit is set only by a latch or by a
   fuse, and a fuse's wire is a trap, cleared before a torch is proved, so
   every bit the checkpoint proof keeps is a latch -- it leans on that; a mechanism that needs
   another (a race against a hold) changes `ReachSearch` as well.

The framework ships with toys that prove it — a stone plate and a portcullis
on one mason's mark, in `tests/unit/test_mechanisms.gd` (in play) and
`tests/unit/test_reach_mechanisms.gd` (in the proof). Copy their shape.

**A mechanism the search cannot see still owes a proof.** A blade on a beat
(`scripts/mechanisms/beat_blade.gd`) is air between its cuts, and the search
has no clock, so its reach hook changes no cell: it files its timing with
`model.note(&"beat", …)`, and `BeatProof` reads `model.notes(&"beat")` to
prove every crossing's window and slack -- found through the same hooks, from
the same marks, as the search finds its gates. Notes leave the model empty,
so a level that only files notes keeps the plain search. A hook that must
read the cells round its mark (a scythe cut into a ladder shaft is still a
ladder) has the level as `model.level`.

**A foe or a trap asks what the camera shows** through `CameraView`
(`scripts/entities/camera_view.gd`), and a foe that hunts what is not
standing reads `target_off_stone`, which Game writes beside `target_rect`
from `Owl.off_the_stone()` -- the owl (`scripts/entities/owl.gd`) is
both.

### Adding a chapter

The Adventure is *The Last Light*, an ordered list of entries in
`scripts/campaign/campaign.gd`. A chapter is a level file under `levels/` and
its line in `Campaign.entries()` — `id`, numeral, title, epigraph, the hour it
is set at, and the file. The five chapters and the finale are already listed
from `docs/campaign.md`, with their files empty: an entry with no file is
shown on the chapter select as still being built and is never played, so the
campaign works with only chapter I. Building a chapter is filling in its
`file`.

Three things to keep:

1. **The `id` never changes** once a build with the entry has shipped. It
   keys the saved progress (`user://progress.cfg`, `CampaignProgress`), so a
   chapter can be retitled or moved without anyone's record moving with it.
2. **The level says its own hour.** `;! time golden` in the file is what the
   grade reads; the entry's `time` is what the chapter select prints, and
   `tests/unit/test_campaign_catalogue.gd` fails if they differ — and if the
   level does not parse clean, is not wired, or cannot be finished.
3. **A finale is an entry.** The Eclipse is the sixth entry, marked `finale`,
   rather than a phase of Chapter V's level: a checkpoint respawn is per
   level, and the boss's arena has to be where a death comes back to, with
   its won phases kept. It carries no numeral (the select draws it under
   chapter V) and needs no other kind of thing — progress, unlocking and
   CONTINUE treat it as one more entry. Anything else that ends a chapter can
   be the same.

`CampaignGame` (`scenes/campaign_game.tscn`) plays the entries through the one
`scenes/game.tscn`, as Endless does: a clear is recorded when it happens and
opens the next entry; jump on the complete screen plays the next entry behind
the wipe (`Game.advance`, with `Game.advance_label` saying CONTINUE), goes back
to the chapter select when the next is not built, and shows the ending card
(`Campaign.ENDING`) after the last; sword leaves for the chapter select
(`Game.quit_scene`). `tests/unit/test_campaign_game.gd` plays a two-chapter
campaign through all of it.

## Configuration as code

`project.godot` is written by `tools/configure_project.gd`. Settings and input
bindings therefore show up as readable diffs instead of as editor state, and a
fresh clone can regenerate them. Add a setting to that script, not to the
editor.

## Extending

- **New level** — add an ASCII file under `levels/`, point a scene's
  `level_path` at it. `Game.level_source` takes an `AsciiLevel` directly for
  levels that are generated rather than stored.
- **New entity** — a script under `scripts/entities/` that keeps the protocol
  (`place(site)`, and `meet(contact)` if the prince can touch it), one line in
  `EntityRegistry.kinds()`, and its glyph in `Tiles.ENTITY_LEGEND`. Never a
  case in `Game`. A foe extends `Foe`: see [Adding a foe](#adding-a-foe).
- **New mode** — add one entry to `scripts/core/mode_registry.gd` and it
  appears in the menu. The scene is loaded only when the mode is chosen.
