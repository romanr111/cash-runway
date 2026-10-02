import Foundation

/// One converted retrospective month as rendered by the UI.
public struct RetrospectiveMonthlyUSDMetric: Hashable, Sendable {
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

    init(aggregate: MonthlyUSDSnapshot.MonthAggregate) {
        self.monthKey = aggregate.monthKey
        self.currencyCode = aggregate.currencyCode
        self.baseCurrencyCode = aggregate.baseCurrencyCode
        self.incomeMinor = aggregate.incomeMinor
        self.expenseMinor = aggregate.expenseMinor
        self.savedMinor = aggregate.savedMinor
        self.incomeBaseMinor = aggregate.incomeBaseMinor
        self.expenseBaseMinor = aggregate.expenseBaseMinor
        self.savedBaseMinor = aggregate.savedBaseMinor
        self.rateDecimal = aggregate.rateDecimal
        self.rateEffectiveDate = aggregate.rateEffectiveDate
        self.rateSource = aggregate.rateSource
        self.isApproximate = aggregate.isApproximate
    }

    /// Public memberwise converter so cross-module reloads can map stored
    /// aggregates without exposing the aggregate type's own initializer.
    public init(
        aggregate: MonthlyUSDSnapshot.MonthAggregate,
        monthKey: Int,
        currencyCode: CurrencyCode,
        baseCurrencyCode: CurrencyCode,
        incomeMinor: Int64,
        expenseMinor: Int64,
        savedMinor: Int64,
        incomeBaseMinor: Int64?,
        expenseBaseMinor: Int64?,
        savedBaseMinor: Int64?,
        rateDecimal: String?,
        rateEffectiveDate: Date?,
        rateSource: String?,
        isApproximate: Bool
    ) {
        self.monthKey = monthKey
        self.currencyCode = currencyCode
        self.baseCurrencyCode = baseCurrencyCode
        self.incomeMinor = incomeMinor
        self.expenseMinor = expenseMinor
        self.savedMinor = savedMinor
        self.incomeBaseMinor = incomeBaseMinor
        self.expenseBaseMinor = expenseBaseMinor
        self.savedBaseMinor = savedBaseMinor
        self.rateDecimal = rateDecimal
        self.rateEffectiveDate = rateEffectiveDate
        self.rateSource = rateSource
        self.isApproximate = isApproximate
    }
}

/// Issue #121: retrospective monthly metrics in the reporting currency (USD).
///
/// For every historical month present in `monthly_wallet_cashflow` the service
/// aggregates income / expense / saved (income − expense) totals across wallets
/// (transfers are internal movements and move no money between currencies, so
/// they are excluded), resolves the exchange rate effective at the END of that
/// historical month, converts with the existing `MoneyAmount` rounding
/// conventions (Decimal, half-up to the minor unit), and persists the result via
/// the repository.
///
/// Rate resolution per `exchange_rates` conventions (rows are FOREIGN→UAH, e.g.
/// `source=USD, target=UAH, rate≈41.25`; UAH→USD therefore DIVIDES — see
/// `WalletValueProjectionService.crossRate`), in order:
/// 1. exact month-end rate already stored in `exchange_rates` (staleness is not
///    consulted — historical rates never expire),
/// 2. nearest EARLIER stored rate within `fallbackLookbackDays`, flagged
///    `isApproximate`,
/// 3. fetch for the exact month-end date and persist via the provider chain.
///    Historical fetches go through NBU (`HistoricalOfficialRateProvider` wraps
///    `NBUOfficialRateClient`, the only client with real date support; the bank
///    midpoint clients serve only current rates). The
///    `CachingExchangeRateProvider` wrapper (infinite staleness) persists every
///    fetched rate into `exchange_rates`, so a historical rate is fetched once.
///
/// The snapshot stores the derived ORIGINAL→BASE conversion factor, making rows
/// self-contained; the raw rate row stays in `exchange_rates`. Totals are
/// stored, not recomputed on the fly: history remains stable even if today's
/// rates change (store-once semantics live in the repository).
public final class MonthlyRetrospectiveUSDSnapshotService: @unchecked Sendable {
    // @unchecked Sendable is justified: both stored properties are immutable
    // `let` references to Sendable protocols (repository, rate provider); the
    // service holds no mutable state, so concurrent snapshot refreshes are safe.

