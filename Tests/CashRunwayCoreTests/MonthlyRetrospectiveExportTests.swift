import Testing
import Foundation
import CoreXLSX
@testable import CashRunwayCore

/// Issue #123: export rendering of stored retrospective snapshots.
@Suite(.serialized)
struct MonthlyRetrospectiveExportTests {
    private func snapshot(
        monthKey: Int,
        currency: CurrencyCode,
        income: Int64,
        expense: Int64,
        saved: Int64? = nil,
        baseCurrency: CurrencyCode = .usd,
        incomeBase: Int64? = nil,
        expenseBase: Int64? = nil,
        rate: String? = "0.024242424242424242424242424242424242",
        effectiveDate: Date? = nil,
        source: String? = "nbu-official",
        approximate: Bool = false
    ) -> MonthlyUSDSnapshot {
        let savedMinor = saved ?? (income - expense)
        return MonthlyUSDSnapshot(
            monthKey: monthKey,
            walletID: UUID(),
            currencyCode: currency,
            incomeMinor: income,
            expenseMinor: expense,
            savedMinor: savedMinor,
            baseCurrencyCode: baseCurrency,
            incomeBaseMinor: incomeBase,
            expenseBaseMinor: expenseBase,
            savedBaseMinor: incomeBase.map { $0 - (expenseBase ?? 0) },
            rateDecimal: rate,
            rateEffectiveDate: effectiveDate,
            rateSource: source,
            isApproximate: approximate,
            updatedAt: isoDate("2026-06-30T19:00:00Z")
        )
    }

