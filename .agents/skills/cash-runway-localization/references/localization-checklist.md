# Cash Runway Localization Checklist

## Resources and project wiring

- Keep development region `en`.
- Add `uk` to Xcode known regions.
- Add `AppHost/Localizable.xcstrings` to app resources.
- Validate `.xcstrings` with JSON parsing, not `plutil`.
- Include `en` and `uk` localizations for every v1 app catalog key.

## Language preference

- Preference enum: `system`, `en`, `uk`.
- Storage key: `cashRunway.languagePreference`.
- `system` resolves from iOS preferred languages.
- Ukrainian preferred language maps to `uk`.
- Unsupported languages fall back to `en`.
- Selection must update visible SwiftUI UI immediately.

## SwiftUI and dynamic lookup

- Static literals: use SwiftUI literals or `LocalizedStringKey`.
- Dynamic/interpolated strings: use a helper backed by selected-language `.lproj` bundle lookup.
- Dates: create formatters with the selected locale at the UI boundary.
- Plurals/counts: cover wallets, labels, templates, transactions, cards, rows, and category summary counts.
- Avoid root `.id(locale)` unless resetting model/navigation state is intended.

## Built-in category names

- Display-localize only stable seed UUIDs.
- Use localized names in lists, pickers, charts, legends, accessibility labels, and summaries where the stable ID is available.
- Do not rename database rows.
- Do not localize transaction-list category text unless the row model exposes a stable category ID.
- Do not change CSV import matching, backups, merge/remap logic, or search tables just to localize display text.

## User data that must stay untranslated

- Wallet names.
- User-created category names without stable built-in IDs.
- Merchant names.
- Notes.
- User labels.
- CSV row values and headers.
- Backup JSON contents.
- Raw bank data.
- Low-level debug diagnostics not shown in normal UI.

## Screenshot and smoke checklist

Verify at least:

- Default/system launch shows English or the system-resolved language.
- Ukrainian selection shows localized Timeline title, wallet/period pills, chart month, date header, overview button, and tabs.
- More > Settings > Language shows System, English, and Українська with existing compact settings styling.
- Category Management shows built-in category names localized by stable ID and summary/buttons fitting in Ukrainian.
- One editor or alert path updates in selected language.
- Returning to English updates visible UI.

For layout, check Ukrainian text fit in:

- Pills.
- Segmented controls.
- Toolbar and bottom action buttons.
- Compact rows.
- Alerts/sheets.
