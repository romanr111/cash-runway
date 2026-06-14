import type { ReportStore } from "../storage/reportStore.js";

const hourSeconds = 60 * 60;
const daySeconds = 24 * hourSeconds;

export type RateLimitInput = {
  installHash?: string;
  ip?: string;
};

export async function checkReportRateLimits(
  store: ReportStore,
  input: RateLimitInput
): Promise<boolean> {
  if (input.installHash) {
    const hourly = await store.increment(`rate:install:${input.installHash}:hour`, hourSeconds);
    const daily = await store.increment(`rate:install:${input.installHash}:day`, daySeconds);
    return hourly <= 3 && daily <= 10;
  }

  const ip = input.ip ?? "unknown";
  const hourly = await store.increment(`rate:ip:${ip}:hour`, hourSeconds);
  return hourly <= 10;
}
