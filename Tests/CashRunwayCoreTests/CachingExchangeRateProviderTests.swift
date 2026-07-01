import Foundation
import Testing
import GRDB
@testable import CashRunwayCore

@Suite(.serialized)
struct CachingExchangeRateProviderTests {
    private func makeRepository() throws -> CashRunwayRepository {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        return repository
    }

    private func exchangeRateCount(in repository: CashRunwayRepository) throws -> Int {
        try repository.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM exchange_rates") ?? 0
        }
    }

    private func ageExchangeRates(in repository: CashRunwayRepository, secondsAgo: TimeInterval) throws {
        let stale = Date().addingTimeInterval(-secondsAgo)
        try repository.databaseManager.dbQueue.write { db in
            try db.execute(sql: "UPDATE exchange_rates SET fetched_at = ?", arguments: [stale])
        }
    }

    @Test func cacheMissFetchesUpstreamAndSavesRate() async throws {
        let repository = try makeRepository()
        let upstream = CountingProvider(rate: ExchangeRate(
            sourceCurrencyCode: .usd,
            targetCurrencyCode: .uah,
            rateDecimal: "44.70",
            effectiveDate: .now,
            source: "bank_public_composite"
        ))
        let provider = CachingExchangeRateProvider(upstream: upstream, repository: repository, source: "bank_public_composite")

        let rate = try await provider.rate(from: .usd, to: .uah, on: .now)

        #expect(upstream.callCount == 1)
        #expect(rate.rateDecimal == "44.70")
        #expect(try exchangeRateCount(in: repository) == 1)
    }

    @Test func cacheHitSkipsUpstream() async throws {
        let repository = try makeRepository()
        let upstream = CountingProvider(rate: ExchangeRate(
            sourceCurrencyCode: .usd,
            targetCurrencyCode: .uah,
            rateDecimal: "44.70",
            effectiveDate: .now,
            source: "bank_public_composite"
        ))
        let provider = CachingExchangeRateProvider(upstream: upstream, repository: repository, source: "bank_public_composite")

        _ = try await provider.rate(from: .usd, to: .uah, on: .now)
        let cached = try await provider.rate(from: .usd, to: .uah, on: .now)

        #expect(upstream.callCount == 1)
        #expect(cached.rateDecimal == "44.70")
        #expect(try exchangeRateCount(in: repository) == 1)
    }

    @Test func sameCurrencyReturnsIdentityWithoutUpstreamOrSave() async throws {
        let repository = try makeRepository()
        let upstream = CountingProvider(rate: ExchangeRate(
            sourceCurrencyCode: .usd,
            targetCurrencyCode: .uah,
            rateDecimal: "44.70",
            effectiveDate: .now,
            source: "bank_public_composite"
        ))
        let provider = CachingExchangeRateProvider(upstream: upstream, repository: repository)

        let rate = try await provider.rate(from: .usd, to: .usd, on: .now)

        #expect(rate.rateDecimal == "1")
        #expect(rate.source == "identity")
        #expect(upstream.callCount == 0)
        #expect(try exchangeRateCount(in: repository) == 0)
    }

    @Test func staleEntryRefetchesFromUpstream() async throws {
        let repository = try makeRepository()
        let upstream = CountingProvider(rate: ExchangeRate(
            sourceCurrencyCode: .usd,
            targetCurrencyCode: .uah,
            rateDecimal: "44.70",
            effectiveDate: .now,
            source: "bank_public_composite"
        ))
        let provider = CachingExchangeRateProvider(upstream: upstream, repository: repository, maxStaleness: 6 * 60 * 60, source: "bank_public_composite")

        _ = try await provider.rate(from: .usd, to: .uah, on: .now)

        // Force the cached row to be older than the staleness window.
        try ageExchangeRates(in: repository, secondsAgo: 7 * 60 * 60)

        _ = try await provider.rate(from: .usd, to: .uah, on: .now)

        #expect(upstream.callCount == 2)
    }
}

private final class CountingProvider: ExchangeRateProviding, @unchecked Sendable {
    let rate: ExchangeRate
    private(set) var callCount = 0

    init(rate: ExchangeRate) {
        self.rate = rate
    }

    func rate(from sourceCurrency: CurrencyCode, to targetCurrency: CurrencyCode, on date: Date) async throws -> ExchangeRate {
        callCount += 1
        return rate
    }
}
