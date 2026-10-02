import Foundation

/// Issue #123: spreadsheet export of the persisted retrospective monthly data
/// (issues #121/#122). Pure functions only — the caller supplies stored
/// snapshot rows; nothing here touches the database or recomputes conversions.
/// Rendered values mirror `monthly_usd_snapshot` exactly (store-once semantics:
/// history in the file equals history in the app, incl. the `Approximate` flag).
public enum MonthlyRetrospectiveExportError: Error, LocalizedError {
    case noData

    public var errorDescription: String? {
        switch self {
        case .noData:
            return L10n.string("Nothing to export yet — no monthly history stored.")
        }
    }
}

public enum MonthlyRetrospectiveExportFormat: String, CaseIterable, Sendable {
    case csv
    case xlsx

    public var fileExtension: String { rawValue }
}

/// Issue #123: CSV/XLSX export of the persisted retrospective.
public enum MonthlyRetrospectiveExport {
    /// One canonical row consumed by both the CSV and XLSX writers.
    public struct Row: Hashable, Sendable {
        public static let header = [
            "Month", "Base Currency", "Currency", "Income", "Expenses", "Saved",
            "Income USD", "Expenses USD", "Saved USD",
            "Rate (Currency→USD)", "Rate Effective Date", "Rate Source", "Approximate",
        ]

        public let month: String
        public let baseCurrency: String
        public let currency: String
        public let income: String
        public let expenses: String
        public let saved: String
        /// `nil` when the source rows were stored unconverted (no rate yet).
        public let incomeUSD: String?
        public let expensesUSD: String?
        public let savedUSD: String?
        public let rate: String?
        public let rateEffectiveDate: String?
        public let rateSource: String?
        public let approximate: Bool

        /// Flat cell values in `header` order (USD cells empty when unconverted).
        public var cells: [String] {
            [
                month, baseCurrency, currency, income, expenses, saved,
                incomeUSD ?? "", expensesUSD ?? "", savedUSD ?? "",
                rate ?? "", rateEffectiveDate ?? "", rateSource ?? "",
                approximate ? "yes" : "no",
            ]
        }
    }

    /// Grouping key: one snapshot row per `(month, wallet, currency)` — a group is
    /// all wallets sharing a month and currency.
    private struct MonthCurrencyKey: Hashable {
        let monthKey: Int
        let currency: String
    }

    /// Groups stored snapshots by (month, currency) and sums across wallets.
    /// Throws `.noData` when there is nothing stored at all.
    public static func rows(from snapshots: [MonthlyUSDSnapshot]) throws -> [Row] {
        guard !snapshots.isEmpty else { throw MonthlyRetrospectiveExportError.noData }
        let byGroup = Dictionary(grouping: snapshots) { snapshot in
            MonthCurrencyKey(monthKey: snapshot.monthKey, currency: snapshot.currencyCode.rawValue)
        }
        return byGroup
            .sorted { ($0.key.monthKey, $0.key.currency) < ($1.key.monthKey, $1.key.currency) }
            .map { key, group -> Row in
                let first = group[0]
                let income = group.reduce(Int64(0)) { $0 + $1.incomeMinor }
                let expense = group.reduce(Int64(0)) { $0 + $1.expenseMinor }
                let saved = group.reduce(Int64(0)) { $0 + $1.savedMinor }
                // A group with ANY unconverted wallet renders as unconverted —
                // a partial USD sum would read as a misleadingly small total
                // (same rule as `MonthlyUSDSnapshot.MonthAggregate.sumBase`).
                let incomeUSD = sumBase(group.map { $0.incomeBaseMinor })
                let expenseUSD = sumBase(group.map { $0.expenseBaseMinor })
                let savedUSD = sumBase(group.map { $0.savedBaseMinor })
                let converted = incomeUSD != nil
                return Row(
                    month: monthString(key.monthKey),
                    baseCurrency: first.baseCurrencyCode.rawValue,
                    currency: key.currency,
                    income: major2(income),
                    expenses: major2(expense),
                    saved: major2(saved),
                    incomeUSD: incomeUSD.map(major2),
                    expensesUSD: expenseUSD.map(major2),
                    savedUSD: savedUSD.map(major2),
                    rate: converted ? first.rateDecimal : nil,
                    rateEffectiveDate: converted ? first.rateEffectiveDate.map(dateString) : nil,
                    rateSource: converted ? first.rateSource : nil,
                    approximate: group.contains { $0.isApproximate }
                )
            }
    }

    /// RFC-4180 CSV: every field quoted, quotes doubled. Header always present.
    public static func csv(rows: [Row]) -> String {
        let body = rows.map { $0.cells.map(escape).joined(separator: ",") }
        return ([Row.header.map(escape).joined(separator: ",")] + body).joined(separator: "\n")
    }

    // MARK: - Formatting helpers (QA-verified: NumberFormatter keeps "41250.00";
    // bare NSDecimalNumber.stringValue would print "41250")

    static func major2(_ minor: Int64) -> String {
        var decimalValue = Decimal(minor) / 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &decimalValue, 2, .plain)
        let number = NSDecimalNumber(decimal: rounded)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: number) ?? number.stringValue
    }

    static func monthString(_ monthKey: Int) -> String {
        String(format: "%04d-%02d", monthKey / 100, monthKey % 100)
    }

    static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    /// Partial conversions (some wallets converted, some without a rate) would
    /// render a misleadingly small USD total; treated as unconverted (`nil`).
    static func sumBase(_ values: [Int64?]) -> Int64? {
        guard !values.isEmpty, values.allSatisfy({ $0 != nil }) else { return nil }
        return values.compactMap { $0 }.reduce(0, +)
    }

    static func escape(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

/// Issue #123: export file naming (`cash-runway-retrospective-<first>-<last>.ext`;
/// a single-month range collapses to one date).
public enum ExportFile {
    public static func name(from firstMonth: String, to lastMonth: String, format: MonthlyRetrospectiveExportFormat) -> String {
        let ext = format.fileExtension
        return firstMonth == lastMonth
            ? "cash-runway-retrospective-\(firstMonth).\(ext)"
            : "cash-runway-retrospective-\(firstMonth)-\(lastMonth).\(ext)"
    }
}