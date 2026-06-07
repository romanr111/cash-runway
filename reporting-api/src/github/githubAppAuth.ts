import { createAppAuth } from "@octokit/auth-app";

export type GitHubAppConfig = {
  appId: string;
  privateKey: string;
  installationId: string;
};

export async function createInstallationToken(config: GitHubAppConfig): Promise<string> {
  const auth = createAppAuth({
    appId: config.appId,
    privateKey: config.privateKey,
    installationId: config.installationId
  });
  const installationAuth = await auth({ type: "installation" });
  return installationAuth.token;
}
