import Foundation

public enum MoneyError: Error, LocalizedError, Equatable {
    case invalidAmount(String)
    case invalidCurrencyCode(String)
    case currencyMismatch(lhs: CurrencyCode, rhs: CurrencyCode)
    case missingExchangeRate(from: CurrencyCode, to: CurrencyCode)

    public var errorDescription: String? {
        switch self {
        case let .invalidAmount(value):
            "Invalid amount: \(value)"
        case let .invalidCurrencyCode(value):
            "Invalid currency code: \(value)."
        case let .currencyMismatch(lhs, rhs):
            "Currency mismatch: \(lhs.rawValue) cannot be combined with \(rhs.rawValue)."
        case let .missingExchangeRate(source, target):
            "Missing exchange rate from \(source.rawValue) to \(target.rawValue)."
        }
    }
}

public struct CurrencyCode: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard Self.isValid(normalized) else { return nil }
        self.rawValue = normalized
    }

    public init(validating rawValue: String) throws {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard Self.isValid(normalized) else {
            throw MoneyError.invalidCurrencyCode(rawValue)
        }
        self.rawValue = normalized
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard CurrencyCode.isValid(normalized) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Currency code must be a three-letter ISO 4217 alpha code."
            )
        }
        self.rawValue = normalized
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private static func isValid(_ value: String) -> Bool {
        value.count == 3 && value.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 65 && scalar.value <= 90
        }
    }
}

public extension CurrencyCode {
    static let uah = CurrencyCode(rawValue: "UAH")!
    static let usd = CurrencyCode(rawValue: "USD")!
    static let eur = CurrencyCode(rawValue: "EUR")!
}

public struct MoneyAmount: Codable, Hashable, Sendable {
    public var minorUnits: Int64
    public var currencyCode: CurrencyCode

    public init(minorUnits: Int64, currencyCode: CurrencyCode) {
        self.minorUnits = minorUnits
        self.currencyCode = currencyCode
    }

    public func adding(_ other: MoneyAmount) throws -> MoneyAmount {
        guard currencyCode == other.currencyCode else {
            throw MoneyError.currencyMismatch(lhs: currencyCode, rhs: other.currencyCode)
        }
        return MoneyAmount(minorUnits: minorUnits + other.minorUnits, currencyCode: currencyCode)
    }
}

public struct CurrencyPreferences: Codable, Hashable, Sendable {
    public var defaultCurrencyCode: CurrencyCode
    public var reportingCurrencyCode: CurrencyCode

    public init(
        defaultCurrencyCode: CurrencyCode = .uah,
        reportingCurrencyCode: CurrencyCode = .uah
    ) {
        self.defaultCurrencyCode = defaultCurrencyCode
        self.reportingCurrencyCode = reportingCurrencyCode
    }

    public static let `default` = CurrencyPreferences()
}

public struct ExchangeRate: Codable, Hashable, Sendable {
    public var sourceCurrencyCode: CurrencyCode
    public var targetCurrencyCode: CurrencyCode
    public var rateDecimal: String
    public var effectiveDate: Date
    public var source: String

    public init(
        sourceCurrencyCode: CurrencyCode,
        targetCurrencyCode: CurrencyCode,
        rateDecimal: String,
        effectiveDate: Date,
        source: String
    ) {
        self.sourceCurrencyCode = sourceCurrencyCode
        self.targetCurrencyCode = targetCurrencyCode
        self.rateDecimal = rateDecimal
        self.effectiveDate = effectiveDate
        self.source = source
    }

    public static func isValidRateDecimal(_ value: String) -> Bool {
        guard value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              !value.contains(","),
              !value.hasPrefix("-"),
              !value.hasPrefix("+")
        else {
            return false
        }

        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
        else {
            return false
        }
        return decimal > 0
    }
}

public enum CurrencyConversionPolicy: Codable, Hashable, Sendable {
    case latestAvailable
    case effectiveDate
    case noConversion
}

public protocol ExchangeRateProviding: Sendable {
    func rate(
        from sourceCurrency: CurrencyCode,
        to targetCurrency: CurrencyCode,
        on date: Date
    ) async throws -> ExchangeRate
}

public protocol CurrencyConverting: Sendable {
    func convert(
        _ amount: MoneyAmount,
        to targetCurrency: CurrencyCode,
        on date: Date,
        policy: CurrencyConversionPolicy
    ) async throws -> MoneyAmount
}

public protocol PublicExchangeRateClient: Sendable {
    func fetchRates(baseCurrency: CurrencyCode, date: Date?) async throws -> [ExchangeRate]
}

public struct NoopCurrencyConverter: CurrencyConverting {
    public init() {}

    public func convert(
        _ amount: MoneyAmount,
        to targetCurrency: CurrencyCode,
        on date: Date,
        policy: CurrencyConversionPolicy
    ) async throws -> MoneyAmount {
        guard amount.currencyCode == targetCurrency else {
            throw MoneyError.missingExchangeRate(from: amount.currencyCode, to: targetCurrency)
        }
        return amount
    }
}

public enum MoneyFormatter {
    public static func parseMinorUnits(_ input: String) throws -> Int64 {
        let sanitized = input
            .replacingOccurrences(of: "₴", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sanitized.isEmpty, let decimal = Decimal(string: sanitized) else {
            throw MoneyError.invalidAmount(input)
        }

        var scaled = decimal * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)

        let nsNumber = NSDecimalNumber(decimal: rounded)
        guard nsNumber != NSDecimalNumber.notANumber,
              let result = nsNumber.int64Value as Int64?,
              Decimal(result) == rounded
        else {
            throw MoneyError.invalidAmount(input)
        }
        return result
    }

    public static func string(from minorUnits: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "₴"
        formatter.currencyCode = "UAH"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.locale = Locale(identifier: "uk_UA")
        let value = NSDecimalNumber(value: minorUnits).dividing(by: 100)
        return formatter.string(from: value) ?? "\(minorUnits / 100)"
    }

    public static func plainString(from minorUnits: Int64) -> String {
        let sign = minorUnits < 0 ? "-" : ""
        let absolute = minorUnits == Int64.min ? UInt64(Int64.max) + 1 : UInt64(abs(minorUnits))
        return "\(sign)\(absolute / 100).\(String(format: "%02d", absolute % 100))"
    }
}
