import assert from "node:assert/strict";
import test from "node:test";
import { consoleSafeReportLogger } from "../src/security/safeLogger.js";

test("safe report logger omits title and description", () => {
  const original = console.log;
  let captured = "";
  console.log = (value?: unknown) => {
    captured = String(value);
  };

  try {
    consoleSafeReportLogger({
      reportId: "report-1",
      category: "bug",
      screen: "CSVImportView",
      appVersion: "1.0.0",
      status: "created",
      issueNumber: 123,
      durationMs: 42
    });
  } finally {
    console.log = original;
  }

  assert.doesNotMatch(captured, /title/i);
  assert.doesNotMatch(captured, /description/i);
  assert.match(captured, /CSVImportView/);
});
