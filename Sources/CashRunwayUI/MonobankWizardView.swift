import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import CashRunwayCore

struct MonobankWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var coordinator: MonobankCoordinator

    var body: some View {
        if coordinator.isConnected || coordinator.completedStatus != nil {
            statusView
        } else {
            wizardView
        }
    }

    private var wizardView: some View {
        NavigationStack {
            Group {
                switch coordinator.step {
                case .intro:
                    MonobankTokenIntroView {
                        coordinator.step = .token
                    }
                case .token:
                    MonobankTokenStepView(
                        token: $coordinator.token,
                        isValidating: coordinator.isValidating,
                        error: coordinator.validationError,
                        onValidate: coordinator.validateToken
                    )
                case .accounts:
                    MonobankAccountSelectionView(
                        model: coordinator.model,
                        accounts: coordinator.clientInfo?.accounts ?? [],
                        enabledAccountIDs: $coordinator.enabledAccountIDs,
                        selectedWalletIDs: $coordinator.selectedWalletIDs,
                        onContinue: {
                            coordinator.syncStartAt = Date()
                            coordinator.step = .confirmation
                        }
                    )
                case .confirmation:
                    MonobankStartConfirmationView(
                        syncStartAt: coordinator.syncStartAt,
                        isConnecting: coordinator.isConnecting,
                        error: coordinator.connectionError,
                        onStart: coordinator.startSyncing
                    )
                }
            }
            .navigationTitle("Monobank")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var statusView: some View {
        let currentStatus = coordinator.model.monobankConnectionStatus()
        return NavigationStack {
            Form {
                Section {
                    summaryRow("Connected accounts", value: "\(currentStatus.enabledAccountCount)")
                    summaryRow("Sync starts from", value: dateText(currentStatus.syncStartAt))
                    summaryRow("Last successful sync", value: dateText(currentStatus.lastSuccessfulSyncAt))
                    summaryRow("Imported expenses", value: "\(currentStatus.importedExpenseCount)", valueIdentifier: CashRunwayAccessibilityID.monobankImportedExpensesValue)
                    if let message = coordinator.model.bankSyncMessage ?? currentStatus.lastSyncError {
                        summaryRow("Last result", value: message, valueIdentifier: CashRunwayAccessibilityID.monobankLastResultValue)
                    } else {
                        summaryRow("Last result", value: L10n.string("success"), valueIdentifier: CashRunwayAccessibilityID.monobankLastResultValue)
                    }
                } header: {
                    Text("Monobank connected")
                        .accessibilityIdentifier(CashRunwayAccessibilityID.monobankStatusScreen)
                }

                Section("Diagnostics") {
                    summaryRow("Provider", value: "Monobank")
                    summaryRow("Enabled accounts", value: "\(currentStatus.enabledAccountCount)")
                    summaryRow("Sync start", value: dateText(currentStatus.syncStartAt))
                    summaryRow("Last sync", value: dateText(currentStatus.lastSuccessfulSyncAt))
                    summaryRow("Imported expenses", value: "\(currentStatus.importedExpenseCount)")
                }

                Section {
                    Button(coordinator.isSyncing ? L10n.string("Syncing...") : L10n.string("Sync now")) {
                        coordinator.syncNow()
                    }
                    .disabled(coordinator.isSyncing)
                    .accessibilityIdentifier(CashRunwayAccessibilityID.monobankSyncNowButton)
                    Button("Manage accounts") {
                        coordinator.isAccountManagementPresented = true
                    }
                    .accessibilityIdentifier(CashRunwayAccessibilityID.monobankManageAccountsButton)
                    Button("Disconnect", role: .destructive) {
                        coordinator.isDisconnectConfirmationPresented = true
                    }
                    .accessibilityIdentifier(CashRunwayAccessibilityID.monobankDisconnectButton)
                }
            }
            .navigationTitle("Monobank")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Disconnect Monobank?", isPresented: $coordinator.isDisconnectConfirmationPresented) {
                Button("Cancel", role: .cancel) {}
                Button("Disconnect", role: .destructive) {
                    coordinator.disconnect()
                }
            } message: {
                Text("Imported transactions stay in Cash Runway. Only future Monobank sync is disabled on this iPhone.")
            }
            .sheet(isPresented: $coordinator.isAccountManagementPresented) {
                if let integration = currentStatus.integration {
                    MonobankAccountManagementView(model: coordinator.model, integrationID: integration.id)
                }
            }
        }
    }

    private func summaryRow(_ title: LocalizedStringKey, value: String, valueIdentifier: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(CashRunwayTheme.textSecondary)
            Spacer(minLength: 16)
            if let valueIdentifier {
                Text(value)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                    .accessibilityIdentifier(valueIdentifier)
            } else {
                Text(value)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(CashRunwayTheme.textPrimary)
            }
        }
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else { return L10n.string("Never") }
        return Self.dateFormatter(locale: L10n.locale).string(from: date)
    }

    private static func dateFormatter(locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }
}

