import assert from "node:assert/strict";
import test from "node:test";
import { readReportingEnv } from "../src/config/reportingEnv.js";

const completeEnv = {
  REPORTING_ENABLED: "true",
  CASH_RUNWAY_REPORT_SECRET: "shared-secret",
  GITHUB_APP_ID: "12345",
  GITHUB_APP_INSTALLATION_ID: "67890",
  GITHUB_APP_PRIVATE_KEY: "-----BEGIN PRIVATE KEY-----\\nkey\\n-----END PRIVATE KEY-----",
  GITHUB_REPO_OWNER: "romanr111",
  GITHUB_REPO_NAME: "cash-runway",
  UPSTASH_REDIS_REST_URL: "https://example.upstash.io",
  UPSTASH_REDIS_REST_TOKEN: "upstash-token"
};

test("enabled reporting requires all deployment env vars", () => {
  const config = readReportingEnv({
    ...completeEnv,
    UPSTASH_REDIS_REST_TOKEN: undefined
  });

  assert.equal(config.enabled, true);
  assert.deepEqual(config.missing, ["UPSTASH_REDIS_REST_TOKEN"]);
});

test("disabled reporting does not require secrets", () => {
  const config = readReportingEnv({ REPORTING_ENABLED: "false" });

  assert.equal(config.enabled, false);
  assert.deepEqual(config.missing, []);
});
