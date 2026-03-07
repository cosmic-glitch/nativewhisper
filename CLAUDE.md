# Whisper Anywhere

macOS menu bar app for system-wide dictation using OpenAI Whisper. Built with Swift Package Manager.

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

### Versioning

Current series: **1.3.x**. Auto-increment patch for each release (1.3.0, 1.3.1, 1.3.2, …). Do not bump to 1.4.x unless explicitly asked. Check `website/downloads/` for the latest released version to determine the next patch number.
3. Do **not** use `--skip-notarize` unless explicitly requested.
4. Ensure both artifacts are produced in `dist/`:
   - `Whisper-Anywhere-<version>.dmg` (signed + notarized + stapled)
   - `Whisper Anywhere-<version>.zip` (notarization submission bundle)
5. Copy the new versioned DMG to `website/downloads/`.
6. Update website download links to the new versioned DMG.

### Do not push if
- Only one DMG path was updated
- DMG hashes do not match

