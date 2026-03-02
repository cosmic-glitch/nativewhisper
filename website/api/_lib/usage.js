export function utcDayBucket(date = new Date()) {
  return date.toISOString().slice(0, 10);
}

export function resetAtUTC(date = new Date()) {
  const next = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate() + 1, 0, 0, 0, 0));
  return next.toISOString();
}

export function asNumber(value, fallback = 0) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    return fallback;
  }
  return parsed;
}

export function estimateUSDCost(durationMs, perAudioMinuteUSD) {
  const safeDurationMs = Math.max(0, asNumber(durationMs));
  const minutes = safeDurationMs / 60_000;
  return Number((minutes * perAudioMinuteUSD).toFixed(6));
}

export function ensureDayDeviceState(device, dayBucket) {
  if (!device || device.day_bucket !== dayBucket) {
    return {
      daily_transcription_count: 0,
      daily_audio_ms: 0,
      daily_estimated_usd: 0,
      day_bucket: dayBucket,
    };
  }

  return {
    daily_transcription_count: asNumber(device.daily_transcription_count),
    daily_audio_ms: asNumber(device.daily_audio_ms),
    daily_estimated_usd: asNumber(device.daily_estimated_usd),
    day_bucket: dayBucket,
  };
}

export function remainingDeviceCount(state, cap) {
  return Math.max(0, cap - asNumber(state.daily_transcription_count));
}

export function budgetStateLabel(hardStopTriggered) {
  return hardStopTriggered ? "paused" : "active";
}
