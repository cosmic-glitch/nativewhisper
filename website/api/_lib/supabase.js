function makeURL(baseURL, path, query = undefined) {
  const url = new URL(path, baseURL.endsWith("/") ? baseURL : `${baseURL}/`);
  if (query) {
    for (const [key, value] of Object.entries(query)) {
      if (value !== undefined && value !== null) {
        url.searchParams.set(key, String(value));
      }
    }
  }
  return url;
}

async function parseJSONResponse(response) {
  const text = await response.text();
  if (!text) {
    return null;
  }

  try {
    return JSON.parse(text);
  } catch {
    return {
      raw: text,
    };
  }
}

async function supabaseFetch(url, init) {
  const response = await fetch(url, init);
  const payload = await parseJSONResponse(response);

  if (!response.ok) {
    const message = payload?.msg || payload?.message || payload?.error_description || payload?.error || "Supabase request failed.";
    const error = new Error(message);
    error.status = response.status;
    error.payload = payload;
    throw error;
  }

  return payload;
}

function authHeaders(apiKey, bearer) {
  const headers = {
    "Content-Type": "application/json",
    apikey: apiKey,
  };

  if (bearer) {
    headers.Authorization = `Bearer ${bearer}`;
  }

  return headers;
}

function restHeaders(serviceRoleKey, prefer = undefined) {
  const headers = {
    "Content-Type": "application/json",
    apikey: serviceRoleKey,
    Authorization: `Bearer ${serviceRoleKey}`,
  };

  if (prefer) {
    headers.Prefer = prefer;
  }

  return headers;
}

export async function startOTP(config, email) {
  const url = makeURL(config.supabaseURL, "/auth/v1/otp");

  return supabaseFetch(url, {
    method: "POST",
    headers: authHeaders(config.supabaseAnonKey),
    body: JSON.stringify({
      email,
      create_user: true,
      should_create_user: true,
    }),
  });
}

export async function verifyOTP(config, email, otp) {
  const url = makeURL(config.supabaseURL, "/auth/v1/verify");

  return supabaseFetch(url, {
    method: "POST",
    headers: authHeaders(config.supabaseAnonKey),
    body: JSON.stringify({
      email,
      token: otp,
      type: "email",
    }),
  });
}

export async function refreshSession(config, refreshToken) {
  const url = makeURL(config.supabaseURL, "/auth/v1/token", {
    grant_type: "refresh_token",
  });

  return supabaseFetch(url, {
    method: "POST",
    headers: authHeaders(config.supabaseAnonKey),
    body: JSON.stringify({
      refresh_token: refreshToken,
    }),
  });
}

export async function getUserForAccessToken(config, accessToken) {
  const url = makeURL(config.supabaseURL, "/auth/v1/user");

  return supabaseFetch(url, {
    method: "GET",
    headers: authHeaders(config.supabaseAnonKey, accessToken),
  });
}

export async function upsertProfile(config, profile) {
  const url = makeURL(config.supabaseURL, "/rest/v1/profiles", {
    on_conflict: "id",
  });

  return supabaseFetch(url, {
    method: "POST",
    headers: restHeaders(config.supabaseServiceRoleKey, "resolution=merge-duplicates,return=representation"),
    body: JSON.stringify([profile]),
  });
}

export async function getDevice(config, userID, deviceID) {
  const url = makeURL(config.supabaseURL, "/rest/v1/devices", {
    user_id: `eq.${userID}`,
    device_id: `eq.${deviceID}`,
    select: "*",
    limit: 1,
  });

  const rows = await supabaseFetch(url, {
    method: "GET",
    headers: restHeaders(config.supabaseServiceRoleKey),
  });

  if (Array.isArray(rows) && rows.length > 0) {
    return rows[0];
  }

  return null;
}

export async function upsertDevice(config, deviceRow) {
  const url = makeURL(config.supabaseURL, "/rest/v1/devices", {
    on_conflict: "user_id,device_id",
  });

  const rows = await supabaseFetch(url, {
    method: "POST",
    headers: restHeaders(config.supabaseServiceRoleKey, "resolution=merge-duplicates,return=representation"),
    body: JSON.stringify([deviceRow]),
  });

  return Array.isArray(rows) && rows.length > 0 ? rows[0] : null;
}

export async function patchDevice(config, userID, deviceID, patch) {
  const url = makeURL(config.supabaseURL, "/rest/v1/devices", {
    user_id: `eq.${userID}`,
    device_id: `eq.${deviceID}`,
    select: "*",
  });

  const rows = await supabaseFetch(url, {
    method: "PATCH",
    headers: restHeaders(config.supabaseServiceRoleKey, "return=representation"),
    body: JSON.stringify(patch),
  });

  return Array.isArray(rows) && rows.length > 0 ? rows[0] : null;
}

export async function getBudgetState(config, dayBucket) {
  const url = makeURL(config.supabaseURL, "/rest/v1/budget_state", {
    day_bucket: `eq.${dayBucket}`,
    select: "*",
    limit: 1,
  });

  const rows = await supabaseFetch(url, {
    method: "GET",
    headers: restHeaders(config.supabaseServiceRoleKey),
  });

  if (Array.isArray(rows) && rows.length > 0) {
    return rows[0];
  }

  return null;
}

export async function upsertBudgetState(config, budgetState) {
  const url = makeURL(config.supabaseURL, "/rest/v1/budget_state", {
    on_conflict: "day_bucket",
  });

  const rows = await supabaseFetch(url, {
    method: "POST",
    headers: restHeaders(config.supabaseServiceRoleKey, "resolution=merge-duplicates,return=representation"),
    body: JSON.stringify([budgetState]),
  });

  return Array.isArray(rows) && rows.length > 0 ? rows[0] : null;
}

export async function insertUsageLedger(config, ledgerRow) {
  const url = makeURL(config.supabaseURL, "/rest/v1/usage_ledger");

  await supabaseFetch(url, {
    method: "POST",
    headers: restHeaders(config.supabaseServiceRoleKey, "return=minimal"),
    body: JSON.stringify([ledgerRow]),
  });
}
