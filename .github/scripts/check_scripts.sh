#!/usr/bin/env bash
#
# Parse-check every GDScript file we own.
#
# Why this exists: `godot --headless --import` does NOT fail on a GDScript
# parse error. It exits 0 and happily writes the import cache. Verified on
# 4.5.1 -- a file containing deliberate garbage imported "successfully".
#
# The only parse check the engine gives us is `--check-only`, and the help text
# is explicit that it is "use with --script", i.e. one file per invocation.
# So we drive it in a loop and aggregate.
#
# Usage:
#   .github/scripts/check_scripts.sh [godot-binary]
#
# Expects to be run from the repository root. Exits non-zero if any file fails
# to parse, after reporting every failure rather than stopping at the first.

set -uo pipefail

GODOT="${1:-${GODOT_BIN:-godot}}"

if ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "error: godot binary '$GODOT' not found on PATH" >&2
	exit 127
fi

# Directories that are not ours to validate:
#   legacy/  reference prototypes (also .gdignore'd, the engine never sees them)
#   addons/  vendored third-party code, shipped as released
#   .godot/  generated import cache
#   build/   generated export output
#   .claude/ agent worktrees -- each is a full copy of this project, so
#            scanning them checks every file several times over and reports
#            stale copies of findings that have already been fixed here
mapfile -t scripts < <(
	find . \
		-type d \( \
		-name .git -o \
		-name .godot -o \
		-name .claude -o \
		-name addons -o \
		-name build -o \
		-name legacy \
		\) -prune -o \
		-type f -name '*.gd' -print |
		sed 's|^\./||' |
		sort
)

if [[ ${#scripts[@]} -eq 0 ]]; then
	echo "error: no GDScript files found -- is this the repository root?" >&2
	exit 1
fi

echo "Parse-checking ${#scripts[@]} GDScript file(s) with $("$GODOT" --version)"
echo

failed=()

for script in "${scripts[@]}"; do
	# --check-only reports parse errors on stderr/stdout and exits non-zero.
	if output=$("$GODOT" --headless --path . --check-only --script "res://${script}" 2>&1); then
		printf '  ok    %s\n' "$script"
	else
		printf '  FAIL  %s\n' "$script"
		# Reproduce the engine's diagnostics, indented, dropping the banner.
		printf '%s\n' "$output" |
			grep -vE '^(Godot Engine v|Free and open source|\s*$)' |
			sed 's/^/          /'
		failed+=("$script")
	fi
done

echo
if [[ ${#failed[@]} -gt 0 ]]; then
	echo "FAILED: ${#failed[@]} of ${#scripts[@]} script(s) did not parse:" >&2
	for script in "${failed[@]}"; do
		echo "  - $script" >&2
	done
	exit 1
fi

echo "All ${#scripts[@]} script(s) parsed cleanly."
