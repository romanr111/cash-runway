import type { GitHubClient, GitHubFileUploadResult, GitHubIssueInput, GitHubIssueResult } from "../types/report.js";

export type RestGitHubClientConfig = {
  owner: string;
  repo: string;
  tokenProvider: () => Promise<string>;
};

export class RestGitHubClient implements GitHubClient {
  constructor(private readonly config: RestGitHubClientConfig) {}

  async createIssue(input: GitHubIssueInput): Promise<GitHubIssueResult> {
    const token = await this.config.tokenProvider();
    const response = await fetch(`https://api.github.com/repos/${this.config.owner}/${this.config.repo}/issues`, {
      method: "POST",
      headers: {
        "Accept": "application/vnd.github+json",
        "Authorization": `Bearer ${token}`,
        "Content-Type": "application/json",
        "X-GitHub-Api-Version": "2022-11-28"
      },
      body: JSON.stringify({
        title: input.title,
        body: input.body,
        labels: input.labels
      })
    });

    if (!response.ok) {
      throw new GitHubIssueError(response.status);
    }

    const payload = await response.json() as { number?: number; html_url?: string };
    if (typeof payload.number !== "number") {
      throw new Error("GitHub issue creation response did not include an issue number.");
    }
    return { issueNumber: payload.number, issueUrl: payload.html_url };
  }

  async uploadFile(path: string, content: Buffer, message: string): Promise<GitHubFileUploadResult> {
    const token = await this.config.tokenProvider();
    const response = await fetch(`https://api.github.com/repos/${this.config.owner}/${this.config.repo}/contents/${path}`, {
      method: "PUT",
      headers: {
        "Accept": "application/vnd.github+json",
        "Authorization": `Bearer ${token}`,
        "Content-Type": "application/json",
        "X-GitHub-Api-Version": "2022-11-28"
      },
      body: JSON.stringify({
        message,
        content: content.toString("base64")
      })
    });

    if (!response.ok) {
      throw new GitHubIssueError(response.status);
    }

    const payload = await response.json() as { content?: { download_url?: string; html_url?: string } };
    const rawUrl = payload.content?.download_url ?? payload.content?.html_url;
    if (!rawUrl) {
      throw new Error("GitHub file upload response did not include a URL.");
    }
    return { rawUrl };
  }
}

export class GitHubIssueError extends Error {
  constructor(public readonly statusCode: number) {
    super(`GitHub issue creation failed: ${statusCode}`);
    this.name = "GitHubIssueError";
  }
}
