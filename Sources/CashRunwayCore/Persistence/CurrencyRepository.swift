import Foundation
import GRDB

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
                ORDER BY source ASC, fetched_at DESC
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
}
