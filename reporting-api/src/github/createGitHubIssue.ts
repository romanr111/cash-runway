import { duplicateHash } from "../reports/duplicateHash.js";
import { formatIssueBody, formatIssueTitle, issueLabels } from "../reports/formatIssueBody.js";
import type { GitHubClient, GitHubIssueResult, NormalizedReport } from "../types/report.js";

export async function createGitHubIssue(
  client: GitHubClient,
  report: NormalizedReport
): Promise<GitHubIssueResult> {
  const hash = duplicateHash(report);
  return client.createIssue({
    title: formatIssueTitle(report),
    body: `${formatIssueBody(report)}\n\n<!-- duplicate-hash:${hash} -->`,
    labels: issueLabels(report)
  });
}
