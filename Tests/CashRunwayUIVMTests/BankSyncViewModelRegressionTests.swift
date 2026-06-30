@testable import CashRunwayCore
@testable import CashRunwayUIVM
import Foundation
import Testing

@MainActor
@Suite("BankSyncViewModelRegression")
struct BankSyncViewModelRegressionTests {
    @Test("resetSensitiveWizardState clears transient state")
    func resetSensitiveWizardStateClearsTransientState() {
        let repository = FakeBankSyncRepository()
        let performer = FakeBankSyncPerformer()
        let connectionService = FakeMonobankConnectionService()
        let viewModel = BankSyncViewModel(
            repository: repository,
            syncPerformer: performer,
            connectionService: connectionService,
            walletsProvider: { [] }
        )

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
        let status = BankConnectionStatusSnapshot(
            integration: integration,
            enabledAccountCount: 1,
            syncStartAt: Date(),
            lastSuccessfulSyncAt: Date(),
            lastSyncError: nil,
            importedExpenseCount: 0
        )

        viewModel.token = "token"
        viewModel.clientInfo = MonobankClientInfo(name: "Test", accounts: [])
        viewModel.enabledAccountIDs = ["acc-1"]
        viewModel.selectedWalletIDs = ["acc-1": UUID()]
        viewModel.validationError = "validation error"
        viewModel.connectionError = "connection error"
        viewModel.isValidating = true
        viewModel.isConnecting = true
        viewModel.isAccountManagementPresented = true
        viewModel.isDisconnectConfirmationPresented = true
        viewModel.step = .confirmation
        viewModel.completedStatus = status

        viewModel.resetSensitiveWizardState()

        #expect(viewModel.token.isEmpty)
        #expect(viewModel.clientInfo == nil)
        #expect(viewModel.enabledAccountIDs.isEmpty)
        #expect(viewModel.selectedWalletIDs.isEmpty)
        #expect(viewModel.validationError == nil)
        #expect(viewModel.connectionError == nil)
        #expect(!viewModel.isValidating)
        #expect(!viewModel.isConnecting)
        #expect(!viewModel.isAccountManagementPresented)
        #expect(!viewModel.isDisconnectConfirmationPresented)
        #expect(viewModel.step == .intro)
        #expect(viewModel.completedStatus == status)
    }

    @Test("disconnect failure preserves completed status")
    func disconnectFailurePreservesCompletedStatus() async throws {
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
        let connectionService = FakeMonobankConnectionService()
        connectionService.disconnectShouldFail = true
        let viewModel = BankSyncViewModel(
            repository: repository,
            syncPerformer: FakeBankSyncPerformer(),
            connectionService: connectionService,
            walletsProvider: { [] }
        )
        viewModel.completedStatus = repository.status

        var failureCalled = false
        viewModel.onFailure = { _ in failureCalled = true }

        await viewModel.disconnect()

        #expect(failureCalled)
        #expect(viewModel.completedStatus != nil)
    }
}
