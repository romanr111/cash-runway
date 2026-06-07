import assert from "node:assert/strict";
import test from "node:test";
import { createGitHubIssue } from "../src/github/createGitHubIssue.js";
import type { GitHubClient, GitHubIssueInput, NormalizedReport } from "../src/types/report.js";

const report: NormalizedReport = {
  category: "bug",
  title: "CSV import crashes",
  description: "The app crashes after selecting a CSV file.",
  screen: "CSVImportView"
};

test("creates issue through mockable GitHub client", async () => {
  let captured: GitHubIssueInput | undefined;
  const client: GitHubClient = {
    async createIssue(input) {
      captured = input;
      return { issueNumber: 123 };
    }
  };

  const result = await createGitHubIssue(client, report);

  assert.equal(result.issueNumber, 123);
  assert.equal(captured?.title, "[Bug] CSV import crashes");
  assert.deepEqual(captured?.labels, ["user-report", "bug", "ios", "needs-triage"]);
  assert.match(captured?.body ?? "", /duplicate-hash:/);
});
