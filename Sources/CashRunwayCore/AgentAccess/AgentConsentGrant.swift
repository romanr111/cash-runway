import Foundation

// MARK: - Consent Constants

public enum AgentConsentConstants {
    /// Maximum session lifetime in v1. Short by design: agent access must be
    /// re-approved frequently and cannot become a background/permanent channel.
    public static let maxSessionTTL: TimeInterval = 15 * 60

    /// Consent version string. Bumped whenever the scope/capability model changes
    /// materially so that old grants cannot be silently reinterpreted.
    public static let consentVersion: String = "v1.0"
}

// MARK: - Consent Grant

/// User-approved input for creating an agent session.
///
/// The service clamps `requestedTTL` to `maxSessionTTL` and validates the scope.
public struct AgentConsentGrant: Codable, Hashable, Sendable {
    public var capabilities: Set<AgentCapability>
    public var scope: AgentScope
    public var requestedTTL: TimeInterval
    public var consentVersion: String

    public init(
        capabilities: Set<AgentCapability>,
        scope: AgentScope = .init(),
        requestedTTL: TimeInterval = AgentConsentConstants.maxSessionTTL,
        consentVersion: String = AgentConsentConstants.consentVersion
    ) {
        self.capabilities = capabilities
        self.scope = scope
        self.requestedTTL = min(max(requestedTTL, 0), AgentConsentConstants.maxSessionTTL)
        self.consentVersion = consentVersion
    }

    /// Clamp TTL and validate scope.
    public func validated() throws(AgentAccessError) -> AgentConsentGrant {
        guard !capabilities.isEmpty else {
            throw .missingCapability
        }
        try scope.validate()
        var copy = self
        copy.requestedTTL = min(requestedTTL, AgentConsentConstants.maxSessionTTL)
        return copy
    }
}