    /// How far back from an exact month-end date a stored rate may sit and still
    /// be used as a nearest-available fallback.
    public static let fallbackLookbackDays = 10

    private let repository: any CashRunwayRepositorying
    private let rateProvider: ExchangeRateProviding

    public init(
        repository: any CashRunwayRepositorying,
        rateProvider: ExchangeRateProviding
    ) {
        self.repository = repository
        self.rateProvider = rateProvider
    }

    /// Refreshes persisted snapshots for every historical month found in the
    /// cashflow aggregates. Returns the stored month aggregates for UI reloads.
    @discardableResult
    public func refreshSnapshots(now: Date = Date()) async throws -> [RetrospectiveMonthlyUSDMetric] {
        try await refreshSnapshots(monthKeys: nil, now: now)
    }

    /// Refreshes persisted snapshots. `monthKeys == nil` refreshes every
    /// historical month (full backfill on first run); a non-nil set refreshes
    /// only those months (targeted rebuilds after edits / aggregate rebuilds).
    @discardableResult
    public func refreshSnapshots(monthKeys: Set<Int>?, now: Date = Date()) async throws -> [RetrospectiveMonthlyUSDMetric] {
        let preferences = try repository.currencyPreferences()
        let baseCurrency = Self.reportingCurrency(fallback: .usd, preferences: preferences)
        let historicalMonths = try repository.historicalMonthKeys()
        let targetMonths = monthKeys
            .map { Set(historicalMonths).intersection($0).sorted() }
            ?? historicalMonths.filter { Self.monthEndDate(for: $0) <= now }
        guard !targetMonths.isEmpty else { return [] }

        // Wallet lookup once per run: the cashflow aggregate carries no currency
        // column; currency comes from the wallet. `wallets()` already excludes
        // archived wallets, matching the UI aggregate scope.
        let walletCurrencies = try repository.wallets().reduce(into: [UUID: CurrencyCode]()) { result, wallet in
            result[wallet.id] = wallet.currencyCode
        }

        for monthKey in targetMonths {
            // One month's rate failure must not starve the rest of the
            // retrospective; that month stays unconverted and the next
            // maintenance run retries it.
            try? await refreshSnapshot(monthKey: monthKey, baseCurrency: baseCurrency, walletCurrencies: walletCurrencies, now: now)
        }

        return try repository.monthlyUSDMonthAggregates()
            .map(RetrospectiveMonthlyUSDMetric.init(aggregate:))
    }

    /// Stored month aggregates for the UI (no network, no recompute).
    public func storedMetrics() throws -> [RetrospectiveMonthlyUSDMetric] {
        try repository.monthlyUSDMonthAggregates()
            .map(RetrospectiveMonthlyUSDMetric.init(aggregate:))
    }

    /// Resolves the reporting currency for the feature. USD is the issue's base
    /// currency; the stored preference wins when the user changed it. The seed
    /// `UAH` reporting preference predates this feature and is treated as
    /// "unset", so the retrospective still reports USD by default.
    public static func reportingCurrency(fallback: CurrencyCode, preferences: CurrencyPreferences) -> CurrencyCode {
        preferences.reportingCurrencyCode == .uah ? fallback : preferences.reportingCurrencyCode
    }

    // MARK: - Snapshot assembly

