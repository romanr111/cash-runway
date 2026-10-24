# Річний ретроспективний експорт (якщо є всі 12 місяців)

**Залежність:** будується НАД PR #124 (гілка `feature/issue-122-retrospective-export`); stacked-PR з base = гілка #124, після мержу #124 — ретаргет на `dev`.
**Семантика:** річний рядок — це **сума 12 місячних рядків** (native + USD), НЕ пов'язана з `TimelinePeriod.year` (той агрегує транзакції напряму; ретроспектива — store-once снапшоти).

## Головне рішення (умова повноти)

Річний підсумок додається **тільки коли в році є всі 12 завершених місяців** —
 і правило застосовується **окремо для кожної (рік, валюта)**: валюта, що
трапляється менше ніж у 12 місяцях року, річного рядка не отримує (сума за 1
місяць із підписом «рік» читалась би як повний рік). Частковий рік НЕ
сумаризується — деталі місяців і так показують реальне охоплення.

## QA-нотатки (другий прохід, виправлено в місці)

1. **Ім'я файлу**: межі діапазону беруться лише з місячних рядків — річний
   рядок (`2026 (year)`) псував би `cash-runway-retrospective-…-2026 (year).csv`
   (виправлено в `AppModel.exportMonthlyRetrospective`).
2. **Per-currency повнота**: v1 рахувала місяці по всіх валютах разом —
   USD з одним місяцем отримав би «річний» рядок; виправлено на
   `per (year, currency)` + 2 тести (1-місячна валюта → рядка нема;
   дві валюти × 12 місяців → два рядки).

## План (T1–T4)

### T1 — Exporter: річні рядки в `MonthlyRetrospectiveExport.rows(from:)`

Файл: `Sources/CashRunwayCore/Export/MonthlyRetrospectiveExport.swift`

1. Після групування по `(monthKey, currency)` порахувати для кожного року
   множину місяців (`Set(monthKey / 100)`): рік **повний** ⇔ рівно 12 ключів.
2. Для кожного повного року + кожної валюти: новий `Row` з
   `month: "\(year) (year)"` (`"2026 (year)"`), суми = суми 12 місячних груп
   (native через `reduce`, USD через існуючий `sumBase` — ті самі guards:
   single base + all-non-nil, інакше USD-колонки nil).
3. `rate`/`rateEffectiveDate`/`rateSource` для річного рядка = `nil`
   (у року 12 різних курсів; єдиний «річний курс» — брехня).
   `approximate` = OR по групах року.
4. Річні рядки йдуть **після** 12 місячних рядків свого року (сортування:
   за роком, тип-рядка місяць<рік).
5. Header не змінюється (13 колонок як є) — річний рядок у тій самій схемі.

### T2 — XLSX/CSV без змін + ім'я файлу

- `MonthlyRetrospectiveXLSX.export(csvRows:)` приймає `[[String]]` — рядки з
  `"(year)"` проходять без правок (перевірити тестом round-trip).
- `ExportFile.name` вже працює (first/last беруться з усіх рядків).
- Тест: `yearlyRowsAppendAfterTwelveCompleteMonths` +
  `partialYearProducesNoYearlyRow` (11 місяців → 0 річних рядків).

Gate: toolchain `swift test --filter MonthlyRetrospective` (обидва suite'и,
має стати 19+3). Commit: `feat(export): yearly retrospective rows when all 12 months present`.

### T3 — UI: вибір періоду в Settings-діалозі

Файл: `Sources/CashRunwayUI/SettingsView.swift` (+ localization)

1. `enum RetrospectiveExportScope { case monthly, yearly }` (UI-локальний,
   або просто 2 кнопки-режими).
2. У діалозі: заголовок → 2 групи кнопок: «Помісячно» / «За рік (усі 12
   місяців)»; формат xlsx/csv другий крок ( або один крок: 4 кнопки).
   Простіше v1: перший крок — вибір scope, другий — формат.
3. `AppModel.exportMonthlyRetrospective(format:)` отримає параметр
   `scope:`; в акторі: `scope == .yearly` → фільтр snapshot-ів на роки з 12
   місяцями → `rows(from:)` (експортер сам додає річні рядки) — або в v1
   експортуємо весь діапазон і річні рядки просто присутні.
   **Рішення v1:** окремий scope «За рік» експортує ТІЛЬКИ річні рядки
   (12+ місяців на рік); «Помісячно» — як зараз (тільки місячні, без річних).
4. Локалізація нових кнопок через `Scripts/localize-xcstrings.py`
   (файл payload — untracked).

Gate: `-parse`, lint 0. Commit: `feat(ui): yearly retrospective export scope in settings`.

### T4 — CI + PR plumbing

- CI прогнати (unit + integration + Xcode App Build).
- Stacked PR `feature/issue-123-yearly-retrospective-export` з base =
  `feature/issue-122-retrospective-export`.

## Критерії приймання (requirement → evidence)

| Вимога | Доказ |
|---|---|
| Річний рядок тільки при 12 місяцях | тест `partialYearProducesNoYearlyRow` |
| Суми = сума 12 місячних | тест `yearlyRowsAppendAfterTwelveCompleteMonths` (точні числа) |
| USD guards ті самі | тест mixed/unconverted на річному рівні |
| Без «єдиного річного курсу» | річний рядок: rate/date/source nil — pinned тестом |
| CSV і XLSX відкриваються | XLSX round-trip тест з річним рядком |
| Список рядків: рік після своїх 12 місяців | порядок pinned тестом |

## Ризики

- Плутанина «year (year)»: місячний рядок `2026-06`, річний `2026 (year)` —
  зрозуміло в Excel.
- `approximate` OR-логіка: річний рядок з ≈, якщо хоч один місяць ≈.
- Якщо #124 змінить схему рядків до мержу — rebase stacked-гілки (класично).