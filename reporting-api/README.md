# Cash Runway Reporting API

Text-only feedback intake for Cash Runway.

The iOS app posts bug/improvement reports to `POST /api/reports`. The API validates and sanitizes the report, then creates a GitHub issue server-side through a GitHub App installation token.

## Payload

```json
{
  "category": "bug",
  "idempotencyKey": "a4c0af2f-73cb-4d35-a47e-7ef273fd82d1",
  "title": "CSV import crashes",
  "description": "The app crashes after selecting a CSV file.",
  "screen": "CSVImportView",
  "appVersion": "1.0.0",
  "buildNumber": "42",
  "iosVersion": "18.7",
  "deviceModel": "iPhone15,4",
  "locale": "uk-UA",
  "timezone": "Europe/Uzhgorod",
  "installHash": "sha256..."
}
```

## Safety

This MVP is text-only. It does not accept screenshots, logs, CSV files, database files, balances, transactions, or Monobank tokens.

The API enforces `application/json`, a 32 KB request body limit, duplicate suppression for 24 hours, and Redis-backed limits:

- 3 reports/hour per `installHash`
- 10 reports/day per `installHash`
- 10 reports/hour per IP when `installHash` is missing

Server logs must not include report title or description. Only safe metadata is logged: report id, category, screen, app version, status, issue number, and duration.

## Setup

Copy `.env.example` into Vercel environment variables after creating and installing the GitHub App. The app needs Issues: write permission on `romanr111/cash-runway`.

Required enabled configuration:

- `REPORTING_ENABLED=true`
- `CASH_RUNWAY_REPORT_SECRET`
- `GITHUB_APP_ID`
- `GITHUB_APP_INSTALLATION_ID`
- `GITHUB_APP_PRIVATE_KEY`
- `GITHUB_REPO_OWNER`
- `GITHUB_REPO_NAME`
- `KV_REST_API_URL`
- `KV_REST_API_TOKEN`

Set `REPORTING_ENABLED=false` to fail closed with HTTP 503 without creating issues.

Use separate Vercel projects or environment variable sets for staging and production. Point debug iOS builds at local/staging endpoints; release builds should only receive the production endpoint and shared client secret through build configuration.

## Staging E2E Readiness

1. Create a GitHub App with Issues: write.
2. Install it on `romanr111/cash-runway`.
3. Create an Upstash Redis database and copy the REST URL/token into Vercel.
4. Create a Vercel staging project with the enabled environment variables above.
5. Configure a debug build with the staging endpoint and client secret.
6. Submit one text-only report from Simulator/device and confirm exactly one GitHub issue is created.
7. Re-submit the same report and confirm the API returns a duplicate/rate-limit error instead of creating another issue.

```bash
npm install
npm test
npm run typecheck
```
