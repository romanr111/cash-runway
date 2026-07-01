import Foundation

public enum ExchangeRateClientError: Error, Equatable {
    case invalidResponse
    case rateLimit
    case httpStatus(Int)
}

struct FlexibleDecimal: Decodable {
    let decimalValue: Decimal

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let decimal = try? container.decode(Decimal.self) {
            decimalValue = decimal
        } else {
            let string = try container.decode(String.self)
            guard let decimal = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid decimal value"
                )
            }
            decimalValue = decimal
        }
    }
}

func validateHTTPStatus(_ response: URLResponse) throws {
    guard let httpResponse = response as? HTTPURLResponse else {
        throw ExchangeRateClientError.invalidResponse
    }
    switch httpResponse.statusCode {
    case 200..<300:
        return
    case 429:
        throw ExchangeRateClientError.rateLimit
    default:
        throw ExchangeRateClientError.httpStatus(httpResponse.statusCode)
    }
}

func exchangeRate(source: CurrencyCode, target: CurrencyCode, value: Decimal, date: Date, sourceLabel: String) -> ExchangeRate {
    ExchangeRate(
        sourceCurrencyCode: source,
        targetCurrencyCode: target,
        rateDecimal: value.description,
        effectiveDate: date,
        source: sourceLabel
    )
}
