# Interface and typography

The game's text is set in **Alcazar**, a bitmap typeface drawn by
`tools/generate_font.py`. Nothing in the interface uses
`ThemeDB.fallback_font`, and nothing should: the fallback is Open Sans, and a
sun-bleached Moorish city wearing the system UI font is the loudest possible
signal that a game was assembled rather than designed.

The specimen sheet is `docs/typography.png` — the face at the size it is
actually set at, magnified, and before/after of every screen.

---

## The face

Alcazar is a Latin **unicase** built on square-Kufic manners. It is invented,
not traced: no real script is imitated, only the posture is borrowed.

| | |
| --- | --- |
| Square counters | O, C, G, D are rectangles. At five pixels a curve is a lie, and the reference inscriptions are rectilinear anyway. |
| Terminal bars | C, E, S, Z, L, U close on a full-width horizontal. The long baseline bar is the loudest thing about the reference lettering. |
| Raised bars | A, B, E, F, G, H, P, R carry the crossbar one row above centre, so every letter stands on a long leg. |
| Flat apexes | A, M, W, V have no points; diagonals are steps. Both a Kufic cue and the only way a diagonal survives at five pixels. |
| Barred I, footed 1 | The alif-like stem closed top and bottom. |
| Dotted zero | `0` carries a centre pixel; `O` does not. They are otherwise the same rectangle. |

### Three cuts, not one scaled face

The viewport is 180 units tall. The difference between a five-pixel cap and a
seven-pixel cap is the difference between a readable hint and a smear, and
neither one is a title scaled down. So there are three drawings:

| Cut | Cap | Atlas | Used for |
| --- | --- | --- | --- |
| `UiFont.Cut.MICRO` | 5 px | `assets/font_alcazar_micro.*` | hints, readouts, button labels, captions |
| `UiFont.Cut.TEXT` | 7 px | `assets/font_alcazar_text.*` | menu rows, counters, settings labels |
| `UiFont.Cut.DISPLAY` | 14 px | `assets/font_alcazar_display.*` | the title, level cards, overlay titles |

MICRO is its own drawing on a 5×5 body — at that size every letter has to be
square, which is conveniently the most Kufic the face ever looks. DISPLAY is
the TEXT cut at double scale with one addition: every vertical stem that
reaches the baseline is stood on a one-pixel **spur**, while anything wider
than a stem (the terminal bars of C, E, L, S, Z, the bowl of D) stays flat.
That is what makes it a display cut rather than the small face enlarged.

There is no fourth size and there is no scaling. Asking for a point size that
is not a cut is how a bitmap face turns to mud.

### What is in it, and what is not

Present: `A–Z`, `0–9`, space, and `. , : ; - / ( ) ' " ! ? % +` plus the two
typographic marks the UI leans on, the middle dot `·` (U+00B7) and the em dash
`—` (U+2014). Lowercase is mapped onto the capitals in the `.fnt`, so a string
that forgot its `.to_upper()` still renders.

**Left out, deliberately:** true lowercase, accented letters, `@ # $ & * = _
| ~ ^ < > [ ] { } \`` and every currency symbol, and kerning pairs. Nothing in
the game prints them. `tests/ui_layout_test.gd` asserts that every character in
the documented set exists in all three cuts — a missing glyph renders as
nothing at all, which is invisible in a diff and obvious only to a player.

---

## The font pipeline

```
tools/generate_font.py          glyph tables -> atlas PNG + BMFont .fnt
    |
    v
assets/font_alcazar_{micro,text,display}.{png,fnt}
    |
    v   godot --headless --path . --import
FontFile resources
    |
    v
scripts/ui/ui_font.gd           the only thing that names those files
```

To rebuild:

```sh
python3 tools/generate_font.py
godot --headless --path . --import
```

Both the `.png` and the `.fnt` are committed, along with their `.import`
files. The `.fnt` is BMFont's text flavour, which Godot imports to a `FontFile`
with no further configuration.

