# NativeWhisper v1

Minimal macOS 14+ menu bar dictation app with strict Fn hold-to-talk behavior:

- Hold `Fn` to start recording
- Start chime plays once recording begins
- Floating recording HUD appears at bottom-center with a live 5-bar mic equalizer
- Release `Fn` to stop and transcribe with OpenAI `whisper-1` (`language=en`)
- Insert transcript into focused text field
- If no editable field is focused, copy transcript to clipboard and notify

## Requirements

- macOS 14+
- OpenAI API key in `OPENAI_API_KEY`
- Microphone, Accessibility, and Input Monitoring permissions

## Run

```bash
export OPENAI_API_KEY="your_key_here"
swift run NativeWhisper
```

## Install As App

```bash
cd nativewhisper
./scripts/install_app.sh
```

This builds a signed app bundle, installs it into `/Applications/NativeWhisper.app`,
copies the custom `AppIcon.icns`, loads `OPENAI_API_KEY` from `.env` into `launchctl`
if present, and launches the app.

If permissions appear as denied after an update even though the app is listed in System
Settings, toggle the permission off/on for NativeWhisper and relaunch the app.

## Tests

```bash
swift test
```

`swift test` currently requires a full Xcode installation on this machine because the active
Command Line Tools environment does not provide the `XCTest` module. Once Xcode is installed
and selected via `xcode-select`, tests should run normally.

## Notes

- This environment lacked full Xcode (`xcodebuild` unavailable), so a generated `.xcodeproj` was not produced.
- Open `Package.swift` in Xcode to run/debug as a native app.
