# Cash Runway Testing Strategy

## Validation Target

```text
70–85% risk-weighted behavior validation: unit + integration tests
10–20% confidence validation: seeded smoke / build / previews
~5% primary validation: UI/E2E
```

## Layer Definitions

### Primary Correctness Layer

Unit and integration tests in `CashRunwayCoreTests`.

This layer proves business rules, data integrity, and financial correctness. It runs fast, uses isolated temporary repositories/databases, and does not depend on the simulator or app UI.

### Secondary Confidence Layer

Build validation, SwiftUI previews, seeded debug states, and deterministic seeded smoke.

This layer catches compilation errors, obvious layout regressions, and launch-time crashes. It is cheaper than UI/E2E but does not prove deep correctness.

### Minimal UI/E2E Layer

Approximately 5% of primary risk-weighted validation.

Used only for app launch, critical navigation, and a few happy-path workflows that cannot be validated well by unit/integration tests. Run mainly in CI, not as a default local/agent loop.

## Core Rule

Business rules must not depend on UI/E2E tests as their primary validation.
If behavior can be tested through `CashRunwayCoreTests`, it should be tested there.

## Test Isolation Principles

- Use isolated temporary repositories/databases.
- Do not rely on simulator or app UI.
- Do not use global shared state.
- Prefer direct repository/core API calls.
- Assert domain state, not UI state.
- Keep fixtures small and deterministic.
