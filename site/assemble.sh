#!/usr/bin/env bash
#
# Assemble the public site: the page from site/public/ and the web export under
# play/.
#
# Usage, from the repository root:
#   site/assemble.sh --web build/web --out build/site
#
# Environment (all optional):
#   SITE_URL    absolute URL the site is served from, with a trailing slash. Only
#               link previews need it (Open Graph wants absolute URLs); when it is
#               unset those two tags are dropped, which is right for a local
#               preview.
#   COMMIT      full commit hash the web build came from. Default: git HEAD.
#   BUILD_DATE  date shown on the page. Default: today, UTC.
#   REPOSITORY  OWNER/REPO whose `dev` pre-release the Android button links to.
#               Default: andreas83/swordknights.
#
# The APK is not part of the site. The download button points at the stable
# asset of the rolling `dev` pre-release that android.yml publishes,
#   https://github.com/OWNER/REPO/releases/download/dev/swordknights-dev.apk
# so the site and the app's own update check are one channel, and an APK
# fetched from the page is one the game will later offer to update.
#
# This is the one place the parts meet, and it is a script rather than
# workflow YAML so that what Pages publishes can be built and looked at on a
# laptop: export the web build, run this, and serve the output with
# `python3 -m http.server -d build/site`.
#
# The page carries the facts that only exist after the build -- the engine's
# download size, the commit, the APK's address -- as {{PLACEHOLDERS}} filled in
# here. Any placeholder left over fails the script, so a typo cannot
# publish a page that says "{{APK_SIZE}}".

set -euo pipefail

cd "$(dirname "$0")/.."

web="" out=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		--web) web="$2"; shift 2 ;;
		--out) out="$2"; shift 2 ;;
		*) echo "assemble: unknown argument $1" >&2; exit 2 ;;
	esac
done
if [[ -z "$web" || -z "$out" ]]; then
	echo "usage: site/assemble.sh --web DIR --out DIR" >&2
	exit 2
fi

for f in index.html index.js index.wasm index.pck; do
	if [[ ! -s "$web/$f" ]]; then
		echo "assemble: web export is missing $web/$f" >&2
		exit 1
	fi
done
repository="${REPOSITORY:-andreas83/swordknights}"
if [[ ! "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
	echo "assemble: REPOSITORY '${repository}' is not OWNER/REPO" >&2
	exit 1
fi
release_url="https://github.com/${repository}/releases/tag/dev"
apk_url="https://github.com/${repository}/releases/download/dev/swordknights-dev.apk"

commit="${COMMIT:-$(git rev-parse HEAD)}"
build_date="${BUILD_DATE:-$(date -u '+%-d %B %Y')}"

# Decimal megabytes, as a phone's download manager reports them: one decimal
# below ten, whole numbers above.
megabytes() {
	awk -v b="$1" 'BEGIN { m = b / 1000000; printf (m < 10 ? "%.1f MB" : "%.0f MB"), m }'
}

rm -rf "$out"
mkdir -p "$out/play"
cp -R site/public/. "$out/"
cp icon.svg "$out/icon.svg"
cp -R "$web/." "$out/play/"

play_bytes="$(cat "$out/play/index.wasm" "$out/play/index.pck" "$out/play/index.js" | wc -c)"

page="$out/index.html"
if [[ -n "${SITE_URL:-}" ]]; then
	sed -i "s|{{SITE_URL}}|${SITE_URL}|g" "$page"
else
	sed -i '/{{SITE_URL}}/d' "$page"
fi
sed -i \
	-e "s|{{APK_URL}}|${apk_url}|g" \
	-e "s|{{RELEASE_URL}}|${release_url}|g" \
	-e "s|{{PLAY_SIZE}}|$(megabytes "$play_bytes")|g" \
	-e "s|{{COMMIT_SHORT}}|${commit:0:7}|g" \
	-e "s|{{COMMIT}}|${commit}|g" \
	-e "s|{{BUILD_DATE}}|${build_date}|g" \
	"$page"

if grep -n '{{[A-Z_0-9]*}}' "$page"; then
	echo "assemble: placeholders left unfilled in $page (above)" >&2
	exit 1
fi

echo "assembled $out:"
printf '  %-28s %s\n' "page" "$page"
printf '  %-28s %s (%s bytes)\n' "play/" "$(megabytes "$play_bytes")" "$play_bytes"
printf '  %-28s %s\n' "android button" "$apk_url"
