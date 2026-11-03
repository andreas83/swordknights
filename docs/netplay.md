# Netplay

Two-player duelling, locally and over a network.

This is the oldest idea in the repository: `legacy/prototype-py/` was a
two-player sword fight before it was anything else. This document is how that
works on the Godot foundation.

---

## The short version

| I want to…                        | Do this                                                  |
| --------------------------------- | -------------------------------------------------------- |
| Duel on one keyboard              | Menu → **Duel**. No network, nothing to configure.        |
| Duel on two phones, one Wi-Fi     | Menu → **Duel Online** → *Host on this Wi-Fi* shows a code like `23`; the other phone picks *Join on this Wi-Fi* and types it. |
| Duel over the internet            | Run a relay (below), both players pick *Host a room* / *Join a room*. |
| Play when none of that works      | *Local two-player*, which is on the same screen for exactly that reason. |

Controls are at the bottom of this file.

---

## Why it is built this way

Three decisions shaped everything else.

### 1. WebSocket, not ENet

The web export is the build you can send someone a link to, and a browser has
no UDP: `ENetMultiplayerPeer` does not exist there. A WebSocket is the only
transport a web build, an Android build and a desktop build can all share, so
it is the one the duel runs on.

The cost is honest: WebSocket is TCP. A lost packet is not dropped, it is
retransmitted, and everything behind it waits — so loss arrives as a latency
spike rather than as a gap. The prediction and reconciliation below is what
absorbs that.

`scripts/net/transport.gd` is an eight-method interface, and
`scripts/net/ws_transport.gd` is one implementation of it. An ENet transport for
native builds is a drop-in: nothing above that interface knows what a socket is.
`scripts/net/loopback_transport.gd` is the other implementation, used by the
tests, and it models true packet loss and reordering precisely because a future
UDP transport will have them.

### 2. Host-authoritative with prediction, not lockstep

Godot's physics is reproducible for one binary on one platform — that is what
`tests/duel_determinism_test.gd` pins down — but it is **not** guaranteed identical
across a web export, an Android build and a desktop build. A lockstep duel
between a phone and a browser would desync, and lockstep has no way to recover
when it does.

So one peer is the host and its simulation is the truth:

- **Host**: reads its own input, takes the client's input for the current frame
  if it has arrived, steps once, and every other frame broadcasts the state, its
  checksum, and the input it applied to get there.
- **Client**: steps immediately on its own input, so the sword answers the
  button with no delay, predicting the host's input by repeating the last one it
  was told about. When a snapshot arrives it discards its prediction, loads the
  host's state, and replays the frames since.

That replay is exact, which is the whole trick: `DuelMatch.step(bits_a, bits_b)`
(`scripts/duel/match.gd`) is a pure function of the match's state and two bytes.
`tests/duel_determinism_test.gd` asserts that running a stream of frames as a
burst inside one physics frame gives the same match as pacing it out one frame
per physics frame. If that were not true, the client would drift away from the
host on every correction. On the real fighter "the same" means every discrete
field identical and every position within the checksum's quantum, not bit for
bit — see the last item under *Not handled yet*.

Keeping the step pure also buys local two-player, replays, headless tests — and
leaves rollback possible later without rewriting anything.

### 3. Divergence is detected, not assumed away

A **mispredicted** frame is normal: the client guessed the host's input and
guessed wrong. A **divergence** is the two machines computing different results
from the *same* inputs — a bug, or a platform difference. Conflating the two
gives you a desync detector that cries wolf and gets ignored.

They are told apart like this. Every snapshot carries the input the host
actually applied for the frames behind it. So the client can take the *previous*
authoritative state, apply those *authoritative* inputs, and arrive at this
snapshot's frame with no guessing anywhere. If its checksum still disagrees,
that is a real divergence. It is counted, reported to the other peer, and put on
screen in letters across the middle of the display.

Ordinary misprediction is counted separately as `corrections` and is just the
cost of doing business.

