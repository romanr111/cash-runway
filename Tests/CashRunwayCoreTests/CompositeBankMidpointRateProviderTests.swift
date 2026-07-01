import Foundation
import Testing
@testable import CashRunwayCore

struct CompositeBankMidpointRateProviderTests {
    @Test func monobankAndPrivatBankRatesAverageToCompositeMidpoint() async throws {
        let monobank = StaticPublicRateClient(rates: [
            ExchangeRate(sourceCurrencyCode: .usd, targetCurrencyCode: .uah, rateDecimal: "44.00", effectiveDate: .now, source: "monobank-midpoint"),
            ExchangeRate(sourceCurrencyCode: .eur, targetCurrencyCode: .uah, rateDecimal: "52.00", effectiveDate: .now, source: "monobank-midpoint"),
        ])
        let privatbank = StaticPublicRateClient(rates: [
            ExchangeRate(sourceCurrencyCode: .usd, targetCurrencyCode: .uah, rateDecimal: "46.00", effectiveDate: .now, source: "privatbank-midpoint"),
            ExchangeRate(sourceCurrencyCode: .eur, targetCurrencyCode: .uah, rateDecimal: "52.00", effectiveDate: .now, source: "privatbank-midpoint"),
        ])
        let provider = CompositeBankMidpointRateProvider(clients: [monobank, privatbank])
        let rate = try await provider.rate(from: .usd, to: .uah, on: .now)
        #expect(rate.rateDecimal == "45")
        #expect(rate.source == "bank_public_composite")
    }

    @Test func missingPublicBankRatesFallBackToNbuOfficial() async throws {
        let monobank = StaticPublicRateClient(rates: [])
        let privatbank = StaticPublicRateClient(rates: [])
        let nbu = StaticPublicRateClient(rates: [
            ExchangeRate(sourceCurrencyCode: .usd, targetCurrencyCode: .uah, rateDecimal: "44.70", effectiveDate: .now, source: "nbu-official")
        ])
        let provider = CompositeBankMidpointRateProvider(clients: [monobank, privatbank], officialClient: nbu)
        let rate = try await provider.rate(from: .usd, to: .uah, on: .now)
        #expect(rate.source == "nbu-official")
    }

    @Test func noRatesThrowsMissingRate() async throws {
        let provider = CompositeBankMidpointRateProvider(clients: [])
        await #expect(throws: MoneyError.missingExchangeRate(from: .usd, to: .uah)) {
            try await provider.rate(from: .usd, to: .uah, on: .now)
        }
    }

    @Test func sameCurrencyReturnsIdentityRate() async throws {
        let provider = CompositeBankMidpointRateProvider(clients: [])
        let rate = try await provider.rate(from: .uah, to: .uah, on: .now)
        #expect(rate.rateDecimal == "1")
        #expect(rate.source == "identity")
    }
}

private struct StaticPublicRateClient: PublicExchangeRateClient {
    let rates: [ExchangeRate]

    func fetchRates(baseCurrency: CurrencyCode, date: Date?) async throws -> [ExchangeRate] {
        rates
    }
}
