#!/usr/bin/env bash
#
# Assemble the public site: the page from site/public/, the web export under
# play/, and the debug APK under download/.
#
# Usage, from the repository root:
#   site/assemble.sh --web build/web --apk dist/swordknights.apk --out build/site
#
# Environment (all optional):
#   SITE_URL    absolute URL the site is served from, with a trailing slash. Only
#               link previews need it (Open Graph wants absolute URLs); when it is
#               unset those two tags are dropped, which is right for a local
#               preview.
#   COMMIT      full commit hash the builds came from. Default: git HEAD.
#   BUILD_DATE  date shown on the page. Default: today, UTC.
#
# This is the one place the three parts meet, and it is a script rather than
# workflow YAML so that what Pages publishes can be built and looked at on a
# laptop: export the web build, drop any file in as the APK, run this, and serve
# the output with `python3 -m http.server -d build/site`.
#
# The page carries the facts that only exist after the build -- the APK's size
# and checksum, the engine's download size, the commit -- as {{PLACEHOLDERS}}
# filled in here. Any placeholder left over fails the script, so a typo cannot
# publish a page that says "{{APK_SIZE}}".

set -euo pipefail

cd "$(dirname "$0")/.."

web="" apk="" out=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		--web) web="$2"; shift 2 ;;
		--apk) apk="$2"; shift 2 ;;
		--out) out="$2"; shift 2 ;;
		*) echo "assemble: unknown argument $1" >&2; exit 2 ;;
	esac
done
if [[ -z "$web" || -z "$apk" || -z "$out" ]]; then
	echo "usage: site/assemble.sh --web DIR --apk FILE --out DIR" >&2
	exit 2
fi

for f in index.html index.js index.wasm index.pck; do
	if [[ ! -s "$web/$f" ]]; then
		echo "assemble: web export is missing $web/$f" >&2
		exit 1
	fi
done
if [[ ! -s "$apk" ]]; then
	echo "assemble: no APK at $apk" >&2
	exit 1
fi

commit="${COMMIT:-$(git rev-parse HEAD)}"
build_date="${BUILD_DATE:-$(date -u '+%-d %B %Y')}"

# Decimal megabytes, as a phone's download manager reports them: one decimal
# below ten, whole numbers above.
megabytes() {
	awk -v b="$1" 'BEGIN { m = b / 1000000; printf (m < 10 ? "%.1f MB" : "%.0f MB"), m }'
}

rm -rf "$out"
mkdir -p "$out/play" "$out/download"
cp -R site/public/. "$out/"
cp icon.svg "$out/icon.svg"
cp -R "$web/." "$out/play/"
cp "$apk" "$out/download/swordknights.apk"

apk_bytes="$(stat -c%s "$out/download/swordknights.apk")"
apk_sha="$(sha256sum "$out/download/swordknights.apk" | cut -d' ' -f1)"
play_bytes="$(cat "$out/play/index.wasm" "$out/play/index.pck" "$out/play/index.js" | wc -c)"

page="$out/index.html"
if [[ -n "${SITE_URL:-}" ]]; then
	sed -i "s|{{SITE_URL}}|${SITE_URL}|g" "$page"
else
	sed -i '/{{SITE_URL}}/d' "$page"
fi
sed -i \
	-e "s|{{APK_SIZE}}|$(megabytes "$apk_bytes")|g" \
	-e "s|{{APK_SHA256}}|${apk_sha}|g" \
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
printf '  %-28s %s (%s bytes)\n' "download/swordknights.apk" "$(megabytes "$apk_bytes")" "$apk_bytes"
printf '  %-28s %s\n' "apk sha256" "$apk_sha"
