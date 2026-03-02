export function json(data, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      ...extraHeaders,
    },
  });
}

export function jsonError(status, code, message, details = undefined) {
  const body = {
    ok: false,
    error: {
      code,
      message,
    },
  };

  if (details !== undefined) {
    body.error.details = details;
  }

  return json(body, status);
}

export async function parseJSONRequest(request) {
  try {
    return await request.json();
  } catch {
    return null;
  }
}

export function requireMethod(request, method) {
  if (request.method !== method) {
    return jsonError(405, "method_not_allowed", `Expected ${method}.`);
  }

  return null;
}

export function getClientIP(request) {
  const forwardedFor = request.headers.get("x-forwarded-for");
  if (forwardedFor) {
    const first = forwardedFor.split(",")[0]?.trim();
    if (first) {
      return first;
    }
  }

  return request.headers.get("x-real-ip") ?? "unknown";
}

export function normalizeEmail(value) {
  return String(value ?? "").trim().toLowerCase();
}

export function sanitizeDeviceID(value) {
  const candidate = String(value ?? "").trim();
  if (!candidate) {
    return "unknown-device";
  }
  return candidate.slice(0, 128);
}

export function readBearerToken(request) {
  const authorization = request.headers.get("authorization") ?? "";
  const parts = authorization.split(" ");
  if (parts.length !== 2 || parts[0] !== "Bearer" || !parts[1]) {
    return null;
  }

  return parts[1].trim();
}