private struct MonobankTokenIntroView: View {
    let onContinue: () -> Void

    var body: some View {
        Form {
            Section {
                Text("Cash Runway will import only new Monobank card expenses after connection.")
                Text("Old bank history will not be imported.")
                Text("Existing Cash Runway transactions will not be changed.")
                Text("Income will not be imported.")
                Text("Your Monobank token stays on this iPhone.")
            } header: {
                Text("Connect Monobank")
            }

            Section {
                Button("Continue", action: onContinue)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityIdentifier(CashRunwayAccessibilityID.monobankIntroContinueButton)
            }
        }
    }
}

private struct MonobankTokenStepView: View {
    @Binding var token: String
    let isValidating: Bool
    let error: String?
    let onValidate: () -> Void

    var body: some View {
        Form {
            Section {
                // XCUITest types into SecureField extremely slowly; use TextField in UI-test mode.
                if ProcessInfo.processInfo.environment["CASH_RUNWAY_UI_TEST_MODE"] == "1" {
                    TextField("Personal API token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier(CashRunwayAccessibilityID.monobankTokenField)
                } else {
                    SecureField("Personal API token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier(CashRunwayAccessibilityID.monobankTokenField)
                }
                #if canImport(UIKit)
                Button("Paste from Clipboard") {
                    token = UIPasteboard.general.string ?? token
                }
                .accessibilityIdentifier(CashRunwayAccessibilityID.monobankPasteTokenButton)
                #endif
                Button(isValidating ? "Validating..." : "Validate Token", action: onValidate)
                    .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidating)
                    .accessibilityIdentifier(CashRunwayAccessibilityID.monobankValidateButton)
            }

            if let error {
                Section("Validation Error") {
                    Text(error)
                        .foregroundStyle(CashRunwayTheme.negative)
                        .accessibilityIdentifier(CashRunwayAccessibilityID.monobankValidationError)
                }
            }
        }
    }
}

private struct MonobankAccountSelectionView: View {
    @Bindable var model: CashRunwayAppModel
    let accounts: [MonobankAccount]
    @Binding var enabledAccountIDs: Set<String>
    @Binding var selectedWalletIDs: [String: UUID]
    let onContinue: () -> Void

    var body: some View {
        Form {
            Section("Cards") {
                ForEach(accounts, id: \.id) { account in
                    if account.currencyCode == 980 {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(accountTitle(account), isOn: Binding(
                                get: { enabledAccountIDs.contains(account.id) },
                                set: { isEnabled in
                                    if isEnabled {
                                        enabledAccountIDs.insert(account.id)
                                    } else {
                                        enabledAccountIDs.remove(account.id)
                                    }
                                }
                            ))
                            .accessibilityIdentifier(CashRunwayAccessibilityID.monobankAccountToggle(account.id))
                            Picker("Map to wallet", selection: Binding(
                                get: { selectedWalletIDs[account.id] ?? model.wallets.first?.id ?? UUID() },
                                set: { selectedWalletIDs[account.id] = $0 }
                            )) {
                                ForEach(model.wallets) { wallet in
                                    Text(wallet.name).tag(wallet.id)
                                }
                            }
                            Button("Create Monobank wallet") {
                                createWallet(for: account)
                            }
                        }
                        .accessibilityIdentifier(CashRunwayAccessibilityID.monobankAccountRow(account.id))
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(accountTitle(account))
                            Text("Not supported in MVP")
                                .font(.footnote)
                                .foregroundStyle(CashRunwayTheme.textSecondary)
                        }
                        .accessibilityIdentifier(CashRunwayAccessibilityID.monobankAccountRow(account.id))
                    }
                }
            }

