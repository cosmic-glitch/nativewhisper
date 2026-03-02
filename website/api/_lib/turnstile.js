import { jsonError } from "./http.js";

export async function verifyTurnstile({ enforced, secretKey, token, ip }) {
  if (!enforced) {
    return { ok: true };
  }

  if (!token) {
    return {
      ok: false,
      response: jsonError(400, "turnstile_required", "Turnstile token is required."),
    };
  }

  const body = new URLSearchParams();
  body.set("secret", secretKey);
  body.set("response", token);
  if (ip) {
    body.set("remoteip", ip);
  }

  let verification;
  try {
    verification = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body,
    });
  } catch (error) {
    return {
      ok: false,
      response: jsonError(503, "turnstile_unavailable", "Turnstile verification failed.", {
        reason: String(error?.message ?? error),
      }),
    };
  }

  let payload = null;
  try {
    payload = await verification.json();
  } catch {
    payload = null;
  }

  if (!verification.ok || !payload?.success) {
    return {
      ok: false,
      response: jsonError(400, "turnstile_failed", "Human verification failed."),
    };
  }

  return { ok: true };
}
