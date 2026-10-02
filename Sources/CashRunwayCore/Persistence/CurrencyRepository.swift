import Foundation
import GRDB

/// Raw per-wallet monthly cashflow totals as stored in `monthly_wallet_cashflow`
/// (native currency minor units; transfers included separately).
public struct MonthlyWalletCashflowRow: Hashable, Sendable {
    public let walletID: UUID
    public let monthKey: Int
    public let incomeMinor: Int64
    public let expenseMinor: Int64
    public let transferInMinor: Int64
    public let transferOutMinor: Int64

    public init(
        walletID: UUID,
        monthKey: Int,
        incomeMinor: Int64,
        expenseMinor: Int64,
        transferInMinor: Int64,
        transferOutMinor: Int64
    ) {
        self.walletID = walletID
        self.monthKey = monthKey
        self.incomeMinor = incomeMinor
        self.expenseMinor = expenseMinor
        self.transferInMinor = transferInMinor
        self.transferOutMinor = transferOutMinor
    }
}

extension CashRunwayRepository {
    public func currencyPreferences() throws -> CurrencyPreferences {
        try databaseManager.dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                SELECT default_currency_code, reporting_currency_code
                FROM currency_preferences
                WHERE id = 'default'
                """
            ) else {
                return .default
            }

            return CurrencyPreferences(
                defaultCurrencyCode: try CurrencyCode(validating: row["default_currency_code"]),
                reportingCurrencyCode: try CurrencyCode(validating: row["reporting_currency_code"])
            )
        }
    }

    public func saveCurrencyPreferences(_ preferences: CurrencyPreferences) throws {
        try databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO currency_preferences (id, default_currency_code, reporting_currency_code, updated_at)
                VALUES ('default', ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    default_currency_code = excluded.default_currency_code,
                    reporting_currency_code = excluded.reporting_currency_code,
                    updated_at = excluded.updated_at
                """,
                arguments: [
                    preferences.defaultCurrencyCode.rawValue,
                    preferences.reportingCurrencyCode.rawValue,
                    Date(),
                ]
            )
        }
    }

    public func cachedExchangeRate(
        from sourceCurrency: CurrencyCode,
        to targetCurrency: CurrencyCode,
        on date: Date,
        source: String? = nil
    ) throws -> ExchangeRate? {
        try cachedExchangeRate(from: sourceCurrency, to: targetCurrency, on: date, source: source, maxStaleness: .infinity)
    }

    public func cachedExchangeRate(
        from sourceCurrency: CurrencyCode,
        to targetCurrency: CurrencyCode,
        on date: Date,
        source: String?,
        maxStaleness: TimeInterval
    ) throws -> ExchangeRate? {
        let effectiveDate = DateKeys.calendar.startOfDay(for: date)
        let staleThreshold = Date().addingTimeInterval(-maxStaleness)
        return try databaseManager.dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                SELECT source, base_currency_code, quote_currency_code, rate_decimal, effective_date, fetched_at
                FROM exchange_rates
                WHERE base_currency_code = ?
                AND quote_currency_code = ?
                AND effective_date = ?
                AND (? IS NULL OR source = ?)
                AND fetched_at >= ?
                ORDER BY fetched_at DESC
                LIMIT 1
                """,
                arguments: [sourceCurrency.rawValue, targetCurrency.rawValue, effectiveDate, source, source, staleThreshold]
            ) else {
                return nil
            }

            return ExchangeRate(
                sourceCurrencyCode: try CurrencyCode(validating: row["base_currency_code"]),
                targetCurrencyCode: try CurrencyCode(validating: row["quote_currency_code"]),
                rateDecimal: row["rate_decimal"],
                effectiveDate: row["effective_date"],
                source: row["source"]
            )
        }
    }

    public func saveExchangeRates(_ rates: [ExchangeRate]) throws {
        try databaseManager.dbQueue.write { db in
            let fetchedAt = Date()
            for rate in rates {
                guard ExchangeRate.isValidRateDecimal(rate.rateDecimal) else {
                    throw CashRunwayError.validation(L10n.string("Exchange rate must be a positive decimal value."))
                }
                let effectiveDate = DateKeys.calendar.startOfDay(for: rate.effectiveDate)
                try db.execute(
                    sql: """
                    INSERT INTO exchange_rates (
                        id, source, base_currency_code, quote_currency_code,
                        rate_decimal, effective_date, fetched_at, expires_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, NULL)
                    ON CONFLICT(source, base_currency_code, quote_currency_code, effective_date) DO UPDATE SET
                        rate_decimal = excluded.rate_decimal,
                        fetched_at = excluded.fetched_at,
                        expires_at = excluded.expires_at
                    """,
                    arguments: [
                        UUID().uuidString,
                        rate.source,
                        rate.sourceCurrencyCode.rawValue,
                        rate.targetCurrencyCode.rawValue,
                        rate.rateDecimal,
                        effectiveDate,
                        fetchedAt,
                    ]
                )
            }
        }
    }

    // MARK: - Issue #121: retrospective monthly USD snapshots

    /// Historical month keys that have cashflow aggregate data, ascending.
    /// Backfills rely on the same sources as `rebuildMonths` (the aggregates are
    /// full-month totals maintained from transactions).
    public func historicalMonthKeys() throws -> [Int] {
        try databaseManager.dbQueue.read { db in
            try Int.fetchAll(
                db,
                sql: "SELECT DISTINCT local_month_key FROM transactions WHERE is_deleted = 0 AND local_month_key IS NOT NULL ORDER BY local_month_key"
            )
        }
    }

    /// Per-wallet monthly cashflow totals (native currency minor units) as
    /// maintained by `AggregateMaintenance` in `monthly_wallet_cashflow`.
    public func monthlyCashflow(monthKey: Int) throws -> [MonthlyWalletCashflowRow] {
        try databaseManager.dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT wallet_id, month_key, income_minor, expense_minor, transfer_in_minor, transfer_out_minor
                FROM monthly_wallet_cashflow
                WHERE month_key = ?
                """,
                arguments: [monthKey]
            ).map { row in
                MonthlyWalletCashflowRow(
                    walletID: UUID(uuidString: row["wallet_id"]) ?? UUID(),
                    monthKey: row["month_key"],
                    incomeMinor: row["income_minor"] as Int64,
                    expenseMinor: row["expense_minor"] as Int64,
                    transferInMinor: row["transfer_in_minor"] as Int64,
                    transferOutMinor: row["transfer_out_minor"] as Int64
                )
            }
        }
    }

    /// Exact-date exchange-rate lookup over the persisted `exchange_rates` table
    /// (no staleness check — historical rates never expire).
    public func historicalExchangeRate(
        from sourceCurrency: CurrencyCode,
        to targetCurrency: CurrencyCode,
        on date: Date
    ) throws -> ExchangeRate? {
        let effectiveDate = DateKeys.calendar.startOfDay(for: date)
        return try databaseManager.dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                SELECT source, base_currency_code, quote_currency_code, rate_decimal, effective_date
                FROM exchange_rates
                WHERE base_currency_code = ?
                AND quote_currency_code = ?
                AND effective_date = ?
                ORDER BY fetched_at DESC
                LIMIT 1
                """,
                arguments: [sourceCurrency.rawValue, targetCurrency.rawValue, effectiveDate]
            ) else {
                return nil
            }

            return ExchangeRate(
                sourceCurrencyCode: try CurrencyCode(validating: row["base_currency_code"]),
                targetCurrencyCode: try CurrencyCode(validating: row["quote_currency_code"]),
                rateDecimal: row["rate_decimal"],
                effectiveDate: row["effective_date"],
                source: row["source"]
            )
        }
    }

    /// Nearest-available fallback for a historical rate: the latest row strictly
    /// at or before the requested month-end date, optionally within a lookback
    /// window. `nil` when nothing is stored in the window.
    public func nearestHistoricalExchangeRate(
        from sourceCurrency: CurrencyCode,
        to targetCurrency: CurrencyCode,
        onOrBefore date: Date,
        maxLookbackDays: Int
    ) throws -> ExchangeRate? {
        let endDate = DateKeys.calendar.startOfDay(for: date)
        let startDate = DateKeys.calendar.date(byAdding: .day, value: -maxLookbackDays, to: endDate) ?? endDate
        return try databaseManager.dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                SELECT source, base_currency_code, quote_currency_code, rate_decimal, effective_date
                FROM exchange_rates
                WHERE base_currency_code = ?
                AND quote_currency_code = ?
                AND effective_date >= ?
                AND effective_date <= ?
                ORDER BY effective_date DESC, fetched_at DESC
                LIMIT 1
                """,
                arguments: [sourceCurrency.rawValue, targetCurrency.rawValue, startDate, endDate]
            ) else {
                return nil
            }

            return ExchangeRate(
                sourceCurrencyCode: try CurrencyCode(validating: row["base_currency_code"]),
                targetCurrencyCode: try CurrencyCode(validating: row["quote_currency_code"]),
                rateDecimal: row["rate_decimal"],
                effectiveDate: row["effective_date"],
                source: row["source"]
            )
        }
    }

    /// Raw stored snapshots for the given months, one row per (wallet, currency, month).
    public func monthlyUSDSnapshots(monthKeys: [Int]) throws -> [MonthlyUSDSnapshot] {
        guard !monthKeys.isEmpty else { return [] }
        return try databaseManager.dbQueue.read { db in
            let placeholders = monthKeys.enumerated().map { ":month\($0.offset)" }.joined(separator: ", ")
            var arguments: [String: any DatabaseValueConvertible] = [:]
            for (index, monthKey) in monthKeys.enumerated() {
                arguments["month\(index)"] = monthKey
            }
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM monthly_usd_snapshot
                WHERE month_key IN (\(placeholders))
                ORDER BY month_key DESC
                """,
                arguments: StatementArguments(arguments)
            )
            return try rows.map(Self.monthlyUSDSnapshot(from:))
        }
    }

    /// All stored snapshots (full retrospective, newest month first).
    public func allMonthlyUSDSnapshots() throws -> [MonthlyUSDSnapshot] {
        try databaseManager.dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM monthly_usd_snapshot ORDER BY month_key DESC")
            return try rows.map(Self.monthlyUSDSnapshot(from:))
        }
    }

    /// Month aggregates across wallets for the retrospective UI, newest month first.
    public func monthlyUSDMonthAggregates() throws -> [MonthlyUSDSnapshot.MonthAggregate] {
        let rows = try allMonthlyUSDSnapshots()
        let byMonth = Dictionary(grouping: rows) { $0.monthKey }
        return byMonth
            .map { MonthlyUSDSnapshot.MonthAggregate(rows: $0.value) }
            .sorted { $0.monthKey > $1.monthKey }
    }

    /// Builds a GRDB row mapper bound to the `monthly_usd_snapshot` schema
    /// (v9_monthly_usd_snapshot). `base_currency_code` defaults to USD for
    /// defense against rows written before that column carried a real value.
    static func monthlyUSDSnapshot(from row: Row) throws -> MonthlyUSDSnapshot {
        MonthlyUSDSnapshot(
            id: row["id"],
            monthKey: row["month_key"],
            walletID: UUID(uuidString: row["wallet_id"]) ?? UUID(),
            currencyCode: try CurrencyCode(validating: row["currency_code"]),
            incomeMinor: row["income_minor"],
            expenseMinor: row["expense_minor"],
            savedMinor: row["saved_minor"],
            baseCurrencyCode: (try? CurrencyCode(validating: row["base_currency_code"])) ?? .usd,
            incomeBaseMinor: row["income_base_minor"],
            expenseBaseMinor: row["expense_base_minor"],
            savedBaseMinor: row["saved_base_minor"],
            rateDecimal: row["rate_decimal"],
            rateEffectiveDate: row["rate_effective_date"],
            rateSource: row["rate_source"],
            isApproximate: row["is_approximate"],
            updatedAt: row["updated_at"]
        )
    }

    /// Stores one snapshot. Store-once semantics per the issue: an existing row is
    /// rewritten only when the underlying native minor totals changed, or the
    /// previously stored conversion targets a different base currency, or the row
    /// has no conversion and we now have one ("never rewrite already-stored rows
    /// unless the underlying minor totals changed" — a never-converted row carries
    /// no rate history, so filling it is not a rewrite of rate history).
    public func saveMonthlyUSDSnapshot(_ snapshot: MonthlyUSDSnapshot) throws {
        try databaseManager.dbQueue.write { db in
            let existing = try Row.fetchOne(
                db,
                sql: """
                SELECT income_minor, expense_minor, saved_minor, base_currency_code,
                       rate_decimal, is_approximate
                FROM monthly_usd_snapshot
                WHERE month_key = ? AND wallet_id = ? AND currency_code = ?
                """,
                arguments: [snapshot.monthKey, snapshot.walletID.uuidString, snapshot.currencyCode.rawValue]
            )

            if let existing {
                let storedIncome: Int64 = existing["income_minor"]
                let storedExpense: Int64 = existing["expense_minor"]
                let storedSaved: Int64 = existing["saved_minor"]
                let storedBaseCurrency: String = existing["base_currency_code"]
                let storedRate: String? = existing["rate_decimal"]
                let storedIsApproximate: Bool = existing["is_approximate"]

                let totalsUnchanged = storedIncome == snapshot.incomeMinor
                    && storedExpense == snapshot.expenseMinor
                    && storedSaved == snapshot.savedMinor
                let baseCurrencyMatches = (try? CurrencyCode(validating: storedBaseCurrency)) == snapshot.baseCurrencyCode
                let hasExistingConversion = !(storedRate ?? "").isEmpty
                // An already-stored approximate row may be upgraded to exact when
                // the rate itself did not change (same rate value, now on the
                // exact month-end date). Never rewrites rate history otherwise.
                let upgradeApproximation = storedIsApproximate
                    && !snapshot.isApproximate
                    && snapshot.rateDecimal == storedRate

                if totalsUnchanged, baseCurrencyMatches, hasExistingConversion, !upgradeApproximation {
                    return
                }
                _ = try snapshot.update(db)
            } else {
                var insert = snapshot
                insert.id = snapshot.id.isEmpty ? UUID().uuidString : snapshot.id
                _ = try insert.insert(db)
            }
        }
    }
}