    private func isoDate(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: string)!
    }

    @Test func noDataThrows() throws {
        #expect(throws: MonthlyRetrospectiveExportError.self) {
            try MonthlyRetrospectiveExport.rows(from: [])
        }
    }

    @Test func escapesQuotesAndCommas() throws {
        let csv = MonthlyRetrospectiveExport.csv(rows: [
            MonthlyRetrospectiveExport.Row(
                month: "2026-06", baseCurrency: "USD", currency: "UAH",
                income: "41,250.00", expenses: "100", saved: "41,150.000",
                incomeUSD: "1000", expensesUSD: "2", savedUSD: "998",
                rate: "0.024242424242", rateEffectiveDate: "2026-06-30",
                rateSource: "nbu", approximate: false
            ),
        ])
        // Fields are wrapped in quotes; embedded quotes doubled.
        #expect(csv.contains("\"41,250.00\""))
        #expect(csv.contains("\"41,150.000\""))
        let firstLine = csv.split(separator: "\n").first.map(String.init) ?? ""
        #expect(firstLine.contains("\"Rate (Currency→USD)\""))
    }

    @Test func headerAlwaysPresentEvenWithNoRows() throws {
        let csv = MonthlyRetrospectiveExport.csv(rows: [])
        #expect(csv.split(separator: "\n").count == 1)
        #expect(csv.contains("Month") && csv.contains("Approximate"))
    }

    /// Formula injection (OWASP Spreadsheet Injection): a cell whose first
    /// character is `=`, `+`, `-`, `@`, tab, or CR must be neutralized with a
    /// leading apostrophe after quote-doubling, or spreadsheet apps execute it
    /// as a formula on open.
    @Test func formulaInjectionNeutralized() throws {
        func cell(_ value: String) -> String {
            MonthlyRetrospectiveExport.escape(value)
        }
        #expect(cell("=SUM(1+1)").hasPrefix("'"))
        #expect(cell("+1+2").hasPrefix("'"))
        #expect(cell("-1+2").hasPrefix("'"))
        #expect(cell("@import").hasPrefix("'"))
        #expect(cell("\tSUM(1+1)").hasPrefix("'"))
        #expect(cell("\rSUM(1+1)").hasPrefix("'"))
        // Neutralized cell = apostrophe + quoted-and-doubled content.
        #expect(cell("=SUM(1+1)") == "'\"=SUM(1+1)\"")
        // Benign cells are untouched (no apostrophe added).
        #expect(cell("41250.00") == "\"41250.00\"")
        #expect(cell("2026-06") == "\"2026-06\"") // leading digit, not '-'
        #expect(cell("nbu-official") == "\"nbu-official\"")
        #expect(cell("") == "\"\"")
        #expect(cell("say \"hi\"") == "\"say \"\"hi\"\"\"")
    }

    /// End-to-end: hostile values flowing through the full CSV export land in
    /// the emitted data rows prefixed with an apostrophe.
    @Test func csvDataRowsNeutralizeFormulaLikeCells() throws {
        let row = MonthlyRetrospectiveExport.Row(
            month: "2026-06", baseCurrency: "=SUM(1+1)", currency: "+1+2",
            income: "41,250.00", expenses: "-1+2", saved: "@import",
            incomeUSD: "1000", expensesUSD: "2", savedUSD: "998",
            rate: "0.0242", rateEffectiveDate: "2026-06-30",
            rateSource: "\tnbu", approximate: false
        )
        let csv = MonthlyRetrospectiveExport.csv(rows: [row])
        let dataLine = csv.split(separator: "\n").dropFirst().first.map(String.init) ?? ""
        #expect(dataLine.contains("'\"=SUM(1+1)\""))
        #expect(dataLine.contains("'\"+1+2\""))
        #expect(dataLine.contains("'\"-1+2\""))
        #expect(dataLine.contains("'\"@import\""))
        #expect(dataLine.contains("'\"\tnbu\""))
        // Header is benign — no neutralization there.
        let headerLine = csv.split(separator: "\n").first.map(String.init) ?? ""
        #expect(!headerLine.hasPrefix("'"))
    }

    @Test func groupsByMonthAndCurrencySumsWallets() throws {
        let rows = try MonthlyRetrospectiveExport.rows(from: [
            snapshot(monthKey: 202606, currency: .uah, income: 1_000_000, expense: 500_000),
            snapshot(monthKey: 202606, currency: .uah, income: 2_000_000, expense: 600_000),
            snapshot(monthKey: 202605, currency: .uah, income: 1, expense: 1),
        ])
        #expect(rows.count == 2)
        #expect(rows[0].month == "2026-05") // sorted by month ascending
        #expect(rows[1].month == "2026-06")
        #expect(rows[1].income == "30000.00")
        #expect(rows[1].expenses == "11000.00")
        #expect(rows[1].saved == "19000.00")
    }

    @Test func unconvertedRowLeavesUSDColumnsEmpty() throws {
        let rows = try MonthlyRetrospectiveExport.rows(from: [
            snapshot(monthKey: 202606, currency: .uah, income: 4_125_000, expense: 100_000, rate: nil, source: nil),
        ])
        let row = rows[0]
        #expect(row.income == "41250.00")
        #expect(row.incomeUSD == nil)
        #expect(row.expensesUSD == nil)
        #expect(row.savedUSD == nil)
        #expect(row.rate == nil)
        #expect(row.rateEffectiveDate == nil)
        #expect(row.rateSource == nil)
        #expect(row.approximate == false)
        #expect(row.cells[6] == "") // Income USD cell empty in CSV
        let csv = MonthlyRetrospectiveExport.csv(rows: rows)
        #expect(csv.contains(",\"\",\"\",\"\",\"\",\"\",\"no\"")) // trailing empty fields then Approximate
    }

    @Test func convertedRowCarriesRateMetadataAndApproximate() throws {
        let juneEnd = isoDate("2026-06-30T00:00:00Z")
        let rows = try MonthlyRetrospectiveExport.rows(from: [
            snapshot(monthKey: 202606, currency: .uah, income: 4_125_000, expense: 500_000, incomeBase: 100_000, expenseBase: 12_121, effectiveDate: juneEnd, approximate: true),
        ])
        let row = rows[0]
        #expect(row.incomeUSD == "1000.00")
        #expect(row.savedUSD == "878.79") // 100000 - 12121 = 87879 → 878.79
        #expect(row.rate == "0.024242424242424242424242424242424242") // verbatim
        #expect(row.rateEffectiveDate == "2026-06-30")
        #expect(row.rateSource == "nbu-official")
        #expect(row.approximate == true)
        #expect(row.cells[12] == "yes")
    }

    @Test func approximateFlagFromAnyWalletInGroup() throws {
        let rows = try MonthlyRetrospectiveExport.rows(from: [
            snapshot(monthKey: 202606, currency: .uah, income: 1_000, expense: 0, incomeBase: 24, expenseBase: 0, approximate: false),
            snapshot(monthKey: 202606, currency: .uah, income: 2_000, expense: 0, incomeBase: 48, expenseBase: 0, approximate: true),
        ])
        #expect(rows.count == 1)
        #expect(rows[0].approximate == true)
    }

    @Test func partialConversionRendersWholeGroupUnconverted() throws {
        let rows = try MonthlyRetrospectiveExport.rows(from: [
            snapshot(monthKey: 202606, currency: .uah, income: 1_000, expense: 0, incomeBase: 24, expenseBase: 0),
            snapshot(monthKey: 202606, currency: .uah, income: 2_000, expense: 0, incomeBase: nil, expenseBase: nil, rate: nil, source: nil),
        ])
        #expect(rows.count == 1) // same month + currency → one group
        #expect(rows[0].incomeUSD == nil)
        #expect(rows[0].rate == nil)
    }

    /// Rows in one (month, currency) group converted to DIFFERENT base
    /// currencies (a reporting-currency switch, e.g. via a restored backup)
    /// must not be summed — same guard as `MonthAggregate.sumBase`; a mixed
    /// USD/EUR base sum would be a meaningless number. Native sums are
    /// unaffected because they share the wallet currency.
    @Test func mixedBaseCurrenciesRenderGroupUnconverted() throws {
        let rows = try MonthlyRetrospectiveExport.rows(from: [
            snapshot(monthKey: 202606, currency: .uah, income: 1_000, expense: 0,
                     baseCurrency: .usd, incomeBase: 24, expenseBase: 0),
            snapshot(monthKey: 202606, currency: .uah, income: 2_000, expense: 0,
                     baseCurrency: .eur, incomeBase: 18, expenseBase: 0),
        ])
        #expect(rows.count == 1)
        #expect(rows[0].incomeUSD == nil)
        #expect(rows[0].expensesUSD == nil)
        #expect(rows[0].savedUSD == nil)
        #expect(rows[0].rate == nil)
        #expect(rows[0].income == "30.00") // native totals still aggregate
    }

    @Test func mixedCurrenciesProduceSeparateRows() throws {
        let rows = try MonthlyRetrospectiveExport.rows(from: [
            snapshot(monthKey: 202606, currency: .uah, income: 1_000, expense: 0),
            snapshot(monthKey: 202606, currency: .usd, income: 5_000, expense: 1_000,
                     incomeBase: 5_000, expenseBase: 1_000, rate: "1", source: "identity"),
        ])
        #expect(rows.count == 2)
        #expect(rows[0].currency == "UAH")
        #expect(rows[1].currency == "USD")
    }

    @Test func majorUnitsTwoDecimals() throws {
        #expect(MonthlyRetrospectiveExport.major2(4_125_000) == "41250.00")
        #expect(MonthlyRetrospectiveExport.major2(41_250) == "412.50")
        #expect(MonthlyRetrospectiveExport.major2(41_251) == "412.51")
        #expect(MonthlyRetrospectiveExport.major2(1) == "0.01")
        #expect(MonthlyRetrospectiveExport.major2(0) == "0.00")
        #expect(MonthlyRetrospectiveExport.major2(-250_000) == "-2500.00")
    }

    @Test func monthAndDateFormatting() throws {
        #expect(MonthlyRetrospectiveExport.monthString(202606) == "2026-06")
        #expect(MonthlyRetrospectiveExport.monthString(203001) == "2030-01")
        #expect(MonthlyRetrospectiveExport.monthString(99912) == "0999-12")
        #expect(MonthlyRetrospectiveExport.dateString(isoDate("2026-06-30T19:00:00Z")) == "2026-06-30")
    }

    @Test func fileNameRangeFormatting() throws {
        // Filename convention helper: cash-runway-retrospective-<first>-<last>
        #expect(ExportFile.name(from: "2026-04", to: "2026-06", format: .xlsx) == "cash-runway-retrospective-2026-04-2026-06.xlsx")
        #expect(ExportFile.name(from: "2026-06", to: "2026-06", format: .csv) == "cash-runway-retrospective-2026-06.csv")
    }

    // MARK: - Yearly retrospective (Issue: yearly totals when all 12 months exist)

    /// `month1..<month13` (exclusive upper bound) — 12 monthly snapshots of one
    /// currency for the year `year`.
    private func fullYear(
        _ year: Int,
        currency: CurrencyCode = .uah,
        incomePerMonth: Int64 = 1_000_000,
        expensePerMonth: Int64 = 400_000,
        incomeBasePerMonth: Int64 = 24_242,
        expenseBasePerMonth: Int64 = 9_697,
        baseCurrency: CurrencyCode = .usd,
        rate: String? = "0.024242424242424242424242424242424242"
    ) -> [MonthlyUSDSnapshot] {
        (1...12).map { month in
            snapshot(
                monthKey: year * 100 + month,
                currency: currency,
                income: incomePerMonth,
                expense: expensePerMonth,
                baseCurrency: baseCurrency,
                incomeBase: incomeBasePerMonth,
                expenseBase: expenseBasePerMonth,
                rate: rate
            )
        }
    }

    @Test func completeYearAppendsYearlyRowAfterItsMonths() throws {
        let rows = try MonthlyRetrospectiveExport.rows(from: fullYear(2025) + fullYear(2026))

        // Ordering: all 24 monthly rows ascending, then yearly rows (by year) at the end.
        #expect(rows.count == 26)
        #expect(rows[23].month == "2026-12")
        #expect(rows[24].month == "2025 (year)")
        #expect(rows[25].month == "2026 (year)")
        // Yearly row = the sum of its 12 monthly groups: 12 × 1,000,000 minor income.
        #expect(rows[25].income == "120000.00")
        #expect(rows[25].expenses == "48000.00")
        #expect(rows[25].saved == "72000.00")
        #expect(rows[25].currency == "UAH")
        #expect(rows[25].baseCurrency == "USD")
    }

    @Test func partialYearProducesNoYearlyRow() throws {
        // 11 months of 2025 + full 2026: only 2026 gets a yearly row.
        let rows = try MonthlyRetrospectiveExport.rows(from: fullYear(2025, incomePerMonth: 1).dropLast() + fullYear(2026))

        #expect(rows.count == 24)
        #expect(!rows.contains { $0.month.contains("(year)") && $0.month.hasPrefix("2025") })
        #expect(rows.contains { $0.month == "2026 (year)" })
    }

    @Test func yearlyRowCarriesNoSingleRateEvenWhenConverted() throws {
        let rows = try MonthlyRetrospectiveExport.rows(from: fullYear(2026))
        let yearRow = try #require(rows.last { $0.month == "2026 (year)" })

        // USD columns sum; a year has no single rate — rate metadata stays empty.
        #expect(yearRow.incomeUSD == "2909.04") // 12 × 24,242 minor → 242.42 × 12
        #expect(yearRow.rate == nil)
        #expect(yearRow.rateEffectiveDate == nil)
        #expect(yearRow.rateSource == nil)
        #expect(yearRow.approximate == false)
    }

    @Test func yearlyRowUnconvertedWhenAnyMonthUnconverted() throws {
        var months = fullYear(2026)
        months[7] = snapshot( // one unconverted month poisons the year's USD sum
            monthKey: 202608,
            currency: .uah,
            income: 1_000_000,
            expense: 400_000,
            incomeBase: nil,
            expenseBase: nil,
            rate: nil,
            source: nil
        )
        let rows = try MonthlyRetrospectiveExport.rows(from: months)
        let yearRow = try #require(rows.last { $0.month == "2026 (year)" })

        // Native totals still sum all 12 months; USD cells empty (same guard as monthly).
        #expect(yearRow.income == "120000.00")
        #expect(yearRow.incomeUSD == nil)
        #expect(yearRow.expensesUSD == nil)
        #expect(yearRow.savedUSD == nil)
    }

    @Test func yearlyMixedBaseCurrenciesRenderUnconverted() throws {
        var months = fullYear(2026)
        months[0] = snapshot( // one row converted to a different reporting currency
            monthKey: 202601,
            currency: .uah,
            income: 1_000_000,
            expense: 400_000,
            baseCurrency: .eur,
            incomeBase: 20_000,
            expenseBase: 8_000
        )
        let rows = try MonthlyRetrospectiveExport.rows(from: months)
        let yearRow = try #require(rows.last { $0.month == "2026 (year)" })

        #expect(yearRow.incomeUSD == nil)
        #expect(yearRow.expensesUSD == nil)
        #expect(yearRow.savedUSD == nil)
    }

    @Test func yearlyRowApproximateWhenAnyMonthApproximate() throws {
        var months = fullYear(2026)
        months[3].isApproximate = true
        let rows = try MonthlyRetrospectiveExport.rows(from: months)
        let yearRow = try #require(rows.last { $0.month == "2026 (year)" })
        #expect(yearRow.approximate == true)
    }

    @Test func multiCurrencyYearsStayDecomposed() throws {
        var months = fullYear(2026)
        months.append(extraCurrency(monthKey: 202612, currency: .usd))
        let rows = try MonthlyRetrospectiveExport.rows(from: months)

        // Completeness is per (year, currency): UAH covers 12 months → yearly
        // row; USD exists only in December (1 month) → NO yearly row.
        let yearRows = rows.filter { $0.month == "2026 (year)" }
        #expect(yearRows.map(\.currency) == ["UAH"])
    }

    @Test func multiCurrencyYearWithAllTwelveMonthsEachGetsYearlyRow() throws {
        var months = fullYear(2026)
        // A second currency also present in all 12 months of the year.
        for month in 1...12 {
            months.append(extraCurrency(monthKey: 202600 + month, currency: .usd))
        }
        let rows = try MonthlyRetrospectiveExport.rows(from: months)

        let yearRows = rows.filter { $0.month == "2026 (year)" }
        #expect(yearRows.map(\.currency) == ["UAH", "USD"])
    }

    /// Extra-currency helper for the decomposition test.
    private func extraCurrency(monthKey: Int, currency: CurrencyCode) -> MonthlyUSDSnapshot {
        snapshot(
            monthKey: monthKey,
            currency: currency,
            income: 1,
            expense: 1,
            incomeBase: 1,
            expenseBase: 1
        )
    }

    @Test func xlsxRoundTripWithYearlyRow() throws {
        let rows = try MonthlyRetrospectiveExport.rows(from: fullYear(2026))
        let data = try MonthlyRetrospectiveXLSX.export(csvRows: [MonthlyRetrospectiveExport.Row.header] + rows.map(\.cells))

        let file = try XLSXFile(data: data)
        let workbooks = try file.parseWorkbooks()
        let sheets = try file.parseWorksheetPathsAndNames(workbook: workbooks[0])
        let worksheet = try file.parseWorksheet(at: sheets[0].path)
        let sheetRows = worksheet.data?.rows ?? []
        // Header + 12 monthly + 1 yearly.
        #expect(sheetRows.count == 14)
        let yearlyValues = text(cells: sheetRows[13].cells)
        #expect(yearlyValues[0] == "2026 (year)")
        #expect(yearlyValues[3] == "120000.00") // 12 × 1,000,000 minor
    }

    /// ColumnReference-padded text extraction (same as the XLSX suite helpers).
    private func text(cells: [Cell]) -> [String] {
        var result: [String] = []
        guard var cursor = ColumnReference("A") else { return [] }
        let sorted = cells.sorted { $0.reference.column < $1.reference.column }
        for cell in sorted {
            while cursor < cell.reference.column {
                result.append("")
                cursor = cursor.advanced(by: 1)
            }
            if let inline = cell.inlineString {
                result.append(inline.text ?? "")
            } else {
                result.append(cell.value ?? "")
            }
            cursor = cursor.advanced(by: 1)
        }
        return result
    }
}