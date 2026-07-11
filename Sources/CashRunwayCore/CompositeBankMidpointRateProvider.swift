import Foundation

public final class CompositeBankMidpointRateProvider: ExchangeRateProviding {
    private let clients: [any PublicExchangeRateClient]
    private let officialClient: (any PublicExchangeRateClient)?

    public init(
        clients: [any PublicExchangeRateClient],
        officialClient: (any PublicExchangeRateClient)? = nil
    ) {
        self.clients = clients
        self.officialClient = officialClient
    }

    public func rate(
        from sourceCurrency: CurrencyCode,
        to targetCurrency: CurrencyCode,
        on date: Date
    ) async throws -> ExchangeRate {
        if sourceCurrency == targetCurrency {
            return ExchangeRate(
                sourceCurrencyCode: sourceCurrency,
                targetCurrencyCode: targetCurrency,
                rateDecimal: "1",
                effectiveDate: date,
                source: "identity"
            )
        }

        let effectiveDate = DateKeys.calendar.startOfDay(for: date)
        let allRates = await withTaskGroup(of: [ExchangeRate].self) { group in
            for client in clients {
                group.addTask {
                    do {
                        return try await client.fetchRates(baseCurrency: sourceCurrency, date: date)
                    } catch {
                        return []
                    }
                }
            }
            var collected: [ExchangeRate] = []
            for await rates in group {
                collected.append(contentsOf: rates)
            }
            return collected
        }

        let midpointSources: Set<String> = ["monobank-midpoint", "privatbank-midpoint"]
        let midpoints = allRates.filter {
            $0.sourceCurrencyCode == sourceCurrency &&
            $0.targetCurrencyCode == targetCurrency &&
            midpointSources.contains($0.source) &&
            DateKeys.calendar.startOfDay(for: $0.effectiveDate) == effectiveDate
        }

        if let composite = averageRate(midpoints, source: "bank_public_composite", effectiveDate: effectiveDate) {
            return composite
        }

        if let officialClient {
            let officialRates = (try? await officialClient.fetchRates(baseCurrency: sourceCurrency, date: date)) ?? []
            if let official = officialRates.first(where: {
                $0.sourceCurrencyCode == sourceCurrency &&
                $0.targetCurrencyCode == targetCurrency &&
                $0.source == "nbu-official" &&
                DateKeys.calendar.startOfDay(for: $0.effectiveDate) == effectiveDate
            }) {
                return official
            }
        }

        throw MoneyError.missingExchangeRate(from: sourceCurrency, to: targetCurrency)
    }

    private func averageRate(_ rates: [ExchangeRate], source: String, effectiveDate: Date) -> ExchangeRate? {
        let decimals = rates.compactMap { Decimal(string: $0.rateDecimal, locale: Locale(identifier: "en_US_POSIX")) }
        guard !decimals.isEmpty else { return nil }
        let sum = decimals.reduce(Decimal(0), +)
        let average = sum / Decimal(decimals.count)
        guard let first = rates.first else { return nil }
        return ExchangeRate(
            sourceCurrencyCode: first.sourceCurrencyCode,
            targetCurrencyCode: first.targetCurrencyCode,
            rateDecimal: average.description,
            effectiveDate: effectiveDate,
            source: source
        )
    }
}
