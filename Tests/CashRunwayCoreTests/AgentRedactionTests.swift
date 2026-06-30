import Foundation
import Testing
@testable import CashRunwayCore

@Suite("Agent Redaction")
struct AgentRedactionTests {

    private func makeServiceWithOneWalletAndTransaction(
        clock: TestClock,
        merchant: String = "",
        note: String = "",
        labels: [Label] = []
    ) async throws -> (AgentAccessService, InMemoryAgentAuditLog, AgentSession) {
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
                currentBalanceMinor: 0,
                isArchived: false,
                sortOrder: 0,
                createdAt: clock.now,
                updatedAt: clock.now
            )
        ])
        dashboard.set(transactions: [
            TransactionListItem(
                id: UUID(),
                walletName: "Cash",
                amountMinor: 100,
                occurredAt: clock.now,
                categoryName: "Food",
                categoryColorHex: nil,
                categoryIconName: nil,
                merchant: merchant,
                note: note,
                kind: .expense,
                source: .manual,
                labels: labels,
                dayKey: 0
            )
        ])
        let session = try await AgentTestMocks.makeSession(
            service: service,
            capabilities: [.readTransactions],
            scope: AgentScope(
                walletScope: .selectedWallets([walletID]),
                maxTransactionCount: 10,
                includeMerchantNames: true,
                includeNotes: true,
                includeLabels: true
            )
        )
        return (service, audit, session)
    }

    @Test func merchantPreviewOmittedUnlessIncluded() async throws {
        let clock = TestClock()
        let (service, _, _) = try await makeServiceWithOneWalletAndTransaction(
            clock: clock,
            merchant: "Store"
        )
        let deniedSession = try await AgentTestMocks.makeSession(
            service: service,
            capabilities: [.readTransactions],
            scope: AgentScope(
                walletScope: .allWallets,
                includeMerchantNames: false,
                includeNotes: false,
                includeLabels: false
            )
        )

        let response = try await service.readTransactions(
            sessionID: deniedSession.id,
            request: .init()
        )
        #expect(response.transactions.first?.merchantPreview == nil)
    }

    @Test func notesOmittedUnlessIncluded() async throws {
        let clock = TestClock()
        let (service, _, _) = try await makeServiceWithOneWalletAndTransaction(
            clock: clock,
            note: "Note text"
        )
        let deniedSession = try await AgentTestMocks.makeSession(
            service: service,
            capabilities: [.readTransactions],
            scope: AgentScope(
                walletScope: .allWallets,
                includeMerchantNames: false,
                includeNotes: false,
                includeLabels: false
            )
        )

        let response = try await service.readTransactions(
            sessionID: deniedSession.id,
            request: .init()
        )
        #expect(response.transactions.first?.notePreview == nil)
    }

    @Test func labelsOmittedUnlessIncluded() async throws {
        let clock = TestClock()
        let (service, _, _) = try await makeServiceWithOneWalletAndTransaction(
            clock: clock,
            labels: [Label(id: UUID(), name: "Trip", colorHex: nil, createdAt: clock.now, updatedAt: clock.now)]
        )
        let deniedSession = try await AgentTestMocks.makeSession(
            service: service,
            capabilities: [.readTransactions],
            scope: AgentScope(
                walletScope: .allWallets,
                includeMerchantNames: false,
                includeNotes: false,
                includeLabels: false
            )
        )

        let response = try await service.readTransactions(
            sessionID: deniedSession.id,
            request: .init()
        )
        #expect(response.transactions.first?.labels.isEmpty == true)
    }

    @Test func bankSyncMetadataOmittedUnlessIncluded() async throws {
        let clock = TestClock()
        let (service, _, _, _, bankSync) = AgentTestMocks.makeService(clock: clock)
        bankSync.setStatus(
            BankConnectionStatusSnapshot(
                integration: nil,
                enabledAccountCount: 1,
                syncStartAt: nil,
                lastSuccessfulSyncAt: nil,
                lastSyncError: nil,
                importedExpenseCount: 0
            ),
            provider: BankProvider.monobank
        )
        let session = try await AgentTestMocks.makeSession(
            service: service,
            capabilities: [.readBankConnectionStatus],
            scope: AgentScope(includeBankSyncMetadata: false)
        )

        await #expect(throws: AgentAccessError.missingCapability) {
            try await service.readBankConnectionStatus(sessionID: session.id, provider: BankProvider.monobank)
        }
    }

    @Test func noteAndMerchantRedactionRemovesIBANCardAccountStrings() async throws {
        let clock = TestClock()
        let merchant = "Payment to UA12345678901234567890123456 from 4111111111111111"
        let note = "Account 12345678"
        let (service, _, session) = try await makeServiceWithOneWalletAndTransaction(
            clock: clock,
            merchant: merchant,
            note: note
        )

        let response = try await service.readTransactions(sessionID: session.id, request: .init())
        let tx = response.transactions.first!
        #expect(tx.merchantPreview?.contains("[REDACTED_IBAN]") == true)
        #expect(tx.merchantPreview?.contains("[REDACTED_CARD]") == true)
        #expect(tx.notePreview?.contains("[REDACTED_ACCOUNT]") == true)
    }

    @Test func encodedDTOFailsRedactionWhenForbiddenLiteralAppears() async throws {
        let clock = TestClock()
        let (service, _, session) = try await makeServiceWithOneWalletAndTransaction(
            clock: clock,
            merchant: "raw_json"
        )

        do {
            _ = try await service.readTransactions(sessionID: session.id, request: .init())
            Issue.record("Expected redactionFailed error")
        } catch let error as AgentAccessError {
            #expect(error == .redactionFailed)
        }
    }

    @Test func encodedDTONeverContainsRawBankOrSecurityFields() async throws {
        let clock = TestClock()
        let (service, _, session) = try await makeServiceWithOneWalletAndTransaction(
            clock: clock,
            merchant: "Coffee",
            note: "Morning"
        )

        let response = try await service.readTransactions(sessionID: session.id, request: .init())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(response)
        let json = String(data: data, encoding: .utf8)!.lowercased()

        #expect(!json.contains("raw_json"))
        #expect(!json.contains("counter_iban"))
        #expect(!json.contains("receipt_id"))
        #expect(!json.contains("masked_pan"))
        #expect(!json.contains("keychain"))
        #expect(!json.contains("file://"))
        #expect(!json.contains(".sqlite"))
        #expect(!json.contains("recovery_key"))
    }

    @Test func happyPathTransactionResponseHasOpaqueHandle() async throws {
        let clock = TestClock()
        let (service, _, session) = try await makeServiceWithOneWalletAndTransaction(
            clock: clock,
            merchant: "Coffee",
            note: "Morning"
        )

        let response = try await service.readTransactions(sessionID: session.id, request: .init())
        let tx = response.transactions.first!
        #expect(tx.handle.hasPrefix("tx_"))
        #expect(tx.merchantPreview == "Coffee")
        #expect(tx.notePreview == "Morning")
    }
}
