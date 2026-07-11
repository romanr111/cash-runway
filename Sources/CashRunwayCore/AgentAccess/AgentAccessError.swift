import Foundation

// MARK: - Agent Access Error

/// Errors thrown by the agent access service.
///
/// All cases are safe to surface and intentionally avoid embedding private data
/// such as wallet IDs, merchant names, notes, or account identifiers.
public enum AgentAccessError: Error, Equatable, Sendable, Codable {
    case sessionNotFound
    case sessionExpired
    case sessionRevoked
    case missingCapability
    case walletOutOfScope
    case dateRangeOutOfScope
    case invalidScope
    case redactionFailed
    case invalidConsentVersion
}

// MARK: - LocalizedError

extension AgentAccessError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .sessionNotFound:
            return "Agent session is missing or invalid."
        case .sessionExpired:
            return "Agent session has expired."
        case .sessionRevoked:
            return "Agent session has been revoked."
        case .missingCapability:
            return "Agent does not have permission for this operation."
        case .walletOutOfScope:
            return "Requested wallet is outside the agent's approved scope."
        case .dateRangeOutOfScope:
            return "Requested date range is outside the agent's approved scope."
        case .invalidScope:
            return "Agent scope is invalid."
        case .redactionFailed:
            return "Could not produce a safe agent response."
        case .invalidConsentVersion:
            return "Agent consent version is not valid."
        }
    }
}
