#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PRODUCT_NAME="Whisper Anywhere"
APP_BUNDLE_NAME="${APP_PRODUCT_NAME}.app"
DMG_BASENAME="Whisper-Anywhere"
EXECUTABLE_NAME="WhisperAnywhere"
BUNDLE_ID="ai.whisperanywhere.app"
MIN_MACOS_VERSION="14.0"
ICON_SOURCE="$ROOT_DIR/WhisperAnywhere/Resources/AppIcon.icns"
BUILD_DIR="$ROOT_DIR/.build/release"
# Output directory for build artifacts (gitignored — do not commit dist/).
DIST_DIR="$ROOT_DIR/dist"
VOLUME_NAME="Whisper Anywhere"
ENTITLEMENTS_PATH="$ROOT_DIR/scripts/whisperanywhere.entitlements"

IDENTITY="${DEVELOPER_IDENTITY:-Developer ID Application: Anurag Ved (94DFHZ6ZTZ)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-whisperanywhere-notary}"
VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
SKIP_NOTARIZE=false
KEEP_STAGING=false

usage() {
  cat <<'EOF'
Create a signed + notarized DMG for Whisper Anywhere.

Usage:
  ./scripts/release_dmg.sh --identity "Developer ID Application: Name (TEAMID)" [options]

Required:
  --identity <name>        Developer ID Application certificate name.

Options:
  --notary-profile <name>  notarytool keychain profile (required unless --skip-notarize).
  --version <string>       CFBundleShortVersionString and DMG version label.
  --build-number <string>  CFBundleVersion.
  --output-dir <path>      Output directory for app bundle + dmg (default: ./dist).
  --skip-notarize          Build and sign only; skip notarization and stapling.
  --keep-staging           Keep temporary dmg staging directory.
  -h, --help               Show this help text.

Environment variable equivalents:
  DEVELOPER_IDENTITY, NOTARY_PROFILE, VERSION, BUILD_NUMBER

Examples:
  ./scripts/release_dmg.sh \
    --identity "Developer ID Application: Your Name (ABCDE12345)" \
    --notary-profile whisperanywhere-notary \
    --version 1.2.3 \
    --build-number 7

  ./scripts/release_dmg.sh \
    --identity "Developer ID Application: Your Name (ABCDE12345)" \
    --version 1.2.3 --build-number 7 --skip-notarize
EOF
}

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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --identity)
      shift
      IDENTITY="${1:-}"
      ;;
    --notary-profile)
      shift
      NOTARY_PROFILE="${1:-}"
      ;;
    --version)
      shift
      VERSION="${1:-}"
      ;;
    --build-number)
      shift
      BUILD_NUMBER="${1:-}"
      ;;
    --output-dir)
      shift
      DIST_DIR="${1:-}"
      ;;
    --skip-notarize)
      SKIP_NOTARIZE=true
      ;;
    --keep-staging)
      KEEP_STAGING=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
  shift
done

[[ -n "$IDENTITY" ]] || die "--identity is required (or set DEVELOPER_IDENTITY)."

if [[ "$SKIP_NOTARIZE" == false ]]; then
  [[ -n "$NOTARY_PROFILE" ]] || die "--notary-profile is required unless --skip-notarize is set."
fi

if [[ -z "$VERSION" ]]; then
  VERSION="$(git -C "$ROOT_DIR" describe --tags --always --dirty 2>/dev/null | sed 's/^v//')"
  [[ -n "$VERSION" ]] || VERSION="1.0.0"
fi

if [[ -z "$BUILD_NUMBER" ]]; then
  BUILD_NUMBER="$(date +%Y%m%d%H%M)"
fi

