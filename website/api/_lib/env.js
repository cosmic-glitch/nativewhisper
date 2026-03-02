const TRUE_VALUES = new Set(["1", "true", "yes", "on"]);

function env(name, fallback = "") {
  const value = process.env[name];
  if (typeof value === "string") {
    return value.trim();
  }
  return fallback;
}

function requiredEnv(name) {
  const value = env(name);
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function envBool(name, fallback = false) {
  const value = env(name);
  if (!value) {
    return fallback;
  }
  return TRUE_VALUES.has(value.toLowerCase());
}

function envNumber(name, fallback) {
  const value = env(name);
  if (!value) {
    return fallback;
  }

  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    return fallback;
  }

  return parsed;
}

export function loadConfig() {
  const turnstileSecret = env("TURNSTILE_SECRET_KEY");
  const turnstileEnforced = envBool("TURNSTILE_ENFORCE", true) && turnstileSecret.length > 0;

  return {
    appTranscriptionEnabled: envBool("APP_TRANSCRIPTION_ENABLED", true),
    backendBaseURL: env("BACKEND_BASE_URL"),
    openAIAPIKey: requiredEnv("OPENAI_API_KEY"),
    supabaseURL: requiredEnv("SUPABASE_URL"),
    supabaseAnonKey: requiredEnv("SUPABASE_ANON_KEY"),
    supabaseServiceRoleKey: requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
    turnstileSecret,
    turnstileEnforced,
    deviceDailyTranscriptionCap: Math.max(1, Math.floor(envNumber("DEVICE_DAILY_TRANSCRIPTION_CAP", 100))),
    maxUploadBytes: Math.max(256_000, Math.floor(envNumber("MAX_UPLOAD_BYTES", 15 * 1024 * 1024))),
    globalDailyEstimatedUSDCap: Math.max(0.01, envNumber("GLOBAL_DAILY_ESTIMATED_USD_CAP", 10)),
    estimatedUSDPerAudioMinute: Math.max(0.0001, envNumber("ESTIMATED_USD_PER_AUDIO_MINUTE", 0.006)),
    otpIPWindowSeconds: Math.max(30, Math.floor(envNumber("OTP_IP_WINDOW_SECONDS", 600))),
    otpIPLimit: Math.max(1, Math.floor(envNumber("OTP_IP_LIMIT", 10))),
    otpEmailWindowSeconds: Math.max(30, Math.floor(envNumber("OTP_EMAIL_WINDOW_SECONDS", 600))),
    otpEmailLimit: Math.max(1, Math.floor(envNumber("OTP_EMAIL_LIMIT", 5))),
    txIPWindowSeconds: Math.max(5, Math.floor(envNumber("TX_IP_WINDOW_SECONDS", 60))),
    txIPLimit: Math.max(1, Math.floor(envNumber("TX_IP_LIMIT", 40))),
    txUserWindowSeconds: Math.max(5, Math.floor(envNumber("TX_USER_WINDOW_SECONDS", 60))),
    txUserLimit: Math.max(1, Math.floor(envNumber("TX_USER_LIMIT", 25))),
    txDeviceWindowSeconds: Math.max(5, Math.floor(envNumber("TX_DEVICE_WINDOW_SECONDS", 60))),
    txDeviceLimit: Math.max(1, Math.floor(envNumber("TX_DEVICE_LIMIT", 25))),
  };
}
