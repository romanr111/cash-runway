import Foundation

public final class CachingExchangeRateProvider: ExchangeRateProviding {
    private let upstream: ExchangeRateProviding
    private let repository: any CurrencyRepositorying
    private let maxStaleness: TimeInterval
    private let source: String?

    public init(
        upstream: ExchangeRateProviding,
        repository: any CurrencyRepositorying,
        maxStaleness: TimeInterval = 6 * 60 * 60,
        source: String? = nil
    ) {
        self.upstream = upstream
        self.repository = repository
        self.maxStaleness = maxStaleness
        self.source = source
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
        if let cached = try repository.cachedExchangeRate(
            from: sourceCurrency,
            to: targetCurrency,
            on: date,
            source: source,
            maxStaleness: maxStaleness
        ) {
            return cached
        }

        let rate = try await upstream.rate(from: sourceCurrency, to: targetCurrency, on: date)
        var rateToCache = rate
        rateToCache.effectiveDate = effectiveDate
        try repository.saveExchangeRates([rateToCache])
        return rate
    }
}
