# The world: light and architecture

Two systems turn a level's terrain into the city in the reference art. Both are
built against [`art-direction.md`](art-direction.md), and both run over every
level the game plays — hand-authored, generated, and duelling zones — without
any of them being rewritten.

| | File |
|---|---|
| Cast shadows | `scripts/render/sun_shadow.gd`, `assets/world_shadow.gdshader` |
| Shade twins in the atlas | `tools/generate_tiles_png.py`, `scripts/world/tiles.gd` |
| Architecture from terrain | `scripts/world/dresser.gd` |
| Secret rooms | `scripts/world/secret_view.gd`, `scripts/world/secret_keeper.gd` |

The docstrings in those files carry the full argument. This page is the map,
plus the facts that do not belong to any one file.

## One sun

The sun is fixed in the world and rakes low from the left at the integer vector
`(RUN, RISE) = (2, 1)`: two pixels across for every one down.

The integer slope is what makes the solve cheap. Index each pixel by its lane,
`lane = x − 2y`. The lanes partition the grid exactly, and stepping
`(x + 2, y + 1)` walks one lane. So casting a shadow is one sweep per lane with
a countdown, not a ray-march per pixel. The whole world is static once a level
is built, so the mask is solved **once**, into one bit per pixel, and after that
a shadow costs one texture fetch per fragment. Nothing is re-solved while the
game runs, and there is no render target and no light pass.

### What casts, and what is spared

A pixel casts if it is opaque in the atlas: terrain and mid-ground architecture
alike. No decoration declares its own silhouette, so a new one casts correctly
the moment it is drawn. Background filler, water and the foreground plane do not
cast.

Two rules decide what is spared. The picture is wrong without either.

1. **A body does not shadow itself.** Without this, a wall's own cap eats the
   gold off the wall below it.
2. **What counts as one body is declared, not inferred.** Terrain and the
   cornices and friezes carved into it are one body. A column, balustrade or
   planter *standing on* a surface is its own body, and throws its shadow across
   that surface. `Tiles.STANDING_DECOR` is the list. It is the difference
   between a terrace of flat gold and one banded by its colonnade.

### Why thin casters are two pixels wide

A one-pixel-wide vertical caster at column `x` covers lanes `x − 2y` for each
row `y`. Stepping down one row moves the lane by two, so a one-pixel post only
ever touches lanes of one parity. Its shadow lands on every other lane, and
reads as a dotted line instead of a shadow. A two-pixel post covers both
parities. That is why balustrade posts in `tools/generate_tiles_png.py` are two
pixels wide, and why any new thin standing decoration should be too.

## Time of day

A level is set at an hour with `;! time <stop>` (`scripts/render/time_of_day.gd`),
and the hour is a grade over the same atlas, palette and solve — never a second
set of tiles, as `docs/art-direction.md` requires. The axis is the duel's:
`MatchDusk.DUSK`, a multiply that keeps red and takes green and blue, with the
sky painting its own dusk instead of being multiplied down. The campaign walks
it by stops and goes one past it for night:

| Stop | World multiply | Sky (`ParallaxSky.dusk`) | Shadow reach | Sun |
| --- | --- | --- | --- | --- |
| `afternoon` (no directive) | none | 0 | 3 tiles | as it was |
| `golden` | `DUSK` at 25% | 0.25 | 3.5 | |
| `sunset` | `DUSK` at 55% | 0.6 | 4 | |
| `dusk` | `DUSK` | 1.0 | 5 | |
| `night` | `TimeOfDay.NIGHT` (0.50, 0.30, 0.46) | `NIGHT_SKY_STOPS`, no disc | — | none: the mask is all shade and nothing is solved |

A number from 0 to 1 is a point between the afternoon and dusk.
`;! horizon <row>` puts every row from that one down in the far city's shadow,
one fill after the solve. Only the reach moves with the hour; the sun's slope is
(2, 1) at every stop, because any other integer slope dots every two-pixel
caster's shadow (*Why thin casters are two pixels wide*).

