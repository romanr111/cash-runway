---
name: cash-runway-localization
description: Cash Runway English/Ukrainian localization workflow for .xcstrings resources, in-app language selection, SwiftUI literal and dynamic string lookup, selected-locale date formatting, built-in category display names, Ukrainian screenshot checks, and user-data translation boundaries. Use for Cash Runway i18n/localization implementation, review, validation, or debugging.
---

# Cash Runway Localization

Use this skill when implementing or reviewing Cash Runway localization. It captures the repo-specific traps from English/Ukrainian work.

## Core Rules

- Use `.xcstrings` for app strings.
- Validate `.xcstrings` as JSON, not with `plutil`.
- Test SwiftUI literal localization separately from dynamic helper lookup.
- Prefer explicit `.lproj` bundle lookup for dynamic strings under an in-app selected language.
- Format dates at the UI boundary with the selected locale.
- Localize built-in category display names by stable seed UUID only.
- Never translate user data.

## Implementation Workflow

Read `references/localization-checklist.md` before editing a non-trivial localization change.

Required behavior for Cash Runway:

- Default language preference is `system`.
- Supported explicit preferences are `en` and `uk`.
- Use storage key `cashRunway.languagePreference`.
- Ukrainian system languages resolve to `uk`; unsupported system languages fall back to `en`.
- Keep project development region as English and add `uk` to known regions/resources.

## String Lookup

Use SwiftUI literals or `LocalizedStringKey` for static visible labels.

Use a dynamic helper for computed/interpolated strings. Verify it resolves the selected language through an `.lproj` bundle, not only the process locale:

```swift
if let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
   let localizedBundle = Bundle(path: path) {
    return localizedBundle.localizedString(forKey: key, value: key, table: nil)
}
return Bundle.main.localizedString(forKey: key, value: key, table: nil)
```

Do not reset the whole SwiftUI app tree with `.id(locale)` unless losing navigation/model state is explicitly acceptable.

## Data Boundaries

Only display-localize system-owned values with stable identity.

Do localize:

- Built-in category display names mapped by seed UUID.
- UI-authored labels, buttons, settings rows, empty states, alerts, and accessibility labels.
- Plural/count text and UI date labels.

Do not localize:

- Wallet names.
- User-created category names not matched by stable seed UUID.
- Merchant names, notes, user labels, CSV cell values, backup contents, bank raw data.
- Raw low-level diagnostics unless they are normal user-facing UI.

## Validation

Validate the catalog with the bundled script:

```bash
ruby "${SKILL_DIR}/scripts/validate_xcstrings_json.rb" AppHost/Localizable.xcstrings
```

Required screenshot coverage for UI localization work:

- Timeline.
- More > Settings > Language.
- Category Management.
- One editor or alert path.

Check Ukrainian text fit in pills, segmented controls, bottom action buttons, compact rows, and alerts. Screenshot evidence is acceptable when interactive simulator snapshots are empty.
