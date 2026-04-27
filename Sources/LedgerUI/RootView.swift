import SwiftUI

public struct LedgerRootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var model = LedgerAppModel()
    @State private var pin = ""
    @State private var onboardingPin = ""
    @State private var onboardingBiometrics = true
    @State private var relockTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    public var body: some View {
        Group {
            if model.isLocked {
                lockView
            } else if shouldShowOnboarding {
                onboardingView
            } else {
                TabView {
                    DashboardView(model: model)
                        .tabItem { SwiftUI.Label("Timeline", systemImage: "list.bullet.clipboard") }

                    TransactionsView(model: model)
                        .tabItem { SwiftUI.Label("Wallets", systemImage: "wallet.pass.fill") }

                    BudgetsView(model: model)
                        .tabItem { SwiftUI.Label("Budgets", systemImage: "suitcase.rolling.fill") }

                    SettingsView(model: model)
                        .tabItem { SwiftUI.Label("More", systemImage: "ellipsis") }
                }
                .tint(LedgerTheme.accent)
                .background(LedgerTheme.background)
            }
        }
        .task { model.bootstrap() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, let configuration = model.lockStore.configuration(), configuration.isEnabled {
                relockTask?.cancel()
                relockTask = Task {
                    try? await Task.sleep(for: .seconds(configuration.backgroundLockSeconds))
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        model.isLocked = true
                    }
                }
            } else if phase == .active {
                relockTask?.cancel()
                model.handleForegroundResume()
            }
        }
        .alert("Error", isPresented: Binding(get: { model.errorMessage != nil }, set: { _ in model.errorMessage = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var lockView: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "lock.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(LedgerTheme.accent)
            Text("Ledger Locked")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(LedgerTheme.textPrimary)
            SecureField("PIN", text: $pin)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
            Button("Unlock") {
                model.unlock(pin: pin)
                pin = ""
            }
            .buttonStyle(.borderedProminent)
            if model.lockStore.canUseBiometrics() {
                Button("Use Biometrics") {
                    Task {
                        await model.unlockWithBiometrics()
                    }
                }
                .buttonStyle(.bordered)
            }
            if let lockMessage = model.lockMessage {
                Text(lockMessage)
                    .foregroundStyle(LedgerTheme.negative)
            }
            Spacer()
        }
        .padding()
        .background(LedgerTheme.background.ignoresSafeArea())
    }

    private var shouldShowOnboarding: Bool {
        !hasCompletedOnboarding && model.lockStore.configuration() == nil
    }

    private var onboardingView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Spacer(minLength: 24)
                Text("Welcome to Spendee Ledger")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(LedgerTheme.textPrimary)
                Text("A local-first finance ledger with encrypted storage, budgets, recurring entries, and CSV import/export.")
                    .font(.system(size: 17))
                    .foregroundStyle(LedgerTheme.textSecondary)

                onboardingCard(title: "Offline First", body: "Your ledger stays on device and is backed by encrypted SQLite.")
                onboardingCard(title: "Fast By Design", body: "Dashboards and budgets read from precomputed aggregates instead of rescanning raw history.")
                onboardingCard(title: "Ready For History", body: "Import CSVs, manage recurring transactions, and keep years of records responsive.")

                VStack(alignment: .leading, spacing: 12) {
                    Text("App Lock Setup")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(LedgerTheme.textPrimary)
                    SecureField("Set a 4+ digit PIN", text: $onboardingPin)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                    Toggle("Enable biometrics", isOn: $onboardingBiometrics)
                        .tint(LedgerTheme.accent)
                    Text("You can skip this now and enable app lock later in Settings.")
                        .font(.system(size: 14))
                        .foregroundStyle(LedgerTheme.textSecondary)
                }
                .padding(20)
                .background(LedgerTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                Button("Continue Without Lock") {
                    hasCompletedOnboarding = true
                }
                .buttonStyle(.bordered)

                Button("Save PIN And Continue") {
                    model.enableLock(pin: onboardingPin, biometrics: onboardingBiometrics)
                    if model.errorMessage == nil {
                        hasCompletedOnboarding = true
                        onboardingPin = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(onboardingPin.isEmpty)
            }
            .padding(20)
        }
        .background(LedgerTheme.background.ignoresSafeArea())
    }

    private func onboardingCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(LedgerTheme.textPrimary)
            Text(body)
                .font(.system(size: 16))
                .foregroundStyle(LedgerTheme.textSecondary)
        }
        .padding(20)
        .background(LedgerTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
