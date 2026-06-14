import type { ReportStore } from "../storage/reportStore.js";

const hourSeconds = 60 * 60;
const daySeconds = 24 * hourSeconds;

const hourlyLimit = 10;
const dailyLimit = 30;

export type RateLimitInput = {
  installHash?: string;
  ip?: string;
};

export type RateLimitResult = {
  allowed: boolean;
  limit: number;
  remaining: number;
  windowSeconds: number;
};

export async function checkReportRateLimits(
  store: ReportStore,
  input: RateLimitInput
): Promise<RateLimitResult> {
  if (input.installHash) {
    const hourly = await store.increment(`rate:install:${input.installHash}:hour`, hourSeconds);
    const daily = await store.increment(`rate:install:${input.installHash}:day`, daySeconds);
    return {
      allowed: hourly <= hourlyLimit && daily <= dailyLimit,
      limit: hourlyLimit,
      remaining: Math.max(0, hourlyLimit - hourly),
      windowSeconds: hourSeconds
    };
  }

  const ip = input.ip ?? "unknown";
  const hourly = await store.increment(`rate:ip:${ip}:hour`, hourSeconds);
  return {
    allowed: hourly <= 10,
    limit: 10,
    remaining: Math.max(0, 10 - hourly),
    windowSeconds: hourSeconds
  };
}
