#!/usr/bin/env bash
# Build LidAwake.app (menu bar app) plus the lidawake and lidawake-mcp CLIs.
#   Scripts/bundle-app.sh            build into ./build
#   Scripts/bundle-app.sh --install  also copy the app to ~/Applications and the CLIs to ~/.local/bin
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="$(sed -n 's/.*static let string = "\(.*\)".*/\1/p' Sources/LidAwakeCore/Version.swift)"
BUNDLE_ID="dev.habibtalib.lidawake"
OUT="build"
APP="$OUT/LidAwake.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/LidAwakeApp" "$APP/Contents/MacOS/LidAwake"
cp Xcode/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp "$BIN/lidawake" "$BIN/lidawake-mcp" "$OUT/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>LidAwake</string>
  <key>CFBundleDisplayName</key><string>LidAwake</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleExecutable</key><string>LidAwake</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>${BUNDLE_ID}</string>
      <key>CFBundleURLSchemes</key><array><string>lidawake</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
codesign --force --sign - "$OUT/lidawake" "$OUT/lidawake-mcp"
echo "Built $APP ($VERSION)"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/Applications" "$HOME/.local/bin"
  osascript -e 'quit app "LidAwake"' 2>/dev/null || true
  rm -rf "$HOME/Applications/LidAwake.app"
  cp -R "$APP" "$HOME/Applications/"
  install -m 0755 "$OUT/lidawake" "$OUT/lidawake-mcp" "$HOME/.local/bin/"
  echo "Installed ~/Applications/LidAwake.app and ~/.local/bin/{lidawake,lidawake-mcp}"
  echo "One-time setup:           lidawake install-permission"
  echo "Register the MCP server:  claude mcp add lidawake -s user -- \$HOME/.local/bin/lidawake-mcp"
fi
