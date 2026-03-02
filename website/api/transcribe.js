import { loadConfig } from "./_lib/env.js";
import { getClientIP, json, jsonError, readBearerToken, requireMethod, sanitizeDeviceID } from "./_lib/http.js";
import { checkRateLimit } from "./_lib/rate-limit.js";
import {
  getBudgetState,
  getDevice,
  getUserForAccessToken,
  insertUsageLedger,
  patchDevice,
  upsertBudgetState,
  upsertDevice,
  upsertProfile,
} from "./_lib/supabase.js";
import {
  asNumber,
  budgetStateLabel,
  ensureDayDeviceState,
  estimateUSDCost,
  remainingDeviceCount,
  resetAtUTC,
  utcDayBucket,
} from "./_lib/usage.js";

export const config = {
  runtime: "edge",
};

function buildMultipartForOpenAI(file) {
  const form = new FormData();
  form.append("model", "whisper-1");
  form.append("language", "en");
  form.append("response_format", "json");
  form.append("temperature", "0");
  form.append("file", file, file.name || "recording.m4a");
  return form;
}

function normalizedTranscript(payload) {
  const text = String(payload?.text ?? "").trim();
  if (!text) {
    return null;
  }
  return text;
}

async function safeLedgerInsert(cfg, row) {
  try {
    await insertUsageLedger(cfg, row);
  } catch {
    // Best-effort usage logging only.
  }
}

