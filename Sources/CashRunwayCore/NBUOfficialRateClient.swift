import Foundation

public final class NBUOfficialRateClient: PublicExchangeRateClient {
    private let urlSession: URLSession
    private let dateProvider: @Sendable () -> Date

    public init(urlSession: URLSession = .shared, dateProvider: @escaping @Sendable () -> Date = Date.init) {
        self.urlSession = urlSession
        self.dateProvider = dateProvider
    }

    public func fetchRates(baseCurrency: CurrencyCode, date: Date?) async throws -> [ExchangeRate] {
        let now = date ?? dateProvider()
        let effectiveDate = DateKeys.calendar.startOfDay(for: now)
        var urlComponents = URLComponents(string: "https://bank.gov.ua/NBUStatService/v1/statdirectory/exchange")!
        var queryItems = [URLQueryItem(name: "json", value: "")]
        if baseCurrency != .uah {
            queryItems.append(URLQueryItem(name: "valcode", value: baseCurrency.rawValue))
        }
        if let date {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd"
            queryItems.append(URLQueryItem(name: "date", value: formatter.string(from: date)))
        }
        urlComponents.queryItems = queryItems
        guard let url = urlComponents.url else { return [] }
        let (data, _) = try await urlSession.data(from: url)
        let items = try JSONDecoder().decode([NBURateItem].self, from: data)
        return items.compactMap { item in
            guard let sourceCurrency = CurrencyCode(rawValue: item.cc.uppercased()) else { return nil }
            return ExchangeRate(
                sourceCurrencyCode: sourceCurrency,
                targetCurrencyCode: .uah,
                rateDecimal: item.rate,
                effectiveDate: effectiveDate,
                source: "nbu-official"
            )
        }
    }
}

private struct NBURateItem: Codable {
    var r030: Int
    var rate: String
    var cc: String
    var exchangedate: String
}
