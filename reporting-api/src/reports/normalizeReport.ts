import { sanitizeSingleLine, sanitizeText } from "../security/sanitizeText.js";
import type { DecodedScreenshot, NormalizedReport, ReportCategory, ReportInput, ReportScreenshot } from "../types/report.js";

export function normalizeReport(input: ReportInput): NormalizedReport {
  const source = input ?? {};
  const category = source.category === "improvement" ? "improvement" : "bug";

  return {
    category,
    title: sanitizeSingleLine(asString(source.title), 120) ?? "",
    description: sanitizeText(asString(source.description)),
    screen: sanitizeSingleLine(asString(source.screen), 100),
    screenshots: normalizeScreenshots(source.screenshots),
    appVersion: sanitizeSingleLine(asString(source.appVersion), 40),
    buildNumber: sanitizeSingleLine(asString(source.buildNumber), 40),
    iosVersion: sanitizeSingleLine(asString(source.iosVersion), 80),
    deviceModel: sanitizeSingleLine(asString(source.deviceModel), 80),
    locale: sanitizeSingleLine(asString(source.locale), 40),
    timezone: sanitizeSingleLine(asString(source.timezone), 80),
    installHash: sanitizeSingleLine(asString(source.installHash), 128)
  };
}

function normalizeScreenshots(value: unknown): DecodedScreenshot[] {
  if (!Array.isArray(value)) {
    return [];
  }
  const result: DecodedScreenshot[] = [];
  for (const item of value) {
    const screenshot = normalizeSingleScreenshot(item);
    if (screenshot) {
      result.push(screenshot);
    }
  }
  return result;
}

function normalizeSingleScreenshot(item: unknown): DecodedScreenshot | undefined {
  if (!item || typeof item !== "object" || Array.isArray(item)) {
    return undefined;
  }
  const source = item as Record<string, unknown>;
  const data = asString(source.data);
  const mimeType = asString(source.mimeType);
  const filename = sanitizeSingleLine(asString(source.filename), 100) ?? "screenshot.jpg";
  if (data.length === 0) {
    return undefined;
  }
  const normalizedMime = normalizeMimeType(mimeType);
  if (!normalizedMime) {
    return undefined;
  }
  return {
    buffer: Buffer.from(data, "base64"),
    mimeType: normalizedMime,
    filename
  };
}

function normalizeMimeType(value: string): "image/jpeg" | "image/png" | undefined {
  const lower = value.toLowerCase();
  if (lower === "image/jpeg" || lower === "image/jpg") {
    return "image/jpeg";
  }
  if (lower === "image/png") {
    return "image/png";
  }
  return undefined;
}

export function decodeScreenshots(value: unknown): ReportScreenshot[] {
  if (!Array.isArray(value)) {
    return [];
  }
  const result: ReportScreenshot[] = [];
  for (const item of value) {
    if (!item || typeof item !== "object" || Array.isArray(item)) {
      continue;
    }
    const source = item as Record<string, unknown>;
    const data = asString(source.data);
    const mimeType = asString(source.mimeType);
    const filename = asString(source.filename);
    if (data.length === 0) {
      continue;
    }
    result.push({ data, mimeType, filename });
  }
  return result;
}

export function normalizeCategory(value: unknown): ReportCategory | undefined {
  if (value === "bug" || value === "improvement") {
    return value;
  }
  return undefined;
}

function asString(value: unknown): string {
  return typeof value === "string" ? value : "";
}
