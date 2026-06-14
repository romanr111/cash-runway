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
  screenshots: [],
  installHash: "sha256:abcdef1234567890"
};

function createMockClient(): GitHubClient {
  return {
    async createIssue() {
      return { issueNumber: 123 };
    },
    async uploadFile() {
      return { rawUrl: "https://example.com/screenshot.png" };
    }
  };
}

test("same idempotency key returns stored result without creating another GitHub issue", async () => {
  const store = new MemoryReportStore();
  let issueCreates = 0;
  const client: GitHubClient = {
    async createIssue() {
      issueCreates += 1;
      return { issueNumber: 123 };
    },
    async uploadFile() {
      return { rawUrl: "https://example.com/screenshot.png" };
    }
  };

  const first = await submitReport({ report, reportId: "report-1", idempotencyKey: "attempt-1", ip: "203.0.113.10", store, client });
  const retry = await submitReport({ report, reportId: "report-1", idempotencyKey: "attempt-1", ip: "203.0.113.10", store, client });

  assert.deepEqual(first, { status: "created", issueNumber: 123 });
  assert.deepEqual(retry, { status: "created", issueNumber: 123 });
  assert.equal(issueCreates, 1);
});

test("same normalized report is blocked for twenty four hours", async () => {
  const store = new MemoryReportStore();
  const client = createMockClient();

  await submitReport({ report, reportId: "report-1", idempotencyKey: "attempt-1", ip: "203.0.113.10", store, client });

  await assert.rejects(
    submitReport({ report, reportId: "report-2", idempotencyKey: "attempt-2", ip: "203.0.113.10", store, client }),
    (error: unknown) => error instanceof ReportSubmissionError
      && error.statusCode === 409
      && /Duplicate/.test(error.message)
  );
});

test("install hash is limited to ten reports per hour", async () => {
  const store = new MemoryReportStore();
  let issueNumber = 100;
  const client: GitHubClient = {
    async createIssue() {
      issueNumber += 1;
      return { issueNumber };
    },
    async uploadFile() {
      return { rawUrl: "https://example.com/screenshot.png" };
    }
  };

  for (let index = 0; index < 10; index += 1) {
    await submitReport({
      report: { ...report, title: `Unique report ${index}`, description: `A unique enough report description ${index}.` },
      reportId: `report-${index}`,
      idempotencyKey: `attempt-${index}`,
      ip: "[IP_ADDRESS]",
      store,
      client
    });
  }

  await assert.rejects(
    submitReport({
      report: { ...report, title: "Unique report 10", description: "An eleventh unique report description." },
      reportId: "report-10",
      idempotencyKey: "attempt-10",
      ip: "[IP_ADDRESS]",
      store,
      client
    }),
    (error: unknown) => error instanceof ReportSubmissionError
      && error.statusCode === 429
  );
});

test("ip fallback is limited when install hash is missing", async () => {
  const store = new MemoryReportStore();
  const client = createMockClient();

  for (let index = 0; index < 10; index += 1) {
    await submitReport({
      report: {
        ...report,
        installHash: undefined,
        title: `Unique IP report ${index}`,
        description: `A unique IP fallback report description ${index}.`
      },
      reportId: `ip-report-${index}`,
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
      reportId: "ip-report-11",
      idempotencyKey: "ip-attempt-11",
      ip: "203.0.113.20",
      store,
      client
    }),
    (error: unknown) => error instanceof ReportSubmissionError
      && error.statusCode === 429
  );
});

test("screenshots are uploaded and returned URLs are embedded in issue body", async () => {
  const store = new MemoryReportStore();
  let capturedBody: string | undefined;
  const client: GitHubClient = {
    async createIssue(input) {
      capturedBody = input.body;
      return { issueNumber: 456 };
    },
    async uploadFile() {
      return { rawUrl: "https://example.com/screenshot.png" };
    }
  };

  const reportWithScreenshots: NormalizedReport = {
    ...report,
    screenshots: [
      { buffer: Buffer.from([0xFF, 0xD8, 0xFF, 0x00]), mimeType: "image/jpeg", filename: "a.jpg" },
      { buffer: Buffer.from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00]), mimeType: "image/png", filename: "b.png" }
    ]
  };

  const result = await submitReport({ report: reportWithScreenshots, reportId: "report-screenshots", idempotencyKey: "s-1", ip: "[IP_ADDRESS]", store, client });

  assert.equal(result.issueNumber, 456);
  assert.ok(capturedBody?.includes("![Screenshot 1](https://example.com/screenshot.png)"), "body should contain first uploaded screenshot URL");
  assert.ok(capturedBody?.includes("![Screenshot 2](https://example.com/screenshot.png)"), "body should contain second uploaded screenshot URL");
  assert.ok(!capturedBody?.includes("data:image/jpeg;base64"), "body should not contain jpeg data URI");
  assert.ok(!capturedBody?.includes("data:image/png;base64"), "body should not contain png data URI");
  assert.ok(capturedBody?.includes("![Screenshot 1]"), "body should contain first screenshot markdown");
  assert.ok(capturedBody?.includes("![Screenshot 2]"), "body should contain second screenshot markdown");
});
