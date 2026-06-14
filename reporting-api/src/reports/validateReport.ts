import { normalizeCategory, normalizeReport } from "./normalizeReport.js";
import type { DecodedScreenshot, NormalizedReport, ReportInput } from "../types/report.js";

const forbiddenFinancialPattern = /\b(account\s+(balance|number)\s*(is|:)?\s*[-+]?[\d\s.,]{3,}\b|balance\s*(is|:)\s*[-+]?[\d\s.,]{3,}\s*(uah|usd|eur|₴|\$|€)?\b|monobank\s+token\s*(is|:)\s*[A-Za-z0-9_\-]{16,}\b|transaction\s+(data|details)\s*(is|:)|database\s+file\s*(is|:)|raw\s+logs?\s*(are|is|:))/i;
const csvHeaderPattern = /(^|\n)\s*(date|account|amount|currency|description|merchant|mcc)\s*,\s*(date|account|amount|currency|description|merchant|mcc)/i;
const base64BlobPattern = /[A-Za-z0-9+/=]{160,}/;
const logDumpPattern = /(?:^|\n).*(?:\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}|ERROR|WARN|Exception|stack trace).*(?:\n.*(?:\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}|ERROR|WARN|Exception|stack trace).*){2,}/i;
const urlOnlyPattern = /^\s*https?:\/\/\S+\s*$/i;
const allowedFields = new Set([
  "category",
  "idempotencyKey",
  "title",
  "description",
  "screen",
  "screenshots",
  "appVersion",
  "buildNumber",
  "iosVersion",
  "deviceModel",
  "locale",
  "timezone",
  "installHash"
]);

const maxScreenshots = 3;
const maxScreenshotBytes = 1_048_576; // 1 MB
const maxTotalScreenshotBytes = 3 * maxScreenshotBytes; // 3 MB
const forbiddenFieldPattern = /(transaction|transactions|balance|balances|account|accounts|csv|database|log|logs|screenshot|screenshots|monobanktoken|token|file|files|attachment|attachments)/i;

export function validateReport(input: ReportInput): NormalizedReport {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new ReportValidationError("Report body must be an object.");
  }
  rejectForbiddenExtraFields(input);

  const category = normalizeCategory(input.category);
  if (!category) {
    throw new ReportValidationError("Unsupported category.");
  }

  const report = { ...normalizeReport(input), category };
  validateLength(report.title, 5, 120, "Title");
  validateLength(report.description, 20, 4000, "Description");

  const combined = `${report.title}\n${report.description}`;
  if (urlOnlyPattern.test(report.description)) {
    throw new ReportValidationError("URL-only reports are not accepted.");
  }
  if (csvHeaderPattern.test(combined)) {
    throw new ReportValidationError("CSV exports are not accepted.");
  }
  if (base64BlobPattern.test(combined)) {
    throw new ReportValidationError("Encoded blobs are not accepted.");
  }
  if (logDumpPattern.test(combined)) {
    throw new ReportValidationError("Raw logs are not accepted.");
  }
  if (forbiddenFinancialPattern.test(combined)) {
    throw new ReportValidationError("Financial data is not accepted in reports.");
  }
  if (looksLikeRepeatedGarbage(report.description)) {
    throw new ReportValidationError("Repeated garbage text is not accepted.");
  }

  validateScreenshots(report.screenshots);

  return report;
}

function validateScreenshots(screenshots: DecodedScreenshot[]): void {
  if (screenshots.length > maxScreenshots) {
    throw new ReportValidationError(`You can attach up to ${maxScreenshots} screenshots.`);
  }
  let totalSize = 0;
  for (const screenshot of screenshots) {
    if (screenshot.buffer.length > maxScreenshotBytes) {
      throw new ReportValidationError("Each screenshot must be smaller than 1 MB.");
    }
    if (!hasValidImageMagicBytes(screenshot.buffer, screenshot.mimeType)) {
      throw new ReportValidationError("Screenshots must be JPEG or PNG images.");
    }
    totalSize += screenshot.buffer.length;
  }
  if (totalSize > maxTotalScreenshotBytes) {
    throw new ReportValidationError("Screenshots must be smaller than 3 MB in total.");
  }
}

function hasValidImageMagicBytes(buffer: Buffer, mimeType: string): boolean {
  if (buffer.length < 8) {
    return false;
  }
  if (mimeType === "image/jpeg") {
    return buffer[0] === 0xFF && buffer[1] === 0xD8 && buffer[2] === 0xFF;
  }
  if (mimeType === "image/png") {
    const pngSignature = Buffer.from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    return buffer.subarray(0, 8).equals(pngSignature);
  }
  return false;
}

function rejectForbiddenExtraFields(input: Record<string, unknown>): void {
  for (const key of Object.keys(input)) {
    if (!allowedFields.has(key)) {
      const label = forbiddenFieldPattern.test(key) ? "Forbidden" : "Unsupported";
      throw new ReportValidationError(`${label} report field: ${key}.`);
    }
  }
}

export class ReportValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ReportValidationError";
  }
}

function validateLength(value: string, min: number, max: number, label: string): void {
  if (value.length < min || value.length > max) {
    throw new ReportValidationError(`${label} must be ${min}-${max} characters.`);
  }
}

function looksLikeRepeatedGarbage(value: string): boolean {
  const compact = value.replace(/\s+/g, "");
  if (compact.length < 40) {
    return false;
  }
  return /^(.{1,8})\1{5,}$/i.test(compact);
}
