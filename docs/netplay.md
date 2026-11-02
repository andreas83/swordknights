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
| Duel on a LAN                     | Menu → **Duel Online** → *Host directly*; the other player picks *Join directly* and types your address. |
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
`tests/duel_determinism.gd` pins down — but it is **not** guaranteed identical
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

That replay is exact, which is the whole trick: `Duel.step(bits_a, bits_b)` is a
pure function of the duel's state and two bytes. `tests/duel_determinism.gd`
asserts that running a stream of frames as a burst inside one physics frame
gives byte-identical checksums to pacing it out one frame per physics frame. If
that were not true, the client would drift away from the host on every
correction.

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

The checksum itself is FNV-1a over the quantised state — 1/256 of a pixel and of
a second, which is far finer than anything visible and still absorbs last-bit
float noise.

---

## The pieces

```
scripts/duel/
  duel.gd            the simulation: two duellists, an arena, rounds, and
                     step(bits_a, bits_b) — the one function that matters
  duel_rules.gd      rounds, countdown, time limit
  duel_camera.gd     frames both duellists, zooms to fit
  duel_art.gd        seat colours and the guard / stagger tells
  duel_hud.gd        score, countdown, results, network status
  duel_touch.gd      the GUARD button the shared touch controls lack
  duel_local.gd      two seats, one keyboard
  duel_online.gd     lobby, connection, and the same duel with a session
scripts/net/
  protocol.gd        versioned messages, encode and decode
  transport.gd       the interface
  ws_transport.gd    WebSocket: direct host, direct join, relayed by code
  loopback_transport.gd  a pair in one process, with lag, jitter and loss
  session.gd         handshake, prediction, reconciliation, desync detection
  rendezvous.gd      the relay
  lobby.gd           the lobby screen
levels/arena_01.txt  the arena (and its design notes)
```

`scripts/player/player.gd` and `scripts/player/player_input.gd` carry small
additive changes, each marked `--- duel (additive) ---`.

---

## Message flow

Every message is `[u8 version][u8 type][payload]`, little-endian. The version is
checked on arrival: two mismatched builds say so in the lobby instead of
desyncing in the third round.

```
guest                         host
  |  HELLO (build, name)       |      repeated every 30 frames until answered
  |--------------------------->|
  |      WELCOME (seat, rounds, arena hash)
  |<---------------------------|      a mismatched arena is refused here
  |                            |
  |  INPUT (first_frame, bits[6])     every frame, a redundant window
  |--------------------------->|
  |      SNAPSHOT (frame, checksum, applied input, state)
  |<---------------------------|      every 2 frames, ~230 bytes
  |                            |
  |  PING / PONG               |      every 20 frames, both ways
  |<-------------------------->|
  |  DESYNC (frame, mine, theirs)     whoever notices tells the other
  |<-------------------------->|
```

Bandwidth: roughly **7 kB/s** from host to client and **0.7 kB/s** back. The
snapshot is large because it is *exact* — every private timer the character
state machine reads is in there, including the input's press-edge memory, so a
replayed frame cannot re-fire a jump that was already held.

The client runs ahead of the newest snapshot by the measured one-way latency
plus two frames of slack, so its input reaches the host before the host needs
it. Drift is corrected by stepping twice in a frame, or not at all — never by
jumping, which would be visible.

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
repeats until answered. `tests/net_desync.gd` runs a scenario with a quarter of
all snapshots discarded; the duel still tracks the host and reports no desync.

**Lag and jitter.** Measured continuously by ping/pong. The client's lead
adjusts to it. `tests/net_desync.gd` runs 100 ms each way with 50 ms of jitter —
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

## Testing

Every test is a standalone headless script. There is no framework yet.

```bash
godot --headless --script tests/duel_input_bits.gd     # the 8-bit wire frame
godot --headless --script tests/duel_determinism.gd    # the step is a function
godot --headless --script tests/duel_combat.gd         # the duelling rules
godot --headless --script tests/duel_arena.gd          # the arena's claims
godot --headless --script tests/net_protocol.gd        # encode, decode, refuse
godot --headless --script tests/net_desync.gd          # predict, reconcile, detect
bash  tests/net_live.sh                                # two real processes
```

Each exits non-zero on failure. Add `--fixed-fps 600` to any of the `.gd` ones
to run them flat out instead of at wall-clock speed — several of them step
hundreds of physics frames.

`tests/net_live.sh` is the one that cannot be a script inside one engine: it
starts the relay and two independent headless Godot processes and makes them
duel through real sockets, direct and relayed, then judges what they wrote. It
is the only check that the transport, the relay, the room codes and the
handshake work as a system rather than individually.

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
- **Round and match state are not separately authoritative.** They ride along
  inside the snapshot, which is correct but means a client that has not heard
  from the host in a while may show a stale score for a few frames.
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
  faster to chase.
- **No bandwidth adaptation.** The snapshot rate is a constant.
- **The clock sync is crude.** One-way latency is taken as half the round trip,
  which is wrong on an asymmetric connection.
