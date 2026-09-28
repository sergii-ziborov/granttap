#!/usr/bin/env bash
set -euo pipefail

package_root="$(cd "$(dirname "$0")" && pwd)"
apple_root="$package_root/../ios"
derived_data="$package_root/.build/catalyst"
app_bundle="$package_root/dist/GrantTap.app"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

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
rm -rf "$app_bundle"
ditto "$source_app" "$app_bundle"
mkdir -p "$app_bundle/Contents/Resources/RepoLensGraph"
graph_resources="$app_bundle/Contents/Resources/RepoLensGraph"
cp "$package_root/GraphWeb/"{index.html,mesh-graph.js,board-data.js,REPO_LENS_COMMIT,THREE_LICENSE.txt} "$graph_resources/"
cp "$package_root/GraphWeb/build/"{cb-core.js,scene.css} "$graph_resources/"
ditto "$package_root/GraphWeb/build/three" "$graph_resources/three"
codesign --force --deep --sign - "$app_bundle"
printf '%s\n' "$app_bundle"
