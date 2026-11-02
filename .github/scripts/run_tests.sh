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

echo "Test suite passed: ${total} test(s)."
