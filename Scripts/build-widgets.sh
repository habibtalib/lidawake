#!/usr/bin/env bash
# Signed build of LidAwake.app with the WidgetKit extension (widgets need a team-signed app + App Group).
#   LIDAWAKE_TEAM=<team id> Scripts/build-widgets.sh            build into ./build/xcode
#   LIDAWAKE_TEAM=<team id> Scripts/build-widgets.sh --install  also install the app and the CLIs
# Find your team ID in Xcode > Settings > Accounts (a free Personal Team works).
set -euo pipefail

cd "$(dirname "$0")/.."
: "${LIDAWAKE_TEAM:?Set LIDAWAKE_TEAM to your Apple Developer team ID}"
command -v xcodegen >/dev/null || { echo "Install XcodeGen: brew install xcodegen" >&2; exit 1; }

export LIDAWAKE_TEAM
xcodegen generate --quiet
xcodebuild -project LidAwake.xcodeproj -scheme LidAwake -configuration Release \
  -derivedDataPath build/xcode -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$LIDAWAKE_TEAM" build | grep -E '^(\*\*|error:|warning: .*LidAwake)' || true

APP="build/xcode/Build/Products/Release/LidAwake.app"
[[ -d "$APP/Contents/PlugIns/LidAwakeWidget.appex" ]] || { echo "Build failed: no widget extension in $APP" >&2; exit 1; }
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  swift build -c release
  BIN="$(swift build -c release --show-bin-path)"
  mkdir -p "$HOME/Applications" "$HOME/.local/bin"
  osascript -e 'quit app "LidAwake"' 2>/dev/null || true
  rm -rf "$HOME/Applications/LidAwake.app"
  cp -R "$APP" "$HOME/Applications/"
  install -m 0755 "$BIN/lidawake" "$BIN/lidawake-mcp" "$HOME/.local/bin/"
  pluginkit -a "$HOME/Applications/LidAwake.app/Contents/PlugIns/LidAwakeWidget.appex" || true
  open "$HOME/Applications/LidAwake.app"
  echo "Installed and launched ~/Applications/LidAwake.app (widget: right-click the desktop > Edit Widgets > LidAwake)"
fi
