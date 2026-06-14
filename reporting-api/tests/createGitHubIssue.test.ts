import assert from "node:assert/strict";
import test from "node:test";
import { createGitHubIssue } from "../src/github/createGitHubIssue.js";
import type { GitHubClient, GitHubIssueInput, NormalizedReport } from "../src/types/report.js";

const report: NormalizedReport = {
  category: "bug",
  title: "CSV import crashes",
  description: "The app crashes after selecting a CSV file.",
  screen: "CSVImportView",
  screenshots: []
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

test("creates issue through mockable GitHub client", async () => {
  let captured: GitHubIssueInput | undefined;
  const client: GitHubClient = {
    async createIssue(input) {
      captured = input;
      return { issueNumber: 123 };
    },
    async uploadFile() {
      return { rawUrl: "https://example.com/screenshot.png" };
    }
  };

  const result = await createGitHubIssue(client, report, "report-1");

  assert.equal(result.issueNumber, 123);
  assert.equal(captured?.title, "[Bug] CSV import crashes");
  assert.deepEqual(captured?.labels, ["user-report", "bug", "ios", "needs-triage"]);
  assert.match(captured?.body ?? "", /duplicate-hash:/);
});

test("uploads screenshots and embeds them in issue body", async () => {
  const uploaded: { path: string; content: Buffer; message: string }[] = [];
  const client: GitHubClient = {
    async createIssue(input) {
      return { issueNumber: 456 };
    },
    async uploadFile(path, content, message) {
      uploaded.push({ path, content, message });
      return { rawUrl: `https://example.com/${path}` };
    }
  };

  const reportWithScreenshots: NormalizedReport = {
    ...report,
    screenshots: [
      { buffer: Buffer.from([0xFF, 0xD8, 0xFF, 0x00]), mimeType: "image/jpeg", filename: "a.jpg" }
    ]
  };

  await createGitHubIssue(client, reportWithScreenshots, "report-2");

  assert.equal(uploaded.length, 1);
  assert.ok(uploaded[0].path.startsWith("reporting-screenshots/report-2/"));
  assert.ok(uploaded[0].path.endsWith(".jpg"));
});
