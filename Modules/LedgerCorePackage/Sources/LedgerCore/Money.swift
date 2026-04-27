import Foundation

public enum MoneyError: Error, LocalizedError, Equatable {
    case invalidAmount(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidAmount(value):
            "Invalid amount: \(value)"
        }
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

        guard let result = NSDecimalNumber(decimal: rounded).int64Value as Int64? else {
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
        let absolute = abs(minorUnits)
        return "\(sign)\(absolute / 100).\(String(format: "%02d", absolute % 100))"
    }
}

