# GitHub App Setup

This file documents the reporting API's GitHub App and deployment configuration.
Do not include real credentials, endpoints containing secrets, private keys, or
production tokens.

## Required GitHub App permissions

The GitHub App needs:

- **Issues: write**
- **Contents: write**

These permissions allow the API to create issues and upload screenshot
attachments so they render inline.

## Repository installation

The app must be installed on the configured repository. The default configured
repository is `romanr111/cash-runway`. Verify the installation and repository
settings before enabling reporting in a new environment.

## Required environment variables

Store all values as deployment environment variables:

- `REPORTING_ENABLED` — set to `true` to enable issue creation, or `false` to fail
  closed with HTTP 503.
- `CASH_RUNWAY_REPORT_SECRET` — shared client secret the iOS app must present.
- `GITHUB_APP_ID` — the GitHub App identifier.
- `GITHUB_APP_INSTALLATION_ID` — the installation identifier for the repository.
- `GITHUB_APP_PRIVATE_KEY` — the App's private key in PEM format.
- `GITHUB_REPO_OWNER` — repository owner.
- `GITHUB_REPO_NAME` — repository name.
- `KV_REST_API_URL` — Upstash Redis REST URL for rate limiting and duplicate
  suppression.
- `KV_REST_API_TOKEN` — Upstash Redis REST token.

## Labels and issue formatting

The API formats issues server-side with safe labels. Preserve the existing issue
template and label set. Do not expose raw provider responses or user-controlled
markdown without sanitization.

## Vercel/deployment configuration

- Use separate Vercel projects or environment variable sets for staging and
  production.
- Point debug iOS builds at local/staging endpoints.
- Release builds should receive only the production endpoint and shared client
  secret through build configuration.
- Do not enable reporting with placeholder or incomplete configuration.

## Safe troubleshooting

- Verify `REPORTING_ENABLED` is set explicitly.
- Check that all GitHub App environment variables are present and valid.
- Confirm the app is still installed on the target repository.
- Inspect structured server logs for allowlisted fields only; do not log raw
  request bodies or secrets.
- Use synthetic data and a staging project when testing issue creation.

## Deployment protection

Vercel deployment protection may block unauthenticated requests. If staging smoke
fails with an unexpected gateway response, verify whether deployment protection
is enabled and whether the test client is allowed through.
