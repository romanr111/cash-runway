import type { NormalizedReport } from "../types/report.js";

export function formatIssueTitle(report: NormalizedReport): string {
  return `[${report.category === "bug" ? "Bug" : "Improvement"}] ${report.title}`;
}

export function issueLabels(report: NormalizedReport): string[] {
  return ["user-report", report.category, "ios", "needs-triage"];
}

export function formatIssueBody(report: NormalizedReport): string {
  const categoryTitle = report.category === "bug" ? "Bug" : "Improvement";
  const lines = [
    "## User report",
    `**Category:** ${categoryTitle}`,
    `**Screen:** ${report.screen ?? "Not provided"}`,
    "",
    "## Description",
    report.description,
    "",
    "## Safe diagnostics",
    `- App version: ${report.appVersion ?? "unknown"}`,
    `- Build: ${report.buildNumber ?? "unknown"}`,
    `- iOS: ${report.iosVersion ?? "unknown"}`,
    `- Device: ${report.deviceModel ?? "unknown"}`,
    `- Locale: ${report.locale ?? "unknown"}`,
    `- Timezone: ${report.timezone ?? "unknown"}`,
    `- Install hash: ${report.installHash ?? "not provided"}`,
    "",
    "## Privacy note",
    "This report was submitted from the app. No financial database, transaction export, Monobank token, CSV file, screenshot, or raw logs were uploaded automatically."
  ];
  return lines.join("\n");
}
