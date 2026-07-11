import Foundation
import Testing
@testable import CashRunwayCore

// MARK: - Date Provider

/// Mutable clock for deterministic agent access tests.
/// Not concurrency-safe by design: each test gets its own instance and the
/// date provider closure is not shared across isolation boundaries.
final class TestClock: @unchecked Sendable {
    var now: Date

    init(now: Date = Date(timeIntervalSince1970: 1_000_000)) {
        self.now = now
    }

    func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }
}

// MARK: - Fake Dashboard Repository

/// In-memory dashboard repository for agent access tests.
/// `@unchecked Sendable` is safe: all mutable state is guarded by `lock`.
final class FakeDashboardRepository: DashboardRepositorying, @unchecked Sendable {
    private var storedWallets: [Wallet] = []
    private var storedCategories: [CashRunwayCore.Category] = []
    private var storedTransactions: [TransactionListItem] = []
    private var storedOverview: OverviewSnapshot?
    private var storedOverviewByWalletID: [UUID: OverviewSnapshot]?
    private let lock = NSLock()

    init() {}

    func set(wallets: [Wallet]) {
        lock.withLock { storedWallets = wallets }
    }

    func set(categories: [CashRunwayCore.Category]) {
        lock.withLock { storedCategories = categories }
    }

    func set(transactions: [TransactionListItem]) {
        lock.withLock { storedTransactions = transactions }
    }

    func set(overview: OverviewSnapshot?) {
        lock.withLock {
            storedOverview = overview
            storedOverviewByWalletID = nil
        }
    }

    func set(overviewByWalletID: [UUID: OverviewSnapshot]?) {
        lock.withLock {
            storedOverviewByWalletID = overviewByWalletID
            storedOverview = nil
        }
    }

    func wallets() throws -> [Wallet] {
        lock.withLock { storedWallets }
    }

    func walletCategories() throws -> [WalletCategory] {
        []
    }

    func categories(kind: CategoryKind?) throws -> [CashRunwayCore.Category] {
        lock.withLock {
            if let kind {
                return storedCategories.filter { $0.kind == kind }
            }
            return storedCategories
        }
    }

    func labels() throws -> [Label] {
        []
    }

    func budgets(monthKey: Int) throws -> [BudgetProgress] {
        []
    }

    func latestTransactionMonthKey() throws -> Int? {
        nil
    }

    func dashboard(monthKey: Int, walletID: UUID?) throws -> DashboardSnapshot {
        DashboardSnapshot(
            monthKey: monthKey,
            walletFilterID: walletID,
            totalBalanceMinor: 0,
            monthIncomeMinor: 0,
            monthExpenseMinor: 0,
            monthNetMinor: 0,
            wealthHistory: [],
            categories: [],
            recentTransactions: []
        )
    }

    func timelineSnapshot(
        monthKey: Int,
        walletID: UUID?,
        query: TransactionQuery,
        period: TimelinePeriod
    ) throws -> TimelineSnapshot {
        TimelineSnapshot(
            anchorMonthKey: monthKey,
            walletFilterID: walletID,
            heroCashFlowMinor: 0,
            bars: [],
            sections: [],
            period: period
        )
    }

    func allBars(walletID: UUID?, period: TimelinePeriod) throws -> [TimelineBarPoint] {
        []
    }

    func overviewSnapshot(monthKey: Int, walletID: UUID?) throws -> OverviewSnapshot {
        lock.withLock {
            if let byWalletID = storedOverviewByWalletID, let id = walletID {
                return byWalletID[id] ?? OverviewSnapshot(
                    selectedMonthKey: monthKey,
                    walletFilterID: walletID,
                    months: [],
                    totalWealthMinor: 0,
                    monthCashFlowMinor: 0,
                    monthIncomeMinor: 0,
                    monthExpenseMinor: 0,
                    categories: [],
                    labels: []
                )
            }
            return storedOverview ?? OverviewSnapshot(
                selectedMonthKey: monthKey,
                walletFilterID: walletID,
                months: [],
                totalWealthMinor: 0,
                monthCashFlowMinor: 0,
                monthIncomeMinor: 0,
                monthExpenseMinor: 0,
                categories: [],
                labels: []
            )
        }
    }

    func transactions(query: TransactionQuery, limit: Int?) throws -> [TransactionListItem] {
        let targetWalletName: String? = query.walletID.map { walletName(for: $0) }
        return lock.withLock {
            var result = storedTransactions
            if let target = targetWalletName {
                result = result.filter { $0.walletName == target }
            }
            if let start = query.startDate {
                result = result.filter { $0.occurredAt >= start }
            }
            if let end = query.endDate {
                result = result.filter { $0.occurredAt <= end }
            }
            if let limit {
                result = Array(result.prefix(limit))
            }
            if query.offset > 0 {
                result = Array(result.dropFirst(query.offset))
            }
            return result
        }
    }