The client needs no second simulation for this; it reuses the one it has,
because reconciliation is about to overwrite it anyway. (A second simulation
would in fact be *wrong*: two duels in one world have to sit at different
coordinates, and 2D physics is single-precision, so the same body at y=8192
resolves collisions on a coarser grid than at y=192 and the two disagree within
a couple of hundred frames. `tests/duel_support.gd` has the scar tissue.)

### The duel does not use `move_and_slide()`

This is the one thing in the design that looks like an eccentricity and is not.

`CharacterBody2D.move_and_slide()` is not a function of the body's transform,
velocity and shape. It carries state inside the engine that GDScript can
neither read nor write, and that state survives a snapshot restore. Two bodies
handed byte-identical state and byte-identical input therefore step to positions
a few thousandths of a pixel apart — measured at 0.0036 px, which is enough to
land on either side of the checksum's rounding.

The consequence is not cosmetic: a client cannot reproduce the host's frame
however correct both of them are, and the desync detector says so, truthfully
and uselessly. Everything else checks out — the snapshot restores every field
bit-exactly, the flags match, the collision shape matches, and a single
`move_and_collide()` query from that state returns bit-identical travel,
remainder, normal and depth. It is only the slide loop inside the engine that
differs.

So the duel runs that loop itself, in `Fighter._move()`
(`scripts/duel/fighter.gd`), over `move_and_collide()`, which has no such
memory. The collision mathematics is still the engine's; only the bookkeeping
between the queries lives in the file. The adventure is not simulated over a
network and still calls `move_and_slide()`.

Two things follow. The fighter's `grounded` is its own answer, not the engine's
`is_on_floor()` — the engine's flag is never set — and it travels in the
snapshot. And a duel is genuinely reproducible from its serialised state, which
is what `scripts/net/session.gd` always claimed and what makes the desync
detector worth having. (This was found, and first fixed, on the round duel the
game started with, which ran the prince himself; the round duel has since been
retired for the tug-of-war match.)

The checksum itself is FNV-1a over the quantised state — 1/256 of a pixel and of
a second, which is far finer than anything visible and still absorbs last-bit
float noise.

---

## The pieces

```
scripts/duel/
  match_sim.gd       DuelSim: the six things the session may know about a duel
  match.gd           the simulation: initiative, the strip, respawns, gates, and
                     step(bits_a, bits_b) — the one function that matters
  match_seat.gd      one fighter as the match sees it, and the referee
  match_ledger.gd    what the screen was told against what the history holds
  fighter.gd         the fighter; its own slide loop over move_and_collide()
  zones.gd           the strip of zones, read as one world
  duel_rules.gd      the step, the countdown, the seat names
  match_scene.gd     two seats, one keyboard
  match_online.gd    lobby, connection, and the same match with a session
  match_hud.gd       the rope, results, network status
  duel_touch.gd      the THROW button the shared touch controls lack
scripts/net/
  protocol.gd        versioned messages, encode and decode
  transport.gd       the interface
  ws_transport.gd    WebSocket: direct host, direct join, relayed by code
  loopback_transport.gd  a pair in one process, with lag, jitter and loss
  session.gd         handshake, prediction, reconciliation, desync detection
  rendezvous.gd      the relay
  lobby.gd           the lobby screen
levels/duel_zones.txt  the strip (and the zone files it names)
```

`scripts/player/player_input.gd` is the 8-bit wire frame both seats are
driven through. [`duel-match.md`](duel-match.md) is the match itself.

---

## Message flow

Every message is `[u8 version][u8 type][payload]`, little-endian. The version is
checked on arrival: two mismatched builds say so in the lobby instead of
desyncing in the third zone.

```
guest                         host
  |  HELLO (build, name, look) |      repeated every 30 frames until answered
  |--------------------------->|
  |      WELCOME (seat, zones, strip hash, look)
  |<---------------------------|      a mismatched strip is refused here
  |                            |
  |  INPUT (first_frame, bits[6])     every frame, a redundant window
  |--------------------------->|
  |      SNAPSHOT (frame, checksum, applied input, state)
  |<---------------------------|      every 2 frames, about 280 bytes
  |                            |
  |  PING / PONG               |      every 20 frames, both ways
  |<-------------------------->|
  |  DESYNC (frame, mine, theirs)     whoever notices tells the other
  |<-------------------------->|
```

