import Foundation
import GRDB

extension CashRunwayRepository: CurrencyRepositorying {
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
                defaultCurrencyCode: CurrencyCode(rawValue: row["default_currency_code"]),
                reportingCurrencyCode: CurrencyCode(rawValue: row["reporting_currency_code"])
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
                sourceCurrencyCode: CurrencyCode(rawValue: row["base_currency_code"]),
                targetCurrencyCode: CurrencyCode(rawValue: row["quote_currency_code"]),
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