    private func refreshSnapshot(
        monthKey: Int,
        baseCurrency: CurrencyCode,
        walletCurrencies: [UUID: CurrencyCode],
        now: Date
    ) async throws {
        let rows = try repository.monthlyCashflow(monthKey: monthKey)
        var totalsByWallet: [UUID: (currency: CurrencyCode, income: Int64, expense: Int64)] = [:]
        for row in rows {
            guard let currency = walletCurrencies[row.walletID] else { continue }
            var entry = totalsByWallet[row.walletID] ?? (currency, 0, 0)
            entry.income += row.incomeMinor
            entry.expense += row.expenseMinor
            totalsByWallet[row.walletID] = entry
        }
        guard !totalsByWallet.isEmpty else { return }

        let monthEnd = Self.monthEndDate(for: monthKey)

        for (walletID, entry) in totalsByWallet {
            let savedMinor = entry.income - entry.expense

            var incomeBase: Int64?
            var expenseBase: Int64?
            var savedBase: Int64?
            var rateDecimal: String?
            var rateEffectiveDate: Date?
            var rateSource: String?
            var isApproximate = false

            if entry.currency == baseCurrency {
                // Same-currency month: totals pass through unchanged.
                incomeBase = entry.income
                expenseBase = entry.expense
                savedBase = savedMinor
            } else {
                let conversion = try await conversionRate(
                    original: entry.currency,
                    base: baseCurrency,
                    monthEnd: monthEnd
                )
                if let factor = conversion.factor {
                    incomeBase = try? Self.convertMinor(entry.income, factor: factor)
                    expenseBase = try? Self.convertMinor(entry.expense, factor: factor)
                    savedBase = try? Self.convertMinor(savedMinor, factor: factor)
                    rateDecimal = factor.description
                } else {
                    // Identity conversion surfaced by the resolver (original == base
                    // races are impossible here, but stay defensive).
                    incomeBase = entry.income
                    expenseBase = entry.expense
                    savedBase = savedMinor
                    rateDecimal = "1"
                }
                rateEffectiveDate = conversion.rateRow?.effectiveDate
                rateSource = conversion.rateRow?.source
                isApproximate = conversion.isApproximate
            }

            let snapshot = MonthlyUSDSnapshot(
                monthKey: monthKey,
                walletID: walletID,
                currencyCode: entry.currency,
                incomeMinor: entry.income,
                expenseMinor: entry.expense,
                savedMinor: savedMinor,
                baseCurrencyCode: baseCurrency,
                incomeBaseMinor: incomeBase,
                expenseBaseMinor: expenseBase,
                savedBaseMinor: savedBase,
                rateDecimal: rateDecimal,
                rateEffectiveDate: rateEffectiveDate,
                rateSource: rateSource,
                isApproximate: isApproximate,
                updatedAt: now
            )
            try repository.saveMonthlyUSDSnapshot(snapshot)
        }
    }

    /// Converted minor units with a pre-resolved ORIGINAL→BASE factor, rounding
    /// half-up to the minor unit (existing `MoneyAmount`/`MoneyFormatter`
    /// convention, mirroring `WalletValueProjectionService.minorUnits(from:)`).
    static func convertMinor(_ minor: Int64, factor: Decimal) throws -> Int64 {
        var scaled = Decimal(minor) * factor
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        let nsNumber = NSDecimalNumber(decimal: rounded)
        guard nsNumber != NSDecimalNumber.notANumber,
              let result = nsNumber.int64Value as Int64?,
              Decimal(result) == rounded
        else {
            throw MoneyError.invalidAmount(factor.description)
        }
        return result
    }

    /// The historical month's end instant (last second of the month, local
    /// calendar — mirrors `RowMappers.endOfMonth(for:)`).
    static func monthEndDate(for monthKey: Int) -> Date {
        let start = DateKeys.startOfMonth(for: monthKey)
        let nextMonth = DateKeys.calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return DateKeys.calendar.date(byAdding: .second, value: -1, to: nextMonth) ?? nextMonth
    }

    /// A fallback is "not exact" only when its effective day differs from the
    /// month-end's last day.
    static func isExactDate(_ effectiveDate: Date, _ monthEnd: Date) -> Bool {
        DateKeys.calendar.startOfDay(for: effectiveDate)
            == DateKeys.calendar.startOfDay(for: monthEnd)
    }

    // MARK: - Rate lookup

    struct RateConversion {
        /// original→base conversion factor; `nil` means pass-through (identity).
        var factor: Decimal?
        /// The underlying rate row (metadata: source label, effective date).
        var rateRow: ExchangeRate?
        /// True when the rate's effective day is not the exact month-end day.
        var isApproximate: Bool
    }