Bandwidth: roughly **8.5 kB/s** from host to client and **0.7 kB/s** back. The
looks are about 45 bytes each way, once.

The applied input on a snapshot is the host's last **twelve** frames, not only
the two since the snapshot before (`NetSession.SNAPSHOT_INPUTS`). The client
can check a snapshot, and replay the frames behind it on the host's own input,
only if it holds the host's input for every frame since the last snapshot it
*received*; with two frames a snapshot, one lost snapshot was a hole in that
input. With twelve it takes six lost in a row. It costs twenty bytes a snapshot
and changes nothing on the wire -- the count was always there, and an older
client files the extra frames exactly where it filed the first two. On the
lossy link in `tests/match_net_test.gd` the client's verified snapshots went
from 427 to 504 of the 510 or so that arrive; it matters below, too, because
the frames the client can replay are the ones whose blood it can put where the
host's was.

The snapshot is *exact*. A 44-byte match header (frame, phase, initiative,
zone, kills, and the timers and scroll as doubles) and a 100-byte block per
fighter: position and velocity as doubles, then the discrete state — state,
frame count, facing, stance, the input's press-edge memory — as 32-bit
integers, then the fighter's sword. A replayed frame cannot re-fire a jump that
was already held, and nothing the simulation compares against a threshold is
rounded on the way: rounding a timer to 32 bits moves a transition by a whole
frame often enough to matter, and in a duel that is a sword landing or missing.

