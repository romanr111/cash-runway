import assert from "node:assert/strict";
import test from "node:test";
import { duplicateHash } from "../src/reports/duplicateHash.js";
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

test("same normalized report gives same hash", () => {
  assert.equal(duplicateHash(report), duplicateHash({ ...report }));
});

test("different report gives different hash", () => {
  assert.notEqual(
    duplicateHash(report),
    duplicateHash({ ...report, description: "The app freezes after selecting a CSV file." })
  );
});

test("screen changes do not affect duplicate hash", () => {
  assert.equal(
    duplicateHash(report),
    duplicateHash({ ...report, screen: "SettingsView" })
  );
});
