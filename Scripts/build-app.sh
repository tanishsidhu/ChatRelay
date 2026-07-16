#!/bin/zsh

set -euo pipefail

ROOT="${0:A:h:h}"
CONFIGURATION="${1:-debug}"
APP_ROOT="$ROOT/.build/app"
APP="$APP_ROOT/ChatRelay.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

swift build --package-path "$ROOT" -c "$CONFIGURATION"
BIN_PATH="$(swift build --package-path "$ROOT" -c "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
cp "$BIN_PATH/ChatRelay" "$MACOS/ChatRelay"
cp "$BIN_PATH/chatrelayctl" "$MACOS/chatrelayctl"
codesign --force --sign - \
  --requirements '=designated => identifier "io.chatrelay.ChatRelay"' \
  "$APP"
codesign --verify --deep --strict "$APP"

if ! codesign -d -r- "$APP" 2>&1 | grep -Fq 'designated => identifier "io.chatrelay.ChatRelay"'; then
  echo "Stable designated requirement was not applied" >&2
  exit 1
fi

echo "$APP"
