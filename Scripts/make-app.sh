#!/bin/bash
#
# Wraps the SwiftPM executable in a .app bundle.
#
# AppKit needs a bundle for a menu bar app to behave: LSUIElement keeps it
# out of the Dock, and the bundle identifier is what UserDefaults and the
# Touch Bar machinery key off.
#
set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Touch My Bar.app"
BIN="$(swift build --package-path "$ROOT" -c "$CONFIG" --show-bin-path)/TouchMyBar"

swift build --package-path "$ROOT" -c "$CONFIG"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TouchMyBar"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Touch My Bar</string>
    <key>CFBundleDisplayName</key>
    <string>Touch My Bar</string>
    <key>CFBundleIdentifier</key>
    <string>dev.ctoasap.touchmybar</string>
    <key>CFBundleExecutable</key>
    <string>TouchMyBar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <!-- Menu bar only: no Dock tile, no main menu. -->
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# Ad-hoc signature. Enough to run locally; replace with a Developer ID
# identity if this ever leaves this machine.
codesign --force --sign - "$APP"

echo "Built $APP"
