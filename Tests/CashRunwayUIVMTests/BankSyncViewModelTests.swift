@testable import CashRunwayCore
@testable import CashRunwayUIVM
import Foundation
import Testing

@Suite("BankSyncViewModel")
@MainActor
struct BankSyncViewModelTests {
    @Test("validateToken advances to accounts step on success")
    func validateTokenSuccess() async throws {
        let repository = FakeBankSyncRepository()
        let performer = FakeBankSyncPerformer()
        let connectionService = FakeMonobankConnectionService()
        connectionService.clientInfo = MonobankClientInfo(
            name: "Test",
            accounts: [MonobankAccount(
                id: "acc-1",
                type: "black",
                currencyCode: 980,
                maskedPan: ["1234"],
                iban: nil
            )]
        )
        let viewModel = BankSyncViewModel(
            repository: repository,
            syncPerformer: performer,
            connectionService: connectionService,
            walletsProvider: { [] }
        )
        viewModel.token = "valid-token"

        viewModel.validateToken()
        try await waitFor { viewModel.step == .accounts }

        #expect(viewModel.clientInfo?.accounts.count == 1)
        #expect(viewModel.validationError == nil)
    }

    @Test("validateToken surfaces error on failure")
    func validateTokenFailure() async throws {
        let repository = FakeBankSyncRepository()
        let performer = FakeBankSyncPerformer()
        let connectionService = FakeMonobankConnectionService()
        connectionService.validateShouldFail = true
        let viewModel = BankSyncViewModel(
            repository: repository,
            syncPerformer: performer,
            connectionService: connectionService,
            walletsProvider: { [] }
        )
        viewModel.token = "invalid-token"

        viewModel.validateToken()
        try await waitFor { viewModel.validationError != nil }

        #expect(viewModel.step == .intro)
        #expect(viewModel.validationError != nil)
    }

    @Test("syncNow clears syncing flag and calls onSuccess")
    func syncNowSuccess() async throws {
        let repository = FakeBankSyncRepository()
        let performer = FakeBankSyncPerformer()
        let connectionService = FakeMonobankConnectionService()
        let viewModel = BankSyncViewModel(
            repository: repository,
            syncPerformer: performer,
            connectionService: connectionService,
            walletsProvider: { [] }
        )

        var successCalled = false
        viewModel.onSuccess = { successCalled = true }

        await viewModel.syncNow()

        #expect(viewModel.isSyncing == false)
        #expect(successCalled)
    }

    @Test("syncNow calls onFailure when sync fails")
    func syncNowFailure() async throws {
        let repository = FakeBankSyncRepository()
        let performer = FakeBankSyncPerformer()
        performer.shouldFail = true
        let connectionService = FakeMonobankConnectionService()
        let viewModel = BankSyncViewModel(
            repository: repository,
            syncPerformer: performer,
            connectionService: connectionService,
            walletsProvider: { [] }
        )

        var failureCalled = false
        viewModel.onFailure = { _ in failureCalled = true }

        await viewModel.syncNow()

        #expect(failureCalled)
    }

    @Test("disconnect clears completed status and calls onSuccess")
    func disconnect() async throws {
        let repository = FakeBankSyncRepository()
        let integration = BankIntegration(
            id: UUID(),
            provider: .monobank,
            displayName: "Monobank",
            status: .active,
            syncStartAt: Date(),
            tokenKeychainAccount: "token",
            lastClientInfoSyncAt: nil,
            lastSuccessfulSyncAt: nil,
            lastSyncError: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        repository.status = BankConnectionStatusSnapshot(
            integration: integration,
            enabledAccountCount: 1,
            syncStartAt: Date(),
            lastSuccessfulSyncAt: Date(),
            lastSyncError: nil,
            importedExpenseCount: 0
        )
        let performer = FakeBankSyncPerformer()
        let connectionService = FakeMonobankConnectionService()
        let viewModel = BankSyncViewModel(
            repository: repository,
            syncPerformer: performer,
            connectionService: connectionService,
            walletsProvider: { [] }
        )
        viewModel.completedStatus = BankConnectionStatusSnapshot(
            integration: integration,
            enabledAccountCount: 1,
            syncStartAt: Date(),
            lastSuccessfulSyncAt: Date(),
            lastSyncError: nil,
            importedExpenseCount: 0
        )

        var successCalled = false
        viewModel.onSuccess = { successCalled = true }

        await viewModel.disconnect()

        #expect(viewModel.completedStatus == nil)
        #expect(successCalled)
    }

    @Test("disconnect does not clear completed status when disconnect fails")
    func disconnectFailure() async throws {
        let repository = FakeBankSyncRepository()
        let integration = BankIntegration(
            id: UUID(),
            provider: .monobank,
            displayName: "Monobank",
            status: .active,
            syncStartAt: Date(),
            tokenKeychainAccount: "token",
            lastClientInfoSyncAt: nil,
            lastSuccessfulSyncAt: nil,
            lastSyncError: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        repository.status = BankConnectionStatusSnapshot(
            integration: integration,
            enabledAccountCount: 1,
            syncStartAt: Date(),
            lastSuccessfulSyncAt: Date(),
            lastSyncError: nil,
            importedExpenseCount: 0
        )
        let performer = FakeBankSyncPerformer()
        let connectionService = FakeMonobankConnectionService()
        connectionService.disconnectShouldFail = true
        let viewModel = BankSyncViewModel(
            repository: repository,
            syncPerformer: performer,
            connectionService: connectionService,
            walletsProvider: { [] }
        )
        viewModel.completedStatus = BankConnectionStatusSnapshot(
            integration: integration,
            enabledAccountCount: 1,
            syncStartAt: Date(),
            lastSuccessfulSyncAt: Date(),
            lastSyncError: nil,
            importedExpenseCount: 0
        )

        var failureCalled = false
        viewModel.onFailure = { _ in failureCalled = true }

        await viewModel.disconnect()

        #expect(viewModel.completedStatus != nil)
        #expect(failureCalled)
    }

    @Test("startSyncing calls onSuccess after connecting")
    func startSyncingSuccess() async throws {
        let repository = FakeBankSyncRepository()
        let performer = FakeBankSyncPerformer()
        let connectionService = FakeMonobankConnectionService()
        let viewModel = BankSyncViewModel(
            repository: repository,
            syncPerformer: performer,
            connectionService: connectionService,
            walletsProvider: { [] }
        )
        viewModel.token = "token"
        viewModel.clientInfo = MonobankClientInfo(
            name: "Test",
            accounts: [MonobankAccount(id: "acc-1", type: "black", currencyCode: 980, maskedPan: ["1234"], iban: nil)]
        )
        viewModel.enabledAccountIDs = ["acc-1"]
        viewModel.selectedWalletIDs = ["acc-1": UUID()]

        var successCalled = false
        viewModel.onSuccess = { successCalled = true }

        await viewModel.startSyncing()

        #expect(viewModel.completedStatus != nil)
        #expect(successCalled)
    }

    private func waitFor(
        timeout: Duration = .milliseconds(500),
        _ condition: @escaping () -> Bool
    ) async throws {
        let deadline = ContinuousClock().now + timeout
        while !condition() {
            if ContinuousClock().now >= deadline {
                throw CancellationError()
            }
            await Task.yield()
        }
    }
}
