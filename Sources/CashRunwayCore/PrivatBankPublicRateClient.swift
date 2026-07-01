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
        let (data, response) = try await urlSession.data(from: url)
        try validateHTTPStatus(response)
        let items = try JSONDecoder().decode([PrivatBankRateItem].self, from: data)
        let now = date ?? dateProvider()
        return items.compactMap { item -> [ExchangeRate]? in
            guard let sourceCurrency = CurrencyCode(rawValue: item.ccy.uppercased()),
                  let targetCurrency = CurrencyCode(rawValue: item.baseCcy.uppercased()),
                  let buy = Decimal(string: item.buy, locale: Locale(identifier: "en_US_POSIX")),
                  let sale = Decimal(string: item.sale, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
            let midpoint = (buy + sale) / 2
            return [
                exchangeRate(source: sourceCurrency, target: targetCurrency, value: buy, date: now, sourceLabel: "privatbank-buy"),
                exchangeRate(source: sourceCurrency, target: targetCurrency, value: sale, date: now, sourceLabel: "privatbank-sell"),
                exchangeRate(source: sourceCurrency, target: targetCurrency, value: midpoint, date: now, sourceLabel: "privatbank-midpoint"),
            ]
        }.flatMap { $0 }
    }
}

private struct PrivatBankRateItem: Decodable {
    var ccy: String
    var baseCcy: String
    var buy: String
    var sale: String

    private enum CodingKeys: String, CodingKey {
        case ccy
        case baseCcy = "base_ccy"
        case buy
        case sale
    }
}
