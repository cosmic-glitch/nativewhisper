const counters = new Map();

function nowMillis() {
  return Date.now();
}

function cleanupExpired(now) {
  for (const [key, entry] of counters.entries()) {
    if (entry.resetAt <= now) {
      counters.delete(key);
    }
  }
}

export function checkRateLimit(key, limit, windowSeconds) {
  const now = nowMillis();
  cleanupExpired(now);

  const windowMillis = Math.max(1, windowSeconds) * 1000;
  const existing = counters.get(key);

  if (!existing || existing.resetAt <= now) {
    const next = {
      count: 1,
      resetAt: now + windowMillis,
    };
    counters.set(key, next);
    return {
      allowed: true,
      remaining: Math.max(0, limit - 1),
      resetAt: next.resetAt,
    };
  }

  existing.count += 1;
  const allowed = existing.count <= limit;

  return {
    allowed,
    remaining: Math.max(0, limit - existing.count),
    resetAt: existing.resetAt,
  };
}
