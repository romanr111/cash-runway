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
        let (data, response) = try await urlSession.data(from: url)
        try validateHTTPStatus(response)
        let items = try JSONDecoder().decode([MonobankRateItem].self, from: data)
        let now = date ?? dateProvider()
        return items.compactMap { item -> [ExchangeRate]? in
            guard let sourceCurrency = currencyCode(fromNumeric: item.currencyCodeA),
                  let targetCurrency = currencyCode(fromNumeric: item.currencyCodeB) else { return nil }
            var rates: [ExchangeRate] = []
            if let buy = item.rateBuy?.decimalValue, let sell = item.rateSell?.decimalValue {
                rates.append(exchangeRate(
                    source: sourceCurrency,
                    target: targetCurrency,
                    value: buy,
                    date: now,
                    sourceLabel: "monobank-buy"
                ))
                rates.append(exchangeRate(
                    source: sourceCurrency,
                    target: targetCurrency,
                    value: sell,
                    date: now,
                    sourceLabel: "monobank-sell"
                ))
                let midpoint = (buy + sell) / 2
                rates.append(exchangeRate(
                    source: sourceCurrency,
                    target: targetCurrency,
                    value: midpoint,
                    date: now,
                    sourceLabel: "monobank-midpoint"
                ))
            } else if let cross = item.rateCross?.decimalValue {
                rates.append(exchangeRate(
                    source: sourceCurrency,
                    target: targetCurrency,
                    value: cross,
                    date: now,
                    sourceLabel: "monobank-cross"
                ))
            }
            return rates.isEmpty ? nil : rates
        }.flatMap { $0 }
    }
}

private struct MonobankRateItem: Decodable {
    var currencyCodeA: Int
    var currencyCodeB: Int
    var rateBuy: FlexibleDecimal?
    var rateSell: FlexibleDecimal?
    var rateCross: FlexibleDecimal?
}

private func currencyCode(fromNumeric code: Int) -> CurrencyCode? {
    switch code {
    case ISO4217NumericCurrencyCode.uah: .uah
    case ISO4217NumericCurrencyCode.usd: .usd
    case ISO4217NumericCurrencyCode.eur: .eur
    default: nil
    }
}
