import Foundation

public final class PrivatBankPublicRateClient: PublicExchangeRateClient {
    private let urlSession: URLSession
    private let dateProvider: @Sendable () -> Date

    public init(urlSession: URLSession = .shared, dateProvider: @escaping @Sendable () -> Date = Date.init) {
        self.urlSession = urlSession
        self.dateProvider = dateProvider
    }

    public func fetchRates(baseCurrency: CurrencyCode, date: Date?) async throws -> [ExchangeRate] {
        let url = URL(string: "https://api.privatbank.ua/p24api/pubinfo?exchange&coursid=5")!
        let (data, _) = try await urlSession.data(from: url)
        let items = try JSONDecoder().decode([PrivatBankRateItem].self, from: data)
        let now = date ?? dateProvider()
        return items.compactMap { item -> [ExchangeRate]? in
            guard let sourceCurrency = CurrencyCode(rawValue: item.ccy.uppercased()),
                  let targetCurrency = CurrencyCode(rawValue: item.baseCcy.uppercased()),
                  Decimal(string: item.buy) != nil,
                  Decimal(string: item.sale) != nil else { return nil }
            return [
                ExchangeRate(
                    sourceCurrencyCode: sourceCurrency,
                    targetCurrencyCode: targetCurrency,
                    rateDecimal: item.buy,
                    effectiveDate: now,
                    source: "privatbank-buy"
                ),
                ExchangeRate(
                    sourceCurrencyCode: sourceCurrency,
                    targetCurrencyCode: targetCurrency,
                    rateDecimal: item.sale,
                    effectiveDate: now,
                    source: "privatbank-sell"
                ),
                ExchangeRate(
                    sourceCurrencyCode: sourceCurrency,
                    targetCurrencyCode: targetCurrency,
                    rateDecimal: midpoint(item.buy, item.sale),
                    effectiveDate: now,
                    source: "privatbank-midpoint"
                ),
            ]
        }.flatMap { $0 }
    }
}

private struct PrivatBankRateItem: Codable {
    var ccy: String
    var baseCcy: String
    var buy: String
    var sale: String
}

private func midpoint(_ buy: String, _ sell: String) -> String {
    guard let buyDecimal = Decimal(string: buy),
          let sellDecimal = Decimal(string: sell) else { return "0" }
    let average = (buyDecimal + sellDecimal) / 2
    return average.description
}
