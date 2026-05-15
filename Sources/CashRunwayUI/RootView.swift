import SwiftUI
import OSLog

public struct CashRunwayRootView: View {
    @State private var model: CashRunwayAppModel?
    @State private var startupFailure: CashRunwayStartupFailure?
    @State private var hasCompletedOnboarding: Bool
    // LEGACY_DISABLED_APP_LOCK:
    // App Lock is disabled for MVP. Do not wire into runtime without a new product decision.
    // @State private var pin = ""
    // @State private var onboardingPin = ""
    // @State private var onboardingBiometrics = true
    // @State private var relockTask: Task<Void, Never>?
    @State private var didRetryStartupOnActive = false
    @Environment(\.scenePhase) private var scenePhase
    private let onboardingStore: UserDefaults
    private let bypassOnboarding: Bool
    private static let onboardingKey = "hasCompletedOnboarding"
    private static let logger = Logger(subsystem: "dev.roman.cashrunway", category: "startup")

    public init(
        model: CashRunwayAppModel? = nil,
        startupError: String? = nil,
        onboardingStore: UserDefaults = .standard,
        bypassOnboarding: Bool = false
    ) {
        if let model {
            _model = State(initialValue: model)
            _startupFailure = State(initialValue: startupError.map(CashRunwayStartupFailure.init(message:)))
        } else if let startupError {
            _model = State(initialValue: nil)
            _startupFailure = State(initialValue: CashRunwayStartupFailure(message: startupError))
        } else {
            do {
                _model = State(initialValue: try CashRunwayAppModel.live())
                _startupFailure = State(initialValue: nil)
            } catch {
                _model = State(initialValue: nil)
                let failure = CashRunwayStartupFailure(error: error)
                Self.logger.error("Startup failed: \(failure.diagnosticCode, privacy: .public)")
                _startupFailure = State(initialValue: failure)
            }
        }
        self.onboardingStore = onboardingStore
        self.bypassOnboarding = bypassOnboarding
        _hasCompletedOnboarding = State(
            initialValue: bypassOnboarding || onboardingStore.bool(forKey: Self.onboardingKey)
        )
    }