    private     func walletName(for walletID: UUID) -> String {
        lock.withLock {
            storedWallets.first { $0.id == walletID }?.name ?? ""
        }
    }

    func walletID(for name: String) -> UUID? {
        lock.withLock { storedWallets.first { $0.name == name }?.id }
    }
}

// MARK: - Fake Bank Sync Repository

/// `@unchecked Sendable` is safe: all mutable state is guarded by `lock`.
final class FakeBankSyncRepository: BankSyncRepositorying, @unchecked Sendable {
    private var statusByProvider: [BankProvider: BankConnectionStatusSnapshot] = [:]
    private let lock = NSLock()

    init() {}

    func setStatus(_ status: BankConnectionStatusSnapshot, provider: BankProvider) {
        lock.withLock { statusByProvider[provider] = status }
    }

    func bankConnectionStatus(provider: BankProvider) throws -> BankConnectionStatusSnapshot {
        lock.withLock {
            statusByProvider[provider] ?? BankConnectionStatusSnapshot(
                integration: nil,
                enabledAccountCount: 0,
                syncStartAt: nil,
                lastSuccessfulSyncAt: nil,
                lastSyncError: nil,
                importedExpenseCount: 0
            )
        }
    }

    func bankIntegrations() throws -> [BankIntegration] { [] }
    func activeBankIntegrations() throws -> [BankIntegration] { [] }
    func bankAccounts(integrationID: UUID) throws -> [BankAccount] { [] }
    func enabledBankAccounts(integrationID: UUID) throws -> [BankAccount] { [] }
    func saveBankIntegration(_ integration: BankIntegration) throws {}
    func saveBankAccount(_ account: BankAccount) throws {}
    func saveBankConnection(integration: BankIntegration, accounts: [BankAccount]) throws {}
    func markBankAccountSynced(_ accountID: UUID, at date: Date) throws {}
    func markBankIntegrationSynced(_ integrationID: UUID, at date: Date) throws {}
    func recordBankSyncError(integrationID: UUID, error: String, at date: Date) throws {}
    func disableBankIntegration(_ integrationID: UUID, at date: Date) throws {}
    func importedBankExpenseCount(integrationID: UUID) throws -> Int { 0 }
    func learnBankMerchantCategoryRule(transactionID: UUID, categoryID: UUID) throws {}
    func existingBankImport(provider: BankProvider, providerAccountID: String, statementItemID: String) throws -> BankTransactionImport? { nil }
    func importBankExpense(
        provider: BankProvider,
        integration: BankIntegration,
        account: BankAccount,
        externalItem: BankExternalExpenseItem,
        draft: TransactionDraft
    ) throws {}
    func importMonobankExpenseItems(
        _ items: [MonobankStatementItem],
        account: BankAccount,
        integration: BankIntegration
    ) throws -> BankSyncImportResult {
        BankSyncImportResult(importedCount: 0, skippedCount: 0)
    }
}

// MARK: - Helpers

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

enum AgentTestMocks {}

extension AgentTestMocks {
    static func makeService(
        clock: TestClock,
        dashboard: FakeDashboardRepository = FakeDashboardRepository(),
        bankSync: FakeBankSyncRepository = FakeBankSyncRepository()
    ) -> (AgentAccessService, InMemoryAgentSessionStore, InMemoryAgentAuditLog, FakeDashboardRepository, FakeBankSyncRepository) {
        let sessions = InMemoryAgentSessionStore()
        let audit = InMemoryAgentAuditLog()
        let service = AgentAccessService(
            sessionStore: sessions,
            auditLog: audit,
            dashboardRepository: dashboard,
            bankSyncRepository: bankSync,
            dateProvider: { clock.now }
        )
        return (service, sessions, audit, dashboard, bankSync)
    }

    static func makeSession(
        service: AgentAccessService,
        capabilities: Set<AgentCapability> = [.readOverview],
        scope: AgentScope = .init(),
        ttl: TimeInterval = AgentConsentConstants.maxSessionTTL,
        consentVersion: String = AgentConsentConstants.consentVersion
    ) async throws(AgentAccessError) -> AgentSession {
        let grant = AgentConsentGrant(capabilities: capabilities, scope: scope, requestedTTL: ttl, consentVersion: consentVersion)
        return try await service.createSession(grant)
    }
}
