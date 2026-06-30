import Foundation

public final class MonobankPublicRateClient: PublicExchangeRateClient {
    private let urlSession: URLSession
    private let dateProvider: @Sendable () -> Date

    public init(urlSession: URLSession = .shared, dateProvider: @escaping @Sendable () -> Date = Date.init) {
        self.urlSession = urlSession
        self.dateProvider = dateProvider
    }

    public func fetchRates(baseCurrency: CurrencyCode, date: Date?) async throws -> [ExchangeRate] {
        let url = URL(string: "https://api.monobank.ua/bank/currency")!
        let (data, _) = try await urlSession.data(from: url)
        let items = try JSONDecoder().decode([MonobankRateItem].self, from: data)
        let now = date ?? dateProvider()
        return items.compactMap { item -> [ExchangeRate]? in
            guard let sourceCurrency = currencyCode(fromNumeric: item.currencyCodeA),
                  let targetCurrency = currencyCode(fromNumeric: item.currencyCodeB),
                  Decimal(string: item.rateBuy) != nil,
                  Decimal(string: item.rateSell) != nil else { return nil }
            return [
                ExchangeRate(
                    sourceCurrencyCode: sourceCurrency,
                    targetCurrencyCode: targetCurrency,
                    rateDecimal: item.rateBuy,
                    effectiveDate: now,
                    source: "monobank-buy"
                ),
                ExchangeRate(
                    sourceCurrencyCode: sourceCurrency,
                    targetCurrencyCode: targetCurrency,
                    rateDecimal: item.rateSell,
                    effectiveDate: now,
                    source: "monobank-sell"
                ),
                ExchangeRate(
                    sourceCurrencyCode: sourceCurrency,
                    targetCurrencyCode: targetCurrency,
                    rateDecimal: midpoint(item.rateBuy, item.rateSell),
                    effectiveDate: now,
                    source: "monobank-midpoint"
                ),
            ]
        }.flatMap { $0 }
    }
}

private struct MonobankRateItem: Codable {
    var currencyCodeA: Int
    var currencyCodeB: Int
    var rateBuy: String
    var rateSell: String
}

private func midpoint(_ buy: String, _ sell: String) -> String {
    guard let buyDecimal = Decimal(string: buy),
          let sellDecimal = Decimal(string: sell) else { return "0" }
    let average = (buyDecimal + sellDecimal) / 2
    return average.description
}

private func currencyCode(fromNumeric code: Int) -> CurrencyCode? {
    switch code {
    case ISO4217NumericCurrencyCode.uah: .uah
    case ISO4217NumericCurrencyCode.usd: .usd
    case ISO4217NumericCurrencyCode.eur: .eur
    default: nil
    }
}