> One trap, since it cost an hour: the `common` line must say
> `alphaChnl=0 redChnl=4 greenChnl=4 blueChnl=4` — the glyph lives in the alpha
> channel and the colour channels are "one". Declare the glyph as living in the
> colour channels and Godot builds each glyph out of a texture that is white
> everywhere, so every letter renders as a solid filled block.

### Adding a glyph

1. Open `tools/generate_font.py`. Add the character to the `TEXT` table as a
   list of seven `#`/`.` rows (eight if it descends below the baseline, like
   `,` and `Q`), and to the `MICRO` table as five rows (six with a descender).
   Widths are free; the advance is the drawn width plus one.
   The DISPLAY cut is derived from `TEXT`, so it needs nothing.
2. `python3 tools/generate_font.py` — it re-packs the atlas and rewrites the
   metrics. The atlas grows to the next power of two by itself.
3. `godot --headless --path . --import`.
4. Add the character to the `used` string in
   `tests/ui_layout_test.gd::_test_font_covers_the_game_strings`, so it stays
   present.
5. Look at it: `python3 tools/specimen_sheet.py docs/typography.png …` (see
   below) and read the sheet at 1:1.

Keep it rectilinear. A diagonal is a step, not a line, and the only diagonals
in the face are in `K N R V W X Y Z / %`.

---

## Layout rules

Three modules, in `scripts/ui/`:

- `ui_font.gd` — the faces, measurement, and the only text-drawing call.
- `ui_layout.gd` — every rectangle the interface is allowed to use.
- `ui_marks.gd` — the drawn parts: rules, lozenges, tallies, gauges, arches.

### Safe areas

`DisplayServer.get_display_safe_area()` reports **physical pixels**; the canvas
is in units. `UiLayout.safe(view)` does the conversion and returns the usable
rectangle. Chrome goes inside `UiLayout.content(view)`, which is that
rectangle pulled in by a 7-unit gutter.

Two things it does that a naive conversion does not:

- It clamps negative insets to zero. On desktop the "safe area" is the whole
  desktop, not the window, so the right inset comes out as a large negative
  number. Believing it pushed the touch buttons clean off the right edge.
- It refuses any single inset larger than `MAX_INSET` (22%) of the screen.

Never write a literal offset from a screen edge. `10.0` from the corner is
underneath the notch on half the phones sold since 2017.

### Variable width

The viewport is fixed-height with an **aspect-derived width**. In practice the
engine floors the canvas at the 320-unit base width — a 4:3 screen is
letterboxed rather than narrowed — and widens it from there, so the real range
is **320 to about 440 units** (21:9). Height is always 180.

Consequences:

- Centre on `UiLayout.safe(view)`, never on `160`.
- Put lists and forms in `UiLayout.column(view, want)`: a column of the width
  you want, centred, clamped to the screen. A 440-unit-wide line of menu text
  is not a menu.
- A sentence that fits at 440 may not fit at 320. `UiFont.fit()` takes a list
  of phrasings, longest first, and returns the first that fits. Use it for
  every hint line.
- `tests/ui_layout_test.gd` exercises the layout at 240, 320 and 440 units and
  asserts that the two extremes do not produce the same numbers.

### The reserved band

`UiLayout.banner(view)` is a 48-unit band across the middle of the safe area.
**It is the only place an overlay may put words.** Level title cards, PAUSED,
ESCAPED, round results, match results, the desync warning and the duel's hit
flashes all live there and nowhere else.

This is a promise to the level art: nothing will be written outside that band,
so the floor can be a row of spikes. `PAUSE TO QUIT` used to be printed across
them. Persistent duel hints now sit at the top centre, under the network line,
for the same reason.

The title card and the pause overlay share the band, so only one is ever drawn.

### The light

Everything obeys the same lighting law as the world (`docs/art-direction.md`):
the sun rakes in low from the left. So:

- Text takes a cast shadow one unit right and down, in ink —
  `UiFont.draw_text(..., shadow: 0.8)`. That is what lets a caption sit over a
  bright sky without a box behind it.
