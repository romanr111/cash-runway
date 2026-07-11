import Foundation

// MARK: - Wallet Scope

/// Explicit wallet scope. `nil` is never used to mean “all wallets”.
public enum AgentWalletScope: Codable, Hashable, Sendable {
    case allWallets
    case selectedWallets(Set<UUID>)

    public var walletIDs: Set<UUID>? {
        switch self {
        case .allWallets: nil
        case let .selectedWallets(ids): ids
        }
    }

    public func contains(_ walletID: UUID) -> Bool {
        switch self {
        case .allWallets: true
        case let .selectedWallets(ids): ids.contains(walletID)
        }
    }
}

// MARK: - Date Scope

/// Explicit date scope. Agents cannot request an unbounded date range in v1.
public enum AgentDateScope: Codable, Hashable, Sendable {
    case lastDays(Int)
    case closedRange(DateInterval)

    /// Returns the absolute date range represented by this scope.
    /// `lastDays` is evaluated relative to `now`.
    public func dateInterval(now: Date) -> DateInterval {
        switch self {
        case let .lastDays(days):
            let end = now
            let start = Calendar.current.date(byAdding: .day, value: -max(days, 0), to: end) ?? end
            return DateInterval(start: start, end: end)
        case let .closedRange(interval):
            return interval
        }
    }

    /// Whether `date` falls within this scope (evaluated at `now`).
    public func contains(_ date: Date, now: Date) -> Bool {
        dateInterval(now: now).contains(date)
    }
}

// MARK: - Agent Scope

/// The user-approved scope for an agent session.
///
/// Defaults are conservative: bounded date range, bounded transaction count,
/// and all optional PII flags disabled.
public struct AgentScope: Codable, Hashable, Sendable {
    public var walletScope: AgentWalletScope
    public var dateScope: AgentDateScope
    public var maxTransactionCount: Int
    public var includeMerchantNames: Bool
    public var includeNotes: Bool
    public var includeLabels: Bool
    public var includeBankSyncMetadata: Bool

    public init(
        walletScope: AgentWalletScope = .allWallets,
        dateScope: AgentDateScope = .lastDays(30),
        maxTransactionCount: Int = 100,
        includeMerchantNames: Bool = false,
        includeNotes: Bool = false,
        includeLabels: Bool = false,
        includeBankSyncMetadata: Bool = false
    ) {
        self.walletScope = walletScope
        self.dateScope = dateScope
        self.maxTransactionCount = max(1, maxTransactionCount)
        self.includeMerchantNames = includeMerchantNames
        self.includeNotes = includeNotes
        self.includeLabels = includeLabels
        self.includeBankSyncMetadata = includeBankSyncMetadata
    }

    /// Validates that the scope is well-formed and clamps to hard upper bounds.
    public mutating func validate() throws(AgentAccessError) {
        switch dateScope {
        case let .lastDays(days):
            guard days > 0 else {
                throw .invalidScope
            }
            self.dateScope = .lastDays(min(days, AgentScopeLimits.maxLastDays))
        case let .closedRange(interval):
            guard interval.duration > 0, interval.start <= interval.end else {
                throw .invalidScope
            }
            let maxDuration: TimeInterval = Double(AgentScopeLimits.maxLastDays) * 24 * 60 * 60
            guard interval.duration <= maxDuration + 1 else {
                throw .invalidScope
            }
        }
        guard maxTransactionCount > 0 else {
            throw .invalidScope
        }
        self.maxTransactionCount = min(maxTransactionCount, AgentScopeLimits.maxTransactionCount)
    }
}

// MARK: - Scope Limits

/// Hard upper bounds for agent scope dimensions. Centralized so they can be
/// reviewed and audited in one place.
public enum AgentScopeLimits {
    /// Maximum number of transactions returned in a single agent read.
    public static let maxTransactionCount: Int = 100
    /// Maximum lookback for date-based scopes, in days.
    public static let maxLastDays: Int = 365
}
