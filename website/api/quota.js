import { loadConfig } from "./_lib/env.js";
import { json, jsonError, readBearerToken, requireMethod, sanitizeDeviceID } from "./_lib/http.js";
import { getBudgetState, getDevice, getUserForAccessToken, upsertBudgetState, upsertDevice } from "./_lib/supabase.js";
import { budgetStateLabel, ensureDayDeviceState, remainingDeviceCount, resetAtUTC, utcDayBucket } from "./_lib/usage.js";

export const config = {
  runtime: "edge",
};

export default async function handler(request) {
  const methodError = requireMethod(request, "GET");
  if (methodError) {
    return methodError;
  }

  let cfg;
  try {
    cfg = loadConfig();
  } catch (error) {
    return jsonError(500, "server_config_error", String(error?.message ?? error));
  }

  const accessToken = readBearerToken(request);
  if (!accessToken) {
    return jsonError(401, "missing_token", "Missing bearer access token.");
  }

  let user;
  try {
    user = await getUserForAccessToken(cfg, accessToken);
  } catch (error) {
    return jsonError(error.status ?? 401, "invalid_token", "Invalid or expired access token.", {
      supabase: error.payload ?? null,
      message: String(error.message ?? error),
    });
  }

  const requestURL = new URL(request.url);
  const deviceID = sanitizeDeviceID(requestURL.searchParams.get("deviceId") ?? request.headers.get("x-device-id"));

  const dayBucket = utcDayBucket();
  const nowISO = new Date().toISOString();

  let device = null;
  try {
    device = await getDevice(cfg, user.id, deviceID);

    const currentState = ensureDayDeviceState(device, dayBucket);
    if (!device || device.day_bucket !== dayBucket) {
      device = await upsertDevice(cfg, {
        ...(device ?? {}),
        user_id: user.id,
        device_id: deviceID,
        created_at: device?.created_at ?? nowISO,
        last_seen_at: nowISO,
        daily_transcription_count: currentState.daily_transcription_count,
        daily_audio_ms: currentState.daily_audio_ms,
        daily_estimated_usd: currentState.daily_estimated_usd,
        day_bucket: dayBucket,
      });
    }
  } catch (error) {
    return jsonError(error.status ?? 500, "quota_device_failed", "Failed to load device quota state.", {
      supabase: error.payload ?? null,
      message: String(error.message ?? error),
    });
  }

  let budget = null;
  try {
    budget = await getBudgetState(cfg, dayBucket);

    if (!budget) {
      budget = await upsertBudgetState(cfg, {
        day_bucket: dayBucket,
        estimated_usd_total: 0,
        hard_stop_triggered: false,
        updated_at: nowISO,
      });
    }
  } catch (error) {
    return jsonError(error.status ?? 500, "quota_budget_failed", "Failed to load global budget state.", {
      supabase: error.payload ?? null,
      message: String(error.message ?? error),
    });
  }

  const remainingToday = remainingDeviceCount(device ?? { daily_transcription_count: 0 }, cfg.deviceDailyTranscriptionCap);

  return json({
    remainingToday,
    deviceCap: cfg.deviceDailyTranscriptionCap,
    globalBudgetState: budgetStateLabel(Boolean(budget?.hard_stop_triggered)),
    resetAt: resetAtUTC(),
  });
}