`WorldGrade` (`scripts/render/world_grade.gd`) is MatchDusk held still: a
`CanvasModulate` with the stop's multiply, the sky's dusk and night set from
the table, and every node in `MatchDusk.LIT` lifted back out by the inverse of
the multiply. The prince, every foe (in `Foe._ready`, so a new foe is lifted by
the contract), every projectile, the torches and the relics join that group:
a tell drawn in `LIGHT` that dims at dusk is a death that cannot be read, so
the grade falls on the city and not on what you fight. An afternoon level gets
no `WorldGrade` at all — the game as it always looked.

The campaign's sky carries one landmark the hour reaches like every other
building: the Mirror Tower (`ParallaxSky.tower`, `docs/campaign.md`, "The
presentation, as built"). Its tone is taken from the band behind its crown —
a step toward ink while that band has light in it, a step up out of the ink
once it has none — because any fixed tone matches some hour's sky exactly.

`tools/screenshot.gd --level <file> --time <stop>` plays any level at any hour
without editing it, which is how a chapter is judged at its stop:

```bash
xvfb-run -a godot --path . --rendering-driver opengl3 --script tools/screenshot.gd -- \
  --level res://levels/level_01.txt --time dusk --out /tmp/dusk --shots 3,5.5 --hold move_right
```

## The dawn: one frame lit from the east

The owner decided that the frame after the Eclipse is the one time in the
game the sun is in the east, "with a mirrored shadow solve made once"
(`docs/campaign.md`, "Decided by the owner"). It is `DawnFrame`
(`scripts/campaign/dawn_frame.gd`) over `levels/dawn.txt`.

**What is mirrored is the whole frame, not the mask.** The atlas is drawn lit
from the west — gold down the west edge of every column, the west reveal of
every arch — and so is the prince (`PlayerArt`: "the lit plane is always the
world-left side of the body"). A mask solved from the east over that art
would throw every shadow one way from stones lit the other, and the frame
would read as wrong without anyone being able to say why. So:

1. `levels/dawn.txt` is written **mirrored**: its rows are the frame as the
   solve sees it, sun in the west. Its header says so; read a row right to
   left to see it as the player will.
2. `Level` builds and dresses it, and `SunShadow` solves it **once**, at load,
   exactly as it solves every chapter. Nothing in the solve changed.
3. The world node is reflected (`scale.x = -1`), and the shader is told by
   giving it a negative width (`level_px.x = -width`, `mask_origin.x` the
   reflected edge): `x` on screen is `width − x` in the mask, and the shader
   itself is untouched.

On screen every shadow then falls down and to the **left**, every column
carries its gold on its east edge, and the swordknight — standing at the
spawn mark, facing west in the file — faces the sunrise with his lit side
toward it. His long shadow along the floor is the one thing drawn by hand: a
body 22 px tall on the sun's lane of two across for one down casts 44 px, and
it is drawn as the floor's cap going to its shade twin, which is what the
solve does to a floor under any standing caster. The sky is in its own
`CanvasLayer` and is not reflected; `ParallaxSky.east` mirrors the disc (and
the Mirror Tower) about the middle of the view instead. Even the words cast
their shadow to the left (`EndingCard.light_from_east`).

`tests/unit/test_dawn_frame.gd` reads the mask back through the reflection
and finds the floor west of the doorway wall shaded and the floor east of it
lit, and — so that it cannot pass by reading a mask with no shade in it —
solves the same stone unreflected and finds the opposite.

## Shade twins

A surface going into shadow is not that surface darkened. It is the next tone
down the duotone ramp, which is the art direction's central idea.

The atlas is two halves in register. Every tile has a shade twin
`Tiles.SHADE_ROW_OFFSET` (4) rows below it. The shader reads the mask and, where
it says shadow, samples the twin instead: one extra texture fetch, and no second
pass over the tilemap. The current atlas is 256 × 128 px — 53 tiles and 53 twins.

The atlas and the TileSet are generated:

```bash
python3 tools/generate_tiles_png.py
godot --headless --path . --script tools/build_tileset.gd
```

Both are byte-for-byte reproducible; that was checked when this work merged.

## Cost

`SunShadow.timings` records each phase of the last build, so the numbers here
can be checked rather than believed. Measured at merge, six builds each, in a
cloud container with no GPU on a shared CPU:

| Level | Mask | Typical build | Range |
|---|---|---|---|
| `level_01` | 1264 × 352 px | 92 ms | 91–149 ms |
| generated | 688 × 336 px | 42 ms | 41–49 ms |

Both are about 0.2 µs per mask pixel, linear in area, as the lane sweep
promises. The phases split roughly a quarter rasterise, a third depth, the rest
the sweep; the upload is negligible. Per-tile opacity bitmaps are cached across
levels: 1.7 ms on the first build, about 0.01 ms after.

This is a **one-off cost at level load**, paid behind the scene wipe
(`docs/feel.md`). It is not per frame. A phone may be several times slower than
the figures above; nobody has measured one yet. If a level load ever shows a
hitch, the sweep is the phase to look at first.

Above 2048 px in either dimension (`SunShadow.MAX_MASK_PX`, the GL ES3
guaranteed texture size), the mask is solved and stored at half resolution. A
long generated level reaches that.

## Architecture from terrain

`scripts/world/dresser.gd` reads terrain and adds what a builder would have:
arcades cut into wall faces, cornices and balustrades along terrace lips,
colonnades down wide terraces, friezes, niches, planters, hanging cloth, and
foreground archways that put the third depth plane in front of the player.

**It cannot change a level's difficulty.** Decoration tiles carry no collision
and no queried kind (`tools/build_tileset.gd`), and every mark sits in a cell
the terrain left empty. A level can be dressed, undressed or re-dressed and the
character's reachable set is identical. That is what makes it safe to run over
levels it has never seen. `tests/world_dressing_test.gd` checks the two
conditions that make it true — no decoration tile can collide, and every mark
leaves its own cell empty — rather than recomputing the reachable set.

**Restraint is a rule.** Every dressing rule has a minimum run width and a
spacing (the constants at the top of `dresser.gd`), because the failure of
automatic decoration is ornament on every surface. Three arches and one long
shadow beat a wall of carving.

**Authors can override.** Marks written in the ASCII win over rules. The
glyphs are documented in the header of `levels/level_01.txt` and defined in
`Tiles.DECOR_LEGEND`. Most of level 1 is deliberately *not* marked up: a level
that needed hand marking would mean generated levels could never look like it.

## Room moods: wear, growth and the things people leave about

Architecture alone made every room the same room. The end of `dresser.gd`
cuts a level into rooms `ROOM_COLS` (20) wide and gives each **one** mood, in an
order shuffled per level from its name so that neighbours never repeat:

| Mood | What it adds |
| --- | --- |
| garden | ivy over the parapets and down the faces, grass along the lips, a potted palm, the planters in flower |
| store | urns and jars, against the walls and stacked in the open |
| ruin | cracked and spalled stone, rubble at the foot of the walls |
| court | latticed windows, lanterns under overhangs, a rug airing over a railing |

Two things happen everywhere regardless of mood: stone standing in water grows
moss, and a wall tall enough to be a building (`TALL_WALL` courses of sheer
face) gets storeys of windows — a sheer face that high with nothing in it is
the placeholder `art-direction.md` warns about.

One mood per room rather than a little of everything everywhere is the
restraint rule applied to life: a room reads as *the garden* the way a street
does. The sixteen tiles are the atlas's third row; their shade twins come from
the same `SHADE_MAP`, which is why the atlas grew to three lit rows and
`SHADE_ROW_OFFSET` to 3.

These go on a fourth layer, **Props**, drawn over Decor on the same plane, so
an urn can stand in front of a cornice and ivy can hang over a frieze without
taking either's cell. `SunShadow.build()` stamps both planes, so a palm or an
urn casts its own shadow without erasing the cornice behind it. The safety
argument is unchanged: no collision, no queried kind, never on a reserved
cell, and every prop either lies over stone the terrain already has or stands
in a cell it left empty. `tests/unit/test_room_moods.gd` checks those, that
neighbouring rooms differ, and that a mirrored arena is dressed as a mirror.

## The air

`scripts/render/ambience.gd`, one node per level. Dust is one pixel of
`LIGHT_SOFT`, drawn **only where the shadow mask says the air is lit**
(`SunShadow.last_mask`, the CPU copy of the mask solved at build). A mote
drifting into a cast shadow vanishes and reappears on the far side, so with a
few dozen of them moving the shadow's edge is visible in the air at exactly the
slope the sun throws it — a shaft of light with no haze, no gradient and no
extra pass. Leaves come down off the ivy, palms and planters, a handful of
sources per level. Everything is a pure function of the clock: nothing is
spawned or freed, and none of it is gameplay.

A flock of birds crosses the far sky every thirty-one seconds
(`ParallaxSky._draw_flock()`), in the sky's own crimson, a step darker.

## The duel's zones

The tug-of-war strip (`levels/duel_zones.txt`) is drawn by the same path, a
zone at a time, by `scripts/duel/zones_view.gd`. Two things differ from a
level, both because the strip is streamed and wider than one texture:

- **Dressed once, whole.** `ZoneStrip.as_level()` stitches the five zones into
  one `AsciiLevel`, and `WorldDresser` runs over that at setup. A terrace
  across a seam gets one colonnade rather than two halves, and since the strip
  mirrors about its centre, so does its dressing.
- **Lit per zone.** The strip is 2400 px wide, over `MAX_MASK_PX`, so one mask
  would be half resolution. Each zone's mask is solved over the zone plus
  `ZoneView.SHADOW_LEAD` (8) columns to its west — shadows fall east and stop
  after `REACH_TILES` — and the shader's `mask_origin` places it.
  `tests/unit/test_zone_dressing.gd` compares each against a solve over
  everything west of it, pixel for pixel; with no lead, two zones disagree.

Measured at setup in the same container as the table above: about 15 ms to
dress the strip and 130–180 ms to solve the five masks, once per match, before
the countdown. Streaming a zone in writes cells and nothing else.

In a duel the foreground plane is drawn at 55% (`ZoneView.FORE_ALPHA`): a
column in front of the prince costs nothing, a column in front of the other
fighter hides the stance you are reading.

The room moods are **not** run on the duel's zones: `ZoneView` draws the
architecture and the foreground the dresser returns and leaves its `props`
plane out, as the art pass intended for the duelling ground.

## Secrets

A secret room is a seal and the room behind it. The ASCII marks only the seal
(`Tiles.SEAL_LEGEND`); the room is the `:` masonry a flood from the seal
reaches, with the entity marks inside it, so it is drawn the way a niche is
drawn and cannot be forgotten. `AsciiLevel._find_secrets()` does the flood.

| Seal | In play | Opens to | Tell |
| --- | --- | --- | --- |
| `%` false | `BACKDROP`: there is no wall | the body walking into it | a bricked-up doorway, air drifting out of its joints |
| `&` cracked | `SOLID`: a wall, a ledge, a floor | the sword: a swing, an air slash, or a plunge onto a cracked floor | the same doorway with a crack, shedding grit; on a floor, a hairline across the cap |

A fall does not open a cracked floor, however hard: luck is not looking.

### The tell is architecture

The tell is the mason's one, because architecture is the subject: a doorway
that was filled in. Coursed ashlar never lets a vertical joint run through two
courses; an opening bricked up afterwards always does, down both jambs, and
the fill is laid in smaller stones whose beds never meet the wall's. The fill
is drawn in the wall's own tones, so the doorway is there for whoever looks
and nothing to whoever runs. The motion — a mote, a grain — is the half that
catches the corner of the eye, one pixel at a time. Ruin rooms crack walls
too, so the doorway's shape is the part that cannot be confused, and the
dresser's marks are cleared off every secret and the cells in front of it.

### Drawing a lie, and taking it back

`Level.build()` paints the terrain as it really is and takes everything that
decides the *look* — caps, lit edges, dressing, the shadow — from the facade
(`AsciiLevel.facade()`), the level with every unfound room solid. Over each
room `SecretView` lays a cover of the facade's own tiles. Finding one:

- repaints the terrain around it from the level as it now is, which is also
  what removes a cracked seal's collision (at once: a plunge that opened a
  floor this frame falls through it this frame);
- drops the cover out in an ordered dither spreading from the point of entry
  (`dissolve` in `assets/world_shadow.gdshader`) — hard pixels the whole way;
- swaps in the room's light. The shadow is solved twice at build, sealed and
  with every room open; each differing mask pixel belongs to its nearest
  secret, and finding it copies those pixels into the live mask. A found room
  is in its own shade with a shaft through the doorway, and nothing is solved
  in play. The second solve costs what the first does, behind the same wipe,
  and only in a level that has secrets.

What a room holds is hidden until it is found; found secrets stay found
through deaths, and a restart seals them all again (`SecretKeeper`).

### Never required, never a trap

`LevelReachability.audit_secrets()` proves it for every combination of found
and unfound secrets; `docs/level-generation.md` has the details.
`tests/unit/test_secret_proof.gd` runs it on the Sun Terrace and refuses one
broken level per clause.

### The Sun Terrace's three

| | Where | Seal | Prize |
| --- | --- | --- | --- |
| A | the cistern's far wall, at the bottom of the pit | false | a relic |
| B | the high block's face, over the basin's run-up | cracked | a relic, and an inscription |
| C | the guard's floor, under the low platform | cracked floor | a relic, in a cellar you climb out of by a ledge grab |

One per act, each teaching the next: walk through, cut through, plunge
through.

## Directives and wiring

A level file can say things about itself that are not rows of it. A comment
that starts `;!` is a **directive**:

```
;! time dusk
;! channel 1 latch
;! channel 2 hold 4.0
; The Cistern Gate
```

A directive is a comment first. The geometry parser skips it like any `;`
line, so it can never move a tile — the failure the format has been burned by
twice — and it is never taken for the title, which is still the first plain
comment. `;` stays the only comment marker; `#` is still a solid tile.

| Directive | Means | Read by |
| --- | --- | --- |
| `time <stop>` | the hour the level is set at | the time-of-day grade |
| `horizon <row>` | the row the sun has set behind | the time-of-day grade |
| `checkpoints x\|route` | what "further on" means for a torch | `Game`'s forward-only rule |
| `channel <name> <mode> …` | what a wire does (below) | `ChannelBus`, the reach model |
| `mark <glyph> <kind> [key=value …]` | `glyph` places an entity of `kind` here, with these parameters | `AsciiLevel` |
| `dress authored` | dressed with the level's own marks and nothing else: no rule adds a colonnade, an arcade, a foreground piece or a room mood | `WorldDresser` |

`dress authored` is for a frame composed shot by shot rather than a level
played through. The rules exist because nobody composes every screen of a
170-column ruin; a still that *is* one composition — the dawn's — would have
them put a colonnade and a foreground archway into a picture whose subject is
one figure on an empty floor (*The dawn*, below).

`AsciiLevel.DIRECTIVES` lists the names something reads. A name that is not
there is a *problem*, like a malformed line or a glyph in no legend; problems
are collected in `AsciiLevel.problems`, `Game` warns about them (and about
what only the registry can tell, `EntityRegistry.problems_in()`) when the
level loads, and `tests/unit/test_level_directives.gd` refuses a shipping
level that has any. Nothing about a problem stops a level from playing.

### Mechanism glyphs

A glyph in `Tiles.MECHANISM_LEGEND` places a mechanism the way an entity
glyph places an entity, with three differences. Every **connected run** of
one kind's glyphs (up, down, left, right) is *one* mechanism, anchored at the
run's bottom-left cell — where a thing that stands, stands — with the whole
run in its `cells`, so a portcullis three cells tall is one gate. Its cell
parses as `Tiles.MECHANISM_TERRAIN` says: empty, unless the mechanism is
terrain and stays it, like a plate, which is a floor stone. And it is wired by
the mason's marks it touches.

Each mechanism's builder adds its glyphs, one line each, with one line in
`EntityRegistry.kinds()`. A kind can have several glyphs that mean different
places in one run -- the lift's slab and its shaft -- so the parser keeps
which glyph is where: `AsciiLevel.mechanism_glyphs`, and `glyphs` on each
mechanism's mark for its reach hook. The campaign's proposed glyphs
(`docs/campaign.md`, *Glyphs*) are all free.

### Mason's marks

A digit `1`–`9` is a **mason's mark**: solid stone carved with a channel
number. A mark wires the one mechanism it touches, up, down, left or right,
and every mechanism carrying the same digit is on the same wire — the stone
under a plate and the lintel over its gate:

```
;! channel 1 latch
#######1#######
       !
  @    !     D
###o###########
###1###########
```

Marks live in stone rather than in a header so an edit that inserts a row or
a column cannot detach a wire, and the mark's cell collides exactly as the
wall it is cut in. Three things are problems, each with its cell named: a
mark touching no mechanism, a mark touching two, and a mechanism touching
two different marks. A fourth needs the registry: a mechanism that is nothing
without a wire (`Mechanism.wired()`) placed with no mark.

### Channels

What a press *means* is the wire's, never the trigger's, so a plate is just a
plate and the level says what it does:

| Line | The wire is on |
| --- | --- |
| *(none)* — momentary | while anything presses it: two plates on one wire are an OR |
| `channel 1 latch` | from the first press, for good |
| `channel 2 hold 4.0` | while pressed, then for 4.0 s after the last foot leaves |
| `channel 4 beat 0` | for the first half of every period (100 frames), from frame 0 |
| `channel 5 beat 50 period=120` | the same clock, phased and with its own period |

`ChannelBus.step()` is the wires' clock, called once per playing physics
frame by `Game`: a hold counts down in frames and a beat is
`frame - phase` modulo its period, so a blade on a beat cuts on the same
physics frame on every device and stops for a hitstop or a pause exactly as
the actors do. A channel can also be named by a word, with `channel=` on a
declared mark (below), and a wire can be latched from code
(`ChannelBus.latch()`), for a deed — a seal opened, a lever pulled.

### Declared marks

`mark` binds a glyph no legend uses to a registered kind for this level only:
for a one-off, or for a test's toy. Letters are free; digits are not, since
they are mason's marks. A declared run is one entity, like a mechanism
glyph's, and its cell is left empty in the grid:

```
;! mark k plate channel=west
;! mark m gate channel=west
      m
      m
  @ k m     D
```

Declared and legend marks join in reading order, which is the order `Game`
places and meets them.

### From the campaign's drafts

`docs/campaign.md` drafted its chapters before this syntax existed, with
`; @` headers. Its marks, channel modes and glyphs are taken as they are;
only the header prefix differs, so converting a draft is one substitution,
`sed 's/^; @/;! /'`:

| Draft | Level file |
| --- | --- |
| `; @time golden` | `;! time golden` |
| `; @horizon 32` | `;! horizon 32` |
| `; @channel 1 latch` | `;! channel 1 latch` |
| `; @channel 2 hold 4.0` | `;! channel 2 hold 4.0` |
| `; @channel 4 beat 0` | `;! channel 4 beat 0` (the drafts' 50-frame beats are the default 100-frame period's halves) |
| digits `1`–`9` beside a mechanism | the same: mason's marks |
| `o ! [ ] ' , x O Q z i` | the same, once registered in `Tiles.MECHANISM_LEGEND` (`o` with `MECHANISM_TERRAIN` solid) |
| `w j g Y E` | the same, in `Tiles.ENTITY_LEGEND` and `EntityRegistry.kinds()` |

`;!` rather than `; @`, because a directive must never be mistaken for prose:
a legend comment such as `; @ marks the spawn` is exactly what a level's
header says, and a `!` straight after the `;` is not something a sentence
does.

### What a mechanism is in play

A mechanism (`scripts/mechanisms/mechanism.gd`) changes what its cells are
with `set_kind()`: stone, a one-way platform, spikes, a ladder, or air. It
never repaints the tilemap. It brings its own `StaticBody2D` on the solid or
one-way collision layer, which the prince's own `move_and_slide()` meets like
terrain — so dropping through a one-way mechanism works the way it does
through a platform, by clearing the one-way bit — and it writes the cell's
kind into the level's **overlay** (`Level.set_overlay()`), which every tile
query reads first: the ledge grab, the footing check, the stand-up room, the
hazard check, a guard's turn at a wall. Both halves are needed, and a test
breaks each one: with only the overlay the prince walks through a shut gate;
with only the body he could grab it and stand up inside it.

The tilemap, the dressing and the cast shadow are built from the level as
authored, so a mechanism draws itself and casts no sun shadow. Mechanisms
are props in the light, like a torch.

### The lift

`[ ]` is a lift's slab at its home stop and `'` the shaft it travels; the
glyphs are one mechanism (`scripts/mechanisms/lift.gd`), and the end of the
run furthest from the slab is the other stop, so a lift drawn with its slab at
the bottom goes up and one drawn at the top goes down. The shaft's top cell is
in the landing's top row, so the slab arrives flush with it. Unwired, it is
ridden: it leaves 30 frames after a body's weight is over it, travels at a
walk's 40 px/s, waits at the far stop, and goes home 180 frames after it is
empty; a rider must step off before he can send it back. A mason's mark beside
it wires it instead: at the far stop while the channel is on. It never closes
on a body, and coming down it waits two tiles above one, room for a hop. At
rest its cells are stone in the overlay; moving, it is only its kinematic
body, which the prince and the foes ride as they stand on terrain. To the
proof an unwired lift is a ladder between its stops with the lower slab as
floor; a wired one is floor at whichever stop its wire puts it.

Who counts as standing on a plate or a lift is one helper,
`scripts/mechanisms/weight.gd`: the prince, and any live foe whose
`has_weight()` is true -- a cat or an owl answers false.

### Restarts and respawns

A restart rebuilds the level, mechanisms included, on a new bus. **A
checkpoint respawn puts every mechanism back as the level text placed it
too, on a new bus that keeps what the old one latched**: a trap resets, a
deed does not. A gate whose plate latched it comes back open; a held gate
comes back shut and its race starts again from the plate; a beat starts its
count again. Relics, found secrets and fallen foes stay as the prince left
them.

What makes keeping latches safe is the checkpoint proof: a torch is proved
from every channel mask the prince can be standing on it under, and every
bit the proof sets is a latch, so a respawn is always into a state the proof
has walked. A latch that drops a floor between a torch and the door costs
that torch its checkpoint instead of making the respawn a soft lock.
`Game`'s checkpoint notes carry the argument.

### Proving a level with mechanisms

Each mechanism kind tells the reachability proof how it changes passability
(`static func reach(mark, model)`), and the proof searches over a channel mask
as well as cells: see `docs/level-generation.md`, *Mechanisms*. A level with
no mechanism is proved exactly as it always was.

## Tests

- `tests/unit/test_level_directives.gd` — directives move no tile and are
  never the title; a mason's mark wires the one mechanism it touches, and a
  stray or doubled mark is a problem with its cell; declared runs, anchors,
  parameters and reading order; channel lines; every malformed line is a
  problem; shipping levels have none.
- `tests/unit/test_mechanisms.gd` — the bus's four modes, the overlay, a
  stone plate and a gate on one mark in the game scene, a beat gate keeping
  time with the game, the restart rule, the respawn keeping latches and
  resetting presses, and an unwired mechanism as a problem.
- `tests/unit/test_lift.gd` — the lift played in the game scene: it leaves 30
  frames after a rider boards, travels five courses at 40 px/s, goes home 180
  frames after it is empty, is not ferried back with a rider aboard, waits two
  tiles over a body in its way, follows a wire, is stone only at rest, is a
  ladder to the proof and goes home at a respawn.
- `tests/unit/test_secret_walls.gd`, `tests/unit/test_secret_count.gd` — the
  seals played through the real game scene, and the count.
- `tests/unit/test_zone_dressing.gd` — the duel's zones: the stitched strip is
  the strip, every zone is dressed, the dressing mirrors, each zone's shadow
  matches the whole strip's, and none of it reaches the simulation.
- `tests/world_shadow_test.gd` — the shadow model: the sun's direction, what
  casts, the two sparing rules, that shipping levels are neither blank nor
  black, and that the mask fits a texture. The shade-twin lookup itself has no
  dedicated test; it is checked by eye in screenshots.
- `tests/world_dressing_test.gd` — decoration cannot collide, marks leave
  their cell empty, every shipping and generated level gets architecture, and a
  symmetric level is dressed symmetrically.
- `tests/unit/test_room_moods.gd` — the props plane: where a prop may sit,
  that rooms differ, determinism, and mirrored arenas.
- `tests/unit/test_dawn_frame.gd` — the dawn: shade west of what casts it,
  the disc in the east, the swordknight facing it, the frame dressed by its
  author alone.
- `tests/unit/test_mirror_tower.gd` — the Mirror Tower in the campaign's sky:
  only ever nearer, reached at Chapter IV, a tone apart from the sky behind
  its crown at every hour and every distance; `tests/unit/test_duel_sky.gd` —
  none of it in the duel's sky or any other scene's.
- `tools/world_debug.gd` — not a test. Dumps a level's dressing and shadow mask
  for inspection.
