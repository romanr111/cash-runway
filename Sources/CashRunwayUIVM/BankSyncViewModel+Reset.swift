import Foundation

extension BankSyncViewModel {
    public func resetSensitiveWizardState() {
        token = ""
        clientInfo = nil
        enabledAccountIDs.removeAll()
        selectedWalletIDs.removeAll()
        validationError = nil
        connectionError = nil
        isValidating = false
        isConnecting = false
        isAccountManagementPresented = false
        isDisconnectConfirmationPresented = false
        step = .intro
        syncStartAt = Date()
    }
}
