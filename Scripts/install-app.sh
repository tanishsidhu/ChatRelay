#!/bin/zsh

set -euo pipefail

ROOT="${0:A:h:h}"
BUILD_APP="$ROOT/.build/app/ChatRelay.app"
INSTALL_DIRECTORY="${CHATRELAY_INSTALL_DIR:-$HOME/Applications}"
INSTALLED_APP="$INSTALL_DIRECTORY/ChatRelay.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

"$ROOT/Scripts/build-app.sh" release

mkdir -p "$INSTALL_DIRECTORY"
pkill -x ChatRelay 2>/dev/null || true
sleep 0.3
rm -rf "$INSTALLED_APP"
ditto "$BUILD_APP" "$INSTALLED_APP"
"$LSREGISTER" -u "$BUILD_APP" 2>/dev/null || true
"$LSREGISTER" -f -R -trusted "$INSTALLED_APP"
codesign --verify --deep --strict "$INSTALLED_APP"
open "$INSTALLED_APP"

echo "Installed and launched $INSTALLED_APP"
