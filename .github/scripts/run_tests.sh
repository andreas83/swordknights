#!/usr/bin/env bash
#
# Run the GUT test suite headlessly and prove it actually ran.
#
# The second part matters. GUT's CLI entry point calls
# error_if_not_all_classes_imported() and, if the project's global class cache
# has not been built, prints a message and quit(0)s. A CI job that only checks
# the exit code would go green having executed zero tests. So we also require
# the JUnit report to exist and to contain at least one test.
#
# Usage:
#   .github/scripts/run_tests.sh [junit-xml-path]
#
# Expects to be run from the repository root, after the project has been
# imported at least once (`godot --headless --path . --import`).

set -uo pipefail

JUNIT="${1:-build/test-results/gut.xml}"
GODOT="${GODOT_BIN:-godot}"

if ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "error: godot binary '$GODOT' not found on PATH" >&2
	exit 127
fi

mkdir -p "$(dirname "$JUNIT")"
rm -f "$JUNIT"

# Test selection (directories, prefix, suffix) lives in .gutconfig.json so that
# this script, the editor panel and a bare `godot -s .../gut_cmdln.gd` all agree.
"$GODOT" --headless --path . \
	-s addons/gut/gut_cmdln.gd \
	-gjunit_xml_file="$JUNIT"
status=$?

echo
if [[ ! -f "$JUNIT" ]]; then
	echo "FAILED: GUT produced no JUnit report at ${JUNIT}." >&2
	echo "        The runner bailed out before running anything -- most likely" >&2
	echo "        the project was not imported, so GutTest was not registered." >&2
	exit 1
fi

# Pull the totals straight out of the report rather than trusting the console.
read -r total failures < <(
	python3 -I - "$JUNIT" <<'PY'
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
suites = [root] if root.tag == "testsuites" else []
total = sum(int(s.get("tests", 0)) for s in suites)
failures = sum(int(s.get("failures", 0)) for s in suites)
if not suites:
    total = sum(int(s.get("tests", 0)) for s in root.iter("testsuite"))
    failures = sum(int(s.get("failures", 0)) for s in root.iter("testsuite"))
print(total, failures)
PY
)

echo "Reported by ${JUNIT}: ${total} test(s), ${failures} failure(s)."

if [[ "$total" -eq 0 ]]; then
	echo "FAILED: the suite reported zero tests. Refusing to call that a pass." >&2
	exit 1
fi

if [[ "$failures" -ne 0 ]]; then
	echo "FAILED: ${failures} test(s) failed." >&2
	exit 1
fi

if [[ $status -ne 0 ]]; then
	echo "FAILED: gut exited with status ${status}." >&2
	exit "$status"
fi

echo "GUT suite passed: ${total} test(s)."

# ---------------------------------------------------------------------------
# Phase 2: standalone SceneTree tests.
#
# GUT is the convention for new tests (see docs/ci.md). But the repository also
# contains hand-rolled tests written before the harness existed: a script that
# `extends SceneTree`, asserts for itself and quit()s with a status. GUT does
# not and cannot collect those -- they do not extend GutTest and they do not
# match its test_* prefix -- so without this phase they would be silently
# skipped, which is the worst of both worlds: the coverage is gone and the
# build is green.
#
# Convention: tests/**/*_test.gd (suffix) is standalone; tests/**/test_*.gd
# (prefix) is GUT. These are being migrated to GUT; this phase is the bridge.
# ---------------------------------------------------------------------------

mapfile -t standalone < <(
	find tests -type f -name '*_test.gd' 2>/dev/null |
		# A GUT file would be named test_*.gd; never run one of those this way.
		grep -vE '(^|/)test_[^/]*\.gd$' |
		sort
)

if [[ ${#standalone[@]} -eq 0 ]]; then
	echo "No standalone SceneTree tests found."
	echo "All tests passed."
	exit 0
fi

echo
echo "Running ${#standalone[@]} standalone SceneTree test(s)..."
standalone_failed=()

for script in "${standalone[@]}"; do
	echo
	echo "  --- ${script}"
	if "$GODOT" --headless --path . --script "res://${script}" 2>&1 |
		grep -vE '^\[|DONE|^Godot Engine v|^Free and open source|^\s*$' |
		sed 's/^/      /'; then
		: # pipeline status is grep's; the real status comes from PIPESTATUS
	fi
	if [[ "${PIPESTATUS[0]}" -ne 0 ]]; then
		echo "      FAILED"
		standalone_failed+=("$script")
	else
		echo "      ok"
	fi
done

echo
if [[ ${#standalone_failed[@]} -gt 0 ]]; then
	echo "FAILED: ${#standalone_failed[@]} standalone test(s) failed:" >&2
	for script in "${standalone_failed[@]}"; do
		echo "  - $script" >&2
	done
	exit 1
fi

echo "All tests passed: ${total} GUT test(s), ${#standalone[@]} standalone script(s)."
