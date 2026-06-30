import Foundation

// MARK: - Agent Session

/// A consent-gated agent session.
///
/// Sessions are short-lived, revocable, and fail closed when missing, expired,
/// or revoked. There is no background or permanent always-on access in v1.
public struct AgentSession: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var expiresAt: Date
    public var revokedAt: Date?
    public var capabilities: Set<AgentCapability>
    public var scope: AgentScope
    public var consentVersion: String

    public init(
        id: UUID,
        createdAt: Date,
        expiresAt: Date,
        revokedAt: Date? = nil,
        capabilities: Set<AgentCapability>,
        scope: AgentScope,
        consentVersion: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.revokedAt = revokedAt
        self.capabilities = capabilities
        self.scope = scope
        self.consentVersion = consentVersion
    }

    /// Whether the session is usable as of `now`.
    public func isValid(now: Date) -> Bool {
        !isExpired(now: now) && !isRevoked(now: now)
    }

    public func isExpired(now: Date) -> Bool {
        now >= expiresAt
    }

    public func isRevoked(now: Date) -> Bool {
        guard let revokedAt else { return false }
        return now >= revokedAt
    }

    /// Validates a requested capability against this session.
    public func requireCapability(_ capability: AgentCapability, now: Date) throws(AgentAccessError) {
        guard isValid(now: now) else {
            if isRevoked(now: now) {
                throw .sessionRevoked
            }
            if isExpired(now: now) {
                throw .sessionExpired
            }
            throw .sessionNotFound
        }
        guard capabilities.contains(capability) else {
            throw .missingCapability
        }
    }
}
