#!/bin/bash
# Builds VocabFlashcards in release mode and assembles a double-clickable .app bundle
# into ./dist. Re-run any time after changing the code.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

# Prefer Xcode's toolchain, but don't insist on it: the Command Line Tools build this
# package fine, and pointing DEVELOPER_DIR at a missing Xcode fails before compiling.
if [ -z "${DEVELOPER_DIR:-}" ]; then
  if [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  else
    export DEVELOPER_DIR="$(xcode-select -p)"
  fi
fi
unset SDKROOT 2>/dev/null || true

# Some Command Line Tools updates leave an older release's PackageDescription
# .private.swiftinterface beside the current module. The compiler prefers it, so
# Package.swift fails to link ("Undefined symbols … Package.__allocating_init"). When the
# private interface was built by a different compiler than the public one, mirror the
# manifest and plugin APIs without it and point SwiftPM at the mirror.
PM_LIBS="$DEVELOPER_DIR/usr/lib/swift/pm"
PD_MODULE="$PM_LIBS/ManifestAPI/PackageDescription.swiftmodule"
if [ -z "${SWIFTPM_CUSTOM_LIBS_DIR:-}" ] \
   && [ -f "$PD_MODULE/arm64-apple-macos.private.swiftinterface" ] \
   && [ "$(sed -n 2p "$PD_MODULE/arm64-apple-macos.private.swiftinterface")" != \
        "$(sed -n 2p "$PD_MODULE/arm64-apple-macos.swiftinterface")" ]; then
  PM_OVERLAY="$(mktemp -d)"
  trap 'rm -rf "$PM_OVERLAY"' EXIT
  for api in ManifestAPI PluginAPI; do
    [ -d "$PM_LIBS/$api" ] || continue
    mkdir -p "$PM_OVERLAY/$api"
    for entry in "$PM_LIBS/$api"/*; do
      name="$(basename "$entry")"
      if [ -d "$entry" ]; then
        mkdir -p "$PM_OVERLAY/$api/$name"
        for f in "$entry"/*; do
          case "$f" in
            *.private.swiftinterface) ;;
            *) ln -s "$f" "$PM_OVERLAY/$api/$name/" ;;
          esac
        done
      else
        ln -s "$entry" "$PM_OVERLAY/$api/"
      fi
    done
  done
  export SWIFTPM_CUSTOM_LIBS_DIR="$PM_OVERLAY"
  echo "==> Skipping a stale PackageDescription interface in $DEVELOPER_DIR"
fi

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

# SwiftPM emits target resources as sibling .bundle directories next to the binary, and
# `Bundle.module` looks for them in Contents/Resources. Without this the app launches fine
# but silently ships with no example sentences.
BIN_DIR="$(dirname "$BIN_PATH")"
shopt -s nullglob
BUNDLES=("$BIN_DIR"/*.bundle)
shopt -u nullglob
for b in "${BUNDLES[@]}"; do
  cp -R "$b" "$APP/Contents/Resources/"
  echo "    bundled $(basename "$b")"
done

CURATED="$APP/Contents/Resources/${BIN_NAME}_VocabKit.bundle/curated_content.json"
if [ ! -f "$CURATED" ]; then
  echo "!!! curated_content.json is missing from the app bundle — example sentences will not appear." >&2
  exit 1
fi
echo "    example bank: $(wc -c < "$CURATED" | tr -d ' ') bytes"

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
