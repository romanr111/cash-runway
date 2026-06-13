export type ReportingEnv = {
  enabled: boolean;
  missing: string[];
  reportSecret?: string;
  githubAppId?: string;
  githubInstallationId?: string;
  githubPrivateKey?: string;
  githubRepoOwner?: string;
  githubRepoName?: string;
  upstashRestUrl?: string;
  upstashToken?: string;
};

const requiredEnabledEnv = [
  "CASH_RUNWAY_REPORT_SECRET",
  "GITHUB_APP_ID",
  "GITHUB_APP_INSTALLATION_ID",
  "GITHUB_APP_PRIVATE_KEY",
  "GITHUB_REPO_OWNER",
  "GITHUB_REPO_NAME",
  "KV_REST_API_URL",
  "KV_REST_API_TOKEN"
] as const;

export function readReportingEnv(env: NodeJS.ProcessEnv): ReportingEnv {
  const enabled = env.REPORTING_ENABLED !== "false" && env.REPORTING_ENABLED !== "0";
  if (!enabled) {
    return { enabled, missing: [] };
  }
  const missing = requiredEnabledEnv.filter((key) => !env[key] || env[key]?.includes("replace-with"));
  return {
    enabled,
    missing,
    reportSecret: env.CASH_RUNWAY_REPORT_SECRET,
    githubAppId: env.GITHUB_APP_ID,
    githubInstallationId: env.GITHUB_APP_INSTALLATION_ID,
    githubPrivateKey: env.GITHUB_APP_PRIVATE_KEY,
    githubRepoOwner: env.GITHUB_REPO_OWNER,
    githubRepoName: env.GITHUB_REPO_NAME,
    upstashRestUrl: env.KV_REST_API_URL,
    upstashToken: env.KV_REST_API_TOKEN
  };
}
