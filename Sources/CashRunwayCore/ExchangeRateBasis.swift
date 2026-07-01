import Foundation

public enum ExchangeRateBasis: String, Codable, Hashable, Sendable {
    case identity
    case official
    case bankBuy
    case bankSell
    case bankMidpoint
    case bankCompositeMidpoint
    case interbankBid
    case interbankAsk
    case exchangeOfficeAverage
    case cardNetwork
}

public struct MarketRatePolicy: Codable, Hashable, Sendable {
    public var preferredBasis: ExchangeRateBasis
    public var allowFallbackToOfficial: Bool
    public var maxStaleness: TimeInterval

    public init(
        preferredBasis: ExchangeRateBasis = .bankCompositeMidpoint,
        allowFallbackToOfficial: Bool = true,
        maxStaleness: TimeInterval = 6 * 60 * 60
    ) {
        self.preferredBasis = preferredBasis
        self.allowFallbackToOfficial = allowFallbackToOfficial
        self.maxStaleness = maxStaleness
    }
}

public struct WalletValueProjection: Sendable {
    public var nativeAmount: MoneyAmount
    public var projectedAmount: MoneyAmount
    public var rate: ExchangeRate?
    public var basis: ExchangeRateBasis
    public var providerLabel: String
    public var isFallback: Bool
    public var isApproximate: Bool

    public init(
        nativeAmount: MoneyAmount,
        projectedAmount: MoneyAmount,
        rate: ExchangeRate?,
        basis: ExchangeRateBasis,
        providerLabel: String,
        isFallback: Bool,
        isApproximate: Bool
    ) {
        self.nativeAmount = nativeAmount
        self.projectedAmount = projectedAmount
        self.rate = rate
        self.basis = basis
        self.providerLabel = providerLabel
        self.isFallback = isFallback
        self.isApproximate = isApproximate
    }
}

public enum WalletValueProjectionProvider {
    public static let publicBankCompositeLabel = "Public bank midpoint"
    public static let monobankLabel = "Monobank midpoint"
    public static let privatBankLabel = "PrivatBank midpoint"
    public static let nbuFallbackLabel = "NBU official fallback"
    public static let nativeCurrencyLabel = "Native currency"
}

public extension ExchangeRate {
    /// Centralized mapping from a rate's `source` string to its `ExchangeRateBasis`.
    /// This is the single source of truth so callers do not pattern-match on
    /// provider-specific source strings (`monobank-midpoint`, `nbu-official`, …).
    var basis: ExchangeRateBasis {
        switch source {
        case "identity":
            return .identity
        case "nbu-official":
            return .official
        case "monobank-midpoint", "privatbank-midpoint":
            return .bankMidpoint
        case "bank_public_composite":
            return .bankCompositeMidpoint
        default:
            return .bankMidpoint
        }
    }
}
