import { loadConfig } from "../_lib/env.js";
import { json, jsonError, parseJSONRequest, requireMethod } from "../_lib/http.js";
import { refreshSession } from "../_lib/supabase.js";

export const config = {
  runtime: "edge",
};

export default async function handler(request) {
  const methodError = requireMethod(request, "POST");
  if (methodError) {
    return methodError;
  }

  const body = await parseJSONRequest(request);
  if (!body) {
    return jsonError(400, "invalid_json", "Request body must be valid JSON.");
  }

  const refreshToken = String(body.refreshToken ?? "").trim();
  if (!refreshToken) {
    return jsonError(400, "missing_refresh_token", "refreshToken is required.");
  }

  let cfg;
  try {
    cfg = loadConfig();
  } catch (error) {
    return jsonError(500, "server_config_error", String(error?.message ?? error));
  }

  let session;
  try {
    session = await refreshSession(cfg, refreshToken);
  } catch (error) {
    return jsonError(error.status ?? 401, "refresh_failed", "Failed to refresh session.", {
      supabase: error.payload ?? null,
      message: String(error.message ?? error),
    });
  }

  const user = session?.user;

  return json({
    accessToken: session.access_token,
    refreshToken: session.refresh_token,
    expiresAt: session.expires_at,
    user: {
      id: user?.id ?? "",
      email: user?.email ?? "",
    },
  });
}
