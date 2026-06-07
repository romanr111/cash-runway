import assert from "node:assert/strict";
import test from "node:test";
import { submitReport, ReportSubmissionError } from "../src/reports/reportSubmission.js";
import { MemoryReportStore } from "../src/storage/reportStore.js";
import type { GitHubClient, NormalizedReport } from "../src/types/report.js";

const report: NormalizedReport = {
  category: "bug",
  title: "CSV import crashes",
  description: "The app crashes after selecting a CSV file.",
  screen: "CSVImportView",
  installHash: "sha256:abcdef1234567890"
};

test("same idempotency key returns stored result without creating another GitHub issue", async () => {
  const store = new MemoryReportStore();
  let issueCreates = 0;
  const client: GitHubClient = {
    async createIssue() {
      issueCreates += 1;
      return { issueNumber: 123 };
    }
  };

  const first = await submitReport({ report, idempotencyKey: "attempt-1", ip: "203.0.113.10", store, client });
  const retry = await submitReport({ report, idempotencyKey: "attempt-1", ip: "203.0.113.10", store, client });

  assert.deepEqual(first, { status: "created", issueNumber: 123 });
  assert.deepEqual(retry, { status: "created", issueNumber: 123 });
  assert.equal(issueCreates, 1);
});

test("same normalized report is blocked for twenty four hours", async () => {
  const store = new MemoryReportStore();
  const client: GitHubClient = {
    async createIssue() {
      return { issueNumber: 123 };
    }
  };

  await submitReport({ report, idempotencyKey: "attempt-1", ip: "203.0.113.10", store, client });

  await assert.rejects(
    submitReport({ report, idempotencyKey: "attempt-2", ip: "203.0.113.10", store, client }),
    (error: unknown) => error instanceof ReportSubmissionError
      && error.statusCode === 409
      && /Duplicate/.test(error.message)
  );
});

test("install hash is limited to three reports per hour", async () => {
  const store = new MemoryReportStore();
  let issueNumber = 100;
  const client: GitHubClient = {
    async createIssue() {
      issueNumber += 1;
      return { issueNumber };
    }
  };

  for (let index = 0; index < 3; index += 1) {
    await submitReport({
      report: { ...report, title: `Unique report ${index}`, description: `A unique enough report description ${index}.` },
      idempotencyKey: `attempt-${index}`,
      ip: "203.0.113.10",
      store,
      client
    });
  }

  await assert.rejects(
    submitReport({
      report: { ...report, title: "Unique report 4", description: "A fourth unique report description." },
      idempotencyKey: "attempt-4",
      ip: "203.0.113.10",
      store,
      client
    }),
    (error: unknown) => error instanceof ReportSubmissionError
      && error.statusCode === 429
  );
});

test("ip fallback is limited when install hash is missing", async () => {
  const store = new MemoryReportStore();
  const client: GitHubClient = {
    async createIssue() {
      return { issueNumber: 123 };
    }
  };

  for (let index = 0; index < 10; index += 1) {
    await submitReport({
      report: {
        ...report,
        installHash: undefined,
        title: `Unique IP report ${index}`,
        description: `A unique IP fallback report description ${index}.`
      },
      idempotencyKey: `ip-attempt-${index}`,
      ip: "203.0.113.20",
      store,
      client
    });
  }

  await assert.rejects(
    submitReport({
      report: {
        ...report,
        installHash: undefined,
        title: "Unique IP report 11",
        description: "Another unique IP fallback report description."
      },
      idempotencyKey: "ip-attempt-11",
      ip: "203.0.113.20",
      store,
      client
    }),
    (error: unknown) => error instanceof ReportSubmissionError
      && error.statusCode === 429
  );
});
