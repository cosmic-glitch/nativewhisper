# Whisper Anywhere

macOS menu bar app for system-wide dictation using OpenAI Whisper. Built with Swift Package Manager.

## Build & Test

```bash
swift build              # Debug build
swift build -c release   # Release build
swift test               # Run all tests
```

## Release

### Mandatory Release Rule

For any change to app/runtime code, do a full release pipeline before push.

#### Trigger paths
- `WhisperAnywhere/**`
- `WhisperAnywhereTests/**`
- `Package.swift`

### Rebuild Semantics (Signed Release)

When asked to "rebuild" or "release", treat it as a full signed release:

1. Run `./scripts/release_dmg.sh` (uses Developer ID identity and notary profile defaulted in the script; override with `--identity`/`DEVELOPER_IDENTITY` or `--notary-profile`/`NOTARY_PROFILE`).
2. Pass explicit `--version` and `--build-number` when available, otherwise let them auto-detect from git tags/date.
3. Do **not** use `--skip-notarize` unless explicitly requested.
4. Ensure both artifacts are produced in `dist/`:
   - `Whisper-Anywhere-<version>.dmg` (signed + notarized + stapled)
   - `Whisper Anywhere-<version>.zip` (notarization submission bundle)
5. Copy the new versioned DMG to `website/downloads/`.
6. Update website download links to the new versioned DMG.

### Do not push if
- Only one DMG path was updated
- DMG hashes do not match

### Scripts

- `scripts/release_dmg.sh` — Builds a **signed + notarized** DMG for production distribution. The real release script.
- `scripts/full_release.sh` — Runs tests, builds an **unsigned** DMG, copies it to `website/downloads/`. Used for CI/website deploy.
- `scripts/build_unsigned_dmg.sh` — Builds an ad-hoc signed DMG (no Developer ID). Called by `full_release.sh`.
- `scripts/install_app.sh` — Local install helper.

## Project Structure

- `WhisperAnywhere/` — Main app source (Swift)
- `Tests/WhisperAnywhereTests/` — Test suite
- `website/` — Project website, downloads served from `website/downloads/`
- `dist/` — Build output directory (gitignored)
- `Package.swift` — SPM manifest
