import assert from "node:assert/strict";
import test from "node:test";
import { validateReport } from "../src/reports/validateReport.js";

const validReport = {
  category: "bug",
  idempotencyKey: "a4c0af2f-73cb-4d35-a47e-7ef273fd82d1",
  title: "CSV import crashes",
  description: "The app crashes after selecting a CSV file from Files.",
  screen: "CSVImportView",
  appVersion: "1.0.0",
  buildNumber: "42",
  iosVersion: "18.7",
  deviceModel: "iPhone15,4",
  locale: "uk-UA",
  timezone: "Europe/Uzhgorod",
  installHash: "sha256:abcdef1234567890"
};

test("accepts valid bug report", () => {
  const report = validateReport(validReport);

  assert.equal(report.category, "bug");
  assert.equal(report.title, "CSV import crashes");
});

test("accepts valid improvement report", () => {
  const report = validateReport({
    ...validReport,
    category: "improvement",
    title: "Add monthly runway chart",
    description: "Please add a monthly runway chart to make cash trends easier to scan."
  });

  assert.equal(report.category, "improvement");
});

test("rejects invalid category", () => {
  assert.throws(
    () => validateReport({ ...validReport, category: "support" }),
    /Unsupported category/
  );
});

test("rejects non-object payload", () => {
  assert.throws(
    () => validateReport(null),
    /Report body must be an object/
  );
});

test("rejects short title", () => {
  assert.throws(
    () => validateReport({ ...validReport, title: "Bug" }),
    /Title must be 5-120 characters/
  );
});

test("rejects short description", () => {
  assert.throws(
    () => validateReport({ ...validReport, description: "Too short" }),
    /Description must be 20-4000 characters/
  );
});

test("rejects oversized description", () => {
  assert.throws(
    () => validateReport({ ...validReport, description: "a".repeat(4001) }),
    /Description must be 20-4000 characters/
  );
});

test("rejects CSV-like payload", () => {
  assert.throws(
    () => validateReport({
      ...validReport,
      description: "date,amount,currency,description\n2026-01-01,-1200,UAH,Rent"
    }),
    /CSV exports are not accepted/
  );
});

test("rejects base64-looking payload", () => {
  assert.throws(
    () => validateReport({
      ...validReport,
      description: "Here is a pasted blob: " + "QWxhZGRpbjpvcGVuIHNlc2FtZQ==".repeat(20)
    }),
    /Encoded blobs are not accepted/
  );
});

test("rejects log-dump-looking payload", () => {
  assert.throws(
    () => validateReport({
      ...validReport,
      description: [
        "2026-06-07T09:00:00Z ERROR Import failed with stack trace",
        "2026-06-07T09:00:01Z WARN Retrying import",
        "2026-06-07T09:00:02Z ERROR Another stack trace line"
      ].join("\n")
    }),
    /Raw logs are not accepted/
  );
});

test("rejects URL-only spam", () => {
  assert.throws(
    () => validateReport({
      ...validReport,
      title: "Please check this",
      description: "https://example.com/suspicious"
    }),
    /URL-only reports are not accepted/
  );
});

test("rejects forbidden financial fields", () => {
  assert.throws(
    () => validateReport({
      ...validReport,
      description: "My account balance is 120000 UAH and the bug is visible in export."
    }),
    /Financial data is not accepted/
  );
});

test("accepts safe finance feature wording without private values", () => {
  const report = validateReport({
    ...validReport,
    title: "Balance display is wrong",
    description: "The balance display is wrong after opening the wallet screen, but I am not including any private values."
  });

  assert.equal(report.title, "Balance display is wrong");
});

test("accepts safe Monobank token screen wording without token value", () => {
  const report = validateReport({
    ...validReport,
    title: "Monobank token screen fails",
    description: "The Monobank token screen does not show the validation error after I tap the continue button."
  });

  assert.equal(report.title, "Monobank token screen fails");
});

test("rejects pasted Monobank token value", () => {
  assert.throws(
    () => validateReport({
      ...validReport,
      description: "My Monobank token is abcdef1234567890abcdef1234567890 and validation fails."
    }),
    /Financial data is not accepted/
  );
});

test("rejects forbidden extra data fields", () => {
  assert.throws(
    () => validateReport({
      ...validReport,
      transactions: [{ amount: 120000, note: "Rent" }]
    }),
    /Forbidden report field/
  );

  assert.throws(
    () => validateReport({
      ...validReport,
      monobankToken: "abcdef1234567890abcdef1234567890"
    }),
    /Forbidden report field/
  );
});

test("rejects unsupported extra fields", () => {
  assert.throws(
    () => validateReport({
      ...validReport,
      debugDump: "The app state goes here."
    }),
    /Unsupported report field/
  );
});

const jpegBytes = Buffer.from([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46]);
const pngBytes = Buffer.from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00]);

test("accepts valid screenshot", () => {
  const report = validateReport({
    ...validReport,
    screenshots: [{ data: jpegBytes.toString("base64"), mimeType: "image/jpeg", filename: "screenshot.jpg" }]
  });

  assert.equal(report.screenshots.length, 1);
  assert.equal(report.screenshots[0].mimeType, "image/jpeg");
});

test("rejects more than three screenshots", () => {
  assert.throws(
    () => validateReport({
      ...validReport,
      screenshots: Array.from({ length: 4 }, () => ({
        data: jpegBytes.toString("base64"),
        mimeType: "image/jpeg",
        filename: "screenshot.jpg"
      }))
    }),
    /You can attach up to 3 screenshots/
  );
});

test("rejects oversized screenshot", () => {
  const large = Buffer.alloc(1_048_577, 0xFF);
  large[0] = 0xFF;
  large[1] = 0xD8;
  large[2] = 0xFF;

  assert.throws(
    () => validateReport({
      ...validReport,
      screenshots: [{ data: large.toString("base64"), mimeType: "image/jpeg", filename: "big.jpg" }]
    }),
    /Each screenshot must be smaller than 1 MB/
  );
});

test("rejects screenshot with invalid magic bytes", () => {
  assert.throws(
    () => validateReport({
      ...validReport,
      screenshots: [{ data: Buffer.from("not an image").toString("base64"), mimeType: "image/jpeg", filename: "fake.jpg" }]
    }),
    /Screenshots must be JPEG or PNG images/
  );
});

test("rejects screenshot with mism MIME type", () => {
  assert.throws(
    () => validateReport({
      ...validReport,
      screenshots: [{ data: pngBytes.toString("base64"), mimeType: "image/jpeg", filename: "mismatch.jpg" }]
    }),
    /Screenshots must be JPEG or PNG images/
  );
});
