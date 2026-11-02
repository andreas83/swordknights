#!/usr/bin/env bash
#
# Compile every GDScript in the project and fail on any that does not.
#
# Why this exists: `godot --headless --import` does NOT fail on a GDScript
# parse error. It exits 0 and happily writes the import cache. Verified on
# 4.5.1 -- a file containing deliberate garbage imported "successfully".
#
# Why it is no longer a per-file `--check-only --script` loop: that mode
# compiles a script in ISOLATION, with none of the project's autoload
# singletons registered. Any script that calls an autoload by name -- the
# documented way to use one -- was reported as "Identifier not found" even
# though it compiles and runs correctly. tools/check_scripts.gd does the same
# job inside a live SceneTree, so every file is validated in the context the
# game really loads it in, and in one process rather than one per file.
#
# Two traps that cost real time, recorded so nobody re-treads them:
#   - load() is not a validity test. A script with a parse error still comes
#     back as a (broken) GDScript object, so a null check is a no-op gate.
#     can_instantiate() is the signal that actually flips.
#   - ResourceLoader.load(..., CACHE_MODE_IGNORE) segfaults 4.5.1 when it
#     re-compiles an already-registered class_name script.
#
# Both are canary-tested: drop a file with a syntax error anywhere under
# scripts/ and this must go red.
#
# Usage:
#   .github/scripts/check_scripts.sh [godot-binary]

set -uo pipefail

GODOT="${1:-${GODOT_BIN:-godot}}"

if ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "error: godot binary '$GODOT' not found on PATH" >&2
	exit 127
fi

exec "$GODOT" --headless --path . --script tools/check_scripts.gd
