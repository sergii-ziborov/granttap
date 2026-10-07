#!/usr/bin/env bash
set -euo pipefail

package_root="$(cd "$(dirname "$0")" && pwd)"
apple_root="$package_root/../ios"
derived_data="$package_root/.build/catalyst"
app_bundle="$package_root/dist/GrantTap.app"
stage_app="$package_root/dist/GrantTap.next.app"
signing_identity="${GRANTTAP_MAC_SIGN_IDENTITY:-Apple Development}"
team_id="XMS5ZC28UJ"
profile="${GRANTTAP_MAC_PROFILE:-$HOME/Library/MobileDevice/Provisioning Profiles/GrantTapMacCatalystDevelopment.provisionprofile}"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
if [[ -z "$profile" || ! -f "$profile" ]]; then
  echo "A Mac Catalyst development profile is required for GrantTap passkeys." >&2
  echo "Install one in ~/Library/MobileDevice/Provisioning Profiles or set GRANTTAP_MAC_PROFILE." >&2
  exit 1
fi

decoded_profile="$(mktemp)"
entitlements="$(mktemp)"
trap 'rm -f "$decoded_profile" "$entitlements"' EXIT
security cms -D -i "$profile" > "$decoded_profile"
python3 - "$decoded_profile" <<'PY'
import plistlib
import sys
from datetime import datetime, timezone

with open(sys.argv[1], "rb") as source:
    profile = plistlib.load(source)
grants = profile.get("Entitlements", {})
app_id = "XMS5ZC28UJ.com.ziborov.granttap"
domains = grants.get("com.apple.developer.associated-domains")
if not any(platform in ("OSX", "macOS") for platform in profile.get("Platform", [])):
    raise SystemExit("The profile is not a Mac Catalyst development profile.")
if app_id not in (grants.get("application-identifier"),
                  grants.get("com.apple.application-identifier")):
    raise SystemExit("The profile does not belong to GrantTap.")
if domains != "*" and "webcredentials:granttap.com" not in (domains or []):
    raise SystemExit("The profile does not grant GrantTap associated domains.")
if grants.get("get-task-allow") is not True:
    raise SystemExit("Local Mac builds require a development profile, not a TestFlight distribution profile.")
expires = profile.get("ExpirationDate")
if expires is None or expires.replace(tzinfo=timezone.utc) <= datetime.now(timezone.utc):
    raise SystemExit("The Mac Catalyst development profile has expired.")
PY

# The Mac uses the same SwiftUI client and Mesh state as iPhone and iPad.
# build-inspector-app.sh keeps the old read-only protocol inspector available.
xcodebuild \
  -project "$apple_root/GrantTap.xcodeproj" \
  -scheme GrantTap \
  -configuration LocalTest \
  -destination 'generic/platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  build -quiet

source_app="$derived_data/Build/Products/LocalTest-maccatalyst/GrantTap.app"
test -d "$source_app"
mkdir -p "$package_root/dist"
rm -rf "$stage_app"
ditto "$source_app" "$stage_app"
mkdir -p "$stage_app/Contents/Resources/RepoLensGraph"
graph_resources="$stage_app/Contents/Resources/RepoLensGraph"
cp "$package_root/GraphWeb/"{index.html,mesh-graph.js,board-data.js,REPO_LENS_COMMIT,THREE_LICENSE.txt} "$graph_resources/"
cp "$package_root/GraphWeb/build/"{cb-core.js,scene.css} "$graph_resources/"
ditto "$package_root/GraphWeb/build/three" "$graph_resources/three"
ditto "$profile" "$stage_app/Contents/embedded.provisionprofile"

# Passkeys require a real Team ID, app identifier and webcredentials entitlement.
# Ad-hoc signing makes AuthenticationServices reject the calling process.
TEAM_ID="$team_id" APP_ID="com.ziborov.granttap" python3 - "$decoded_profile" "$entitlements" <<'PY'
import os
import plistlib
import sys

team = os.environ["TEAM_ID"]
app = os.environ["APP_ID"]
with open(sys.argv[1], "rb") as source:
    grants = plistlib.load(source).get("Entitlements", {})
entitlements = {
        "application-identifier": f"{team}.{app}",
        "com.apple.application-identifier": f"{team}.{app}",
        "com.apple.developer.team-identifier": team,
        "com.apple.developer.associated-domains": ["webcredentials:granttap.com"],
        "com.apple.security.app-sandbox": True,
        "com.apple.security.network.client": True,
        "com.apple.security.device.camera": True,
        "com.apple.security.device.audio-input": True,
        "com.apple.security.files.user-selected.read-write": True,
}
for key in ("aps-environment", "com.apple.developer.usernotifications.time-sensitive",
            "get-task-allow"):
    if key in grants:
        entitlements[key] = grants[key]
with open(sys.argv[2], "wb") as output:
    plistlib.dump(entitlements, output)
PY
codesign --force --deep --options runtime --sign "$signing_identity" \
  --entitlements "$entitlements" "$stage_app"
codesign --verify --deep --strict "$stage_app"
rm -rf "$app_bundle"
mv "$stage_app" "$app_bundle"
printf '%s\n' "$app_bundle"
