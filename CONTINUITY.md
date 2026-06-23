# Continuity Ledger - Generic CSV Source Semantics

## Final state
- PR #63 ready for review. All findings addressed.
- All CI checks green on head `8abaa94`.
- PR is no longer draft.

## Checklist status
| Item | Status |
|------|--------|
| `importFormat` in coordinator | ✅ |
| App target build in CI | ✅ (new job) |
| CSV/XLSX migration | ✅ (extension-aware) |
| Provider detection tightened | ✅ |
| Missing `@Test` added | ✅ |
| Debit/Credit income inference | ✅ |
| Legacy preset → format adapter | ✅ |
| Legacy fingerprint namespace | ✅ |
| Integration with main (#64/#65) | ✅ (merge + rowFilter) |
| Localizable.xcstrings restored | ✅ (from main) |
| Legacy generic dedup documented | ✅ (known-issue tests) |
| CI green | ✅ (run 27972568835) |
| Draft → Ready | ✅ |
| PR description updated | ✅ |

## Known accepted limitations (deferred)
1. `previewPreparedRows` / `importStatement` duplicated loops — shared extraction deferred
2. Legacy generic CSV dedup broken for MCC/alias/unknown-category paths — dual-fingerprint compatibility deferred (pre-alpha limitation, documented as known issue in tests)
3. Temu override uses `contains("temu")` substring — safe for current data