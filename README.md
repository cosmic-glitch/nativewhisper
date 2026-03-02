# Whisper Anywhere

Whisper Anywhere is a native macOS push-to-talk dictation app.
Hold `Fn` to record, release `Fn` to transcribe, and text is inserted at the active cursor.

## What users get

- Fn hold-to-talk across macOS apps
- On-device recording with immediate upload on release
- OpenAI Whisper transcription (`whisper-1`, English only)
- Direct text insertion with clipboard fallback when no cursor is focused
- Menu bar UX with recording/transcribing HUD and permission guidance

## Hosted-key mode (current default)

The app now uses backend-hosted OpenAI credentials by default.
Users sign in with email OTP and do not enter their own OpenAI key.

Data behavior in hosted mode:

- Audio and transcript content are not persisted in app or backend storage
- Backend keeps usage metadata (counts/duration/estimated cost) for limits and budget control
- Backend proxies requests to OpenAI Transcriptions API

## Requirements

- macOS 14+
- Microphone permission
- Accessibility permission
- Input Monitoring permission
- Hosted backend URL (`BACKEND_BASE_URL`) reachable from the app

## App local environment

Create `.env` in repo root (or export these variables before launch):

```bash
WHISPER_ANYWHERE_HOSTED_MODE=true
BACKEND_BASE_URL=https://native-whisper.vercel.app
ALLOW_LEGACY_PERSONAL_KEY_ENTRY=false
```

Optional fallback for one-release compatibility:

```bash
# Only used when WHISPER_ANYWHERE_HOSTED_MODE=false
OPENAI_API_KEY=your_key_here
```

## Install and run app

```bash
./scripts/install_app.sh
```

This builds and installs `/Applications/Whisper Anywhere.app`, terminates any running instance, and relaunches the latest build.

## Backend (Vercel + Supabase)

API routes are implemented under `website/api`:

- `POST /api/auth/start`
- `POST /api/auth/verify`
- `POST /api/auth/refresh`
- `POST /api/transcribe`
- `GET /api/quota`

Configure these Vercel environment variables:

- `OPENAI_API_KEY`
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `TURNSTILE_SECRET_KEY`
- `TURNSTILE_ENFORCE`
- `APP_TRANSCRIPTION_ENABLED`
- `DEVICE_DAILY_TRANSCRIPTION_CAP`
- `MAX_UPLOAD_BYTES`
- `GLOBAL_DAILY_ESTIMATED_USD_CAP`
- `ESTIMATED_USD_PER_AUDIO_MINUTE`
- `OTP_IP_WINDOW_SECONDS`
- `OTP_IP_LIMIT`
- `OTP_EMAIL_WINDOW_SECONDS`
- `OTP_EMAIL_LIMIT`
- `TX_IP_WINDOW_SECONDS`
- `TX_IP_LIMIT`
- `TX_USER_WINDOW_SECONDS`
- `TX_USER_LIMIT`
- `TX_DEVICE_WINDOW_SECONDS`
- `TX_DEVICE_LIMIT`

Supabase tables expected by backend:

- `profiles`
- `devices` (unique `(user_id, device_id)`)
- `usage_ledger`
- `budget_state`

Bootstrap SQL is provided at [`website/supabase-schema.sql`](website/supabase-schema.sql).

## Test

```bash
swift test
```
