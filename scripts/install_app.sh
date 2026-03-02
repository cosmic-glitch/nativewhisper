#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Whisper Anywhere.app"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_PATH="$ROOT_DIR/$APP_NAME"
INSTALL_PATH="/Applications/$APP_NAME"
LEGACY_INSTALL_PATH="/Applications/NativeWhisper.app"
ICON_SOURCE="$ROOT_DIR/NativeWhisper/Resources/AppIcon.icns"

cd "$ROOT_DIR"

terminate_running_app() {
  if pgrep -x "NativeWhisper" >/dev/null 2>&1; then
    echo "Stopping running Whisper Anywhere process..."
    pkill -x "NativeWhisper" || true

    for _ in {1..20}; do
      if ! pgrep -x "NativeWhisper" >/dev/null 2>&1; then
        return
      fi
      sleep 0.1
    done

    echo "Force stopping Whisper Anywhere process..."
    pkill -9 -x "NativeWhisper" || true
  fi
}

swift build -c release

terminate_running_app

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BUILD_DIR/NativeWhisper" "$APP_PATH/Contents/MacOS/"
cp "$ICON_SOURCE" "$APP_PATH/Contents/Resources/AppIcon.icns"

cat > "$APP_PATH/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>NativeWhisper</string>
  <key>CFBundleIdentifier</key><string>ai.whisperanywhere.app</string>
  <key>CFBundleName</key><string>Whisper Anywhere</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.2.2</string>
  <key>CFBundleVersion</key><string>4</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
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

# Keep a stable designated requirement across ad-hoc rebuilds so TCC grants are less likely
# to be invalidated after updates.
codesign --force --deep --sign - -r='designated => identifier "ai.whisperanywhere.app"' "$APP_PATH"
rm -rf "$LEGACY_INSTALL_PATH"
rm -rf "$INSTALL_PATH"
cp -R "$APP_PATH" "$INSTALL_PATH"
xattr -dr com.apple.quarantine "$INSTALL_PATH"

if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a
  source "$ROOT_DIR/.env"
  set +a
  if [[ -n "${OPENAI_API_KEY:-}" ]]; then
    launchctl setenv OPENAI_API_KEY "$OPENAI_API_KEY"
  fi
fi

open -g "$INSTALL_PATH"
echo "Installed and launched $INSTALL_PATH"
