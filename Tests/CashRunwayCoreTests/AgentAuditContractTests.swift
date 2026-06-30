import Foundation
import Testing
@testable import CashRunwayCore

@Suite("Agent Audit Contract")
struct AgentAuditContractTests {

    @Test func allowedRequestRecordsAuditEntryWithResultCountAndNoRawContents() async throws {
        let clock = TestClock()
        let (service, _, audit, dashboard, _) = AgentTestMocks.makeService(clock: clock)
        let walletID = UUID()
        dashboard.set(wallets: [
            Wallet(
                id: walletID,
                name: "Cash",
                kind: .cash,
                colorHex: nil,
                iconName: nil,
                startingBalanceMinor: 0,
                currentBalanceMinor: 500,
                isArchived: false,
                sortOrder: 0,
                createdAt: clock.now,
                updatedAt: clock.now
            )
        ])
        dashboard.set(overview: OverviewSnapshot(
            selectedMonthKey: 202501,
            walletFilterID: walletID,
            months: [],
            totalWealthMinor: 500,
            monthCashFlowMinor: 0,
            monthIncomeMinor: 0,
            monthExpenseMinor: 0,
            categories: [
                OverviewCategoryRow(
                    id: UUID(),
                    name: "Food",
                    kind: .expense,
                    colorHex: nil,
                    iconName: nil,
                    amountMinor: 100,
                    transactionCount: 1,
                    percentage: 1.0
                )
            ],
            labels: []
        ))
        let session = try await AgentTestMocks.makeSession(
            service: service,
            capabilities: [.readOverview],
            scope: AgentScope(walletScope: .selectedWallets([walletID]))
        )

        let response = try await service.readOverview(sessionID: session.id, request: .init(monthKey: currentMonthKey(clock: clock)))
        #expect(response.totalBalance.amountMinor == 500)
        #expect(response.totalBalance.currencyCode == "UAH")

        let entries = try await audit.entries(forSessionID: session.id)
        #expect(entries.count == 1)
        let entry = entries[0]
        #expect(entry.decision == .allowed)
        #expect(entry.capability == .readOverview)
        #expect(entry.operation == "read:overview")
        #expect(entry.resultCount == 1)
        #expect(!entry.scopeHash.isEmpty)
        #expect(!entry.requestSummary.contains("Food"))
        #expect(!entry.requestSummary.contains("500"))
    }

    private func currentMonthKey(clock: TestClock) -> Int {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: clock.now)
        let month = calendar.component(.month, from: clock.now)
        return year * 100 + month
    }

    @Test func deniedRequestRecordsAuditEntryWithDenialReasonAndNoRawContents() async throws {
        let clock = TestClock()
        let (service, _, audit, dashboard, _) = AgentTestMocks.makeService(clock: clock)
        let allowedWalletID = UUID()
        let blockedWalletID = UUID()
        dashboard.set(wallets: [
            Wallet(
                id: allowedWalletID,
                name: "Allowed",
                kind: .cash,
                colorHex: nil,
                iconName: nil,
                startingBalanceMinor: 0,
                currentBalanceMinor: 0,
                isArchived: false,
                sortOrder: 0,
                createdAt: clock.now,
                updatedAt: clock.now
            ),
            Wallet(
                id: blockedWalletID,
                name: "Blocked",
                kind: .card,
                colorHex: nil,
                iconName: nil,
                startingBalanceMinor: 0,
                currentBalanceMinor: 0,
                isArchived: false,
                sortOrder: 1,
                createdAt: clock.now,
                updatedAt: clock.now
            )
        ])
        let session = try await AgentTestMocks.makeSession(
            service: service,
            capabilities: [.readTransactions],
            scope: AgentScope(walletScope: .selectedWallets([allowedWalletID]))
        )

        do {
            _ = try await service.readTransactions(
                sessionID: session.id,
                request: AgentTransactionsRequest(walletIDs: [blockedWalletID])
            )
            Issue.record("Expected walletOutOfScope error")
        } catch let error as AgentAccessError {
            #expect(error == .walletOutOfScope)
        }

        let entries = try await audit.entries(forSessionID: session.id)
        #expect(entries.count == 1)
        let entry = entries[0]
        #expect(entry.decision == .denied)
        #expect(entry.denialReason == .walletOutOfScope)
        #expect(entry.capability == .readTransactions)
        #expect(entry.operation == "read:transactions")
        #expect(entry.resultCount == nil)
        #expect(!entry.requestSummary.contains("Blocked"))
    }

    @Test func auditEntryExcludesSensitiveFields() async throws {
        let clock = TestClock()
        let (service, _, audit, dashboard, _) = AgentTestMocks.makeService(clock: clock)
        let walletID = UUID()
        dashboard.set(wallets: [
            Wallet(
                id: walletID,
                name: "Card",
                kind: .card,
                colorHex: nil,
                iconName: nil,
                startingBalanceMinor: 0,
                currentBalanceMinor: 0,
                isArchived: false,
                sortOrder: 0,
                createdAt: clock.now,
                updatedAt: clock.now
            )
        ])
        let session = try await AgentTestMocks.makeSession(
            service: service,
            capabilities: [.readTransactions],
            scope: AgentScope(
                walletScope: .selectedWallets([walletID]),
                includeMerchantNames: true,
                includeNotes: true
            )
        )
        dashboard.set(transactions: [
            TransactionListItem(
                id: UUID(),
                walletName: "Card",
                amountMinor: 100,
                occurredAt: clock.now,
                categoryName: nil,
                categoryColorHex: nil,
                categoryIconName: nil,
                merchant: "Coffee",
                note: "Morning latte",
                kind: .expense,
                source: .manual,
                labels: [],
                dayKey: 0
            )
        ])

        _ = try await service.readTransactions(sessionID: session.id, request: .init())

        let entries = try await audit.entries(forSessionID: session.id)
        #expect(entries.count == 1)
        let entry = entries[0]
        let encoder = JSONEncoder()
        let data = try encoder.encode(entry)
        let json = String(data: data, encoding: .utf8)!.lowercased()

        #expect(!json.contains("coffee"))
        #expect(!json.contains("latte"))
        #expect(!json.contains("raw_json"))
        #expect(!json.contains("counter_iban"))
        #expect(!json.contains("receipt_id"))
        #expect(!json.contains("masked_pan"))
        #expect(!json.contains("keychain"))
        #expect(!json.contains("file://"))
    }
}
