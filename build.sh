#!/bin/bash
# Builds Linkguide.app, signs it, installs it to /Applications and registers it with Launch Services.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Linkguide"
STAGING="$PWD/.build/$APP_NAME.app"
INSTALL_PATH="/Applications/$APP_NAME.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

echo "==> Compiling (release, arm64)"
swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

echo "==> Assembling $APP_NAME.app"
rm -rf "$STAGING"
mkdir -p "$STAGING/Contents/MacOS" "$STAGING/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$STAGING/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$STAGING/Contents/Info.plist"
cp Resources/AppIcon.icns "$STAGING/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$STAGING/Contents/PkgInfo"
plutil -lint "$STAGING/Contents/Info.plist" >/dev/null

# An Apple Development certificate gives every build the same identity, so macOS keeps the Accessibility
# permission across rebuilds. Without one, fall back to ad-hoc signing (permission needs granting after each build).
SIGN_IDENTITY="${LINKGUIDE_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ { print $2; exit }')}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

echo "==> Signing ($([ "$SIGN_IDENTITY" = "-" ] && echo "ad-hoc" || echo "$SIGN_IDENTITY"))"
codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$STAGING"
codesign --verify --strict "$STAGING"

# Quit a running copy so the next link launches the new build (exact process name only).
if pgrep -x "$APP_NAME" >/dev/null; then
  echo "==> Quitting running $APP_NAME"
  pkill -x "$APP_NAME" || true
  sleep 1
fi

echo "==> Installing to $INSTALL_PATH"
rm -rf "$INSTALL_PATH"
ditto "$STAGING" "$INSTALL_PATH"

echo "==> Registering with Launch Services"
"$LSREGISTER" -u "$STAGING" >/dev/null 2>&1 || true
rm -rf "$STAGING"
"$LSREGISTER" -f -R -trusted "$INSTALL_PATH"

echo "==> Done: $INSTALL_PATH"
