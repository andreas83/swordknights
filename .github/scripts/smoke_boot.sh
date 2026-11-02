#!/usr/bin/env bash
#
# Boot the project headlessly for a few frames and fail on any engine or script
# error.
#
# Why this exists on top of the parse check: a file can parse perfectly and
# still blow up the moment the scene tree touches it (a bad node path, a typed
# assignment that only fails at runtime, a missing resource). Godot reports
# those on stderr but still exits 0, so the exit code alone proves nothing --
# we have to read the output.
#
# Warnings are allowed through on purpose. boot.gd deliberately push_warning()s
# while scenes/menu.tscn does not exist yet, and that is the designed
# behaviour, not a failure.
#
# Usage:
#   .github/scripts/smoke_boot.sh [frames]
#
# Expects to be run from the repository root.

set -uo pipefail

FRAMES="${1:-60}"
GODOT="${GODOT_BIN:-godot}"

if ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "error: godot binary '$GODOT' not found on PATH" >&2
	exit 127
fi

echo "Booting the project headlessly for ${FRAMES} frames..."
echo

# --quit-after <n> runs n iterations of the main loop and then exits, which is
# enough for the main scene to enter the tree and run _ready().
output="$("$GODOT" --headless --path . --quit-after "$FRAMES" 2>&1)"
status=$?

# Strip the progress/banner noise so the log is readable.
printf '%s\n' "$output" | grep -vE '^\[|DONE|^\s*$' || true
echo

if [[ $status -ne 0 ]]; then
	echo "FAILED: godot exited with status ${status}." >&2
	exit "$status"
fi

# The engine prints these and carries on, so the exit code misses them.
#   "SCRIPT ERROR"  - a GDScript runtime error or failed script load
#   "Parse Error"   - a script that failed to compile
#   "ERROR:"        - an engine-level error
if printf '%s\n' "$output" | grep -qE 'SCRIPT ERROR|Parse Error|^ERROR:'; then
	echo "FAILED: the project booted but reported errors:" >&2
	printf '%s\n' "$output" |
		grep -E -A3 'SCRIPT ERROR|Parse Error|^ERROR:' |
		sed 's/^/  /' >&2
	exit 1
fi

echo "Boot smoke test passed: no engine or script errors."
