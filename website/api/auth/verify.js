import { loadConfig } from "../_lib/env.js";
import { json, jsonError, normalizeEmail, parseJSONRequest, requireMethod, sanitizeDeviceID } from "../_lib/http.js";
import { getDevice, upsertDevice, upsertProfile, verifyOTP } from "../_lib/supabase.js";
import { utcDayBucket } from "../_lib/usage.js";

export const config = {
  runtime: "edge",
};

function baseDeviceRow(userID, deviceID, dayBucket, nowISO) {
  return {
    user_id: userID,
    device_id: deviceID,
    created_at: nowISO,
    last_seen_at: nowISO,
    daily_transcription_count: 0,
    daily_audio_ms: 0,
    daily_estimated_usd: 0,
    day_bucket: dayBucket,
  };
}

export default async function handler(request) {
  const methodError = requireMethod(request, "POST");
  if (methodError) {
    return methodError;
  }

  const body = await parseJSONRequest(request);
  if (!body) {
    return jsonError(400, "invalid_json", "Request body must be valid JSON.");
  }

  const email = normalizeEmail(body.email);
  const otp = String(body.otp ?? "").trim();
  const deviceID = sanitizeDeviceID(body.deviceId);

  if (!email || !email.includes("@")) {
    return jsonError(400, "invalid_email", "A valid email is required.");
  }

  if (!otp || otp.length < 4) {
    return jsonError(400, "invalid_otp", "A valid OTP code is required.");
  }

  let cfg;
  try {
    cfg = loadConfig();
  } catch (error) {
    return jsonError(500, "server_config_error", String(error?.message ?? error));
  }

  let session;
  try {
    session = await verifyOTP(cfg, email, otp);
  } catch (error) {
    return jsonError(error.status ?? 401, "otp_verify_failed", "The verification code is invalid or expired.", {
      supabase: error.payload ?? null,
      message: String(error.message ?? error),
    });
  }

  const user = session?.user;
  if (!user?.id) {
    return jsonError(500, "session_missing_user", "Sign-in succeeded but user data is missing.");
  }

  const nowISO = new Date().toISOString();
  const dayBucket = utcDayBucket();

  try {
    await upsertProfile(cfg, {
      id: user.id,
      email,
      created_at: user.created_at ?? nowISO,
      last_seen_at: nowISO,
      status: "active",
    });

    const existingDevice = await getDevice(cfg, user.id, deviceID);
    if (!existingDevice) {
      await upsertDevice(cfg, baseDeviceRow(user.id, deviceID, dayBucket, nowISO));
    } else {
      await upsertDevice(cfg, {
        ...existingDevice,
        user_id: user.id,
        device_id: deviceID,
        last_seen_at: nowISO,
      });
    }
  } catch (error) {
    return jsonError(error.status ?? 500, "profile_sync_failed", "Signed in, but failed to update account metadata.", {
      supabase: error.payload ?? null,
      message: String(error.message ?? error),
    });
  }

  return json({
    accessToken: session.access_token,
    refreshToken: session.refresh_token,
    expiresAt: session.expires_at,
    user: {
      id: user.id,
      email: user.email ?? email,
    },
  });
}
