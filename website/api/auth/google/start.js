import { loadConfig } from "../../_lib/env.js";
import { getClientIP, json, jsonError, parseJSONRequest, requireMethod, sanitizeDeviceID } from "../../_lib/http.js";
import { checkRateLimit } from "../../_lib/rate-limit.js";

export const config = {
  runtime: "edge",
};

function buildAuthorizeURL(cfg) {
  const url = new URL("/auth/v1/authorize", cfg.supabaseURL);
  url.searchParams.set("provider", "google");
  url.searchParams.set("redirect_to", cfg.googleAuthRedirectURI);
  url.searchParams.set("scopes", "email profile");
  url.searchParams.set("prompt", "select_account");
  return url.toString();
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

  const deviceID = sanitizeDeviceID(body.deviceId);
  if (!deviceID || deviceID === "unknown-device") {
    return jsonError(400, "invalid_device", "A device ID is required.");
  }

  const appVersion = String(body.appVersion ?? "").trim().slice(0, 64);
  if (!appVersion) {
    return jsonError(400, "invalid_app_version", "A valid appVersion is required.");
  }

  let cfg;
  try {
    cfg = loadConfig();
  } catch (error) {
    return jsonError(500, "server_config_error", String(error?.message ?? error));
  }

  const ip = getClientIP(request);
  const ipLimit = checkRateLimit(`oauth:start:ip:${ip}`, cfg.authStartIPLimit, cfg.authStartIPWindowSeconds);
  if (!ipLimit.allowed) {
    return jsonError(429, "auth_rate_limited_ip", "Too many sign-in attempts. Please wait a minute and try again.");
  }

  return json({
    authorizeURL: buildAuthorizeURL(cfg),
  });
}
