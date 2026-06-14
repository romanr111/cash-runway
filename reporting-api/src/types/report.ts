export type ReportCategory = "bug" | "improvement";

export type ReportInput = ({
  category?: unknown;
  idempotencyKey?: unknown;
  title?: unknown;
  description?: unknown;
  screen?: unknown;
  screenshots?: unknown;
  appVersion?: unknown;
  buildNumber?: unknown;
  iosVersion?: unknown;
  deviceModel?: unknown;
  locale?: unknown;
  timezone?: unknown;
  installHash?: unknown;
} & Record<string, unknown>) | null | undefined;

export type ReportScreenshot = {
  data: string;
  mimeType: string;
  filename: string;
};

export type DecodedScreenshot = {
  buffer: Buffer;
  mimeType: "image/jpeg" | "image/png";
  filename: string;
};

export type NormalizedReport = {
  category: ReportCategory;
  title: string;
  description: string;
  screen?: string;
  screenshots: DecodedScreenshot[];
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
  uploadFile(path: string, content: Buffer, message: string): Promise<GitHubFileUploadResult>;
};

export type GitHubFileUploadResult = {
  rawUrl: string;
};