The catch ([`duel-combat.md`](duel-combat.md#the-catch)) added no bytes. Its two
states, `SNATCH` and `CATCH`, are appended to the fighter's state enum after
`DEAD`, so every older state keeps its number. The snatch window is the frame
count already carried. A caught sword is a record that was already in one of
the two blocks; the catch swaps the records, as a pickup does.
`tests/match_fighter_test.gd` round-trips and replays every frame of a catch.

The client runs ahead of the newest snapshot by the measured one-way latency
plus two frames of slack, so its input reaches the host before the host needs
it. Drift is corrected by stepping twice in a frame, or not at all — never by
jumping, which would be visible.

### The looks

Each phone draws the other player as that player chose to be drawn. The look —
the figure and the four palette choices from the wardrobe's player one, since a
phone is one player — rides once on the sender's half of the handshake: the
guest's on `HELLO`, the host's on `WELCOME`. It is an optional block on the
end of the message:

```
[u8 look format = 1][u8 count]   then count x   [u8 tag][u8 length][id bytes]
tags: 0 figure, 1 outfit, 2 accent, 3 hair, 4 skin   (append only)
```

The values are the wardrobe's own ids (`heroine`, `saffron`, …), not indices,
for the reason its save file uses them: two builds may list the options in a
different order, and an index would put a different colour on the other
screen. A whole look is under 50 bytes.

**Presentation only.** `NetSession` keeps the received ids in `remote_look` and
hands them to nothing but the scene: not the match, not a snapshot, not a
checksum. `match_online.gd` reads them with `CharacterLook.from_ids()` when it
is seated and dresses the other seat through `FighterArt.dress()`, which puts
the seat's colour on *after* the look. So the guest stays sea-green and the
host crimson whatever either sends — a guest asking for the crimson robe gets
the heroine's sash and hair and a sea-green robe.
`tests/match_net_test.gd` sends two different looks in every scenario and
still asserts zero desyncs.

**Nothing in it is trusted.** It is read by the rule the wardrobe reads its
file by (`scripts/net/protocol.gd`, `_get_look`):

- A block that cannot be read at all — cut short, a count over 16, a look
  format this build does not know — is dropped whole: the other player is the
  seat's default.
- Otherwise each field stands or falls alone. An id that is empty, longer
  than 16 bytes, or not lower-case ASCII, a tag past the end of the list (a
  field from a newer build), or a second copy of a field costs that one field.
  Ids are checked as bytes before they become a string, so a hostile peer's
  bad UTF-8 never reaches a decoder that would log about it.
- What survives is still only strings. `CharacterLook.take_ids()` decides
  whether they name an option, and an id that names nothing keeps that
  field's default.
- A bad look never fails the message it rides on. Refusing a `HELLO` over a
  sash would stall the handshake, which is exactly what a peer must not be
  able to do with it. The reason is kept in `remote_look_error` and logged.
- Once seated, later `HELLO`s cannot change the look.

**Versions.** The protocol version is **2**, bumped for the sword catch. The
catch changed what an empty hand's THROW does without changing a byte on the
wire, so a protocol-1 build and this one would seat each other and diverge the
first time an empty hand pressed throw. Now the HELLO is refused and the lobby
says the other phone runs a different build.

The look on the end of `HELLO` and `WELCOME` needed no bump of its own: it is an
optional block after the last fixed field, and a message without one reads as
"no look". A lookless peer of the same version plays on and is drawn in its
seat's default. A future change to the look itself bumps the look's own format
byte, which this build reads as "no look".

`tests/unit/test_net_look_wire.gd` holds the encoding — every look round-trips,
lookless bytes, a protocol-1 HELLO refused, truncation at every length, noise —
`tests/unit/test_net_look_session.gd` the handshake against a lookless peer, a
pre-catch guest and a bad look, `tests/unit/test_duel_seats_distinct.gd` the seat colour on every
received look, and `tests/net_live.sh` checks that a chosen look crosses a real
socket and the relay, and that a guest sending none is seated as the default.

---

## Running a duel

### Local two-player

Menu → **Duel**. Two complete, non-overlapping binding sets, because the shared
actions already claim both the arrows and WASD, so a second player reusing them
would move both duellists.

|           | Move    | Up/Down | Jump          | Sword | Guard | Walk |
| --------- | ------- | ------- | ------------- | ----- | ----- | ---- |
| Seat one  | `A` `D` | `W` `S` | `Space` / `V` | `F`   | `G`   | `Shift` |
| Seat two  | `←` `→` | `↑` `↓` | `K` / `KP 0`  | `J` / `KP 1` | `L` / `KP 2` | `;` |

Seat two also takes the numpad: `4` `6` `8` `5` to move.

These are written by `tools/configure_project.gd`, not by editor state:

```bash
godot --headless --script tools/configure_project.gd
```

### Direct, on a LAN

One player picks **Host directly** (listens on port 45678). The other picks
**Join directly** and types the host's address — `192.168.1.20` is enough; a
bare address, `host:port` and a full `ws://` URL are all accepted.

Lowest latency, no third machine. Needs both players on the same network, or a
forwarded port.

### By room code, over the internet

A browser cannot accept an incoming connection, so a web player can never host a
direct link and two web players could never meet at all. The relay solves that,
and removes port forwarding and NAT from the picture for native players too:
both sides dial *out*.

Start the relay anywhere both players can reach — a cheap VPS, or your own
machine with one forwarded port:

```bash
godot --headless --path . res://scenes/rendezvous.tscn -- --port 45678
# rendezvous listening on port 45678 — room codes are 4 characters
```

Then, in the game: **Relay:** → type the relay's address (`ws://your.host:45678`,
or `wss://…` behind a TLS terminator — a page served over HTTPS may only open a
`wss://` socket). Then one player picks **Host a room** and reads out the
four-letter code; the other picks **Join a room** and types it.

Codes avoid the characters people mishear: no `O`/`0`, no `I`/`1`/`L`, no
`U`/`V`.

The relay only pairs and forwards. The authoritative simulation still runs on the
player who opened the room, so the round trip becomes player → relay → player:
put the relay somewhere between the two of you. It is deliberately dumb about
duelling — it reads only the `ROOM_*` messages and forwards everything else
untouched, including messages from protocol versions it has never heard of.

Rooms are capped, expire after ten minutes unused, and close when the host
leaves (the authoritative simulation was there).

---

## When things go wrong

**A connection that will not open.** The lobby says why — refused, no such room,
room full, a different build — and offers local two-player on the same screen.
Nothing dead-ends into a blank wait.

**Packet loss.** Over WebSocket there is none; TCP retransmits, and the loss
shows up as a latency spike with everything behind it held up. The client keeps
predicting through the gap and catches up when the backlog lands. Over an
unreliable transport (the one this is built to accept later) a lost `INPUT`
costs nothing because every message repeats the last six frames, and a lost
`SNAPSHOT` costs nothing because the next one is a complete state. The handshake
repeats until answered. `tests/net_desync_test.gd` runs a scenario with a quarter of
all snapshots discarded; the duel still tracks the host and reports no desync.

**Lag and jitter.** Measured continuously by ping/pong. The client's lead
adjusts to it. `tests/net_desync_test.gd` runs 100 ms each way with 50 ms of jitter —
which also reorders messages, as UDP would.

**Input the host has not received yet.** The host repeats the last byte it had.
A held direction keeps running; a tap does not repeat. The count is on the HUD
as `STARVED`.

**A genuine desync.** Counted, reported to the other peer so both screens agree
something is wrong, and written across the middle of the display as
`SIMULATIONS DIVERGED`. The match keeps running on the host's state — it does
not silently drift, and it does not pretend to be fine.

**The other player leaves.** Said plainly, and the lobby comes back.

---

## Corrected outcomes

A client shows every frame twice over: once on its prediction, and again --
sometimes three times -- when the host's snapshot rewinds it and it steps the
same frames on the host's word. The screen must hear of a kill once, not once
per pass. And sometimes the second pass is not the same: the prediction had a
kill the host never had, or the host had one the prediction missed. This is how
those are presented, and why.

**A replay rings nothing.** `NetSession` steps every frame it has stepped before
between `duel.begin_replay()` and `duel.end_replay()` (the `DuelSim` interface,
`scripts/duel/match_sim.gd`), and only through `_restep()`, which refuses
outside that bracket. While it is set nothing is announced: not by the match,
and not by the fighters, which the match passes the flag on to (a disarm, a
clash, the figure's death flash). The flag never reaches the simulation -- it is
not in the snapshot or the checksum and no step decides anything on it -- and
`tests/unit/test_duel_replay_presentation.gd` steps 600 frames inside the
bracket and out of it and requires the two matches identical, byte for byte.

**The match keeps a ledger** (`scripts/duel/match_ledger.gd`): what the scene
has been told, against what the history now holds. Nothing in a step emits a
signal; what happened goes into the ledger, and after every fresh step, and once
at the end of every correction, the match tells the scene the difference. Two
events are the same event if they are of one kind, about one seat, and within
`SAME_BEAT` (30) frames of each other -- half a second, more than a correction
moves any exchange and less than any two real events of one kind about one
seat can be apart, since a fallen fighter is down for two seconds.

**The rule: the beat rings once, when the screen first shows the event; the
record follows the history.**

| The correction...                               | Beat (shake, sound, word) | Blood                         |
| ----------------------------------------------- | ------------------------- | ----------------------------- |
| changed nothing                                 | nothing                   | nothing                       |
| moved a kill a few frames, or a few pixels      | nothing                   | moved to the host's frame and place |
| found a kill the prediction did not have        | rung now, late, once      | spilled at the host's frame and place |
| took away a kill the prediction had             | already spent; the **DOWN** word is withdrawn if still up | wiped, once the history has run 30 frames past it without it |

Why each, against the alternatives:

- *A newly found kill rings late rather than not at all.* The fighter does not
  die late on screen: the correction drops them to a corpse *now*, at the end
  of the replay. A beat now is in step with what the player sees; a body that
  drops silently, with blood appearing under it, reads as a bug. The beat is
  late only against the host's clock, which nobody is watching.
- *A kill taken away loses its blood.* The floor is the match's record of who
  died where (`docs/duel-match.md`); blood for a death that did not happen is a
  record that lies, for the rest of the match, and the two phones would no
  longer show the same floor. The shake and the sound cannot be unrung -- they
  were brief, and they marked a moment the screen really did show -- but the
  word is still on the screen, saying something untrue, so it comes off.
- *It waits half a second before wiping.* A correction usually moves a kill
  rather than removing it: the host's input arrives a frame or two off the
  prediction and the cut lands a frame or two later. Wiping at once would then
  wipe, re-spill and ring a second beat for one death -- the echo this was all
  for. So a kill the history has not yet re-produced stays until the history
  has run `SAME_BEAT` frames past it; if it comes back in that time it is a move,
  silent, and if not it is gone.
- *A moved kill is redrawn, silently, on the host's frame.* The splatter is
  seeded from the death's frame and place; both peers agree on those once the
  host has spoken, so both draw the same stain.
- *The other beats follow the same rule* -- initiative, respawn, the gate, the
  catch, the end -- once each, late if found late. None of them leaves a record
  but the HUD word, and the rope, which reads the state and so is never wrong
  for longer than the state is.

**The state outranks a stale replay.** The ledger's history is only as good as
the frames the client could step again. When a run of the host's input is lost
the client loads the host's state without replaying the frames behind it, and
for those frames the ledger holds a guess -- in one lossy run the guess had the
kill two frames early, then a later replay lost it, and the client wiped the
blood of a kill that had happened. The state itself is not a guess: a fallen
fighter's respawn timer names the frame they fell on, exactly, on both peers.
So at every settle the match hands the ledger what the timers say about the
last two seconds, and the ledger makes its history agree: a death the timers
deny is struck out, and one they report that the history lacks is put in -- at
the place the player was shown if there was one, and where the body lies if
not. Whether and when a fighter died is therefore always the host's answer.
*Where* is the host's answer whenever the client could replay the frame, which
the twelve frames of input on each snapshot make nearly always; otherwise it is
the client's best picture, a few pixels off.

`tests/match_net_test.gd` holds two live sessions to this under the clean,
laggy and lossy links: no frame stepped twice outside the bracket; every death
the host had rung exactly once on the client; no death rung twice; every client
beat accounted for as a host death, a kill since taken back, or one the host has
not yet ruled on; and the client's floor, once settled, holding blood for
exactly the host's deaths at the host's frame and place.
`tests/unit/test_duel_replay_presentation.gd` stages each row of the table, and
the stale-replay case, by hand.

This replaced a guard in `match_scene.gd`, `CATCH_ECHO`, that dropped a second
catch by the same seat inside thirty frames. It was the right instinct in the
wrong place: it guarded one signal of seven, it measured the echo against
whatever frame the replay happened to be on, and it could not tell a moved catch
from a new one. The ledger is the same idea -- one event within half a second is
one event -- applied to all of them, against the history.

## Testing

The netplay tests are standalone headless scripts rather than GUT tests,
because the match has to be stepped from inside a physics frame
(`tests/duel_support.gd` says why). The CI test runner runs them all; one at a
time:

```bash
godot --headless --path . --script tests/duel_input_bits_test.gd   # the 8-bit wire frame
godot --headless --path . --script tests/duel_determinism_test.gd  # the step is a function
godot --headless --path . --script tests/match_fighter_test.gd     # the match on the fighter
godot --headless --path . --script tests/net_protocol_test.gd      # encode, decode, refuse
godot --headless --path . --script tests/net_desync_test.gd        # predict, reconcile, detect
godot --headless --path . --script tests/match_net_test.gd         # two live sessions
bash  tests/net_live.sh                                  # two real processes
```

Each exits non-zero on failure. Add `--fixed-fps 600` to any of the `.gd` ones
to run them flat out instead of at wall-clock speed — several of them step
hundreds of physics frames.

`tests/net_live.sh` is the one that cannot be a script inside one engine: it
starts the relay and two independent headless Godot processes and makes them
duel through real sockets, direct and relayed, then judges what they wrote. It
is the only check that the transport, the relay, the room codes and the
handshake work as a system rather than individually. Each peer sends a
different look and must report the other's arriving intact, and a third round
seats a guest that sends no look at all.

The looks' own tests are GUT tests, because nothing in them steps a match:
`tests/unit/test_net_look_wire.gd` and `tests/unit/test_net_look_session.gd`.
So is `tests/unit/test_duel_replay_presentation.gd`, which steps one on the
placeholder fighter, which is not a physics body.

---

## Not handled yet

Honestly, and in roughly the order I would fix them.

- **No public relay.** You have to run your own, and the default address in the
  lobby is `127.0.0.1`. There is no relay discovery, no TLS termination built in,
  and no authentication: anyone who can reach the port can open a room.
- **No rollback.** The client replays from the host's last snapshot, which is
  correct but means a correction can visibly snap the opponent. The simulation
  is already a pure function of its inputs, so rollback is a change to
  `session.gd` alone — but it is not written.
- **No ENet transport.** The interface is there and `ws_transport.gd` is the
  only thing behind it. Native builds pay TCP's head-of-line blocking for no
  reason.
- **Match state is not separately authoritative.** Initiative, kills and the
  window ride along inside the snapshot, which is correct but means a client
  that has not heard from the host in a while may show a stale rope for a few
  frames.
- **No reconnect.** A dropped connection ends the match; there is no grace
  period and no resume.
- **No spectators, no more than two players.** The transport interface is
  explicitly two-seat.
- **No lag compensation on the sword.** Hits are resolved on the host's clock,
  so a high-latency client's attacks land where the host saw them, not where the
  client did. At LAN and normal broadband latencies this is not noticeable; at
  200 ms it is.
- **No input delay option.** Some players prefer a couple of frames of local
  delay over any correction at all. There is no setting for it.
- **Local two-player is keyboard only.** A Godot action cannot tell one gamepad
  from another without per-device events, so a pad bound to both seats would
  drive both duellists. Two players on two pads needs per-device bindings in
  `tools/configure_project.gd`.
- **The desync detector cannot localise.** It says *that* frame N diverged, not
  which field. A per-field checksum would make a real platform difference much
  faster to chase; finding the `move_and_slide()` problem above took a long
  session of bisecting by hand that a localising checksum would have shortened.
- **`Fighter._move()` does no floor snapping.** `move_and_slide()` glues a body
  to the ground over small steps and seams; the duel's loop relies on gravity
  pulling it down each frame instead. On the strip's flat, axis-aligned tiles
  the two agree, and the tests say so, but a sloped or stepped zone would want
  snapping put back — deterministically, inside `_move()`.
- **The prediction kills the other player more often than the host does.**
  The client guesses the host's input by repeating the last byte, and a fighter
  running at a pit keeps running in the guess after the real player has
  jumped. On the laggy link in `tests/match_net_test.gd` (100 ms each way) the
  client showed the host's fighter falling seven times in twenty seconds that
  the host never had. *Corrected outcomes* above makes each one honest -- one
  beat, the blood wiped half a second later -- but the body on screen is the
  prediction, and it falls. That is a prediction problem, not a presentation
  one: rollback, an input delay option, or a guess that does not walk into
  hazards would each reduce it.
- **No bandwidth adaptation.** The snapshot rate is a constant.
- **The clock sync is crude.** One-way latency is taken as half the round trip,
  which is wrong on an asymmetric connection.
- **A burst and a paced run are not bit-identical on the real fighter.** Two
  paced runs agree exactly, and so do two bursts, but a burst and a paced run
  of the same inputs part in the last bits of a standing fighter's y — about
  1e-4 px, two hundred frames in, under 4e-4 px across the run in
  `tests/duel_determinism_test.gd`, which prints the numbers every time. Which
  bits move depends on what the physics space held before, so it reads as the
  engine's collision recovery visiting the ground's tile shapes in a different
  order. The round duel this was first tested on was bit-exact. The checksum's
  1/256 quantum absorbs it unless a value sits on a rounding boundary, where a
  reconciling client would report a false desync; none has been seen in
  `tests/net_live.sh`. Fixing it is a change to the fighter's movement or to
  the ground's collision, both of which are the owner's open decisions.
