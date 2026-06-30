import Foundation

// MARK: - Agent Capability

/// Read-only v1 capabilities for consent-gated agent access.
///
/// No write, import, backup, token, database, or file-system capabilities are
/// exposed in this version. Capabilities are deliberately explicit so that a
/// missing capability always fails closed.
public enum AgentCapability: String, CaseIterable, Codable, Hashable, Sendable {
    case readOverview
    case readWallets
    case readCategories
    case readTransactions
    case readRecurring
    case readBankConnectionStatus
}

// MARK: - Capability Requirements

extension AgentCapability {
    /// The concrete operation label used for audit logging.
    public var auditOperation: String {
        switch self {
        case .readOverview: "read:overview"
        case .readWallets: "read:wallets"
        case .readCategories: "read:categories"
        case .readTransactions: "read:transactions"
        case .readRecurring: "read:recurring"
        case .readBankConnectionStatus: "read:bankConnectionStatus"
        }
    }
}
