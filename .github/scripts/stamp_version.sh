#!/usr/bin/env bash
#
# Write a release tag into export_presets.cfg, in the runner only.
#
# export_presets.cfg carries a placeholder version (0.1.0) because a committed
# file cannot know the tag it will be built under. Rather than ask a human to
# bump it before every tag, the release workflow stamps it here. The edit is
# never committed.
#
# Usage:
#   .github/scripts/stamp_version.sh v1.2.3
#
# Android wants two values: version/name, a human string, and version/code, a
# monotonically increasing integer. The code is derived from the three version
# components so that it always rises with the tag:
#
#   v1.2.3  ->  version/name "1.2.3", version/code 10203
#
# which leaves room for 99 minor and 99 patch releases per major.

set -euo pipefail

TAG="${1:?usage: stamp_version.sh <tag>}"
PRESETS="${2:-export_presets.cfg}"

if [[ ! -f "$PRESETS" ]]; then
	echo "error: ${PRESETS} not found -- run this from the repository root" >&2
	exit 1
fi

# Accept "v1.2.3" and "1.2.3"; reject anything else loudly rather than
# stamping a nonsense version into a store build.
version="${TAG#v}"
if [[ ! "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
	echo "error: tag '${TAG}' is not vMAJOR.MINOR.PATCH" >&2
	exit 1
fi

major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
patch="${BASH_REMATCH[3]}"

if ((minor > 99 || patch > 99)); then
	echo "error: minor/patch above 99 would break version/code ordering" >&2
	exit 1
fi

code=$((major * 10000 + minor * 100 + patch))

# Only the keys that exist in the file are touched, and each is anchored to the
# start of the line so a commented-out example cannot be rewritten.
sed -i \
	-e "s|^version/name=.*|version/name=\"${version}\"|" \
	-e "s|^version/code=.*|version/code=${code}|" \
	-e "s|^application/short_version=.*|application/short_version=\"${version}\"|" \
	-e "s|^application/version=.*|application/version=\"${code}\"|" \
	"$PRESETS"

echo "Stamped ${PRESETS} from tag ${TAG}:"
grep -nE '^(version/(name|code)|application/(short_)?version)=' "$PRESETS" | sed 's/^/  /'
