#!/usr/bin/env bash
# A real networked duel between two operating-system processes, over localhost.
#
#     bash tests/net_live.sh
#
# Everything else under tests/ runs inside one engine. This does not: it starts
# the rendezvous relay and two independent headless Godot processes and makes
# them duel through real sockets. It is the only check that the transport, the
# relay, the room codes and the handshake actually work, as opposed to being
# individually correct.
#
# Two rounds of it:
#   1. DIRECT    one peer listens on a port, the other dials it
#   2. RELAY     both peers dial the relay; one opens a room, the other joins
#                by the four-letter code the first one printed
#
# Exits non-zero if either peer failed to connect, if the guest saw no
# authoritative verifications, or if anything desynced.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-/usr/local/bin/godot}"
WORK="$(mktemp -d)"
RELAY_PORT="${RELAY_PORT:-45678}"
DIRECT_PORT="${DIRECT_PORT:-45679}"
FRAMES="${FRAMES:-300}"
fail=0

cleanup() {
  [ -n "${RELAY_PID:-}" ] && kill "$RELAY_PID" 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT

peer() {  # peer <report-name> <args...>
  local name="$1"; shift
  "$GODOT" --headless --path "$ROOT" --script tests/net_live.gd -- \
    --frames "$FRAMES" --report "$WORK/$name.txt" "$@" \
    > "$WORK/$name.log" 2>&1
}

field() {  # field <report> <key>
  sed -n "s/^$2=//p" "$WORK/$1.txt" 2>/dev/null | head -1
}

expect() {  # expect <report> <key> <test> <value> <description>
  local actual; actual="$(field "$1" "$2")"
  if [ -z "$actual" ]; then
    echo "  FAIL  $5 — $1 wrote no '$2' (did it start?)"
    fail=1
    return
  fi
  if [ "$actual" -"$3" "$4" ] 2>/dev/null; then
    echo "  ok    $5 ($2=$actual)"
  else
    echo "  FAIL  $5 — $2=$actual, wanted $3 $4"
    fail=1
  fi
}

judge() {  # judge <host-report> <guest-report>
  # "ran" counts frames spent actually duelling. Whichever peer reaches its
  # budget first exits, so the other is no longer running by the time it writes
  # its report; what matters is how far each one got.
  expect "$1" ran gt 100 "host duelled"
  expect "$2" ran gt 100 "guest duelled"

  expect "$1" snapshots_sent gt 0 "host broadcast state"
  expect "$2" snapshots_received gt 0 "guest received state"
  expect "$2" verifications gt 20 "guest reproduced the host's frames"
  expect "$2" desyncs eq 0 "guest saw no divergence"
  expect "$1" desyncs eq 0 "host saw no divergence"
  expect "$1" frames gt 100 "the duel actually advanced"
  echo "       host:  $(field "$1" transport) | corrections=$(field "$1" corrections) rtt=$(field "$1" rtt_ms)ms starved=$(field "$1" starved)"
  echo "       guest: $(field "$2" transport) | corrections=$(field "$2" corrections) rtt=$(field "$2" rtt_ms)ms"
}

echo "=== 1. direct connection on 127.0.0.1:$DIRECT_PORT ==="
peer direct_host --mode direct-host --port "$DIRECT_PORT" &
HOST_PID=$!
sleep 3
peer direct_guest --mode direct-guest --url "ws://127.0.0.1:$DIRECT_PORT" &
GUEST_PID=$!
wait "$HOST_PID" "$GUEST_PID"
judge direct_host direct_guest

echo
echo "=== 2. relayed by room code via 127.0.0.1:$RELAY_PORT ==="
"$GODOT" --headless --path "$ROOT" res://scenes/rendezvous.tscn -- \
  --port "$RELAY_PORT" > "$WORK/relay.log" 2>&1 &
RELAY_PID=$!
sleep 4
if ! grep -q "rendezvous listening" "$WORK/relay.log"; then
  echo "  FAIL  the relay did not start"
  sed -n '1,20p' "$WORK/relay.log"
  exit 1
fi
echo "  ok    relay listening"

peer room_host --mode room-host --url "ws://127.0.0.1:$RELAY_PORT" \
  --code-out "$WORK/code.txt" &
HOST_PID=$!

CODE=""
for _ in $(seq 1 40); do
  sleep 0.5
  if [ -s "$WORK/code.txt" ]; then CODE="$(head -1 "$WORK/code.txt" | tr -d '\r\n')"; break; fi
done
if [ -z "$CODE" ]; then
  echo "  FAIL  the host never got a room code"
  sed -n '1,20p' "$WORK/room_host.log"
  kill "$HOST_PID" 2>/dev/null
  exit 1
fi
echo "  ok    room code is $CODE"

peer room_guest --mode room-guest --url "ws://127.0.0.1:$RELAY_PORT" --code "$CODE" &
GUEST_PID=$!
wait "$HOST_PID" "$GUEST_PID"
judge room_host room_guest

echo
echo "  relay said:"
sed -n 's/^/       /p' "$WORK/relay.log" | grep -E "room|peer" | head -8

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS  net_live  (two processes, direct and relayed)"
else
  echo "FAIL  net_live"
  for n in direct_host direct_guest room_host room_guest; do
    [ -f "$WORK/$n.log" ] && { echo "--- $n ---"; tail -15 "$WORK/$n.log"; }
  done
fi
exit "$fail"
