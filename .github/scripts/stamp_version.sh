#!/usr/bin/env bash
#
# Write a build's version into export_presets.cfg and scripts/core/build_stamp.gd,
# in the runner only.
#
# Both files carry placeholders because a committed file cannot know the run it
# will be built in. Rather than ask a human to bump them, the workflows stamp
# them here. The edit is never committed.
#
# Usage:
#   .github/scripts/stamp_version.sh v1.2.3 [PRESETS]
#   .github/scripts/stamp_version.sh --dev CODE SHA FEED [PRESETS]
#
# BUILD_STAMP in the environment names the GDScript stamp to write; the default
# is scripts/core/build_stamp.gd. Under GitHub Actions, `name` and `code` are
# also written to $GITHUB_OUTPUT.
#
# Android wants two values: version/name, a human string, and version/code, a
# monotonically increasing integer. Android only installs a build over another
# when its code is higher, so where the code comes from is the whole design:
#
#   A release tag (release.yml). The code is derived from the three version
#   components so that it always rises with the tag:
#
#     v1.2.3  ->  version/name "1.2.3", version/code 10203, channel "release"
#
#   which leaves room for 99 minor and 99 patch releases per major.
#
#   A development build (android.yml). CODE is the workflow's run number, which
#   GitHub increases by one on every run of that workflow and never reuses; the
#   name is the committed base version with the channel and the commit:
#
#     --dev 57 4f2c9e1...  ->  version/name "0.1.0-dev+4f2c9e1", version/code 57,
#                              channel "dev", the feed URL the app checks
#
# The two ranges do not need to interleave: a dev build and a release are
# signed with different keys, so Android will not install one over the other
# whatever their codes say.
#
# build_stamp.gd gets the same code and name, because the engine cannot read
# the running package's version code back on Android and the update check has
# to compare against something. Stamping both from one call is what keeps the
# manifest's idea of the build and the app's idea of it from drifting apart.

set -euo pipefail

usage() {
	echo "usage: stamp_version.sh vMAJOR.MINOR.PATCH [PRESETS]" >&2
	echo "       stamp_version.sh --dev CODE SHA FEED [PRESETS]" >&2
	exit 2
}

[[ $# -ge 1 ]] || usage

if [[ "$1" == "--dev" ]]; then
	[[ $# -ge 4 ]] || usage
	mode="dev"
	code="$2"
	sha="$3"
	feed="$4"
	PRESETS="${5:-export_presets.cfg}"
else
	mode="release"
	TAG="$1"
	PRESETS="${2:-export_presets.cfg}"
fi
STAMP="${BUILD_STAMP:-scripts/core/build_stamp.gd}"

for f in "$PRESETS" "$STAMP"; do
	if [[ ! -f "$f" ]]; then
		echo "error: ${f} not found -- run this from the repository root" >&2
		exit 1
	fi
done

if [[ "$mode" == "release" ]]; then
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
	name="${version}"
	sha="${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || true)}"
	channel="release"
	# A release never calls home; an empty feed is the second lock on that door.
	feed=""
else
	if [[ ! "$code" =~ ^[1-9][0-9]{0,9}$ ]] || ((code > 2100000000)); then
		echo "error: build code '${code}' is not a whole number from 1 to 2100000000" >&2
		exit 1
	fi
	if [[ ! "$sha" =~ ^[0-9a-f]{7,40}$ ]]; then
		echo "error: '${sha}' is not a commit hash" >&2
		exit 1
	fi
	# Quotes, backslashes, spaces and the sed delimiter would all break the line
	# this lands in; a URL that needs any of them is not the release feed.
	if [[ ! "$feed" =~ ^https?://[^[:space:]\"\\|]+$ ]]; then
		echo "error: feed '${feed}' is not a plain http(s) URL" >&2
		exit 1
	fi

	# The committed version, without whatever an earlier stamp appended to it.
	base="$(sed -n 's|^version/name="\(.*\)"$|\1|p' "$PRESETS" | head -1)"
	base="${base%%[-+]*}"
	if [[ ! "$base" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		echo "error: no MAJOR.MINOR.PATCH version/name in ${PRESETS} to build on" >&2
		exit 1
	fi
	name="${base}-dev+${sha:0:7}"
	channel="dev"
fi

if [[ -n "$sha" && ! "$sha" =~ ^[0-9a-f]{7,40}$ ]]; then
	echo "error: '${sha}' is not a commit hash" >&2
	exit 1
fi

# Only the keys that exist in the file are touched, and each is anchored to the
# start of the line so a commented-out example cannot be rewritten.
sed -i \
	-e "s|^version/name=.*|version/name=\"${name}\"|" \
	-e "s|^version/code=.*|version/code=${code}|" \
	-e "s|^application/short_version=.*|application/short_version=\"${name}\"|" \
	-e "s|^application/version=.*|application/version=\"${code}\"|" \
	"$PRESETS"

sed -i \
	-e "s|^const CODE := .*|const CODE := ${code}|" \
	-e "s|^const NAME := .*|const NAME := \"${name}\"|" \
	-e "s|^const SHA := .*|const SHA := \"${sha}\"|" \
	-e "s|^const CHANNEL := .*|const CHANNEL := \"${channel}\"|" \
	-e "s|^const FEED := .*|const FEED := \"${feed}\"|" \
	"$STAMP"

# sed reports success whether or not a line matched. A stamp that silently
# missed would ship a build that believes it is build 1 -- and a dev build that
# believes that offers every update forever -- so read the result back.
expect() {
	if ! grep -qxF "$2" "$1"; then
		echo "error: ${1} does not contain the line: $2" >&2
		exit 1
	fi
}
expect "$PRESETS" "version/code=${code}"
expect "$PRESETS" "version/name=\"${name}\""
expect "$STAMP" "const CODE := ${code}"
expect "$STAMP" "const NAME := \"${name}\""
expect "$STAMP" "const SHA := \"${sha}\""
expect "$STAMP" "const CHANNEL := \"${channel}\""
expect "$STAMP" "const FEED := \"${feed}\""

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
	{
		echo "name=${name}"
		echo "code=${code}"
	} >>"$GITHUB_OUTPUT"
fi

echo "Stamped a ${channel} build, ${name} (code ${code}):"
grep -nE '^(version/(name|code)|application/(short_)?version)=' "$PRESETS" | sed 's/^/  /'
grep -nE '^const ' "$STAMP" | sed "s|^|  ${STAMP}:|"
