# Simulator Smoke Notes

This is reference material for interpreting simulator smoke output. For the
executable smoke script, see `Scripts/smoke-seeded-simulator.sh`.

## Empty runtime snapshots

XcodeBuildMCP runtime snapshots may return no element refs for this app. If a
settled seeded launch returns an empty runtime snapshot once, do not keep
retrying tap/type navigation. Use screenshot evidence plus a runtime/os log scan,
report that interactive smoke was blocked by empty runtime snapshots, and do not
run local UI/E2E tests.

## Stale build artifacts

A legacy `$PROJECT_DIR/DerivedData/` directory may contain old simulator builds.
If smoke tests behave unexpectedly (missing new UI, empty seeded data, or sheets
not presenting), verify the installed `.app` is fresh. The smoke script resolves
the true build path via `xcodebuild -showBuildSettings`.

## Simulator selection and launch

The default smoke destination is the newest available iPhone simulator. When the
default simulator is unavailable, the script selects the newest available device
and records the exact name. Prefer deterministic seeded scenarios over manual
navigation.

## Seeded scenarios

The smoke script uses deterministic data seeded through `UITestRuntime.swift`.
Known scenarios include transaction core, category merge, category editor, and
Monobank first-start flows. Inspect `AppHost/UITestRuntime.swift` for the current
scenario list and the variables that control them.

## Benign runtime-log patterns

Some framework messages during launch are expected and do not indicate a defect.
Treat repeated crashes, missing root views, or seeded-data errors as failures;
treat one-off metadata warnings as benign unless they correlate with broken
functionality.

## Screenshot-only evidence

A successful screenshot proves the app launched and rendered a view. It does not
prove interactive correctness, data persistence, or network behavior. Pair
screenshots with log scans and, where practical, targeted package tests.