    public var body: some View {
        Group {
            if let model {
                content(model: model)
            } else {
                startupErrorView
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active,
                  model == nil,
                  startupFailure?.isRetryable == true,
                  !didRetryStartupOnActive
            else { return }
            didRetryStartupOnActive = true
            retryStartup()
        }
    }

    private func content(model: CashRunwayAppModel) -> some View {
        Group {
            // LEGACY_DISABLED_APP_LOCK:
            // App Lock and onboarding are disabled for MVP.
            // if model.isLocked { lockView(model: model) }
            // else if shouldShowOnboarding(for: model) { onboardingView(model: model) }
            // else {
                TabView {
                    DashboardView(model: model)
                        .tabItem { SwiftUI.Label("Timeline", systemImage: "list.bullet.clipboard") }

                    TransactionsView(model: model)
                        .tabItem { SwiftUI.Label("Wallets", systemImage: "wallet.pass.fill") }

                    SettingsView(model: model)
                        .tabItem { SwiftUI.Label("More", systemImage: "ellipsis") }
                }
                .tint(CashRunwayTheme.accent)
                .background(CashRunwayTheme.background)
            // }
        }
        .task { await model.bootstrap() }
        .onChange(of: scenePhase) { _, phase in
            // LEGACY_DISABLED_APP_LOCK:
            // Background relock logic is disabled for MVP.
            // if phase == .background, let configuration = model.lockStore.configuration(), configuration.isEnabled {
            //     relockTask?.cancel()
            //     relockTask = Task {
            //         try? await Task.sleep(for: .seconds(configuration.backgroundLockSeconds))
            //         guard !Task.isCancelled else { return }
            //         await MainActor.run {
            //             model.isLocked = true
            //         }
            //     }
            // } else
            if phase == .active {
                // relockTask?.cancel()
                model.handleForegroundResume()
            }
        }
        .alert("Error", isPresented: Binding(get: { model.errorMessage != nil }, set: { _ in model.errorMessage = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var startupErrorView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 54))
                .foregroundStyle(CashRunwayTheme.negative)
            Text("Cash Runway Could Not Open")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(CashRunwayTheme.textPrimary)
            Text(startupFailure?.message ?? "The local database could not be opened.")
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
                .foregroundStyle(CashRunwayTheme.textSecondary)
                .padding(.horizontal, 24)
            if startupFailure?.isRetryable == true {
                Button("Retry") {
                    retryStartup()
                }
                .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .padding()
        .background(CashRunwayTheme.background.ignoresSafeArea())
    }

    private func retryStartup() {
        do {
            model = try CashRunwayAppModel.live()
            startupFailure = nil
        } catch {
            let failure = CashRunwayStartupFailure(error: error)
            Self.logger.error("Startup retry failed: \(failure.diagnosticCode, privacy: .public)")
            startupFailure = failure
        }
    }

    // LEGACY_DISABLED_APP_LOCK:
    // App Lock is disabled for MVP. Do not wire into runtime without a new product decision.
    // private func lockView(model: CashRunwayAppModel) -> some View {
    //     VStack(spacing: 18) {
    //         Spacer()
    //         Image(systemName: "lock.circle.fill")
    //             .font(.system(size: 72))
    //             .foregroundStyle(CashRunwayTheme.accent)
    //         Text("Cash Runway Locked")
    //             .font(.system(size: 30, weight: .bold, design: .rounded))
    //             .foregroundStyle(CashRunwayTheme.textPrimary)
    //         SecureField("PIN", text: $pin)
    //             .textFieldStyle(.roundedBorder)
    //             .frame(maxWidth: 240)
    //         Button("Unlock") {
    //             model.unlock(pin: pin)
    //             pin = ""
    //         }
    //         .buttonStyle(.borderedProminent)
    //         if model.lockStore.canUseBiometrics() {
    //             Button("Use Biometrics") {
    //                 Task {
    //                     await model.unlockWithBiometrics()
    //                 }
    //             }
    //             .buttonStyle(.bordered)
    //         }
    //         if let lockMessage = model.lockMessage {
    //             Text(lockMessage)
    //                 .foregroundStyle(CashRunwayTheme.negative)
    //         }
    //         Spacer()
    //     }
    //     .padding()
    //     .background(CashRunwayTheme.background.ignoresSafeArea())
    // }

    private func shouldShowOnboarding(for model: CashRunwayAppModel) -> Bool {
        // DEPRECATED — Onboarding and App Lock setup are deprecated.
        // App launches straight to Timeline on first startup.
        false
    }

    // LEGACY_DISABLED_APP_LOCK:
    // Onboarding with App Lock setup is disabled for MVP.
    // private func onboardingView(model: CashRunwayAppModel) -> some View {
    //     ScrollView {
    //         VStack(alignment: .leading, spacing: 22) {
    //             Spacer(minLength: 24)
    //             Text("Welcome to Cash Runway")
    //                 .font(.system(size: 32, weight: .bold, design: .rounded))
    //                 .foregroundStyle(CashRunwayTheme.textPrimary)
    //             Text("Cash Runway keeps encrypted local finance history, budgets, recurring entries, and CSV import/export.")
    //                 .font(.system(size: 17))
    //                 .foregroundStyle(CashRunwayTheme.textSecondary)
    //
    //             onboardingCard(title: "Offline First", body: "Your Cash Runway data stays on device and is backed by encrypted SQLite.")
    //             onboardingCard(title: "Fast By Design", body: "Dashboards and budgets read from precomputed aggregates instead of rescanning raw history.")
    //             onboardingCard(title: "Ready For History", body: "Import CSVs, manage recurring transactions, and keep years of records responsive.")
    //
    //             VStack(alignment: .leading, spacing: 12) {
    //                 Text("App Lock Setup")
    //                     .font(.system(size: 20, weight: .semibold))
    //                     .foregroundStyle(CashRunwayTheme.textPrimary)
    //                 SecureField("Set a 4+ digit PIN", text: $onboardingPin)
    //                     .textFieldStyle(.roundedBorder)
    //                     .keyboardType(.numberPad)
    //                 Toggle("Enable biometrics", isOn: $onboardingBiometrics)
    //                     .tint(CashRunwayTheme.accent)
    //                 Text("You can skip this now and enable app lock later in Settings.")
    //                     .font(.system(size: 14))
    //                     .foregroundStyle(CashRunwayTheme.textSecondary)
    //             }
    //             .padding(20)
    //             .background(CashRunwayTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    //
    //             Button("Continue Without Lock") {
    //                 completeOnboarding()
    //             }
    //             .buttonStyle(.bordered)
    //
    //             Button("Save PIN And Continue") {
    //                 model.enableLock(pin: onboardingPin, biometrics: onboardingBiometrics)
    //                 if model.errorMessage == nil {
    //                     completeOnboarding()
    //                     onboardingPin = ""
    //                 }
    //             }
    //             .buttonStyle(.borderedProminent)
    //             .disabled(onboardingPin.isEmpty)
    //         }
    //         .padding(20)
    //     }
    //     .background(CashRunwayTheme.background.ignoresSafeArea())
    // }

    private func onboardingCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(CashRunwayTheme.textPrimary)
            Text(body)
                .font(.system(size: 16))
                .foregroundStyle(CashRunwayTheme.textSecondary)
        }
        .padding(20)
        .background(CashRunwayTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func completeOnboarding() {
        hasCompletedOnboarding = true
        onboardingStore.set(true, forKey: Self.onboardingKey)
    }
}
