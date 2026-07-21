#!/bin/bash
# Builds VocabFlashcards in release mode and assembles a double-clickable .app bundle
# into ./dist. Re-run any time after changing the code.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
unset SDKROOT 2>/dev/null || true

CONFIG=release
APP_NAME="Vocab Flashcards"
BIN_NAME="VocabFlashcards"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

echo "==> Building ($CONFIG)…"
swift build -c "$CONFIG" --product "$BIN_NAME"
BIN_PATH="$(swift build -c "$CONFIG" --product "$BIN_NAME" --show-bin-path)/$BIN_NAME"

echo "==> Assembling app bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/$BIN_NAME"
cp "$ROOT/Packaging/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Generating icon…"
ICON_TMP="$(mktemp -d)"
if swift "$ROOT/Packaging/make_icon.swift" "$ICON_TMP/icon_1024.png" >/dev/null 2>&1; then
  ICONSET="$ICON_TMP/AppIcon.iconset"; mkdir -p "$ICONSET"
  for s in 16 32 64 128 256 512 1024; do
    sips -z "$s" "$s" "$ICON_TMP/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null 2>&1 || true
  done
  cp "$ICONSET/icon_32x32.png"     "$ICONSET/icon_16x16@2x.png"   2>/dev/null || true
  cp "$ICONSET/icon_64x64.png"     "$ICONSET/icon_32x32@2x.png"   2>/dev/null || true
  cp "$ICONSET/icon_256x256.png"   "$ICONSET/icon_128x128@2x.png" 2>/dev/null || true
  cp "$ICONSET/icon_512x512.png"   "$ICONSET/icon_256x256@2x.png" 2>/dev/null || true
  cp "$ICONSET/icon_1024x1024.png" "$ICONSET/icon_512x512@2x.png" 2>/dev/null || true
  rm -f "$ICONSET/icon_64x64.png" "$ICONSET/icon_1024x1024.png"
  if iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null; then
    echo "    icon added."
  else
    echo "    (iconutil failed; continuing without icon)"
  fi
else
  echo "    (icon generation skipped)"
fi
rm -rf "$ICON_TMP"

# Ad-hoc signature so launching is smooth on the local machine.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "==> Done: $APP"
