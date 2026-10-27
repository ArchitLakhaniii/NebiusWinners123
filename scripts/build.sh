#!/usr/bin/env bash
# Builds BrowserSkills.app into ./build. Requires macOS 15+ on Apple Silicon with Xcode 16+.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIG:-release}"
cd "$ROOT/app"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/BrowserSkills"
APP="$ROOT/build/BrowserSkills.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/BrowserSkills"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>BrowserSkills</string>
  <key>CFBundleDisplayName</key><string>BrowserSkills</string>
  <key>CFBundleIdentifier</key><string>ai.browserskills.app</string>
  <key>CFBundleExecutable</key><string>BrowserSkills</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
