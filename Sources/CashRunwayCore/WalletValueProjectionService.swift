import Foundation

public final class WalletValueProjectionService {
    private let repository: any CashRunwayRepositorying
    private let rateProvider: ExchangeRateProviding

    public init(repository: any CashRunwayRepositorying, rateProvider: ExchangeRateProviding) {
        self.repository = repository
        self.rateProvider = rateProvider
    }

    public func projectedValue(
        wallet: Wallet,
        targetCurrency: CurrencyCode,
        policy: MarketRatePolicy = MarketRatePolicy()
    ) async throws -> WalletValueProjection {
        let nativeAmount = MoneyAmount(minorUnits: wallet.currentBalanceMinor, currencyCode: wallet.currencyCode)

        if wallet.currencyCode == targetCurrency {
            return WalletValueProjection(
                nativeAmount: nativeAmount,
                projectedAmount: nativeAmount,
                rate: nil,
                basis: .bankCompositeMidpoint,
                providerLabel: WalletValueProjectionProvider.publicBankCompositeLabel,
                isFallback: false,
                isApproximate: false
            )
        }

        let date = Date()
        let crossRate = try await crossRate(
            from: wallet.currencyCode,
            to: targetCurrency,
            date: date,
            policy: policy
        )
        guard let decimalRate = Decimal(string: crossRate.rateDecimal) else {
            throw MoneyError.missingExchangeRate(from: wallet.currencyCode, to: targetCurrency)
        }

        let decimalAmount = Decimal(wallet.currentBalanceMinor) / 100
        let converted = decimalAmount * decimalRate
        let projectedMinor = Self.minorUnits(from: converted)

        let projectedAmount = MoneyAmount(minorUnits: projectedMinor, currencyCode: targetCurrency)
        let isFallback = crossRate.source == "nbu-official"
        let providerLabel = isFallback ? WalletValueProjectionProvider.nbuFallbackLabel : WalletValueProjectionProvider.publicBankCompositeLabel
        let basis: ExchangeRateBasis = isFallback ? .official : .bankCompositeMidpoint
        return WalletValueProjection(
            nativeAmount: nativeAmount,
            projectedAmount: projectedAmount,
            rate: crossRate,
            basis: basis,
            providerLabel: providerLabel,
            isFallback: isFallback,
            isApproximate: true
        )
    }

    public func projectedValue(
        walletID: UUID,
        targetCurrency: CurrencyCode,
        policy: MarketRatePolicy = MarketRatePolicy()
    ) async throws -> WalletValueProjection {
        guard let wallet = try repository.wallets().first(where: { $0.id == walletID }) else {
            throw CashRunwayError.notFound
        }
        return try await projectedValue(wallet: wallet, targetCurrency: targetCurrency, policy: policy)
    }

    private func crossRate(
        from sourceCurrency: CurrencyCode,
        to targetCurrency: CurrencyCode,
        date: Date,
        policy: MarketRatePolicy
    ) async throws -> ExchangeRate {
        if sourceCurrency == targetCurrency {
            return identityRate(for: sourceCurrency, date: date)
        }

        if sourceCurrency == .uah {
            let targetToUAH = try await rateToUAH(currency: targetCurrency, date: date, policy: policy)
            return inverted(targetToUAH)
        }

        let sourceToUAH = try await rateToUAH(currency: sourceCurrency, date: date, policy: policy)

        if targetCurrency == .uah {
            return sourceToUAH
        }

        let targetToUAH = try await rateToUAH(currency: targetCurrency, date: date, policy: policy)
        return cross(from: sourceToUAH, to: targetToUAH)
    }

    private func rateToUAH(currency: CurrencyCode, date: Date, policy: MarketRatePolicy) async throws -> ExchangeRate {
        guard currency != .uah else {
            return identityRate(for: .uah, date: date)
        }
        let rate = try await rateProvider.rate(from: currency, to: .uah, on: date)
        guard Decimal(string: rate.rateDecimal) != nil else {
            throw MoneyError.missingExchangeRate(from: currency, to: .uah)
        }
        return rate
    }

    private func identityRate(for currency: CurrencyCode, date: Date) -> ExchangeRate {
        ExchangeRate(
            sourceCurrencyCode: currency,
            targetCurrencyCode: currency,
            rateDecimal: "1",
            effectiveDate: date,
            source: "identity"
        )
    }

    private func inverted(_ rate: ExchangeRate) -> ExchangeRate {
        guard let decimal = Decimal(string: rate.rateDecimal), decimal != 0 else {
            return ExchangeRate(
                sourceCurrencyCode: rate.targetCurrencyCode,
                targetCurrencyCode: rate.sourceCurrencyCode,
                rateDecimal: "0",
                effectiveDate: rate.effectiveDate,
                source: rate.source
            )
        }
        return ExchangeRate(
            sourceCurrencyCode: rate.targetCurrencyCode,
            targetCurrencyCode: rate.sourceCurrencyCode,
            rateDecimal: (1 / decimal).description,
            effectiveDate: rate.effectiveDate,
            source: rate.source
        )
    }

    private func cross(from sourceToUAH: ExchangeRate, to targetToUAH: ExchangeRate) -> ExchangeRate {
        guard let sourceRate = Decimal(string: sourceToUAH.rateDecimal),
              let targetRate = Decimal(string: targetToUAH.rateDecimal),
              targetRate != 0 else {
            return ExchangeRate(
                sourceCurrencyCode: sourceToUAH.sourceCurrencyCode,
                targetCurrencyCode: targetToUAH.sourceCurrencyCode,
                rateDecimal: "0",
                effectiveDate: sourceToUAH.effectiveDate,
                source: "bank_public_composite"
            )
        }
        let crossRate = sourceRate / targetRate
        return ExchangeRate(
            sourceCurrencyCode: sourceToUAH.sourceCurrencyCode,
            targetCurrencyCode: targetToUAH.sourceCurrencyCode,
            rateDecimal: crossRate.description,
            effectiveDate: sourceToUAH.effectiveDate,
            source: "bank_public_composite"
        )
    }

    private static func minorUnits(from decimal: Decimal) -> Int64 {
        var scaled = decimal * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        let nsNumber = NSDecimalNumber(decimal: rounded)
        guard nsNumber != NSDecimalNumber.notANumber,
              let result = nsNumber.int64Value as Int64?,
              Decimal(result) == rounded
        else {
            return 0
        }
        return result
    }
}
