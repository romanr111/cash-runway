import { createHash } from "node:crypto";
import type { NormalizedReport } from "../types/report.js";

export function duplicateHash(report: NormalizedReport): string {
  const normalized = [
    report.category,
    normalizeForHash(report.title),
    normalizeForHash(report.description),
    report.installHash ?? "",
    screenshotHash(report.screenshots)
  ].join("\n");

  return createHash("sha256").update(normalized).digest("hex");
}

function normalizeForHash(value: string): string {
  return value.trim().toLocaleLowerCase().replace(/\s+/g, " ");
}

function screenshotHash(screenshots: NormalizedReport["screenshots"]): string {
  return screenshots
    .map((screenshot) => createHash("sha256").update(screenshot.buffer).digest("hex"))
    .join(",");
}
