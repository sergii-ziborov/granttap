#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../../.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
archive="${GRANTTAP_MAC_ARCHIVE:-$root/.release/mac-store/GrantTap.xcarchive}"
args=()
if [[ "${GRANTTAP_UNSIGNED_ARCHIVE:-0}" == 1 ]]; then args+=(CODE_SIGNING_ALLOWED=NO); fi
xcodebuild -quiet -project "$root/apps/ios/GrantTap.xcodeproj" -scheme GrantTap \
  -configuration Release -destination 'generic/platform=macOS,variant=Mac Catalyst' \
  -archivePath "$archive" "${args[@]}" archive
printf '%s\n' "$archive"
