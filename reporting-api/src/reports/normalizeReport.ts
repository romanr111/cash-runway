import { sanitizeSingleLine, sanitizeText } from "../security/sanitizeText.js";
import type { NormalizedReport, ReportCategory, ReportInput } from "../types/report.js";

export function normalizeReport(input: ReportInput): NormalizedReport {
  const source = input ?? {};
  const category = source.category === "improvement" ? "improvement" : "bug";

  return {
    category,
    title: sanitizeSingleLine(asString(source.title), 120) ?? "",
    description: sanitizeText(asString(source.description)),
    screen: sanitizeSingleLine(asString(source.screen), 100),
    appVersion: sanitizeSingleLine(asString(source.appVersion), 40),
    buildNumber: sanitizeSingleLine(asString(source.buildNumber), 40),
    iosVersion: sanitizeSingleLine(asString(source.iosVersion), 80),
    deviceModel: sanitizeSingleLine(asString(source.deviceModel), 80),
    locale: sanitizeSingleLine(asString(source.locale), 40),
    timezone: sanitizeSingleLine(asString(source.timezone), 80),
    installHash: sanitizeSingleLine(asString(source.installHash), 128)
  };
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