- A raised mark throws the same shadow (`UiMarks.CAST`).
- A carved recess is lit along its **lower and right** inner walls
  (`UiMarks.recess`), because those are the faces the sun reaches.

### Pixel grid

`UiFont.draw_text` rounds its origin to whole canvas units. A bitmap glyph on a
half unit samples between pixels and goes soft. If you draw type by any other
route, round it yourself.

---

## The screens

| Screen | File |
| --- | --- |
| Title screen | `scripts/ui/menu.gd`, `scenes/menu.tscn` |
| Settings | `scripts/ui/settings_panel.gd` |
| Level HUD, title card, pause/complete overlay | `scripts/ui/hud.gd` |
| Touch controls | `scripts/ui/touch_controls.gd`, `scripts/ui/touch_surface.gd` |
| Duel HUD | `scripts/duel/match_hud.gd` |

### Title screen

Built back to front: the parallax city, a graded wash, a scalloped lintel
across the top, the title, the list, and a **foreground balustrade** you are
standing behind. The balustrade is the only piece of foreground occlusion on
any screen and it is what makes the menu a place rather than a background.

Only the selected mode shows its subtitle, in a fixed slot below the list, so
moving the selection does not reflow anything. Five modes each with a caption
is a wall of small type.

The hint line is cut into the rail (`UiLayout.rail(view)`, shared with the
settings page). When the on-screen stick is up, a sword button covers the right
end of that rail, so the hint moves to the left end and says less — the buttons
are lettered and are the instruction at that point.

