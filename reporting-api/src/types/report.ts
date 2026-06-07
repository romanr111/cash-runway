export type ReportCategory = "bug" | "improvement";

export type ReportInput = ({
  category?: unknown;
  idempotencyKey?: unknown;
  title?: unknown;
  description?: unknown;
  screen?: unknown;
  appVersion?: unknown;
  buildNumber?: unknown;
  iosVersion?: unknown;
  deviceModel?: unknown;
  locale?: unknown;
  timezone?: unknown;
  installHash?: unknown;
} & Record<string, unknown>) | null | undefined;

export type NormalizedReport = {
  category: ReportCategory;
  title: string;
  description: string;
  screen?: string;
  appVersion?: string;
  buildNumber?: string;
  iosVersion?: string;
  deviceModel?: string;
  locale?: string;
  timezone?: string;
  installHash?: string;
};

export type GitHubIssueInput = {
  title: string;
  body: string;
  labels: string[];
};

export type GitHubIssueResult = {
  issueNumber: number;
  issueUrl?: string;
};

export type GitHubClient = {
  createIssue(input: GitHubIssueInput): Promise<GitHubIssueResult>;
};
