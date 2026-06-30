import CashRunwayCore
import Foundation
import Observation

@MainActor
@Observable
public final class BankSyncViewModel: Identifiable {
    public let id = UUID()

    // Wizard state
    public var step: MonobankWizardStep = .intro
    public var token = ""
    public var clientInfo: MonobankClientInfo?
    public var enabledAccountIDs: Set<String> = []
    public var selectedWalletIDs: [String: UUID] = [:]
    public var validationError: String?
    public var connectionError: String?
    public var isValidating = false
    public var isConnecting = false
    public var syncStartAt = Date()
    public var completedStatus: BankConnectionStatusSnapshot?

    // Status state
    public var isSyncing = false
    public var isAccountManagementPresented = false
    public var isDisconnectConfirmationPresented = false

    public var onSuccess: (() async -> Void)?
    public var onFailure: ((String) -> Void)?

    public var wallets: [Wallet] { walletsProvider() }

    private let repository: any BankSyncRepositorying
    private let syncPerformer: any BankSyncPerforming
    private let connectionService: any MonobankConnectionServicing
    private let walletsProvider: () -> [Wallet]

    public init(
        repository: any BankSyncRepositorying,
        syncPerformer: any BankSyncPerforming,
        connectionService: any MonobankConnectionServicing,
        walletsProvider: @escaping () -> [Wallet]
    ) {
        self.repository = repository
        self.syncPerformer = syncPerformer
        self.connectionService = connectionService
        self.walletsProvider = walletsProvider
    }

    public var isConnected: Bool {
        let status = connectionStatus()
        guard let integration = status.integration, integration.status != .disabled else {
            return false
        }
        return true
    }

    public func connectionStatus() -> BankConnectionStatusSnapshot {
        (try? repository.bankConnectionStatus(provider: .monobank)) ?? BankConnectionStatusSnapshot(
            integration: nil,
            enabledAccountCount: 0,
            syncStartAt: nil,
            lastSuccessfulSyncAt: nil,
            lastSyncError: nil,
            importedExpenseCount: 0
        )
    }

    public func connectedAccounts(integrationID: UUID) -> [BankAccount] {
        (try? repository.bankAccounts(integrationID: integrationID)) ?? []
    }

    public func validateToken() {
        guard !isValidating else { return }
        validationError = nil
        isValidating = true

        Task { @MainActor in
            defer { isValidating = false }
            do {
                let info = try await connectionService.validateToken(token)
                clientInfo = info
                let uahIDs = Set(info.accounts.filter { $0.currencyCode == 980 }.map(\.id))
                enabledAccountIDs = uahIDs
                let fallbackWalletID = walletsProvider().first?.id
                selectedWalletIDs = Dictionary(uniqueKeysWithValues: info.accounts.compactMap { account in
                    guard account.currencyCode == 980, let fallbackWalletID else { return nil }
                    return (account.id, fallbackWalletID)
                })
                step = .accounts
            } catch {
                validationError = error.localizedDescription
            }
        }
    }

    public func startSyncing() async {
        guard !isConnecting else { return }
        connectionError = nil
        isConnecting = true
        syncStartAt = Date()
        defer { isConnecting = false }
        do {
            let selections = clientInfo?.accounts.compactMap { account -> MonobankAccountConnectionSelection? in
                guard enabledAccountIDs.contains(account.id) else { return nil }
                guard let walletID = selectedWalletIDs[account.id] else { return nil }
                return MonobankAccountConnectionSelection(
                    account: account,
                    walletID: walletID,
                    isEnabled: enabledAccountIDs.contains(account.id)
                )
            } ?? []
            _ = try await connectionService.connectMonobank(token: token, selections: selections)
            completedStatus = connectionStatus()
            await onSuccess?()
        } catch {
            let message = error.localizedDescription
            connectionError = message
            onFailure?(message)
        }
    }

    public func syncNow() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            _ = try await syncPerformer.syncOnDemand()
            await onSuccess?()
        } catch {
            let message = error.localizedDescription
            onFailure?(message)
        }
    }

    public func disconnect() async {
        let status = connectionStatus()
        guard let integration = status.integration else {
            completedStatus = nil
            return
        }
        do {
            try connectionService.disconnectIntegration(integration.id)
            completedStatus = nil
            await onSuccess?()
        } catch {
            let message = error.localizedDescription
            onFailure?(message)
        }
    }

    public func learnBankCategoryRule(transactionID: UUID, categoryID: UUID) {
        do {
            try repository.learnBankMerchantCategoryRule(transactionID: transactionID, categoryID: categoryID)
        } catch {
            onFailure?(error.localizedDescription)
        }
    }

}

public enum MonobankWizardStep {
    case intro
    case token
    case accounts
    case confirmation
}
