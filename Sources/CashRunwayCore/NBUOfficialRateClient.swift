import Foundation

public final class NBUOfficialRateClient: PublicExchangeRateClient {
    private let urlSession: URLSession
    private let dateProvider: @Sendable () -> Date
    private static let responseDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter
    }()

    public init(urlSession: URLSession = .shared, dateProvider: @escaping @Sendable () -> Date = Date.init) {
        self.urlSession = urlSession
        self.dateProvider = dateProvider
    }

    public func fetchRates(baseCurrency: CurrencyCode, date: Date?) async throws -> [ExchangeRate] {
        let now = date ?? dateProvider()
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
        let (data, response) = try await urlSession.data(from: url)
        try validateHTTPStatus(response)
        let items = try JSONDecoder().decode([NBURateItem].self, from: data)
        return items.compactMap { item in
            guard let sourceCurrency = CurrencyCode(rawValue: item.cc.uppercased()) else { return nil }
            let effectiveDate = Self.responseDateFormatter.date(from: item.exchangedate)
                ?? DateKeys.calendar.startOfDay(for: now)
            return exchangeRate(
                source: sourceCurrency,
                target: .uah,
                value: item.rate.decimalValue,
                date: effectiveDate,
                sourceLabel: "nbu-official"
            )
        }
    }
}

private struct NBURateItem: Decodable {
    var r030: Int
    var rate: FlexibleDecimal
    var cc: String
    var exchangedate: String
}
