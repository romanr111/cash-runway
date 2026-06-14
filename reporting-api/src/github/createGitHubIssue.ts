import crypto from "node:crypto";
import { duplicateHash } from "../reports/duplicateHash.js";
import { formatIssueBody, formatIssueTitle, issueLabels } from "../reports/formatIssueBody.js";
import type { DecodedScreenshot, GitHubClient, GitHubIssueResult, NormalizedReport } from "../types/report.js";

export async function createGitHubIssue(
  client: GitHubClient,
  report: NormalizedReport,
  reportId: string
): Promise<GitHubIssueResult> {
  const screenshotUrls = await uploadScreenshots(client, report.screenshots, reportId);
  const hash = duplicateHash(report);

  return client.createIssue({
    title: formatIssueTitle(report),
    body: `${formatIssueBody(report, screenshotUrls)}\n\n<!-- duplicate-hash:${hash} -->`,
    labels: issueLabels(report)
  });
}

async function uploadScreenshots(
  client: GitHubClient,
  screenshots: DecodedScreenshot[],
  reportId: string
): Promise<string[]> {
  const urls: string[] = [];

  for (const screenshot of screenshots) {
    const ext = screenshot.mimeType === "image/png" ? "png" : "jpg";
    const path = `reporting-screenshots/${reportId}/${crypto.randomUUID()}.${ext}`;
    const result = await client.uploadFile(
      path,
      screenshot.buffer,
      `Upload feedback screenshot for ${reportId}`
    );
    urls.push(result.rawUrl);
  }

  return urls;
}
