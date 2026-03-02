import { loadConfig } from "../../_lib/env.js";
import { json, jsonError, parseJSONRequest, readBearerToken, requireMethod, sanitizeDeviceID } from "../../_lib/http.js";
import { getDevice, getUserForAccessToken, upsertDevice, upsertProfile } from "../../_lib/supabase.js";
import { utcDayBucket } from "../../_lib/usage.js";

export const config = {
  runtime: "edge",
};

export default async function handler(request) {
  const methodError = requireMethod(request, "POST");
  if (methodError) {
    return methodError;
  }

  const accessToken = readBearerToken(request);
  if (!accessToken) {
    return jsonError(401, "missing_token", "Missing bearer access token.");
  }

  const body = await parseJSONRequest(request);
  if (!body) {
    return jsonError(400, "invalid_json", "Request body must be valid JSON.");
  }

  const deviceID = sanitizeDeviceID(body.deviceId);
  if (!deviceID || deviceID === "unknown-device") {
    return jsonError(400, "invalid_device", "A device ID is required.");
  }

  let cfg;
  try {
    cfg = loadConfig();
  } catch (error) {
    return jsonError(500, "server_config_error", String(error?.message ?? error));
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

  const nowISO = new Date().toISOString();
  const dayBucket = utcDayBucket();

  try {
    await upsertProfile(cfg, {
      id: user.id,
      email: user.email ?? "",
      created_at: user.created_at ?? nowISO,
      last_seen_at: nowISO,
      status: "active",
    });

    const existingDevice = await getDevice(cfg, user.id, deviceID);
    if (!existingDevice) {
      await upsertDevice(cfg, {
        user_id: user.id,
        device_id: deviceID,
        created_at: nowISO,
        last_seen_at: nowISO,
        daily_transcription_count: 0,
        daily_audio_ms: 0,
        daily_estimated_usd: 0,
        day_bucket: dayBucket,
      });
    } else if (existingDevice.day_bucket !== dayBucket) {
      await upsertDevice(cfg, {
        ...existingDevice,
        day_bucket: dayBucket,
        daily_transcription_count: 0,
        daily_audio_ms: 0,
        daily_estimated_usd: 0,
        last_seen_at: nowISO,
      });
    } else {
      await upsertDevice(cfg, {
        ...existingDevice,
        last_seen_at: nowISO,
      });
    }
  } catch (error) {
    return jsonError(error.status ?? 500, "profile_sync_failed", "Google sign-in succeeded, but account sync failed.", {
      supabase: error.payload ?? null,
      message: String(error.message ?? error),
    });
  }

  return json({
    user: {
      id: user.id,
      email: user.email ?? "",
    },
  });
}
