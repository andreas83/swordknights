#!/usr/bin/env bash
#
# Write the dev channel's version.json and release notes for one build.
#
# Usage:
#   .github/scripts/dev_manifest.sh --apk FILE --code N --name NAME --sha SHA \
#       --repo OWNER/REPO --message-file FILE --out DIR \
#       [--commits-file FILE] [--signer SHA256]
#
#   --message-file  the full message of the commit that was built
#   --commits-file  optional; one "<sha> <subject>" line per commit the push
#                   brought, oldest first. More than one line adds an
#                   "Also in this build" list to the notes.
#   --signer        the APK's signing-certificate SHA-256, as apksigner prints it
#
# Writes DIR/version.json and DIR/notes.md. Publishes nothing: android.yml
# uploads the two files, and keeping this half out of the workflow YAML means
# the exact manifest a phone will read can be produced and read on a laptop.
#
# version.json is what the app's update check reads (scripts/core/dev_update.gd):
#
#   code     the build's Android version code; the app offers it when it is
#            higher than its own
#   name     the version name, with the short commit
#   sha      the full commit
#   date     when the build was made, UTC, ISO 8601
#   apk_url  the stable download URL of the APK on the `dev` pre-release
#
# plus apk_sha256 and signer_sha256, which the app ignores and a person
# diagnosing a failed install wants.

set -euo pipefail

apk="" code="" name="" sha="" repo="" message="" commits="" signer="" out=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		--apk) apk="$2"; shift 2 ;;
		--code) code="$2"; shift 2 ;;
		--name) name="$2"; shift 2 ;;
		--sha) sha="$2"; shift 2 ;;
		--repo) repo="$2"; shift 2 ;;
		--message-file) message="$2"; shift 2 ;;
		--commits-file) commits="$2"; shift 2 ;;
		--signer) signer="$2"; shift 2 ;;
		--out) out="$2"; shift 2 ;;
		*) echo "dev_manifest: unknown argument $1" >&2; exit 2 ;;
	esac
done
for required in apk code name sha repo message out; do
	if [[ -z "${!required}" ]]; then
		echo "dev_manifest: --${required/message/message-file} is required" >&2
		exit 2
	fi
done
if [[ ! -s "$apk" ]]; then
	echo "dev_manifest: no APK at ${apk}" >&2
	exit 1
fi
if [[ ! "$code" =~ ^[1-9][0-9]*$ ]]; then
	echo "dev_manifest: code '${code}' is not a positive whole number" >&2
	exit 1
fi
if [[ ! "$sha" =~ ^[0-9a-f]{40}$ ]]; then
	echo "dev_manifest: '${sha}' is not a full commit hash" >&2
	exit 1
fi
if [[ ! "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
	echo "dev_manifest: '${repo}' is not OWNER/REPO" >&2
	exit 1
fi

# The tag and the asset name are the whole contract with everything that links
# here -- the app, the README, the site. Neither changes from build to build.
apk_url="https://github.com/${repo}/releases/download/dev/swordknights-dev.apk"
date="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
apk_sha="$(sha256sum "$apk" | cut -d' ' -f1)"
short="${sha:0:7}"

mkdir -p "$out"
jq -n \
	--argjson code "$code" \
	--arg name "$name" \
	--arg sha "$sha" \
	--arg date "$date" \
	--arg apk_url "$apk_url" \
	--arg apk_sha256 "$apk_sha" \
	--arg signer_sha256 "$signer" \
	'{code: $code, name: $name, sha: $sha, date: $date, apk_url: $apk_url,
	  apk_sha256: $apk_sha256, signer_sha256: $signer_sha256}' \
	>"$out/version.json"

subject="$(head -n 1 "$message")"
# The body without its trailer block (Co-Authored-By:, Signed-off-by: and the
# like): the last paragraph, when every line in it is a `Key: value` trailer.
# They are bookkeeping for git, not notes for whoever is installing the build.
body="$(tail -n +2 "$message" | awk '
	{ lines[NR] = $0 }
	END {
		n = NR
		while (n > 0 && lines[n] ~ /^[[:space:]]*$/) n--
		start = n
		while (start > 0 && lines[start] ~ /^[A-Za-z][A-Za-z0-9-]*: /) start--
		if (start < n && (start == 0 || lines[start] ~ /^[[:space:]]*$/)) n = start
		while (n > 0 && lines[n] ~ /^[[:space:]]*$/) n--
		first = 1
		while (first <= n && lines[first] ~ /^[[:space:]]*$/) first++
		for (i = first; i <= n; i++) print lines[i]
	}')"

{
	echo "**Build ${code}** · \`${name}\` · [\`${short}\`](https://github.com/${repo}/commit/${sha}) · ${date}"
	echo
	echo "### ${subject}"
	if [[ -n "$body" ]]; then
		echo
		echo "$body"
	fi
	if [[ -n "$commits" && -s "$commits" && "$(wc -l <"$commits")" -gt 1 ]]; then
		echo
		echo "### Also in this build"
		echo
		while read -r id line; do
			[[ "$id" == "$sha" || "$id" == "$short"* ]] && continue
			echo "- [\`${id:0:7}\`](https://github.com/${repo}/commit/${id}) ${line}"
		done <"$commits"
	fi
	echo
	echo "---"
	echo
	echo "**Install:** open [swordknights-dev.apk](${apk_url}) on the phone and let Android"
	echo "install it. A build installed from here watches this release itself: when a newer one"
	echo "is published, its title screen shows **UPDATE AVAILABLE**, and one tap fetches it."
	echo
	echo "This pre-release is replaced on every push to \`main\`, and its \`dev\` tag moves with it."
	echo
	echo "- APK SHA-256: \`${apk_sha}\`"
	if [[ -n "$signer" ]]; then
		echo "- Signing certificate SHA-256: \`${signer}\`"
		echo "  If this differs from the build on the phone, Android will refuse the update as"
		echo "  signed differently: uninstall once, then install. See docs/ci.md, \"The debug key\"."
	fi
} >"$out/notes.md"

echo "dev_manifest: wrote ${out}/version.json and ${out}/notes.md"
jq . "$out/version.json"
