#!/usr/bin/env bash
#
# Inject iOS signing values into export_presets.cfg, in the runner only.
#
# Unlike Android -- where Godot 4.5 reads the keystore straight out of
# GODOT_ANDROID_KEYSTORE_RELEASE_* -- there is no environment-variable path for
# the iOS team id, signing identity or provisioning profile. They have to be in
# the preset. So the committed preset keeps them empty and this script writes
# them at build time from secrets. The edit is never committed.
#
# With no secrets configured it leaves application/export_project_only=true,
# and the export produces an Xcode project instead of a signed .ipa. That is
# the best a runner without Apple credentials can do, and it is still useful:
# someone with a developer account can open and sign it.
#
# Usage (reads the environment):
#   IOS_TEAM_ID, IOS_CODE_SIGN_IDENTITY, IOS_PROVISIONING_PROFILE_UUID
#   .github/scripts/ios_signing_overlay.sh

set -euo pipefail

PRESETS="${1:-export_presets.cfg}"

TEAM_ID="${IOS_TEAM_ID:-}"
IDENTITY="${IOS_CODE_SIGN_IDENTITY:-}"
PROFILE="${IOS_PROVISIONING_PROFILE_UUID:-}"

if [[ ! -f "$PRESETS" ]]; then
	echo "error: ${PRESETS} not found -- run this from the repository root" >&2
	exit 1
fi

if [[ -z "$TEAM_ID" || -z "$IDENTITY" || -z "$PROFILE" ]]; then
	echo "No complete iOS signing material in the environment."
	echo "  IOS_TEAM_ID                   $([[ -n $TEAM_ID ]] && echo set || echo 'not set')"
	echo "  IOS_CODE_SIGN_IDENTITY        $([[ -n $IDENTITY ]] && echo set || echo 'not set')"
	echo "  IOS_PROVISIONING_PROFILE_UUID $([[ -n $PROFILE ]] && echo set || echo 'not set')"
	echo
	echo "Leaving export_project_only=true: the export will emit an Xcode"
	echo "project rather than a signed .ipa. See docs/ci.md."
	exit 0
fi

# All three present: sign for real.
sed -i \
	-e "s|^application/app_store_team_id=.*|application/app_store_team_id=\"${TEAM_ID}\"|" \
	-e "s|^application/code_sign_identity_release=.*|application/code_sign_identity_release=\"${IDENTITY}\"|" \
	-e "s|^application/provisioning_profile_uuid_release=.*|application/provisioning_profile_uuid_release=\"${PROFILE}\"|" \
	-e "s|^application/export_project_only=.*|application/export_project_only=false|" \
	"$PRESETS"

# Deliberately does not echo the values back -- they would land in the log.
echo "Applied iOS signing overlay (team id, identity and profile set)."
echo "export_project_only is now:"
grep -n '^application/export_project_only=' "$PRESETS" | sed 's/^/  /'
