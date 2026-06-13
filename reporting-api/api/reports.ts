import type { IncomingMessage, ServerResponse } from "node:http";
import { randomUUID } from "node:crypto";
import { readReportingEnv } from "../src/config/reportingEnv.js";
import { createInstallationToken } from "../src/github/githubAppAuth.js";
import { GitHubIssueError, RestGitHubClient } from "../src/github/githubClient.js";
import { submitReport, ReportSubmissionError } from "../src/reports/reportSubmission.js";
import { validateReport, ReportValidationError } from "../src/reports/validateReport.js";
import { consoleSafeReportLogger } from "../src/security/safeLogger.js";
import { verifySharedSecret } from "../src/security/verifySharedSecret.js";
import { UpstashReportStore } from "../src/storage/reportStore.js";
import type { ReportInput } from "../src/types/report.js";

const maxBodyBytes = 32 * 1024;

export default async function handler(req: IncomingMessage, res: ServerResponse): Promise<void> {
  const startedAt = Date.now();
  const reportId = randomUUID();
  let metadata: { category?: string; screen?: string; appVersion?: string } = {};

  if (req.method !== "POST") {
    sendJson(res, 405, { error: "Method not allowed." });
    return;
  }

  const config = readReportingEnv(process.env);
  if (!config.enabled) {
    consoleSafeReportLogger({ reportId, status: "disabled", durationMs: Date.now() - startedAt });
    sendJson(res, 503, { error: "Reporting is disabled." });
    return;
  }
  if (config.missing.length > 0) {
    consoleSafeReportLogger({ reportId, status: "config_error", durationMs: Date.now() - startedAt });
    sendJson(res, 503, { error: "Reporting service is not configured.", missing: config.missing });
    return;
  }

  if (req.headers["x-cashrunway-client"] !== "ios") {
    sendJson(res, 400, { error: "Unsupported client." });
    return;
  }

  const providedSecret = headerValue(req.headers["x-cashrunway-secret"]);
  if (!verifySharedSecret(providedSecret, config.reportSecret)) {
    sendJson(res, 401, { error: "Unauthorized." });
    return;
  }

  if (!contentTypeIsJson(req)) {
    sendJson(res, 415, { error: "Content-Type must be application/json." });
    return;
  }

  try {
    const body = await readJsonBody(req);
    const report = validateReport(body as ReportInput);
    metadata = { category: report.category, screen: report.screen, appVersion: report.appVersion };
    const client = new RestGitHubClient({
      owner: config.githubRepoOwner ?? "",
      repo: config.githubRepoName ?? "",
      tokenProvider: () => createInstallationToken({
        appId: config.githubAppId ?? "",
        privateKey: (config.githubPrivateKey ?? "").replace(/\\n/g, "\n"),
        installationId: config.githubInstallationId ?? ""
      })
    });
    const store = new UpstashReportStore({
      restUrl: config.upstashRestUrl ?? "",
      token: config.upstashToken ?? ""
    });
    const result = await submitReport({
      report,
      idempotencyKey: idempotencyKeyFromBody(body),
      ip: clientIp(req),
      store,
      client
    });
    consoleSafeReportLogger({
      reportId,
      ...metadata,
      status: "created",
      issueNumber: result.issueNumber,
      durationMs: Date.now() - startedAt
    });
    sendJson(res, 201, { status: "created", issueNumber: result.issueNumber });
  } catch (error) {
    if (error instanceof ReportValidationError) {
      consoleSafeReportLogger({
        reportId,
        ...metadata,
        status: "validation_failed",
        durationMs: Date.now() - startedAt
      });
      sendJson(res, 400, { error: error.message });
      return;
    }
    if (error instanceof PayloadError) {
      sendJson(res, error.statusCode, { error: error.message });
      return;
    }
    if (error instanceof ReportSubmissionError) {
      consoleSafeReportLogger({
        reportId,
        ...metadata,
        status: error.statusCode === 429 ? "rate_limited" : "duplicate",
        durationMs: Date.now() - startedAt
      });
      sendJson(res, error.statusCode, { error: error.message });
      return;
    }
    if (error instanceof GitHubIssueError) {
      consoleSafeReportLogger({
        reportId,
        ...metadata,
        status: "server_error",
        durationMs: Date.now() - startedAt
      });
      sendJson(res, mapGitHubStatus(error.statusCode), { error: githubErrorMessage(error.statusCode) });
      return;
    }
    consoleSafeReportLogger({
      reportId,
      ...metadata,
      status: "server_error",
      durationMs: Date.now() - startedAt
    });
    sendJson(res, 502, { error: "Could not create GitHub issue." });
  }
}

function sendJson(res: ServerResponse, statusCode: number, payload: unknown): void {
  res.statusCode = statusCode;
  res.setHeader("Content-Type", "application/json");
  res.end(JSON.stringify(payload));
}

function headerValue(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

async function readJsonBody(req: IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = [];
  let total = 0;
  for await (const chunk of req) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    total += buffer.length;
    if (total > maxBodyBytes) {
      throw new PayloadError(413, "Report payload is too large.");
    }
    chunks.push(buffer);
  }

  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8")) as unknown;
  } catch {
    throw new PayloadError(400, "Invalid JSON body.");
  }
}

function contentTypeIsJson(req: IncomingMessage): boolean {
  return (headerValue(req.headers["content-type"]) ?? "").toLowerCase().startsWith("application/json");
}

function idempotencyKeyFromBody(body: unknown): string | undefined {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return undefined;
  }
  const value = (body as { idempotencyKey?: unknown }).idempotencyKey;
  return typeof value === "string" && value.trim().length > 0 ? value.trim().slice(0, 128) : undefined;
}

function clientIp(req: IncomingMessage): string {
  const forwardedFor = headerValue(req.headers["x-forwarded-for"]);
  return forwardedFor?.split(",")[0]?.trim() || req.socket.remoteAddress || "unknown";
}

function mapGitHubStatus(statusCode: number): number {
  if (statusCode === 401 || statusCode === 403 || statusCode >= 500) {
    return 502;
  }
  if (statusCode === 422) {
    return 400;
  }
  return 502;
}

function githubErrorMessage(statusCode: number): string {
  if (statusCode === 401 || statusCode === 403) {
    return "Reporting service authentication is not configured correctly.";
  }
  if (statusCode === 422) {
    return "Report could not be accepted by GitHub.";
  }
  return "GitHub issue creation is temporarily unavailable.";
}

class PayloadError extends Error {
  constructor(public readonly statusCode: number, message: string) {
    super(message);
  }
}