export default async function handler(request) {
  const methodError = requireMethod(request, "POST");
  if (methodError) {
    return methodError;
  }

  let cfg;
  try {
    cfg = loadConfig();
  } catch (error) {
    return jsonError(500, "server_config_error", String(error?.message ?? error));
  }

  if (!cfg.appTranscriptionEnabled) {
    return jsonError(503, "service_paused", "Transcription service is temporarily paused.");
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

  const ip = getClientIP(request);

  const ipLimit = checkRateLimit(`tx:ip:${ip}`, cfg.txIPLimit, cfg.txIPWindowSeconds);
  if (!ipLimit.allowed) {
    return jsonError(429, "transcription_rate_limited_ip", "Too many transcription requests from this IP.");
  }

  const userLimit = checkRateLimit(`tx:user:${user.id}`, cfg.txUserLimit, cfg.txUserWindowSeconds);
  if (!userLimit.allowed) {
    return jsonError(429, "transcription_rate_limited_user", "Too many transcription requests for this account.");
  }

  let formData;
  try {
    formData = await request.formData();
  } catch {
    return jsonError(400, "invalid_form_data", "Expected multipart/form-data request body.");
  }

  const rawFile = formData.get("file");
  if (!rawFile || typeof rawFile.arrayBuffer !== "function") {
    return jsonError(400, "missing_file", "Audio file is required.");
  }

  const file = rawFile;
  if (asNumber(file.size, 0) <= 0) {
    return jsonError(400, "empty_file", "Audio file is empty.");
  }

  if (asNumber(file.size, 0) > cfg.maxUploadBytes) {
    return jsonError(413, "file_too_large", `Audio file exceeds ${cfg.maxUploadBytes} bytes.`);
  }

  const language = String(formData.get("language") ?? "en").trim().toLowerCase();
  if (language && language !== "en") {
    return jsonError(400, "unsupported_language", "Only English transcription is supported.");
  }

  const deviceID = sanitizeDeviceID(formData.get("deviceId") ?? request.headers.get("x-device-id"));
  const durationMs = Math.max(0, Math.floor(asNumber(formData.get("durationMs"), 0)));
  const clientVersion = String(formData.get("clientVersion") ?? "unknown").trim().slice(0, 64);
  const requestID = crypto.randomUUID();
  const nowISO = new Date().toISOString();
  const dayBucket = utcDayBucket();

  const deviceLimit = checkRateLimit(`tx:device:${deviceID}`, cfg.txDeviceLimit, cfg.txDeviceWindowSeconds);
  if (!deviceLimit.allowed) {
    await safeLedgerInsert(cfg, {
      user_id: user.id,
      device_id: deviceID,
      request_id: requestID,
      audio_ms: durationMs,
      estimated_usd: 0,
      created_at: nowISO,
      status: "blocked_quota",
    });
    return jsonError(429, "transcription_rate_limited_device", "Too many transcription requests for this device.");
  }

  try {
    await upsertProfile(cfg, {
      id: user.id,
      email: user.email ?? "",
      last_seen_at: nowISO,
      status: "active",
    });
  } catch {
    // Do not block transcription if profile update fails.
  }

  let device = null;
  let budget = null;

  try {
    device = await getDevice(cfg, user.id, deviceID);

    const normalizedDeviceState = ensureDayDeviceState(device, dayBucket);

    if (!device) {
      device = await upsertDevice(cfg, {
        user_id: user.id,
        device_id: deviceID,
        created_at: nowISO,
        last_seen_at: nowISO,
        daily_transcription_count: normalizedDeviceState.daily_transcription_count,
        daily_audio_ms: normalizedDeviceState.daily_audio_ms,
        daily_estimated_usd: normalizedDeviceState.daily_estimated_usd,
        day_bucket: normalizedDeviceState.day_bucket,
      });
    } else if (device.day_bucket !== dayBucket) {
      device = await patchDevice(cfg, user.id, deviceID, {
        day_bucket: dayBucket,
        daily_transcription_count: 0,
        daily_audio_ms: 0,
        daily_estimated_usd: 0,
        last_seen_at: nowISO,
      });
    }

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
    await safeLedgerInsert(cfg, {
      user_id: user.id,
      device_id: deviceID,
      request_id: requestID,
      audio_ms: durationMs,
      estimated_usd: 0,
      created_at: nowISO,
      status: "error",
    });

    return jsonError(error.status ?? 500, "usage_state_failed", "Failed to load usage state.", {
      supabase: error.payload ?? null,
      message: String(error.message ?? error),
    });
  }

  const normalizedDeviceState = ensureDayDeviceState(device, dayBucket);
  const dailyCount = normalizedDeviceState.daily_transcription_count;

  if (dailyCount >= cfg.deviceDailyTranscriptionCap) {
    await safeLedgerInsert(cfg, {
      user_id: user.id,
      device_id: deviceID,
      request_id: requestID,
      audio_ms: durationMs,
      estimated_usd: 0,
      created_at: nowISO,
      status: "blocked_quota",
    });

    return jsonError(429, "device_quota_reached", "Daily device transcription limit reached.", {
      deviceCap: cfg.deviceDailyTranscriptionCap,
      remainingToday: 0,
    });
  }

  const estimatedTotal = asNumber(budget?.estimated_usd_total, 0);
  const hardStop = Boolean(budget?.hard_stop_triggered) || estimatedTotal >= cfg.globalDailyEstimatedUSDCap;

  if (hardStop) {
    await upsertBudgetState(cfg, {
      day_bucket: dayBucket,
      estimated_usd_total: estimatedTotal,
      hard_stop_triggered: true,
      updated_at: nowISO,
    });

    await safeLedgerInsert(cfg, {
      user_id: user.id,
      device_id: deviceID,
      request_id: requestID,
      audio_ms: durationMs,
      estimated_usd: 0,
      created_at: nowISO,
      status: "blocked_budget",
    });

    return jsonError(503, "global_budget_reached", "Service paused because the daily budget has been reached.");
  }

  let openAIResponse;
  let openAIPayload;

  try {
    openAIResponse = await fetch("https://api.openai.com/v1/audio/transcriptions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${cfg.openAIAPIKey}`,
      },
      body: buildMultipartForOpenAI(file),
    });

    openAIPayload = await openAIResponse.json();
  } catch (error) {
    await safeLedgerInsert(cfg, {
      user_id: user.id,
      device_id: deviceID,
      request_id: requestID,
      audio_ms: durationMs,
      estimated_usd: 0,
      created_at: nowISO,
      status: "error",
    });

    return jsonError(503, "openai_unavailable", "OpenAI transcription request failed.", {
      message: String(error.message ?? error),
    });
  }

  if (!openAIResponse.ok) {
    await safeLedgerInsert(cfg, {
      user_id: user.id,
      device_id: deviceID,
      request_id: requestID,
      audio_ms: durationMs,
      estimated_usd: 0,
      created_at: nowISO,
      status: "error",
    });

    return jsonError(openAIResponse.status, "openai_error", "OpenAI transcription failed.", {
      upstream: openAIPayload,
    });
  }

  const transcript = normalizedTranscript(openAIPayload);
  if (!transcript) {
    await safeLedgerInsert(cfg, {
      user_id: user.id,
      device_id: deviceID,
      request_id: requestID,
      audio_ms: durationMs,
      estimated_usd: 0,
      created_at: nowISO,
      status: "error",
    });

    return jsonError(502, "empty_transcript", "OpenAI returned an empty transcript.");
  }

  const estimatedUSD = estimateUSDCost(durationMs, cfg.estimatedUSDPerAudioMinute);
  const newDeviceCount = dailyCount + 1;
  const newDeviceAudioMs = normalizedDeviceState.daily_audio_ms + durationMs;
  const newDeviceEstimatedUSD = Number((normalizedDeviceState.daily_estimated_usd + estimatedUSD).toFixed(6));
  const newGlobalEstimatedUSD = Number((estimatedTotal + estimatedUSD).toFixed(6));
  const shouldStopNow = newGlobalEstimatedUSD >= cfg.globalDailyEstimatedUSDCap;

  try {
    await patchDevice(cfg, user.id, deviceID, {
      day_bucket: dayBucket,
      daily_transcription_count: newDeviceCount,
      daily_audio_ms: newDeviceAudioMs,
      daily_estimated_usd: newDeviceEstimatedUSD,
      last_seen_at: nowISO,
    });

    await upsertBudgetState(cfg, {
      day_bucket: dayBucket,
      estimated_usd_total: newGlobalEstimatedUSD,
      hard_stop_triggered: shouldStopNow,
      updated_at: nowISO,
    });

    await safeLedgerInsert(cfg, {
      user_id: user.id,
      device_id: deviceID,
      request_id: requestID,
      audio_ms: durationMs,
      estimated_usd: estimatedUSD,
      created_at: nowISO,
      status: "accepted",
    });
  } catch (error) {
    return jsonError(error.status ?? 500, "usage_update_failed", "Transcription succeeded but usage accounting failed.", {
      message: String(error.message ?? error),
      supabase: error.payload ?? null,
    });
  }

  return json({
    text: transcript,
    remainingToday: remainingDeviceCount({ daily_transcription_count: newDeviceCount }, cfg.deviceDailyTranscriptionCap),
    deviceCap: cfg.deviceDailyTranscriptionCap,
    globalBudgetState: budgetStateLabel(shouldStopNow),
    resetAt: resetAtUTC(),
    metadata: {
      requestId: requestID,
      estimatedUSD,
      durationMs,
      clientVersion,
    },
  });
}
