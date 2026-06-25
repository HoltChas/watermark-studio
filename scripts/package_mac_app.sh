#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_ROOT="$ROOT/macos/WatermarkStudio"
DIST="$ROOT/dist"
mkdir -p "$DIST"

cd "$APP_ROOT"
swift build -c release

BIN="$APP_ROOT/.build/release/WatermarkStudioMac"
APP="$DIST/Watermark Studio.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"

rm -rf "$APP"
mkdir -p "$MACOS"
cp "$BIN" "$MACOS/WatermarkStudioMac"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>WatermarkStudioMac</string>
  <key>CFBundleIdentifier</key>
  <string>studio.watermark.mac</string>
  <key>CFBundleName</key>
  <string>Watermark Studio</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
</dict>
</plist>
PLIST

echo "$APP"

