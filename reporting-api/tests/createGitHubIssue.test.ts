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

test("creates a GitHub issue with normalized report metadata", async () => {
  let captured: GitHubIssueInput | undefined;
  const client = createMockClient();
  client.createIssue = async (input) => {
    captured = input;
    return { issueNumber: 123 };
  };

  const result = await createGitHubIssue(client, report, "report-1");

  assert.equal(result.issueNumber, 123);
  assert.equal(captured?.title, "[Bug] CSV import crashes");
  assert.deepEqual(captured?.labels, ["user-report", "bug", "ios", "needs-triage"]);
  assert.match(captured?.body ?? "", /duplicate-hash:/);
});

test("uploads screenshots and embeds returned file URLs in issue body", async () => {
  let capturedBody = "";
  const uploadedPaths: string[] = [];
  const client: GitHubClient = {
    async createIssue(input) {
      capturedBody = input.body;
      return { issueNumber: 456 };
    },

    async uploadFile(path) {
      uploadedPaths.push(path);
      return { rawUrl: "https://example.com/screenshot.png" };
    }
  };
  const reportWithScreenshots: NormalizedReport = {
    ...report,
    screenshots: [
      {
        buffer: Buffer.from([0xFF, 0xD8, 0xFF, 0x00]),
        mimeType: "image/jpeg",
        filename: "a.jpg"
      }
    ]
  };

  const result = await createGitHubIssue(client, reportWithScreenshots, "report-2");

  assert.equal(result.issueNumber, 456);
  assert.equal(uploadedPaths.length, 1);
  assert.ok(uploadedPaths[0]?.startsWith("reporting-screenshots/report-2/"));
  assert.ok(capturedBody.includes("![Screenshot 1](https://example.com/screenshot.png)"));
  assert.ok(!capturedBody.includes("data:image/jpeg;base64"), "body should not contain data URI");
});
