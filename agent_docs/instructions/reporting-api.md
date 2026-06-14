# Reporting API Instructions

## Scope

These rules apply to `reporting-api/**`.

Follow the existing Node.js and TypeScript architecture. Prefer small changes and
existing service boundaries.

## Request validation

- Preserve strict request validation.
- Preserve payload-size limits.
- Reject unknown, malformed, or oversized fields.
- Sanitize all user-controlled text before adding it to GitHub issues.
- Do not expose raw validation-library or provider errors to clients.

## Security and privacy

- Keep GitHub App credentials server-side.
- Keep deployment secrets in environment variables.
- Never include private keys, tokens, installation identifiers, authorization
  headers, or raw provider responses in logs or API responses.
- Preserve safe diagnostic allowlists.
- Do not accept screenshots, documents, arbitrary files, raw logs, databases, or
  financial data unless separately requested as an approved architecture change.

## GitHub App integration

- Preserve minimum required GitHub App permissions.
- Preserve repository and installation validation.
- Preserve safe issue formatting and expected labels.
- Preserve mockable GitHub-client boundaries.
- Map GitHub provider failures to stable, safe application errors.

## Idempotency and abuse protection

- Preserve idempotency-key handling.
- Preserve duplicate suppression.
- Preserve Redis/Upstash-backed rate limiting.
- Avoid changes that allow retry storms or duplicate GitHub issues.
- Keep rate-limit and duplicate-detection behavior testable.

## Logging

- Log structured, allowlisted fields only.
- Never log full user descriptions when not required.
- Never log secrets, authorization headers, raw request bodies, or sensitive
  diagnostics.
- Preserve correlation and failure information needed for debugging without
  exposing private values.

## Validation

During implementation, run the smallest relevant API test subset where available.

Before completion of API changes, run:

```bash
cd reporting-api
npm test
npm run typecheck
```

Run:

```bash
npm audit --omit=dev
```

when dependencies change or when publish-readiness/security verification is
explicitly required.
