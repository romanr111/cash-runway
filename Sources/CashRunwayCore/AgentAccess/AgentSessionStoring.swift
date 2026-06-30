import Foundation

// MARK: - Session Store Contract

/// Storage contract for agent sessions.
///
/// Phase 5.0 uses in-memory/fake implementations for tests only. A DB-backed
/// store will be introduced in Phase 5.1.
public protocol AgentSessionStoring: Sendable {
    func save(_ session: AgentSession) async throws
    func session(id: UUID) async throws -> AgentSession?
    func activeSessions(now: Date) async throws -> [AgentSession]
    func revoke(id: UUID, at date: Date) async throws
}

// MARK: - In-Memory Fake (Phase 5.0 tests only)

/// In-memory session store intended for tests only. Uses a lock so it is
/// concurrency-safe without actor hops.
///
public final class InMemoryAgentSessionStore: AgentSessionStoring, @unchecked Sendable {
    // `@unchecked Sendable` is justified: all mutable state is guarded by `lock`.
    private var sessions: [UUID: AgentSession] = [:]
    private let lock = NSLock()

    public init() {}

    public func save(_ session: AgentSession) async throws {
        lock.withLock { sessions[session.id] = session }
    }

    public func session(id: UUID) async throws -> AgentSession? {
        lock.withLock { sessions[id] }
    }

    public func activeSessions(now: Date) async throws -> [AgentSession] {
        lock.withLock { sessions.values.filter { $0.isValid(now: now) } }
    }

    public func revoke(id: UUID, at date: Date) async throws {
        lock.withLock {
            guard var session = sessions[id] else { return }
            session.revokedAt = date
            sessions[id] = session
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
