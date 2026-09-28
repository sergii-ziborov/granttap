#!/usr/bin/env bash
set -euo pipefail
# Xcode runs this before signing. iPhone/iPad use their native graph view.
if [[ "${EFFECTIVE_PLATFORM_NAME:-}" != "-maccatalyst" ]]; then exit 0; fi
web_root="${SRCROOT:?}/../macos/GraphWeb"
output="${TARGET_BUILD_DIR:?}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}/RepoLensGraph"
mkdir -p "$output"
cp "$web_root/"{index.html,mesh-graph.js,board-data.js,REPO_LENS_COMMIT,THREE_LICENSE.txt} "$output/"
cp "$web_root/build/"{cb-core.js,scene.css} "$output/"
ditto "$web_root/build/three" "$output/three"
