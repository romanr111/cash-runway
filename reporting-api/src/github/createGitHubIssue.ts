import { duplicateHash } from "../reports/duplicateHash.js";
import { formatIssueBody, formatIssueTitle, issueLabels } from "../reports/formatIssueBody.js";
import type { DecodedScreenshot, GitHubClient, GitHubIssueResult, NormalizedReport } from "../types/report.js";

export async function createGitHubIssue(
  client: GitHubClient,
  report: NormalizedReport,
  reportId: string
): Promise<GitHubIssueResult> {
  const screenshotUrls = embedScreenshots(report.screenshots);
  const hash = duplicateHash(report);
  return client.createIssue({
    title: formatIssueTitle(report),
    body: `${formatIssueBody(report, screenshotUrls)}\n\n<!-- duplicate-hash:${hash} -->`,
    labels: issueLabels(report)
  });
}

function embedScreenshots(screenshots: DecodedScreenshot[]): string[] {
  return screenshots.map((s) => {
    const base64 = s.buffer.toString("base64");
    const mime = s.mimeType === "image/png" ? "image/png" : "image/jpeg";
    return `data:${mime};base64,${base64}`;
  });
}