APP_BUNDLE_PATH="$DIST_DIR/$APP_BUNDLE_NAME"
DMG_STAGING_PATH="$DIST_DIR/dmg-root"
DMG_PATH="$DIST_DIR/${DMG_BASENAME}-${VERSION}.dmg"
APP_ZIP_PATH="$DIST_DIR/${APP_PRODUCT_NAME}-${VERSION}.zip"
EXECUTABLE_PATH="$APP_BUNDLE_PATH/Contents/MacOS/$EXECUTABLE_NAME"
INFO_PLIST_PATH="$APP_BUNDLE_PATH/Contents/Info.plist"
RESOURCE_BUNDLE_PATH="$BUILD_DIR/${EXECUTABLE_NAME}_${EXECUTABLE_NAME}.bundle"

cleanup() {
  if [[ "$KEEP_STAGING" == false ]]; then
    rm -rf "$DMG_STAGING_PATH"
  fi
}
trap cleanup EXIT

require_cmd swift
require_cmd codesign
require_cmd hdiutil
require_cmd xcrun

if [[ "$SKIP_NOTARIZE" == false ]]; then
  require_cmd xcrun
fi

[[ -f "$ICON_SOURCE" ]] || die "Icon file not found: $ICON_SOURCE"
[[ -f "$ENTITLEMENTS_PATH" ]] || die "Entitlements file not found: $ENTITLEMENTS_PATH"

log "Building release binary"
cd "$ROOT_DIR"
swift build -c release

[[ -f "$BUILD_DIR/$EXECUTABLE_NAME" ]] || die "Build output missing: $BUILD_DIR/$EXECUTABLE_NAME"

log "Preparing output directory: $DIST_DIR"
mkdir -p "$DIST_DIR"
rm -rf "$APP_BUNDLE_PATH" "$DMG_STAGING_PATH" "$DMG_PATH" "$APP_ZIP_PATH"
mkdir -p "$APP_BUNDLE_PATH/Contents/MacOS" "$APP_BUNDLE_PATH/Contents/Resources"

cp "$BUILD_DIR/$EXECUTABLE_NAME" "$EXECUTABLE_PATH"
cp "$ICON_SOURCE" "$APP_BUNDLE_PATH/Contents/Resources/AppIcon.icns"

if [[ -d "$RESOURCE_BUNDLE_PATH" ]]; then
  cp -R "$RESOURCE_BUNDLE_PATH" "$APP_BUNDLE_PATH/Contents/Resources/"
fi

cat > "$INFO_PLIST_PATH" <<PLIST
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

log "Signing app bundle with Developer ID identity"
codesign --force --sign "$IDENTITY" --options runtime --timestamp --entitlements "$ENTITLEMENTS_PATH" "$EXECUTABLE_PATH"
codesign --force --sign "$IDENTITY" --options runtime --timestamp --entitlements "$ENTITLEMENTS_PATH" "$APP_BUNDLE_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE_PATH"

if [[ "$SKIP_NOTARIZE" == false ]]; then
  log "Creating zip for app notarization submission"
  ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE_PATH" "$APP_ZIP_PATH"

  log "Submitting app zip for notarization"
  xcrun notarytool submit "$APP_ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

  log "Stapling app bundle"
  xcrun stapler staple "$APP_BUNDLE_PATH"
fi

log "Creating DMG staging content"
mkdir -p "$DMG_STAGING_PATH"
cp -R "$APP_BUNDLE_PATH" "$DMG_STAGING_PATH/"
ln -s /Applications "$DMG_STAGING_PATH/Applications"

log "Creating compressed DMG"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$DMG_STAGING_PATH" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

log "Signing DMG"
codesign --force --sign "$IDENTITY" --timestamp "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

if [[ "$SKIP_NOTARIZE" == false ]]; then
  log "Submitting DMG for notarization"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

  log "Stapling DMG"
  xcrun stapler staple "$DMG_PATH"

  log "Validating Gatekeeper assessment"
  spctl -a -t open --context context:primary-signature -vv "$DMG_PATH"
fi

log "Release artifact ready:"
echo "$DMG_PATH"
