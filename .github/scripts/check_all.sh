#!/usr/bin/env bash
#
# Run everything CI runs, in CI's order, locally.
#
# Usage:
#   .github/scripts/check_all.sh
#
# Expects to be run from the repository root, with `godot` on PATH (or
# GODOT_BIN set) and gdtoolkit installed:
#   pip install -r .github/requirements-ci.txt
#
# Each stage reports pass or fail and the script keeps going, so one run tells
# you everything that is wrong rather than only the first thing.

set -uo pipefail

GODOT="${GODOT_BIN:-godot}"
failed=()

step() {
	local name="$1"
	shift
	printf '\n\033[1m==> %s\033[0m\n' "$name"
	if "$@"; then
		printf '\033[32m    PASS\033[0m  %s\n' "$name"
	else
		printf '\033[31m    FAIL\033[0m  %s\n' "$name"
		failed+=("$name")
	fi
}

if ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "error: godot binary '$GODOT' not found on PATH (or set GODOT_BIN)" >&2
	exit 127
fi

if ! command -v gdlint >/dev/null 2>&1; then
	echo "error: gdlint not found. pip install -r .github/requirements-ci.txt" >&2
	exit 127
fi

echo "godot:  $("$GODOT" --version)"
echo "gdlint: $(gdlint --version)"

# Import first: it builds .godot/, including the global class registry that
# makes GutTest resolvable in the test scripts.
step "import"        "$GODOT" --headless --path . --import
step "gdlint"        gdlint .
step "parse-check"   ./.github/scripts/check_scripts.sh
step "boot smoke"    ./.github/scripts/smoke_boot.sh 60
step "tests"         ./.github/scripts/run_tests.sh

# Advisory, exactly as in CI: reported, never fatal. See docs/ci.md for why
# gdformat is not yet a gate, and for the two steps to make it one.
printf '\n\033[1m==> gdformat (advisory)\033[0m\n'
if gdformat --check scripts tools tests; then
	printf '\033[32m    clean\033[0m\n'
else
	printf '\033[33m    would reformat -- advisory only, not a failure\033[0m\n'
fi

printf '\n'
if [[ ${#failed[@]} -gt 0 ]]; then
	printf '\033[31m%d stage(s) failed:\033[0m\n' "${#failed[@]}" >&2
	for name in "${failed[@]}"; do
		echo "  - $name" >&2
	done
	exit 1
fi

printf '\033[32mAll checks passed.\033[0m\n'
