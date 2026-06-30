import Foundation

// MARK: - Audit Entry

/// A single audit record for an agent access decision.
///
/// Audit entries intentionally exclude raw prompts, full transaction data,
/// merchant lists, notes, raw JSON, SQL, file paths, tokens, and keychain
/// account names. Only capability, operation, decision, reason, scope hash,
/// a short request summary, and a result count are stored.
public struct AgentAuditEntry: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var sessionID: UUID?
    public var capability: AgentCapability
    public var operation: String
    public var decision: AgentAuditDecision
    public var denialReason: AgentAccessError?
    public var scopeHash: String
    public var requestSummary: String
    public var resultCount: Int?
    public var createdAt: Date

    public init(
        id: UUID,
        sessionID: UUID?,
        capability: AgentCapability,
        operation: String,
        decision: AgentAuditDecision,
        denialReason: AgentAccessError? = nil,
        scopeHash: String,
        requestSummary: String,
        resultCount: Int? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.sessionID = sessionID
        self.capability = capability
        self.operation = operation
        self.decision = decision
        self.denialReason = denialReason
        self.scopeHash = scopeHash
        self.requestSummary = requestSummary
        self.resultCount = resultCount
        self.createdAt = createdAt
    }
}

public enum AgentAuditDecision: String, Codable, Hashable, Sendable {
    case allowed
    case denied
}

// MARK: - Audit Logging Contract

/// Audit logging contract for agent access decisions.
///
/// Phase 5.0 uses in-memory/fake implementations for tests only. A DB-backed
/// append-only table will be introduced in Phase 5.1.
public protocol AgentAuditLogging: Sendable {
    func append(_ entry: AgentAuditEntry) async throws
    func entries(forSessionID sessionID: UUID) async throws -> [AgentAuditEntry]
    func allEntries() async throws -> [AgentAuditEntry]
}

// MARK: - In-Memory Fake (Phase 5.0 tests only)

/// In-memory audit log intended for tests only. Uses a lock so it is
/// concurrency-safe without actor hops.
///
public final class InMemoryAgentAuditLog: AgentAuditLogging, @unchecked Sendable {
    // `@unchecked Sendable` is justified: all mutable state is guarded by `lock`.
    private var entries: [AgentAuditEntry] = []
    private let lock = NSLock()

    public init() {}

    public func append(_ entry: AgentAuditEntry) async throws {
        lock.withLock { entries.append(entry) }
    }

    public func entries(forSessionID sessionID: UUID) async throws -> [AgentAuditEntry] {
        lock.withLock { entries.filter { $0.sessionID == sessionID } }
    }

    public func allEntries() async throws -> [AgentAuditEntry] {
        lock.withLock { Array(entries) }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