**The update plaque.** A development build (and only one: see
[`docs/ci.md`](ci.md#the-dev-channel-one-tap-updates-on-the-phone)) asks the
dev channel's `version.json` whether it has been superseded. If it has, a
plaque hangs from the centre of the lintel reading `UPDATE AVAILABLE · BUILD n`
in MICRO, in the light colour, between two lozenges. It sits there because the
top centre is the only place on this screen that is neither the list nor a
touch button, and the only place wide enough for the whole phrase at 320 units;
`MenuScene.PLAQUE_CLEARANCE` keeps it clear of the pause and mute buttons, and
`UiFont.fit()` shortens it to `UPDATE · BUILD n` or `BUILD n` if a screen is
too narrow. It is hung from the architecture rather than floated as a toast,
so it reads as part of the place.

It is the one thing on the title screen that is **touched** rather than chosen
with the stick: it is not a way into the game and does not belong in the list
the stick walks. Its touch target reaches `PLAQUE_TOUCH` (24) units below the
top of the safe area — about 9 mm on a phone held sideways — and overlaps the
top of the title, which is not touchable, rather than shrinking. Only the touch
event counts, not the mouse click Godot emulates from it, so one tap opens the
browser once. `tests/unit/test_menu_update.gd` holds both properties.

### The HUD answers

A count that silently changes in the corner is a count nobody saw change. So
the corner answers for `Hud.PULSE_TIME` (0.45 s): a relic gained pops the
lozenge two units larger and steps it back in whole units, the count lit; a
health mark lost stays lit and burns white for a few blinks before it goes
dark. A heart regained answers the same way, mirrored: the mark burns white
for the same blinks at the same rate and then stays lit, so the blink says
which mark changed and what is left afterwards says which way. Only a gain
pops and only a change burns — a restart or a respawn at a torch refills
health and resets counts, and `Game` reports it to `Hud.update_model()` as a
refill, which sets off nothing (`tests/unit/test_pickup_feedback.gd`,
`tests/unit/test_relic_heals.gd`).

A relic is worth a heart. At full health it is only a relic: it still counts
toward the tally on the complete screen, nothing is banked and nothing becomes
a score — the game keeps none, and a heal you could store would make every
relic a reason to stand still in front of a guard. The heart comes back
through `Player.heal()`, which emits `healed`; `Game` refreshes the corner on
that and on `hurt`. Before, the corner heard only about deaths, so a hit that
did not kill left three marks lit and the loss flash never fired in play.

The relic itself answers in the world: it bursts into a star and six sparks for
`Relic.BURST_TIME` instead of vanishing, and is no longer collectable from the
moment it is taken, so standing in the burst cannot count it twice. Still no
hitstop on a pickup — `docs/feel.md` explains why.

### Duel HUD

The rope hangs from the top of the content rectangle: five zone pips, the
initiative arrow in the leader's colour, and under them one MICRO line that
says what the arrow says (`ONE PUSHING WEST`, or `NEUTRAL`). That line is set
in paper, not in the seat's colour — crimson type on a crimson sky is
illegible, and the arrow already carries the colour. Under it, for an online
match, the network line, then the persistent hint; a hint wider than the safe
area breaks at its `  ·  ` separators rather than running off a 4:3 screen.

Everything an event throws up — a death, the initiative changing hands, the
gate — goes in the band, at the display cut if it fits and the text cut if it
does not. `MatchHud.flash(text, terse)` takes a second, shorter phrasing for
the narrow screen. The result is the band plate with title, rule, how the
match was won and the hint. A desync takes the band over. The only things
drawn at the bottom are the two respawn rings, which are marks, not words.

### Settings

A sub-screen of the menu, not a mode: it is not something you play, and
`ModeRegistry` is the list of things you play. **`scripts/core/mode_registry.gd`
is unchanged.**

Master / music / SFX volume and mute, written through
`AudioDirector.set_volume()` and `AudioDirector.toggle_mute()`, both of which
persist to `user://audio.cfg` for themselves. The panel subscribes to
`AudioDirector.settings.changed`, so a change made elsewhere — the `M` key, the
touch mute button — is on screen immediately.

The panel takes its director through an injected `audio` property rather than
reaching for the global, so `tests/ui_layout_test.gd` can drive it with a stub
and not touch the real mixer or write to `user://`.

Under the list, small and dim, is the running build: its version name, build
number and commit (`0.1.0-DEV+4F2C9E1 · BUILD 57`; a build nobody stamped says
`LOCAL`). It is on this page and not the title screen because only someone
reporting a bug needs it, and they will look for it where the settings are.

Volume is a ten-cell gauge, and a step snaps to the grid. Driven by the same
four actions as the menu: up/down to choose, left/right to set, jump to
confirm, sword to go back.

### Touch

`scripts/ui/touch_controls.gd` lays its buttons out against `UiLayout.safe()`.
It carries a **mute** button next to pause, drawn as a horn with a bar struck
through it when the game is silent — not lettered, because `SOUND` and `MUTED`
are the same width at five pixels and nobody reads a label on a button they
are hitting with a thumb. It is the only touch-reachable way to silence the
game short of the settings screen.

---

## Looking at it

Text is judged at actual size. A 1280×720 screenshot is a **four times
magnification** of the 320×180 canvas; judging type on it is judging a
different typeface.

```sh
# One frame per interface state, including the ones you cannot reach by
# playing: pause, settings, a finished match.
xvfb-run -a godot --path . --rendering-driver opengl3 \
  --script tests/ui_screens.gd -- --out /tmp/ui/after --window 1280x720

# The same at a wide-phone aspect: a 440x180 canvas.
xvfb-run -a godot --path . --rendering-driver opengl3 \
  --script tests/ui_screens.gd -- --out /tmp/ui/wide --window 1760x720

# Back down to 1:1, or a magnified crop in canvas units.
python3 tools/crop_1to1.py /tmp/ui/after/menu.png /tmp/menu.png
python3 tools/crop_1to1.py /tmp/ui/after/menu.png /tmp/title.png \
  --rect 60,20,200,70 --zoom 5

# The specimen sheet.
python3 tools/specimen_sheet.py docs/typography.png \
  before=/tmp/ui/before after=/tmp/ui/after wide=/tmp/ui/wide
```

`tests/ui_screens.gd` is deliberately **not** named `*_test.gd`:
`.github/scripts/run_tests.sh` collects that suffix and would try to run the
harness as an assertion suite. The suite is `tests/ui_layout_test.gd`.
