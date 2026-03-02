import { loadConfig } from "../_lib/env.js";
import { json, jsonError, getClientIP, normalizeEmail, parseJSONRequest, requireMethod, sanitizeDeviceID } from "../_lib/http.js";
import { checkRateLimit } from "../_lib/rate-limit.js";
import { startOTP } from "../_lib/supabase.js";
import { verifyTurnstile } from "../_lib/turnstile.js";

export const config = {
  runtime: "edge",
};

function extractUpstreamMessage(payload) {
  if (!payload || typeof payload !== "object") {
    return "";
  }

  const messageCandidates = [
    payload.msg,
    payload.message,
    payload.error_description,
    payload.error,
    payload?.raw,
  ];

  for (const candidate of messageCandidates) {
    const value = String(candidate ?? "").trim();
    if (value) {
      return value;
    }
  }

  return "";
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
  const turnstileToken = String(body.turnstileToken ?? "").trim();
  const deviceID = sanitizeDeviceID(body.deviceId);

  if (!email || !email.includes("@")) {
    return jsonError(400, "invalid_email", "A valid email is required.");
  }

  if (!deviceID || deviceID === "unknown-device") {
    return jsonError(400, "invalid_device", "A device ID is required.");
  }

  let cfg;
  try {
    cfg = loadConfig();
  } catch (error) {
    return jsonError(500, "server_config_error", String(error?.message ?? error));
  }

  const ip = getClientIP(request);

  const turnstile = await verifyTurnstile({
    enforced: cfg.turnstileEnforced,
    secretKey: cfg.turnstileSecret,
    token: turnstileToken,
    ip,
  });

  if (!turnstile.ok) {
    return turnstile.response;
  }

  const ipLimit = checkRateLimit(`otp:ip:${ip}`, cfg.otpIPLimit, cfg.otpIPWindowSeconds);
  if (!ipLimit.allowed) {
    return jsonError(429, "otp_rate_limited_ip", "Too many code requests. Please wait a few minutes and try again.");
  }

  const emailLimit = checkRateLimit(`otp:email:${email}`, cfg.otpEmailLimit, cfg.otpEmailWindowSeconds);
  if (!emailLimit.allowed) {
    return jsonError(429, "otp_rate_limited_email", "Too many code requests for this email. Please wait a few minutes and try again.");
  }

  try {
    await startOTP(cfg, email);
    return json({ ok: true });
  } catch (error) {
    const upstreamMessage = extractUpstreamMessage(error.payload);
    let userMessage = "Failed to send sign-in code.";

    if ((error.status ?? 500) === 429) {
      userMessage = "Please wait about a minute, then tap Send code again.";
    } else if (upstreamMessage) {
      userMessage = upstreamMessage;
    }

    return jsonError(error.status ?? 500, "otp_send_failed", userMessage, {
      supabase: error.payload ?? null,
      message: upstreamMessage || String(error.message ?? error),
    });
  }
}
