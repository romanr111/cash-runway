import type { GitHubClient, GitHubIssueInput, GitHubIssueResult } from "../types/report.js";

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
}

export class GitHubIssueError extends Error {
  constructor(public readonly statusCode: number) {
    super(`GitHub issue creation failed: ${statusCode}`);
    this.name = "GitHubIssueError";
  }
}