    /// Resolves the ORIGINAL→BASE conversion for a historical month-end.
    ///
    /// - `original == base`: pass-through.
    /// - `original == UAH, base != UAH`: rate rows are FOREIGN→UAH, so the factor
    ///   is the INVERSE of the base→UAH rate (divides, matching
    ///   `WalletValueProjectionService.crossRate` for UAH sources).
    /// - otherwise: factor = (original→UAH) ÷ (base→UAH) — a cross rate.
    func conversionRate(
        original: CurrencyCode,
        base: CurrencyCode,
        monthEnd: Date
    ) async throws -> RateConversion {
        if original == base {
            return RateConversion(factor: nil, rateRow: nil, isApproximate: false)
        }

        if original == .uah {
            let baseLookup = try await uahRate(currency: base, monthEnd: monthEnd)
            guard let baseLookup else {
                throw MoneyError.missingExchangeRate(from: original, to: base)
            }
            let factor = 1 / baseLookup.decimal
            return RateConversion(
                factor: factor,
                rateRow: baseLookup.rate,
                isApproximate: !Self.isExactDate(baseLookup.rate.effectiveDate, monthEnd)
            )
        }

        let originalLookup = try await uahRate(currency: original, monthEnd: monthEnd)
        guard let originalLookup else {
            throw MoneyError.missingExchangeRate(from: original, to: .uah)
        }

        if base == .uah {
            return RateConversion(
                factor: originalLookup.decimal,
                rateRow: originalLookup.rate,
                isApproximate: !Self.isExactDate(originalLookup.rate.effectiveDate, monthEnd)
            )
        }

        let baseLookup = try await uahRate(currency: base, monthEnd: monthEnd)
        guard let baseLookup else {
            throw MoneyError.missingExchangeRate(from: base, to: .uah)
        }
        return RateConversion(
            factor: originalLookup.decimal / baseLookup.decimal,
            rateRow: baseLookup.rate,
            isApproximate: !Self.isExactDate(originalLookup.rate.effectiveDate, monthEnd)
                || !Self.isExactDate(baseLookup.rate.effectiveDate, monthEnd)
        )
    }

    /// Rate `currency`→UAH effective at the historical date, in resolution order:
    /// exact stored → nearest-earlier stored within the lookback window (kept
    /// verbatim; the effective date divergence drives `isApproximate`) → fetch
    /// through the provider chain (NBU official; persists into `exchange_rates`).
    private func uahRate(currency: CurrencyCode, monthEnd: Date) async throws -> (rate: ExchangeRate, decimal: Decimal)? {
        if let exact = try repository.historicalExchangeRate(from: currency, to: .uah, on: monthEnd),
           let decimal = Self.validDecimal(exact.rateDecimal) {
            return (exact, decimal)
        }

        if let nearest = try repository.nearestHistoricalExchangeRate(
            from: currency,
            to: .uah,
            onOrBefore: monthEnd,
            maxLookbackDays: Self.fallbackLookbackDays
        ), let decimal = Self.validDecimal(nearest.rateDecimal) {
            return (nearest, decimal)
        }

        let fetched = try await rateProvider.rate(from: currency, to: .uah, on: monthEnd)
        guard let decimal = Self.validDecimal(fetched.rateDecimal) else {
            throw MoneyError.missingExchangeRate(from: currency, to: .uah)
        }
        return (fetched, decimal)
    }

    private static func validDecimal(_ value: String) -> Decimal? {
        guard let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")), decimal > 0 else {
            return nil
        }
        return decimal
    }
}

/// Wraps `NBUOfficialRateClient` for historical (month-end) lookups. Bank
/// midpoint clients (Monobank returns only current rates; a request for a past
/// date would be silently stamped "today") are intentionally not used for
/// historical months. NBU is the source with genuine per-date support.
public struct HistoricalOfficialRateProvider: ExchangeRateProviding {
    private let officialClient: NBUOfficialRateClient

    public init(urlSession: URLSession = .shared) {
        self.officialClient = NBUOfficialRateClient(urlSession: urlSession)
    }

    public func rate(
        from sourceCurrency: CurrencyCode,
        to targetCurrency: CurrencyCode,
        on date: Date
    ) async throws -> ExchangeRate {
        guard targetCurrency == .uah, sourceCurrency != .uah else {
            throw MoneyError.missingExchangeRate(from: sourceCurrency, to: targetCurrency)
        }
        let rates = try await officialClient.fetchRates(baseCurrency: sourceCurrency, date: date)
        guard let match = rates.first(where: {
            $0.sourceCurrencyCode == sourceCurrency && $0.targetCurrencyCode == .uah
        }) else {
            throw MoneyError.missingExchangeRate(from: sourceCurrency, to: .uah)
        }
        return match
    }
}