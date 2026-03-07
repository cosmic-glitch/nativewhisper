import { loadConfig } from "../_lib/env.js";
import { json, jsonError, readBearerToken, requireMethod } from "../_lib/http.js";
import { getUserForAccessToken } from "../_lib/supabase.js";

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

  let cfg;
  try {
    cfg = loadConfig();
  } catch (error) {
    return jsonError(500, "server_config_error", String(error?.message ?? error));
  }

  try {
    await getUserForAccessToken(cfg, accessToken);
  } catch (error) {
    return jsonError(error.status ?? 401, "invalid_token", "Invalid or expired access token.", {
      supabase: error.payload ?? null,
      message: String(error.message ?? error),
    });
  }

  return json({ apiKey: cfg.openAIAPIKey });
}
