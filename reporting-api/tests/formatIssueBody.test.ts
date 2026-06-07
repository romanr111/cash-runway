import assert from "node:assert/strict";
import test from "node:test";
import { formatIssueBody, formatIssueTitle, issueLabels } from "../src/reports/formatIssueBody.js";
import type { NormalizedReport } from "../src/types/report.js";

const report: NormalizedReport = {
  category: "bug",
  title: "CSV import crashes",
  description: "The app crashes after selecting a CSV file.",
  screen: "CSVImportView",
  appVersion: "1.0.0",
  buildNumber: "42",
  iosVersion: "18.7",
  deviceModel: "iPhone15,4",
  locale: "uk-UA",
  timezone: "Europe/Uzhgorod",
  installHash: "sha256:abcdef"
};

test("formats bug title correctly", () => {
  assert.equal(formatIssueTitle(report), "[Bug] CSV import crashes");
});

test("formats improvement title correctly", () => {
  assert.equal(
    formatIssueTitle({ ...report, category: "improvement", title: "Add monthly runway chart" }),
    "[Improvement] Add monthly runway chart"
  );
});

test("applies correct labels", () => {
  assert.deepEqual(issueLabels(report), ["user-report", "bug", "ios", "needs-triage"]);
  assert.deepEqual(issueLabels({ ...report, category: "improvement" }), ["user-report", "improvement", "ios", "needs-triage"]);
});

test("includes safe diagnostics", () => {
  const body = formatIssueBody(report);

  assert.match(body, /\*\*Screen:\*\* CSVImportView/);
  assert.match(body, /- App version: 1\.0\.0/);
  assert.match(body, /- Build: 42/);
  assert.match(body, /- Install hash: sha256:abcdef/);
});

test("excludes forbidden financial fields", () => {
  const body = formatIssueBody({
    ...report,
    description: "The app crashes after selecting a CSV file.",
    installHash: "sha256:redacted-install"
  });

  assert.doesNotMatch(body, /120000 UAH/i);
  assert.doesNotMatch(body, /4242 4242/i);
  assert.match(body, /No financial database, transaction export, Monobank token, CSV file, screenshot, or raw logs were uploaded automatically/);
});
