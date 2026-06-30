import Foundation

public enum SupportedCurrency: String, CaseIterable, Codable, Sendable {
    case uah = "UAH"
    case usd = "USD"
    case eur = "EUR"

    public var currencyCode: CurrencyCode { CurrencyCode(rawValue: rawValue)! }

    public var displayName: String {
        switch self {
        case .uah: "Ukrainian Hryvnia"
        case .usd: "US Dollar"
        case .eur: "Euro"
        }
    }

    public var symbol: String {
        switch self {
        case .uah: "₴"
        case .usd: "$"
        case .eur: "€"
        }
    }
}
