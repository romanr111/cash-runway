import Foundation
import Testing
@testable import CashRunwayCore

@Suite("Agent Permission Boundaries")
struct AgentPermissionBoundaryTests {

    // MARK: - Session lifecycle failures

    @Test func missingSessionIsDeniedAndAudited() async throws {
        let clock = TestClock()
        let (service, _, audit, _, _) = AgentTestMocks.makeService(clock: clock)
        let missingSessionID = UUID()

        await #expect(throws: AgentAccessError.sessionNotFound) {
            try await service.readWallets(sessionID: missingSessionID)
        }

        let entries = try await audit.allEntries()
        #expect(entries.count == 1)
        let entry = entries[0]
        #expect(entry.sessionID == missingSessionID)
        #expect(entry.decision == .denied)
        #expect(entry.denialReason == .sessionNotFound)
        #expect(entry.capability == .readWallets)
        #expect(entry.operation == "read:wallets")
    }

    @Test func expiredSessionIsDeniedAndAudited() async throws {
        let clock = TestClock()
        let (service, sessions, audit, _, _) = AgentTestMocks.makeService(clock: clock)
        let session = try await AgentTestMocks.makeSession(
            service: service,
            capabilities: [.readWallets],
            ttl: 60
        )

        clock.advance(by: 61)

        await #expect(throws: AgentAccessError.sessionExpired) {
            try await service.readWallets(sessionID: session.id)
        }

        let entries = try await audit.entries(forSessionID: session.id)
        #expect(entries.count == 1)
        #expect(entries[0].decision == .denied)
        #expect(entries[0].denialReason == .sessionExpired)
    }

    @Test func revokedSessionIsDeniedAndAudited() async throws {
        let clock = TestClock()
        let (service, sessions, audit, _, _) = AgentTestMocks.makeService(clock: clock)
        let session = try await AgentTestMocks.makeSession(
            service: service,
            capabilities: [.readWallets]
        )
        try await service.revokeSession(id: session.id)

        await #expect(throws: AgentAccessError.sessionRevoked) {
            try await service.readWallets(sessionID: session.id)
        }

        let entries = try await audit.entries(forSessionID: session.id)
        #expect(entries.count == 1)
        #expect(entries[0].decision == .denied)
        #expect(entries[0].denialReason == .sessionRevoked)
    }

    // MARK: - Capability failures

    @Test func missingCapabilityIsDeniedAndAudited() async throws {
        let clock = TestClock()
        let (service, _, audit, _, _) = AgentTestMocks.makeService(clock: clock)
        let session = try await AgentTestMocks.makeSession(
            service: service,
            capabilities: [.readWallets]
        )

        await #expect(throws: AgentAccessError.missingCapability) {
            try await service.readTransactions(sessionID: session.id, request: .init())
        }

        let entries = try await audit.entries(forSessionID: session.id)
        #expect(entries.count == 1)
        #expect(entries[0].decision == .denied)
        #expect(entries[0].denialReason == .missingCapability)
        #expect(entries[0].capability == .readTransactions)
    }

    // MARK: - Scope failures

    @Test func outOfScopeWalletIsDeniedAndAudited() async throws {
        let clock = TestClock()
        let (service, _, audit, dashboard, _) = AgentTestMocks.makeService(clock: clock)
        let allowedWalletID = UUID()
        let blockedWalletID = UUID()
        dashboard.set(wallets: [
            Wallet(id: allowedWalletID, name: "Allowed", kind: .cash, colorHex: nil, iconName: nil, startingBalanceMinor: 0, currentBalanceMinor: 100, isArchived: false, sortOrder: 0, createdAt: .now, updatedAt: .now),
            Wallet(id: blockedWalletID, name: "Blocked", kind: .card, colorHex: nil, iconName: nil, startingBalanceMinor: 0, currentBalanceMinor: 200, isArchived: false, sortOrder: 1, createdAt: .now, updatedAt: .now)
        ])
        let session = try await AgentTestMocks.makeSession(
            service: service,
            capabilities: [.readTransactions],
            scope: AgentScope(walletScope: .selectedWallets([allowedWalletID]))
        )

        await #expect(throws: AgentAccessError.walletOutOfScope) {
            try await service.readTransactions(
                sessionID: session.id,
                request: AgentTransactionsRequest(walletIDs: [blockedWalletID])
            )
        }

        let entries = try await audit.entries(forSessionID: session.id)
        #expect(entries.count == 1)
        #expect(entries[0].decision == .denied)
        #expect(entries[0].denialReason == .walletOutOfScope)
    }

    @Test func outOfScopeDateRangeIsDeniedAndAudited() async throws {
        let clock = TestClock()
        let (service, _, audit, dashboard, _) = AgentTestMocks.makeService(clock: clock)
        let walletID = UUID()
        dashboard.set(wallets: [
            Wallet(id: walletID, name: "Cash", kind: .cash, colorHex: nil, iconName: nil, startingBalanceMinor: 0, currentBalanceMinor: 0, isArchived: false, sortOrder: 0, createdAt: .now, updatedAt: .now)
        ])
        let session = try await AgentTestMocks.makeSession(
            service: service,
            capabilities: [.readTransactions],
            scope: AgentScope(dateScope: .lastDays(7))
        )
        let farPast = clock.now.addingTimeInterval(-86400 * 30)

        await #expect(throws: AgentAccessError.dateRangeOutOfScope) {
            try await service.readTransactions(
                sessionID: session.id,
                request: AgentTransactionsRequest(startDate: farPast)
            )
        }

        let entries = try await audit.entries(forSessionID: session.id)
        #expect(entries.count == 1)
        #expect(entries[0].decision == .denied)
        #expect(entries[0].denialReason == .dateRangeOutOfScope)
    }

    // MARK: - Count clamping

    @Test func transactionResultCountIsClampedAndAudited() async throws {
        let clock = TestClock()
        let (service, _, audit, dashboard, _) = AgentTestMocks.makeService(clock: clock)
        let walletID = UUID()
        dashboard.set(wallets: [
            Wallet(id: walletID, name: "Cash", kind: .cash, colorHex: nil, iconName: nil, startingBalanceMinor: 0, currentBalanceMinor: 0, isArchived: false, sortOrder: 0, createdAt: .now, updatedAt: .now)
        ])
        let transactions = (1...10).map { index in
            TransactionListItem(
                id: UUID(),
                walletName: "Cash",
                amountMinor: Int64(index * 100),
                occurredAt: clock.now,
                categoryName: nil,
                categoryColorHex: nil,
                categoryIconName: nil,
                merchant: "Merchant \(index)",
                note: "",
                kind: .expense,
                source: .manual,
                labels: [],
                dayKey: 0
            )
        }
        dashboard.set(transactions: transactions)
        let session = try await AgentTestMocks.makeSession(
            service: service,
            capabilities: [.readTransactions],
            scope: AgentScope(maxTransactionCount: 3, includeMerchantNames: true)
        )

        let response = try await service.readTransactions(sessionID: session.id, request: .init())
        #expect(response.transactions.count == 3)
        #expect(response.returnedCount == 3)
        #expect(response.truncatedToMax == true)
        #expect(response.transactions.allSatisfy { $0.amount.currencyCode == "UAH" })

        let entries = try await audit.entries(forSessionID: session.id)
        #expect(entries.count == 1)
        #expect(entries[0].decision == .allowed)
        #expect(entries[0].resultCount == 3)
    }

    @Test func moneyResponsesPreserveSourceCurrencyCodes() async throws {
        let clock = TestClock()
        let (service, _, _, dashboard, _) = AgentTestMocks.makeService(clock: clock)
        let walletID = UUID()
        dashboard.set(wallets: [
            Wallet(
                id: walletID,
                name: "USD Card",
                kind: .card,
                colorHex: nil,
                iconName: nil,
                startingBalanceMinor: 0,
                currentBalanceMinor: 12_345,
                currencyCode: .usd,
                isArchived: false,
                sortOrder: 0,
                createdAt: clock.now,
                updatedAt: clock.now
            )
        ])
        dashboard.set(transactions: [
            TransactionListItem(
                id: UUID(),
                walletName: "USD Card",
                amountMinor: 1_234,
                currencyCode: .usd,
                occurredAt: clock.now,
                categoryName: nil,
                categoryColorHex: nil,
                categoryIconName: nil,
                merchant: "Store",
                note: "",
                kind: .expense,
                source: .manual,
                labels: [],
                dayKey: 0
            )
        ])
        let session = try await AgentTestMocks.makeSession(
            service: service,
            capabilities: [.readWallets, .readTransactions],
            scope: AgentScope(walletScope: .selectedWallets([walletID]), includeMerchantNames: true)
        )

        let wallets = try await service.readWallets(sessionID: session.id)
        let transactions = try await service.readTransactions(sessionID: session.id, request: .init())

        #expect(wallets.wallets.first?.currentBalance.currencyCode == "USD")
        #expect(transactions.transactions.first?.amount.currencyCode == "USD")
    }
}
