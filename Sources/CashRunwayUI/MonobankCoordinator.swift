import Foundation
import SwiftUI
#if canImport(CashRunwayCore)
import CashRunwayCore
#endif

enum MonobankWizardStep {
    case intro
    case token
    case accounts
    case confirmation
}

@MainActor
@Observable
final class MonobankCoordinator: Identifiable {
    let id = UUID()
    let model: CashRunwayAppModel

    // Wizard state
    var step: MonobankWizardStep = .intro
    var token = ""
    var clientInfo: MonobankClientInfo?
    var enabledAccountIDs: Set<String> = []
    var selectedWalletIDs: [String: UUID] = [:]
    var validationError: String?
    var connectionError: String?
    var isValidating = false
    var isConnecting = false
    var syncStartAt = Date()
    var completedStatus: BankConnectionStatusSnapshot?

    // Status state
    var isSyncing = false
    var isAccountManagementPresented = false
    var isDisconnectConfirmationPresented = false

    init(model: CashRunwayAppModel) {
        self.model = model
    }

    var isConnected: Bool {
        let status = model.monobankConnectionStatus()
        guard let integration = status.integration, integration.status != .disabled else {
            return false
        }
        return true
    }

    func validateToken() {
        guard !isValidating else { return }
        validationError = nil
        isValidating = true
        Task { @MainActor in
            do {
                let info = try await model.validateMonobankToken(token)
                clientInfo = info
                let uahIDs = Set(info.accounts.filter { $0.currencyCode == 980 }.map(\.id))
                enabledAccountIDs = uahIDs
                let fallbackWalletID = model.wallets.first?.id
                selectedWalletIDs = Dictionary(uniqueKeysWithValues: info.accounts.compactMap { account in
                    guard account.currencyCode == 980, let fallbackWalletID else { return nil }
                    return (account.id, fallbackWalletID)
                })
                step = .accounts
            } catch {
                validationError = error.localizedDescription
            }
            isValidating = false
        }
    }

    func startSyncing() {
        guard !isConnecting else { return }
        connectionError = nil
        isConnecting = true
        syncStartAt = Date()
        Task { @MainActor in
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
                _ = try await model.connectMonobank(token: token, selections: selections, syncStartAt: syncStartAt)
                completedStatus = model.monobankConnectionStatus()
            } catch {
                connectionError = error.localizedDescription
            }
            isConnecting = false
        }
    }

    func syncNow() {
        guard !isSyncing else { return }
        isSyncing = true
        Task { @MainActor in
            await model.syncMonobankNow()
            isSyncing = false
        }
    }

    func disconnect() {
        let status = model.monobankConnectionStatus()
        if let integration = status.integration {
            model.disconnectBankIntegration(integration.id)
        }
        completedStatus = nil
    }
}
