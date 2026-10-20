#!/usr/bin/env bash
set -euo pipefail
# Xcode embeds the same offline viewer before signing every Apple client.
web_root="${SRCROOT:?}/../macos/GraphWeb"
output="${TARGET_BUILD_DIR:?}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}/RepoLensGraph"
rm -rf "$output"
mkdir -p "$output"
cp "$web_root/"{index.html,graph-ui.css,REPO_LENS_COMMIT,REPO_LENS_LICENSE.txt,THREE_LICENSE.txt} "$output/"
cp "$web_root/build/"{scene.css,viewer.js} "$output/"
