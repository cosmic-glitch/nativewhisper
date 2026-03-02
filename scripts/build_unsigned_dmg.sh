#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PRODUCT_NAME="Whisper Anywhere"
APP_BUNDLE_NAME="${APP_PRODUCT_NAME}.app"
EXECUTABLE_NAME="NativeWhisper"
BUNDLE_ID="ai.whisperanywhere.app"
MIN_MACOS_VERSION="14.0"
ICON_SOURCE="$ROOT_DIR/NativeWhisper/Resources/AppIcon.icns"
BUILD_DIR="$ROOT_DIR/.build/release"
DIST_DIR="$ROOT_DIR/dist"
DMG_STAGING_PATH="$DIST_DIR/dmg-root"
APP_BUNDLE_PATH="$DIST_DIR/$APP_BUNDLE_NAME"
DMG_PATH="$DIST_DIR/Whisper-Anywhere-unsigned.dmg"
RESOURCE_BUNDLE_PATH="$BUILD_DIR/${EXECUTABLE_NAME}_${EXECUTABLE_NAME}.bundle"

log() {
  echo "==> $*"
}

die() {
  echo "Error: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

require_cmd swift
require_cmd hdiutil
require_cmd codesign

[[ -f "$ICON_SOURCE" ]] || die "Icon file not found: $ICON_SOURCE"

VERSION="${VERSION:-$(git -C "$ROOT_DIR" describe --tags --always --dirty 2>/dev/null | sed 's/^v//' || true)}"
if [[ -z "$VERSION" ]]; then
  VERSION="1.0.0"
fi
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"

log "Building release binary"
cd "$ROOT_DIR"
swift build -c release
[[ -f "$BUILD_DIR/$EXECUTABLE_NAME" ]] || die "Build output missing: $BUILD_DIR/$EXECUTABLE_NAME"

log "Preparing unsigned app bundle"
mkdir -p "$DIST_DIR"
rm -rf "$APP_BUNDLE_PATH" "$DMG_STAGING_PATH" "$DMG_PATH"
mkdir -p "$APP_BUNDLE_PATH/Contents/MacOS" "$APP_BUNDLE_PATH/Contents/Resources"

cp "$BUILD_DIR/$EXECUTABLE_NAME" "$APP_BUNDLE_PATH/Contents/MacOS/$EXECUTABLE_NAME"
cp "$ICON_SOURCE" "$APP_BUNDLE_PATH/Contents/Resources/AppIcon.icns"
if [[ -d "$RESOURCE_BUNDLE_PATH" ]]; then
  cp -R "$RESOURCE_BUNDLE_PATH" "$APP_BUNDLE_PATH/Contents/Resources/"
fi

cat > "$APP_BUNDLE_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>${EXECUTABLE_NAME}</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleName</key><string>${APP_PRODUCT_NAME}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key><string>${MIN_MACOS_VERSION}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>ai.whisperanywhere.auth</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>whisperanywhere</string>
      </array>
    </dict>
  </array>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Whisper Anywhere needs microphone access for dictation.</string>
</dict>
</plist>
PLIST

log "Applying ad-hoc signature for local run compatibility"
codesign --force --deep --sign - "$APP_BUNDLE_PATH"

log "Creating unsigned DMG"
mkdir -p "$DMG_STAGING_PATH"
cp -R "$APP_BUNDLE_PATH" "$DMG_STAGING_PATH/"
ln -s /Applications "$DMG_STAGING_PATH/Applications"

hdiutil create \
  -volname "Whisper Anywhere" \
  -srcfolder "$DMG_STAGING_PATH" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

log "Unsigned DMG ready: $DMG_PATH"