            Section {
                Button("Continue", action: onContinue)
                    .disabled(!hasEnabledMappedAccount)
                    .accessibilityIdentifier(CashRunwayAccessibilityID.monobankAccountsContinueButton)
            } footer: {
                Text("Only selected UAH card accounts will sync.")
            }
        }
    }

    private var hasEnabledMappedAccount: Bool {
        accounts.contains { account in
            account.currencyCode == 980 && enabledAccountIDs.contains(account.id) && selectedWalletIDs[account.id] != nil
        }
    }

    private func accountTitle(_ account: MonobankAccount) -> String {
        let type = (account.type?.isEmpty == false ? account.type! : L10n.string("Card")).capitalized
        let suffix = account.maskedPan?.first.map { " ****\(String($0.suffix(4)))" } ?? ""
        let currency = account.currencyCode == 980 ? "UAH" : String(account.currencyCode)
        return L10n.string("%@ card%@ · %@", type, suffix, currency)
    }

    private func createWallet(for account: MonobankAccount) {
        let suffix = account.maskedPan?.first.map { " ****\(String($0.suffix(4)))" } ?? ""
        let type = (account.type?.isEmpty == false ? account.type! : L10n.string("Card")).capitalized
        let wallet = Wallet(
            id: UUID(),
            name: "Monobank \(type)\(suffix)",
            kind: .card,
            colorHex: "#1CC389",
            iconName: "creditcard.fill",
            startingBalanceMinor: 0,
            currentBalanceMinor: 0,
            isArchived: false,
            sortOrder: model.wallets.count,
            createdAt: .now,
            updatedAt: .now
        )
        selectedWalletIDs[account.id] = wallet.id
        model.saveWallet(wallet)
    }
}

private struct MonobankStartConfirmationView: View {
    let syncStartAt: Date
    let isConnecting: Bool
    let error: String?
    let onStart: () -> Void

    var body: some View {
        Form {
            Section("Sync starts from now") {
                summaryRow("Start time", value: Self.dateFormatter(locale: L10n.locale).string(from: syncStartAt))
            }

            Section("Cash Runway will import") {
                Text(L10n.string("New Monobank expenses after %@", Self.dateFormatter(locale: L10n.locale).string(from: syncStartAt)))
                Text("Only selected UAH card accounts")
                Text("Only outgoing expenses")
            }

            Section("Cash Runway will not") {
                Text("Import old bank history")
                Text("Import income")
                Text("Modify existing manual, CSV, or recurring transactions")
            }

            if let error {
                Section("Connection Error") {
                    Text(error)
                        .foregroundStyle(CashRunwayTheme.negative)
                        .accessibilityIdentifier(CashRunwayAccessibilityID.monobankConnectionError)
                }
            }

            Section {
                Button(isConnecting ? L10n.string("Starting...") : L10n.string("Start syncing new expenses"), action: onStart)
                    .disabled(isConnecting)
                    .accessibilityIdentifier(CashRunwayAccessibilityID.monobankStartSyncButton)
            }
        }
    }

    private func summaryRow(_ title: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(CashRunwayTheme.textSecondary)
        }
    }

    private static func dateFormatter(locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }
}

private struct MonobankAccountManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CashRunwayAppModel
    let integrationID: UUID

    var body: some View {
        NavigationStack {
            Form {
                Section("Connected accounts") {
                    ForEach(model.monobankConnectedAccounts(integrationID: integrationID)) { account in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(account.displayName)
                            Text(accountSummary(account))
                                .font(.footnote)
                                .foregroundStyle(CashRunwayTheme.textSecondary)
                        }
                    }
                }
            }
            .navigationTitle("Manage accounts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func accountSummary(_ account: BankAccount) -> String {
        let walletName = model.wallets.first(where: { $0.id == account.walletID })?.name ?? L10n.string("Unknown wallet")
        let state = account.isEnabled ? L10n.string("Enabled") : L10n.string("Disabled")
        return "\(state) · \(walletName)"
    }
}
