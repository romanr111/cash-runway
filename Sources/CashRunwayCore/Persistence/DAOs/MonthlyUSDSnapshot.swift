import Foundation
import GRDB

/// Issue #121: persisted retrospective monthly snapshot.
///
/// One row per (month, wallet, original currency). Holds the month's income /
/// expense / saved totals in the wallet's original currency together with the
/// conversion to the reporting (base) currency at that month's end rate.
/// Totals are stored once and stay stable even when current rates change;
/// `rateDecimal` / `rateEffectiveDate` / `rateSource` record exactly which rate
/// produced the base-currency figures at snapshot time.
public struct MonthlyUSDSnapshot: Codable, Hashable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "monthly_usd_snapshot"

    private enum CodingKeys: String, CodingKey {
        case id
        case monthKey = "month_key"
        case walletID = "wallet_id"
        case currencyCode = "currency_code"
        case incomeMinor = "income_minor"
        case expenseMinor = "expense_minor"
        case savedMinor = "saved_minor"
        case baseCurrencyCode = "base_currency_code"
        case incomeBaseMinor = "income_base_minor"
        case expenseBaseMinor = "expense_base_minor"
        case savedBaseMinor = "saved_base_minor"
        case rateDecimal = "rate_decimal"
        case rateEffectiveDate = "rate_effective_date"
        case rateSource = "rate_source"
        case isApproximate = "is_approximate"
        case updatedAt = "updated_at"
    }
    public var id: String
    public var monthKey: Int
    public var walletID: UUID
    public var currencyCode: CurrencyCode
    /// Month income totals in the wallet's ORIGINAL currency (minor units).
    public var incomeMinor: Int64
    /// Month expense totals in the wallet's ORIGINAL currency (minor units).
    public var expenseMinor: Int64
    /// Cash saved (income − expense) in the wallet's ORIGINAL currency (minor units).
    public var savedMinor: Int64
    /// Reporting currency the conversion targets (USD by default,
    /// mirrors `currency_preferences.reporting_currency_code` at snapshot time).
    public var baseCurrencyCode: CurrencyCode
    /// Converted totals in the base currency (minor units, rounded half-up to
    /// match existing `MoneyAmount` conventions). `nil` while no rate is known.
    public var incomeBaseMinor: Int64?
    public var expenseBaseMinor: Int64?
    public var savedBaseMinor: Int64?
    /// The month-end rate used: base-currency units per one unit of `currencyCode`
    /// (e.g. USD per UAH when converting UAH -> USD). Identical to the
    /// `exchange_rates` row direction. `nil` when no rate was available.
    public var rateDecimal: String?
    /// Effective date of the stored rate — the historical month-end date, or the
    /// nearest available earlier date when the exact month end had no rate.
    public var rateEffectiveDate: Date?
    public var rateSource: String?
    /// True when the stored rate came from a nearest-available fallback (not the
    /// exact month-end date); UI renders converted figures with an `≈` marker.
    public var isApproximate: Bool
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        monthKey: Int,
        walletID: UUID,
        currencyCode: CurrencyCode,
        incomeMinor: Int64,
        expenseMinor: Int64,
        savedMinor: Int64,
        baseCurrencyCode: CurrencyCode,
        incomeBaseMinor: Int64? = nil,
        expenseBaseMinor: Int64? = nil,
        savedBaseMinor: Int64? = nil,
        rateDecimal: String? = nil,
        rateEffectiveDate: Date? = nil,
        rateSource: String? = nil,
        isApproximate: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.monthKey = monthKey
        self.walletID = walletID
        self.currencyCode = currencyCode
        self.incomeMinor = incomeMinor
        self.expenseMinor = expenseMinor
        self.savedMinor = savedMinor
        self.baseCurrencyCode = baseCurrencyCode
        self.incomeBaseMinor = incomeBaseMinor
        self.expenseBaseMinor = expenseBaseMinor
        self.savedBaseMinor = savedBaseMinor
        self.rateDecimal = rateDecimal
        self.rateEffectiveDate = rateEffectiveDate
        self.rateSource = rateSource
        self.isApproximate = isApproximate
        self.updatedAt = updatedAt
    }

    /// Aggregated month-level view used by the retrospective UI: sums the native
    /// and base-currency totals across wallets. Rows sharing a month but missing
    /// a conversion (no rate yet) contribute only to the native figures.
    public struct MonthAggregate: Hashable, Sendable {
        public let monthKey: Int
        public let currencyCode: CurrencyCode
        public let baseCurrencyCode: CurrencyCode
        public let incomeMinor: Int64
        public let expenseMinor: Int64
        public let savedMinor: Int64
        public let incomeBaseMinor: Int64?
        public let expenseBaseMinor: Int64?
        public let savedBaseMinor: Int64?
        public let rateDecimal: String?
        public let rateEffectiveDate: Date?
        public let rateSource: String?
        public let isApproximate: Bool

        init(rows: [MonthlyUSDSnapshot]) {
            let first = rows[0]
            self.monthKey = first.monthKey
            self.currencyCode = first.currencyCode
            self.baseCurrencyCode = first.baseCurrencyCode
            self.incomeMinor = rows.reduce(0) { $0 + $1.incomeMinor }
            self.expenseMinor = rows.reduce(0) { $0 + $1.expenseMinor }
            self.savedMinor = rows.reduce(0) { $0 + $1.savedMinor }
            self.incomeBaseMinor = Self.sumBase(rows, keyPath: \.incomeBaseMinor)
            self.expenseBaseMinor = Self.sumBase(rows, keyPath: \.expenseBaseMinor)
            self.savedBaseMinor = Self.sumBase(rows, keyPath: \.savedBaseMinor)
            self.rateDecimal = rows.first?.rateDecimal
            self.rateEffectiveDate = rows.first?.rateEffectiveDate
            self.rateSource = rows.first?.rateSource
            self.isApproximate = rows.contains { $0.isApproximate }
        }

        /// Partial conversions (some wallets converted, some without a rate)
        /// would render a misleadingly small USD total; treat as unconverted.
        /// Rows converted to DIFFERENT base currencies must not be summed either
        /// (a reporting-currency switch, e.g. via a restored backup, can leave a
        /// month holding both); the aggregate reads as unconverted and the full
        /// refresh pass rewrites every row to the current base currency.
        private static func sumBase(
            _ rows: [MonthlyUSDSnapshot],
            keyPath: KeyPath<MonthlyUSDSnapshot, Int64?>
        ) -> Int64? {
            guard
                !rows.isEmpty,
                Set(rows.map(\.baseCurrencyCode)).count == 1,
                rows.allSatisfy({ $0[keyPath: keyPath] != nil })
            else { return nil }
            return rows.compactMap { $0[keyPath: keyPath] }.reduce(0, +)
        }
    }
}