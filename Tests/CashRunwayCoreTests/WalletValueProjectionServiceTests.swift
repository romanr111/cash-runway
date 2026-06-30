import Foundation
import Testing
@testable import CashRunwayCore

struct WalletValueProjectionServiceTests {
    private func makeService(rates: [ExchangeRate]) throws -> WalletValueProjectionService {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let provider = StaticRateProvider(rates: rates)
        return WalletValueProjectionService(repository: repository, rateProvider: provider)
    }

    @Test func sameCurrencyProjectionReturnsUnchangedAmount() async throws {
        let service = try makeService(rates: [])
        let wallet = WalletBuilder().with(name: "UAH").with(currentBalanceMinor: 100_000).build()
        let projection = try await service.projectedValue(wallet: wallet, targetCurrency: .uah)
        #expect(projection.nativeAmount == projection.projectedAmount)
        #expect(projection.nativeAmount.minorUnits == 100_000)
        #expect(projection.rate == nil)
        #expect(!projection.isFallback)
        #expect(!projection.isApproximate)
    }

    @Test func uahToUsdDividesByMidpointRate() async throws {
        let rates = [
            ExchangeRate(sourceCurrencyCode: .usd, targetCurrencyCode: .uah, rateDecimal: "44.70", effectiveDate: .now, source: "bank_public_composite")
        ]
        let service = try makeService(rates: rates)
        let wallet = WalletBuilder().with(name: "UAH").with(currentBalanceMinor: 100_000).build()
        let projection = try await service.projectedValue(wallet: wallet, targetCurrency: .usd)
        #expect(projection.projectedAmount.currencyCode == .usd)
        #expect(projection.projectedAmount.minorUnits == 2_237)
        #expect(!projection.isFallback)
    }

    @Test func usdToUahMultipliesByMidpointRate() async throws {
        let rates = [
            ExchangeRate(sourceCurrencyCode: .usd, targetCurrencyCode: .uah, rateDecimal: "44.70", effectiveDate: .now, source: "bank_public_composite")
        ]
        let service = try makeService(rates: rates)
        let wallet = WalletBuilder().with(name: "USD").with(currencyCode: .usd).with(currentBalanceMinor: 100_000).build()
        let projection = try await service.projectedValue(wallet: wallet, targetCurrency: .uah)
        // 1000 USD * 44.70 = 44700 UAH minor
        #expect(projection.projectedAmount.currencyCode == .uah)
        #expect(projection.projectedAmount.minorUnits == 4_470_000)
        #expect(!projection.isFallback)
    }

    @Test func fallbackToOfficialMarksIsFallback() async throws {
        let rates = [
            ExchangeRate(sourceCurrencyCode: .usd, targetCurrencyCode: .uah, rateDecimal: "44.70", effectiveDate: .now, source: "nbu-official")
        ]
        let service = try makeService(rates: rates)
        let wallet = WalletBuilder().with(name: "USD").with(currencyCode: .usd).with(currentBalanceMinor: 100_000).build()
        let projection = try await service.projectedValue(wallet: wallet, targetCurrency: .uah)
        #expect(projection.isFallback)
        #expect(projection.providerLabel == WalletValueProjectionProvider.nbuFallbackLabel)
    }

    @Test func usdToEurConvertsThroughUah() async throws {
        let rates = [
            ExchangeRate(sourceCurrencyCode: .usd, targetCurrencyCode: .uah, rateDecimal: "44.70", effectiveDate: .now, source: "bank_public_composite"),
            ExchangeRate(sourceCurrencyCode: .eur, targetCurrencyCode: .uah, rateDecimal: "52.00", effectiveDate: .now, source: "bank_public_composite"),
        ]
        let service = try makeService(rates: rates)
        let wallet = WalletBuilder().with(name: "USD").with(currencyCode: .usd).with(currentBalanceMinor: 100_000).build()
        let projection = try await service.projectedValue(wallet: wallet, targetCurrency: .eur)
        #expect(projection.projectedAmount.currencyCode == .eur)
        #expect(projection.projectedAmount.minorUnits == 85_962)
        #expect(!projection.isFallback)
    }

    @Test func resultExposesSourceAndBasisAndEffectiveDate() async throws {
        let now = Date()
        let rates = [
            ExchangeRate(sourceCurrencyCode: .usd, targetCurrencyCode: .uah, rateDecimal: "44.70", effectiveDate: now, source: "nbu-official")
        ]
        let service = try makeService(rates: rates)
        let wallet = WalletBuilder().with(name: "USD").with(currencyCode: .usd).with(currentBalanceMinor: 100_000).build()
        let projection = try await service.projectedValue(wallet: wallet, targetCurrency: .uah)
        #expect(projection.rate?.source == "nbu-official")
        #expect(projection.basis == .official)
        #expect(projection.rate?.effectiveDate == now)
        #expect(projection.isFallback)
        #expect(projection.isApproximate)
    }
}

private struct StaticRateProvider: ExchangeRateProviding {
    let rates: [ExchangeRate]

    func rate(from sourceCurrency: CurrencyCode, to targetCurrency: CurrencyCode, on date: Date) async throws -> ExchangeRate {
        let match = rates.first {
            $0.sourceCurrencyCode == sourceCurrency &&
            $0.targetCurrencyCode == targetCurrency
        }
        guard let match else { throw MoneyError.missingExchangeRate(from: sourceCurrency, to: targetCurrency) }
        return match
    }
}
