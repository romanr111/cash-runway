Goal: Fix the CSV import scope work and keep the core source/package trees identical.

State:
- Working in the root checkout on `main`.
- `just mirror-core` required `--force` because the package mirror already had local edits; the sync completed and `Sources/CashRunwayCore` now matches `Modules/CashRunwayCorePackage/Sources/CashRunwayCore`.
- The two test files that were suspected of syntax breakage parse cleanly with `swiftc -parse`.

Implemented / verified:
- `CSVImportRowFilter` is threaded through `CSVService`, `CashRunwayAppModel`, `CSVImportCoordinator`, and `CSVImportView`.
- `CSVEdgeCaseTests` and `MonobankCSVImportTests` cover the expenses-only path.
- `git diff --check` passes.
- `diff -rq Sources/CashRunwayCore Modules/CashRunwayCorePackage/Sources/CashRunwayCore` is clean.

Validation:
- `swiftc -parse Tests/CashRunwayCoreTests/MonobankCSVImportTests.swift` passed.
- `swiftc -parse Tests/CashRunwayCoreTests/DatabaseLifecycleTests.swift` passed.
- `just build` failed in `xcodebuild` while resolving package dependencies because SwiftPM diagnostic `.dia` files could not be written under `~/Library/Caches/org.swift.swiftpm/...` in this environment.
- `just test-filter DatabaseLifecycleTests` failed earlier with a SwiftPM manifest/toolchain error before compilation: `Invalid manifest "-target", "x86_64-apple-macosx14.0"`.

Open questions:
- Whether the build/test environment needs an isolated scratch path or different Xcode/SwiftPM cache permissions for a full compile/test pass.
