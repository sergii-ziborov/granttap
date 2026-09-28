#!/usr/bin/env bash
set -euo pipefail

package_root="$(cd "$(dirname "$0")" && pwd)"
app_bundle="$package_root/dist/GrantTap Desktop.app"

swift build --package-path "$package_root" -c release --product GrantTapDesktop
mkdir -p "$app_bundle/Contents/MacOS"
mkdir -p "$app_bundle/Contents/Resources"
cp "$package_root/.build/release/GrantTapDesktop" "$app_bundle/Contents/MacOS/GrantTapDesktop"
cp "$package_root/DESKTOP_EULA.md" "$app_bundle/Contents/Resources/License.txt"
for provider in Codex Claude Cursor Grok; do
  cp "$package_root/../ios/GrantTap/Assets.xcassets/Provider${provider}.imageset/Provider${provider}.png" \
    "$app_bundle/Contents/Resources/Provider${provider}.png"
done
icon_source="$package_root/../ios/GrantTap/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
icon_tmp="$(mktemp -d)"
trap 'rm -rf "$icon_tmp"' EXIT
iconset="$icon_tmp/GrantTap.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$icon_source" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  doubled=$((size * 2))
  sips -z "$doubled" "$doubled" "$icon_source" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app_bundle/Contents/Resources/GrantTap.icns"
cat > "$app_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>GrantTap</string>
  <key>CFBundleDisplayName</key><string>GrantTap</string>
  <key>CFBundleIdentifier</key><string>com.ziborov.granttap.desktop</string>
  <key>CFBundleExecutable</key><string>GrantTapDesktop</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>GrantTap</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Copyright 2026 Serhii Ziborov. All rights reserved.</string>
</dict></plist>
PLIST
codesign --force --sign - "$app_bundle"
printf '%s\n' "$app_bundle"
