import { createHash } from "node:crypto";
import { createGitHubIssue } from "../github/createGitHubIssue.js";
import { checkReportRateLimits } from "../security/rateLimit.js";
import type { ReportStore } from "../storage/reportStore.js";
import type { GitHubClient, NormalizedReport } from "../types/report.js";
import { duplicateHash } from "./duplicateHash.js";

const oneDaySeconds = 24 * 60 * 60;

type StoredSubmission =
  | { status: "pending" }
  | { status: "created"; issueNumber: number };

export type ReportSubmissionResult = {
  status: "created";
  issueNumber: number;
};

export type SubmitReportInput = {
  report: NormalizedReport;
  reportId: string;
  idempotencyKey?: string;
  ip?: string;
  store: ReportStore;
  client: GitHubClient;
};

export async function submitReport(input: SubmitReportInput): Promise<ReportSubmissionResult> {
  const idempotencyStoreKey = input.idempotencyKey
    ? `idempotency:${keyDigest(input.idempotencyKey)}`
    : undefined;
  let claimedIdempotency = false;
  let duplicateStoreKey: string | undefined;

  if (idempotencyStoreKey) {
    const existing = await input.store.getJson<StoredSubmission>(idempotencyStoreKey);
    if (existing?.status === "created") {
      return { status: "created", issueNumber: existing.issueNumber };
    }
    if (existing?.status === "pending") {
      throw new ReportSubmissionError(409, "Report submission is already in progress.");
    }
    claimedIdempotency = await input.store.setJsonIfAbsent(idempotencyStoreKey, { status: "pending" }, oneDaySeconds);
    if (!claimedIdempotency) {
      throw new ReportSubmissionError(409, "Report submission is already in progress.");
    }
  }

  try {
    if (!await checkReportRateLimits(input.store, { installHash: input.report.installHash, ip: input.ip })) {
      throw new ReportSubmissionError(429, "Too many reports. Try again later.");
    }

    duplicateStoreKey = `duplicate:${duplicateHash(input.report)}`;
    const claimedDuplicate = await input.store.setJsonIfAbsent(duplicateStoreKey, { status: "pending" }, oneDaySeconds);
    if (!claimedDuplicate) {
      throw new ReportSubmissionError(409, "Duplicate report already received.");
    }

    const result = await createGitHubIssue(input.client, input.report, input.reportId);
    const stored: StoredSubmission = { status: "created", issueNumber: result.issueNumber };
    await input.store.setJson(duplicateStoreKey, stored, oneDaySeconds);
    if (idempotencyStoreKey) {
      await input.store.setJson(idempotencyStoreKey, stored, oneDaySeconds);
    }
    return stored;
  } catch (error) {
    if (claimedIdempotency && idempotencyStoreKey) {
      await input.store.delete(idempotencyStoreKey);
    }
    if (duplicateStoreKey) {
      const duplicateValue = await input.store.getJson<StoredSubmission>(duplicateStoreKey);
      if (duplicateValue?.status === "pending") {
        await input.store.delete(duplicateStoreKey);
      }
    }
    throw error;
  }
}

export class ReportSubmissionError extends Error {
  constructor(public readonly statusCode: number, message: string) {
    super(message);
    this.name = "ReportSubmissionError";
  }
}

function keyDigest(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}
