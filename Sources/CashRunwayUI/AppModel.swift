import CashRunwayCore
import CashRunwayUIVM
import Foundation
import Observation
import SwiftUI

public typealias CashRunwayCategory = CashRunwayCore.Category
public typealias CashRunwayLabel = CashRunwayCore.Label

@MainActor
@Observable
public final class CashRunwayAppModel {
    // Narrowed from `public var` to `private let` for encapsulation: no external
    // code reassigns the repository mid-session, and the static snapshot loaders
    // receive it as a parameter. `csvService`/`backupService` remain `public var`
    // until BackupServicing/CSVServicing protocols are introduced (Phase 3.6).
    private let repository: any CashRunwayRepositorying
    public var csvService: any CSVImportServicing
    public var backupService: any BackupServicing
    public var bankTokenStore: any BankTokenStore
    private let bankSyncPerformer: any BankSyncPerforming
    private let monobankConnectionService: any MonobankConnectionServicing
    private let backgroundWork: BackgroundWork

    public let backupViewModel: BackupViewModel
    public let importViewModel: ImportViewModel
    public let bankSyncViewModel: BankSyncViewModel
    // LEGACY_DISABLED_APP_LOCK:
    // App Lock is disabled for MVP. Do not wire into runtime without a new product decision.
    // public var lockStore: AppLockStore

    public var wallets: [Wallet] = []
    public var walletCategories: [WalletCategory] = []
    public var expenseCategories: [CashRunwayCategory] = []
    public var incomeCategories: [CashRunwayCategory] = []
    public var labels: [CashRunwayLabel] = []
    public var transactions: [TransactionListItem] = []
    // DEPRECATED — Budgets feature is de-prioritized. Work stopped; do not modify or add tests until resumed.
    public var budgets: [BudgetProgress] = []
    public var templates: [RecurringTemplate] = []
    public var instances: [RecurringInstance] = []
    public var dashboardSnapshot: DashboardSnapshot?
    public var defaultCurrencyCode: CurrencyCode {
        (try? repository.currencyPreferences().defaultCurrencyCode) ?? .uah
    }
    public var reportingCurrencyCode: CurrencyCode {
        (try? repository.currencyPreferences().reportingCurrencyCode) ?? .uah
    }
    public var timelineSnapshot: TimelineSnapshot?
    public var overviewSnapshot: OverviewSnapshot?
    public var allBars: [TimelineBarPoint] = []
    public var categoryDetailTransactions: [TransactionListItem] = []

    public var selectedMonthKey = DateKeys.monthKey(for: .now)
    public var selectedWalletID: UUID?
    public var selectedTimelinePeriod: TimelinePeriod = .month
    public var transactionQuery = TransactionQuery()
    // LEGACY_DISABLED_APP_LOCK:
    // App Lock is disabled for MVP. Do not wire into runtime without a new product decision.
    // public var isLocked = false
    // public var lockMessage: String?
    public var errorMessage: String?
    public var bankSyncMessage: String?
    public var isLoading = false
    public private(set) var isTimelineLoading = false
    public private(set) var hasBootstrapped = false
    public private(set) var latestTransactionMonthKey: Int?
    private var foregroundRefreshTask: Task<Void, Never>?
    private var timelineReloadState = TimelineReloadState()

    public var currentCashFlowMinor: Int64 {
        let selectedBar = allBars.first(where: {
            switch selectedTimelinePeriod {
            case .month: return $0.periodKey == selectedMonthKey
            case .year: return $0.periodKey == selectedMonthKey / 100
            }
        })
        return selectedBar.map { $0.incomeMinor - $0.expenseMinor } ?? 0
    }
    var aggregateCurrencyCode: CurrencyCode? {
        let walletCurrencies = Set(wallets.map(\.currencyCode))
        guard let first = walletCurrencies.first else {
            return defaultCurrencyCode
        }

        return walletCurrencies.count == 1 ? first : nil
    }

    func canChangeWalletCurrency(_ walletID: UUID) -> Bool {
        (try? repository.canChangeWalletCurrency(id: walletID)) ?? true
    }

    func aggregateMoneyString(from minorUnits: Int64) -> String? {
        guard let currencyCode = aggregateCurrencyCode else {
            return nil
        }

        return MoneyFormatter.string(from: minorUnits, currencyCode: currencyCode)
    }

    private var lastForegroundRefreshAt: Date?
    private let foregroundRefreshMinimumInterval: TimeInterval = 10
    private var overviewSnapshotCache: [String: OverviewSnapshot] = [:]
    private var overviewSnapshotCacheOrder: [String] = []
    private let overviewSnapshotCacheLimit = 12
    private var preRestoreState: PreRestoreState?

    public var maxMonthKey: Int {
        max(DateKeys.monthKey(for: .now), latestTransactionMonthKey ?? 0)
    }

    public static func live() throws -> CashRunwayAppModel {
        // LEGACY_DISABLED_APP_LOCK:
        // App Lock is disabled for MVP.
        return CashRunwayAppModel(
            repository: try CashRunwayRepository()
        )
    }

    public init(
        repository: CashRunwayRepository
        // LEGACY_DISABLED_APP_LOCK:
        // App Lock is disabled for MVP.
        // lockStore: AppLockStore = AppLockStore(keychain: KeychainStore(service: "dev.roman.cash-runway"))
    ) {
        let csvService = CSVService(repository: repository)
        let bankTokenStore = KeychainBankTokenStore(keychain: KeychainStore(service: "dev.roman.cash-runway"))
        let backupService = BackupService(repository: repository, bankTokenStore: bankTokenStore)
        let bankSyncPerformer = BankSyncSerialPerformer(BankSyncCoordinator(repository: repository, tokenStore: bankTokenStore))
        let monobankConnectionService = MonobankConnectionService(
            repository: repository,
            tokenStore: bankTokenStore,
            tokenValidator: MonobankDirectTokenValidator(),
            syncPerformer: bankSyncPerformer
        )
        let backgroundWork = BackgroundWork(
            repository: repository,
            csvService: csvService,
            backupService: backupService,
            bankSyncPerformer: bankSyncPerformer
        )
        self.repository = repository
        self.csvService = csvService
        self.backupService = backupService
        self.bankTokenStore = bankTokenStore
        self.bankSyncPerformer = bankSyncPerformer
        self.monobankConnectionService = monobankConnectionService
        self.backgroundWork = backgroundWork
        self.backupViewModel = BackupViewModel(backupService: backupService)
        self.importViewModel = ImportViewModel(
            csvService: csvService,
            walletsProvider: { (try? repository.wallets()) ?? [] }
        )
        self.bankSyncViewModel = BankSyncViewModel(
            repository: repository,
            syncPerformer: bankSyncPerformer,
            connectionService: monobankConnectionService,
            walletsProvider: { (try? repository.wallets()) ?? [] }
        )
        bindViewModels()
        // self.lockStore = lockStore
    }

    public init(
        repository: any CashRunwayRepositorying,
        bankTokenStore: any BankTokenStore,
        bankSyncPerformer: any BankSyncPerforming,
        monobankTokenValidator: any MonobankTokenValidating,
        csvService: any CSVImportServicing,
        backupService: any BackupServicing
    ) {
        let performer = BankSyncSerialPerformer(bankSyncPerformer)
        let monobankConnectionService: any MonobankConnectionServicing = MonobankConnectionService(
            repository: repository,
            tokenStore: bankTokenStore,
            tokenValidator: monobankTokenValidator,
            syncPerformer: performer
        )
        let backgroundWork = BackgroundWork(
            repository: repository,
            csvService: csvService,
            backupService: backupService,
            bankSyncPerformer: performer
        )
        self.repository = repository
        self.csvService = csvService
        self.backupService = backupService
        self.bankTokenStore = bankTokenStore
        self.bankSyncPerformer = performer
        self.monobankConnectionService = monobankConnectionService
        self.backgroundWork = backgroundWork
        self.backupViewModel = BackupViewModel(backupService: backupService)
        self.importViewModel = ImportViewModel(
            csvService: csvService,
            walletsProvider: { (try? repository.wallets()) ?? [] }
        )
        self.bankSyncViewModel = BankSyncViewModel(
            repository: repository,
            syncPerformer: performer,
            connectionService: monobankConnectionService,
            walletsProvider: { (try? repository.wallets()) ?? [] }
        )
        bindViewModels()
    }

    private func bindViewModels() {
        backupViewModel.onWillRestore = { [weak self] in
            guard let self else { return }
            self.preRestoreState = PreRestoreState(
                selectedWalletID: self.selectedWalletID,
                overviewSnapshotCache: self.overviewSnapshotCache,
                overviewSnapshotCacheOrder: self.overviewSnapshotCacheOrder
            )
            self.selectedWalletID = nil
            self.overviewSnapshotCache.removeAll()
            self.overviewSnapshotCacheOrder.removeAll()
        }
        backupViewModel.onSuccess = { [weak self] in
            await self?.reloadAll()
            self?.errorMessage = nil
            self?.bankSyncMessage = nil
            self?.preRestoreState = nil
        }
        backupViewModel.onFailure = { [weak self] _ in
            guard let self, let state = self.preRestoreState else { return }
            self.selectedWalletID = state.selectedWalletID
            self.overviewSnapshotCache = state.overviewSnapshotCache
            self.overviewSnapshotCacheOrder = state.overviewSnapshotCacheOrder
            self.preRestoreState = nil
        }

        importViewModel.onSuccess = { [weak self] in
            await self?.reloadAll()
            self?.errorMessage = nil
            self?.bankSyncMessage = nil
        }
        importViewModel.onFailure = { [weak self] error in
            self?.errorMessage = error
        }

        bankSyncViewModel.onSuccess = { [weak self] in
            await self?.reloadAll()
            self?.bankSyncMessage = nil
            self?.bankSyncViewModel.resetSensitiveWizardState()
        }
        bankSyncViewModel.onFailure = { [weak self] error in
            self?.bankSyncMessage = error
        }
    }

    public func bootstrap() async {
        do {
            try repository.seedIfNeeded()
            try repository.runMaintenance()
            try repository.refreshRecurringInstances()
            await reloadAll()
            hasBootstrapped = true
            // LEGACY_DISABLED_APP_LOCK:
            // App Lock bootstrap check is disabled for MVP.
            // if let configuration = lockStore.configuration(), configuration.isEnabled {
            //     isLocked = true
            // }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    public func reloadAll() async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            let repository = self.repository
            let selectedMonthKey = self.selectedMonthKey
            let selectedWalletID = self.selectedWalletID
            let selectedTimelinePeriod = self.selectedTimelinePeriod
            var query = self.transactionQuery
            query.walletID = selectedWalletID

            let (bars, snapshot) = try await backgroundWork.loadAllBarsAndSnapshot(
                selectedMonthKey: selectedMonthKey,
                selectedWalletID: selectedWalletID,
                selectedTimelinePeriod: selectedTimelinePeriod,
                transactionQuery: query
            )

            guard currentRefreshScopeMatches(monthKey: selectedMonthKey, walletID: selectedWalletID, period: selectedTimelinePeriod, query: query) else {
                return false
            }
            self.allBars = bars
            self.apply(snapshot)
            self.latestTransactionMonthKey = try? repository.latestTransactionMonthKey()
            if let overview = snapshot.overviewSnapshot {
                self.setCachedOverview(overview, monthKey: overview.selectedMonthKey, walletID: overview.walletFilterID)
            }
            self.errorMessage = nil
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    public func selectWallet(_ walletID: UUID?) async -> Bool {
        selectedWalletID = walletID
        transactionQuery.walletID = walletID
        return await reloadAll()
    }

    private func loadAllBars() throws {
        allBars = try repository.allBars(walletID: selectedWalletID, period: selectedTimelinePeriod)
    }

    /// Loads only the overview snapshot asynchronously. Used for Overview page month navigation.
    public func reloadOverview() async {
        let cacheKey = overviewCacheKey(monthKey: selectedMonthKey, walletID: selectedWalletID)
        if let cached = overviewSnapshotCache[cacheKey] {
            overviewSnapshot = cached
            preloadAdjacentOverviewSnapshots()
            return
        }
        isLoading = true
        defer {
            isLoading = false
            preloadAdjacentOverviewSnapshots()
        }
        do {
            let selectedMonthKey = self.selectedMonthKey
            let selectedWalletID = self.selectedWalletID
            let overview = try await backgroundWork.loadOverviewSnapshot(
                monthKey: selectedMonthKey,
                walletID: selectedWalletID
            )
            overviewSnapshot = overview
            latestTransactionMonthKey = try? repository.latestTransactionMonthKey()
            setCachedOverview(overview, monthKey: selectedMonthKey, walletID: selectedWalletID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func navigateMonth(by offset: Int) {
        guard let newDate = DateKeys.calendar.date(byAdding: .month, value: offset, to: DateKeys.startOfMonth(for: selectedMonthKey)) else { return }
        let newMonthKey = DateKeys.monthKey(for: newDate)
        guard newMonthKey <= maxMonthKey else { return }
        selectedMonthKey = newMonthKey
        Task {
            await reloadOverview()
        }
    }

    public func navigatePeriod(by offset: Int) {
        let monthOffset = selectedTimelinePeriod == .year ? offset * 12 : offset
        guard let newDate = DateKeys.calendar.date(byAdding: .month, value: monthOffset, to: DateKeys.startOfMonth(for: selectedMonthKey)) else { return }
        let newMonthKey = DateKeys.monthKey(for: newDate)
        guard newMonthKey <= maxMonthKey else { return }
        selectedMonthKey = newMonthKey
        reloadTimeline()
    }

    public func selectTimelinePeriod(_ period: TimelinePeriod) {
        guard selectedTimelinePeriod != period else { return }
        if selectedTimelinePeriod == .year, period == .month {
            selectedMonthKey = DateKeys.monthKeyForMonthTimelineReturn(
                selectedYear: selectedMonthKey / 100,
                currentMonthKey: DateKeys.monthKey(for: .now),
                maxMonthKey: maxMonthKey
            )
        }
        selectedTimelinePeriod = period
    }

    public func reloadTimeline() {
        let reloadID = beginTimelineReload()
        Task {
            await reloadSnapshotsAsync(reloadID: reloadID)
        }
    }

    private func reloadSnapshotsAsync(reloadID: Int) async {
        let targetMonthKey = self.selectedMonthKey
        let targetWalletID = self.selectedWalletID
        let targetPeriod = self.selectedTimelinePeriod
        var targetQuery = self.transactionQuery
        targetQuery.walletID = targetWalletID
        defer {
            finishTimelineReload(reloadID: reloadID)
        }

        let cacheKey = overviewCacheKey(monthKey: targetMonthKey, walletID: targetWalletID)
        if let cached = overviewSnapshotCache[cacheKey] {
            overviewSnapshot = cached
        }

        do {
            let mutable = try await backgroundWork.loadMutableSnapshots(
                selectedMonthKey: targetMonthKey,
                selectedWalletID: targetWalletID,
                selectedTimelinePeriod: targetPeriod,
                transactionQuery: targetQuery
            )

            guard selectedMonthKey == targetMonthKey,
                  selectedWalletID == targetWalletID,
                  selectedTimelinePeriod == targetPeriod,
                  timelineReloadState.canApply(reloadID: reloadID) else { return }

            budgets = mutable.budgets
            walletCategories = mutable.walletCategories
            transactions = mutable.transactions
            dashboardSnapshot = mutable.dashboardSnapshot
            timelineSnapshot = mutable.timelineSnapshot
            overviewSnapshot = mutable.overviewSnapshot
            transactionQuery = mutable.transactionQuery
            latestTransactionMonthKey = try? repository.latestTransactionMonthKey()
            if let overview = mutable.overviewSnapshot {
                setCachedOverview(overview, monthKey: targetMonthKey, walletID: targetWalletID)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func beginTimelineReload() -> Int {
        let reloadID = timelineReloadState.beginReload()
        isTimelineLoading = timelineReloadState.isLoading
        return reloadID
    }

    private func finishTimelineReload(reloadID: Int) {
        timelineReloadState.finishReload(reloadID: reloadID)
        isTimelineLoading = timelineReloadState.isLoading
    }

    private func setCachedOverview(_ overview: OverviewSnapshot, monthKey: Int, walletID: UUID?) {
        let key = overviewCacheKey(monthKey: monthKey, walletID: walletID)
        overviewSnapshotCache[key] = overview
        overviewSnapshotCacheOrder.removeAll { $0 == key }
        overviewSnapshotCacheOrder.append(key)
        while overviewSnapshotCacheOrder.count > overviewSnapshotCacheLimit {
            let oldest = overviewSnapshotCacheOrder.removeFirst()
            overviewSnapshotCache.removeValue(forKey: oldest)
        }
    }

    private func preloadAdjacentOverviewSnapshots() {
        let selectedMonthKey = self.selectedMonthKey
        let selectedWalletID = self.selectedWalletID
        let maxMonthKey = self.maxMonthKey
        let backgroundWork = self.backgroundWork
        Task { [selectedMonthKey, selectedWalletID, maxMonthKey, backgroundWork] in
            for offset in [-1, 1] {
                guard let date = DateKeys.calendar.date(byAdding: .month, value: offset, to: DateKeys.startOfMonth(for: selectedMonthKey)) else { continue }
                let monthKey = DateKeys.monthKey(for: date)
                guard monthKey <= maxMonthKey else { continue }
                let key = "\(monthKey)-\(selectedWalletID?.uuidString ?? "all")"
                let shouldLoad = await MainActor.run { [weak self] in
                    guard let self else { return false }
                    return self.overviewSnapshotCache[key] == nil
                }
                guard shouldLoad else { continue }
                guard let snapshot = try? await backgroundWork.loadOverviewSnapshot(monthKey: monthKey, walletID: selectedWalletID) else { continue }
                await MainActor.run { [weak self] in
                    self?.setCachedOverview(snapshot, monthKey: monthKey, walletID: selectedWalletID)
                }
            }
        }
    }

    // LEGACY_DISABLED_APP_LOCK:
    // App Lock is disabled for MVP. Do not wire into runtime without a new product decision.
    // public func unlock(pin: String) {
    //     guard lockStore.validate(pin: pin) else {
    //         lockMessage = "Incorrect PIN."
    //         return
    //     }
    //     isLocked = false
    //     lockMessage = nil
    // }

    // public func unlockWithBiometrics() async {
    //     guard await lockStore.unlockWithBiometrics() else {
    //         lockMessage = "Biometric unlock failed."
    //         return
    //     }
    //     isLocked = false
    //     lockMessage = nil
    // }

    // public func enableLock(pin: String, biometrics: Bool) {
    //     do {
    //         try lockStore.save(pin: pin, biometrics: biometrics, backgroundLockSeconds: 15)
    //         errorMessage = nil
    //     } catch {
    //         errorMessage = error.localizedDescription
    //     }
    // }

    public func saveTransaction(_ draft: TransactionDraft) {
        saveTransaction(draft, recurringTemplate: nil)
    }

    /// Loads a transaction draft for editing. Returns nil if the transaction
    /// cannot be found or loaded.
    public func loadTransactionDraft(id: UUID) -> TransactionDraft? {
        try? repository.transactionDraft(id: id)
    }

    public func saveTransaction(_ draft: TransactionDraft, recurringTemplate: RecurringTemplate?) {
        runMutation {
            try repository.saveTransaction(draft)
            if let recurringTemplate {
                try repository.saveRecurringTemplate(recurringTemplate)
            }
        }
    }

    public func deleteTransaction(id: UUID) {
        runMutation {
            try repository.deleteTransaction(id: id)
        }
    }

    /// Loads a deletion summary off the main actor so the sheet opening stays
    /// responsive even when loading a large year-scoped count.
    public func transactionDeletionSummary(for period: DeletePeriod) async -> TransactionDeletionSummary {
        let repo = repository
        do {
            return try await Task.detached(priority: .userInitiated) {
                try repo.transactionDeletionSummary(for: period)
            }.value
        } catch {
            errorMessage = error.localizedDescription
            return TransactionDeletionSummary(count: 0, displayCount: 0)
        }
    }

    /// Builds a frozen deletion plan off the main actor so the period-selection UI
    /// stays responsive even when previewing a large year-scoped set.
    public func transactionDeletionPlan(for period: DeletePeriod) async -> TransactionDeletionPlan? {
        let repo = repository
        do {
            let task = Task.detached(priority: .userInitiated) {
                try repo.transactionDeletionPlan(for: period)
            }
            let plan = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            return plan
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Bulk-deletes transactions using a frozen `plan` off the main actor so the UI
    /// stays responsive (and the loading spinner can animate) even for large
    /// year-scoped deletes. Awaits the post-delete refresh so callers can distinguish
    /// "delete succeeded, refresh failed" from complete success. Returns a structured
    /// `TransactionDeletionResult`; sets `errorMessage` on any failure.
    public func deleteTransactions(plan: TransactionDeletionPlan) async -> TransactionDeletionResult {
        let repo = repository
        foregroundRefreshTask?.cancel()
        foregroundRefreshTask = nil
        do {
            let deleted = try await Task.detached(priority: .userInitiated) {
                try repo.deleteTransactions(plan)
            }.value
            overviewSnapshotCache.removeAll()
            let refreshSuccess = await reloadAll()
            if refreshSuccess {
                lastForegroundRefreshAt = Date()
            }
            return TransactionDeletionResult(deletedCount: deleted, refreshSuccess: refreshSuccess)
        } catch {
            errorMessage = error.localizedDescription
            return TransactionDeletionResult(deletedCount: 0, refreshSuccess: false)
        }
    }

    public func deleteLabel(id: UUID) {
        runMutation {
            try repository.deleteLabel(id: id)
        }
    }

    public func saveWallet(_ wallet: Wallet) {
        runMutation {
            try repository.saveWallet(wallet)
        }
    }

    @discardableResult
    public func saveWalletCategory(_ category: WalletCategory) -> Bool {
        runMutation {
            try repository.saveWalletCategory(category)
        }
    }

    public func deleteWallet(id: UUID) {
        guard wallets.count > 1 else {
            errorMessage = L10n.string("At least one active wallet must remain.")
            return
        }
        runMutation {
            try repository.deleteWallet(id: id)
        }
    }

    public func saveCategory(_ category: CashRunwayCategory) {
        runMutation {
            try repository.saveCategory(category)
        }
    }

    public func saveLabel(_ label: CashRunwayLabel) {
        runMutation {
            try repository.saveLabel(label)
        }
    }

    // DEPRECATED — Budgets feature is de-prioritized. Work stopped; do not modify or add tests until resumed.
    public func saveBudget(_ budget: Budget) {
        runMutation {
            try repository.saveBudget(budget)
        }
    }

    public func saveCurrencyPreferences(_ preferences: CurrencyPreferences) {
        runMutation {
            try repository.saveCurrencyPreferences(preferences)
        }
    }

    // DEPRECATED — Budgets feature is de-prioritized. Work stopped; do not modify or add tests until resumed.
    public func archiveBudget(_ budget: Budget) {
        var archived = budget
        archived.isArchived = true
        archived.updatedAt = .now
        saveBudget(archived)
    }

    public func saveTemplate(_ template: RecurringTemplate) {
        runMutation {
            try repository.saveRecurringTemplate(template)
        }
    }

    public func saveInstance(_ instance: RecurringInstance) {
        runMutation {
            try repository.saveRecurringInstance(instance)
            try repository.refreshRecurringInstances()
        }
    }

    public func postInstance(_ instance: RecurringInstance) {
        runMutation {
            try repository.postRecurringInstance(id: instance.id)
        }
    }

    public func skipInstance(_ instance: RecurringInstance) {
        runMutation {
            try repository.skipRecurringInstance(id: instance.id)
        }
    }

    @discardableResult
    public func mergeCategory(oldCategoryID: UUID, into newCategoryID: UUID) -> Bool {
        runMutation {
            try repository.mergeCategory(oldCategoryID: oldCategoryID, into: newCategoryID)
        }
    }

    public func categoryManagementItems(kind: CategoryKind) -> [CategoryManagementItem] {
        (try? repository.categoryManagementItems(kind: kind)) ?? []
    }

    public func toggleCategoryVisibility(_ category: CashRunwayCategory) {
        var updated = category
        updated.isArchived.toggle()
        updated.updatedAt = .now
        saveCategory(updated)
    }

    public func reorderCategories(kind: CategoryKind, orderedCategoryIDs: [UUID]) {
        runMutation {
            try repository.reorderCategories(kind: kind, orderedCategoryIDs: orderedCategoryIDs)
        }
    }

    func exportCSV(query: TransactionQuery) async throws -> String {
        try await backgroundWork.exportCSV(query: query)
    }

    public func handleForegroundResume() {
        // LEGACY_DISABLED_APP_LOCK:
        // guard !isLocked else { return }
        let now = Date()
        if let lastForegroundRefreshAt, now.timeIntervalSince(lastForegroundRefreshAt) < foregroundRefreshMinimumInterval {
            return
        }
        guard foregroundRefreshTask == nil else { return }

        let selectedMonthKey = selectedMonthKey
        let selectedWalletID = selectedWalletID
        let selectedTimelinePeriod = selectedTimelinePeriod
        let transactionQuery = transactionQuery
        let backgroundWork = self.backgroundWork
        foregroundRefreshTask = Task { [weak self, backgroundWork] in
            defer {
                self?.foregroundRefreshTask = nil
            }
            do {
                let (snapshot, bankSyncMessage) = try await backgroundWork.refreshForegroundSnapshot(
                    selectedMonthKey: selectedMonthKey,
                    selectedWalletID: selectedWalletID,
                    selectedTimelinePeriod: selectedTimelinePeriod,
                    transactionQuery: transactionQuery
                )
                guard !Task.isCancelled else { return }
                guard let self else { return }
                guard self.currentRefreshScopeMatches(monthKey: selectedMonthKey, walletID: selectedWalletID, period: selectedTimelinePeriod, query: transactionQuery) else {
                    return
                }
                self.apply(snapshot)
                self.latestTransactionMonthKey = try? self.repository.latestTransactionMonthKey()
                if let overview = snapshot.overviewSnapshot {
                    self.setCachedOverview(overview, monthKey: overview.selectedMonthKey, walletID: overview.walletFilterID)
                }
                self.lastForegroundRefreshAt = Date()
                self.bankSyncMessage = bankSyncMessage
                self.errorMessage = nil
            } catch is CancellationError {
                // The next foreground resume can schedule a fresh refresh.
            } catch {
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    @discardableResult
    private func runMutation(_ mutation: () throws -> Void) -> Bool {
        foregroundRefreshTask?.cancel()
        foregroundRefreshTask = nil
        do {
            try mutation()
            overviewSnapshotCache.removeAll()
            Task { @MainActor in
                let success = await reloadAll()
                if success {
                    lastForegroundRefreshAt = Date()
                }
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    fileprivate nonisolated static func loadSnapshot(
        repository: any CashRunwayRepositorying,
        selectedMonthKey: Int,
        selectedWalletID: UUID?,
        selectedTimelinePeriod: TimelinePeriod,
        transactionQuery: TransactionQuery
    ) throws -> AppModelSnapshot {
        var query = transactionQuery
        query.walletID = selectedWalletID
        return AppModelSnapshot(
            wallets: try repository.wallets(),
            walletCategories: try repository.walletCategories(),
            expenseCategories: try repository.categories(kind: .expense),
            incomeCategories: try repository.categories(kind: .income),
            labels: try repository.labels(),
            templates: try repository.recurringTemplates(),
            instances: try repository.recurringInstances(),
            budgets: try repository.budgets(monthKey: selectedMonthKey),
            transactions: try repository.transactions(query: query),
            dashboardSnapshot: try repository.dashboard(monthKey: selectedMonthKey, walletID: selectedWalletID),
            timelineSnapshot: try repository.timelineSnapshot(monthKey: selectedMonthKey, walletID: selectedWalletID, query: query, period: selectedTimelinePeriod),
            overviewSnapshot: try repository.overviewSnapshot(monthKey: selectedMonthKey, walletID: selectedWalletID),
            transactionQuery: query
        )
    }

    fileprivate nonisolated static func loadMutableSnapshots(
        repository: any CashRunwayRepositorying,
        selectedMonthKey: Int,
        selectedWalletID: UUID?,
        selectedTimelinePeriod: TimelinePeriod,
        transactionQuery: TransactionQuery
    ) throws -> MutableSnapshots {
        var query = transactionQuery
        query.walletID = selectedWalletID
        return MutableSnapshots(
            budgets: try repository.budgets(monthKey: selectedMonthKey),
            walletCategories: try repository.walletCategories(),
            transactions: try repository.transactions(query: query),
            dashboardSnapshot: try repository.dashboard(monthKey: selectedMonthKey, walletID: selectedWalletID),
            timelineSnapshot: try repository.timelineSnapshot(monthKey: selectedMonthKey, walletID: selectedWalletID, query: query, period: selectedTimelinePeriod),
            overviewSnapshot: try repository.overviewSnapshot(monthKey: selectedMonthKey, walletID: selectedWalletID),
            transactionQuery: query
        )
    }

    private func overviewCacheKey(monthKey: Int, walletID: UUID?) -> String {
        "\(monthKey)-\(walletID?.uuidString ?? "all")"
    }

    private func apply(_ snapshot: AppModelSnapshot) {
        wallets = snapshot.wallets
        walletCategories = snapshot.walletCategories
        expenseCategories = snapshot.expenseCategories
        incomeCategories = snapshot.incomeCategories
        labels = snapshot.labels
        templates = snapshot.templates
        instances = snapshot.instances
        budgets = snapshot.budgets
        transactions = snapshot.transactions
        dashboardSnapshot = snapshot.dashboardSnapshot
        timelineSnapshot = snapshot.timelineSnapshot
        overviewSnapshot = snapshot.overviewSnapshot
        transactionQuery = snapshot.transactionQuery
    }

    public func loadCategoryDetailTransactions(query: TransactionQuery) async {
        categoryDetailTransactions = []
        do {
            let repository = self.repository
            let txs = try await Task(priority: .userInitiated) {
                try repository.transactions(query: query, limit: nil)
            }.value
            guard !Task.isCancelled else { return }
            categoryDetailTransactions = txs
        } catch {
            categoryDetailTransactions = []
        }
    }

    private func currentRefreshScopeMatches(monthKey: Int, walletID: UUID?, period: TimelinePeriod, query: TransactionQuery) -> Bool {
        var currentQuery = transactionQuery
        currentQuery.walletID = selectedWalletID
        var capturedQuery = query
        capturedQuery.walletID = walletID
        return selectedMonthKey == monthKey && selectedWalletID == walletID && selectedTimelinePeriod == period && currentQuery == capturedQuery
    }
}

private actor BackgroundWork {
    private let repository: any CashRunwayRepositorying
    private let csvService: any CSVImportServicing
    private let backupService: any BackupServicing
    private let bankSyncPerformer: any BankSyncPerforming

    init(
        repository: any CashRunwayRepositorying,
        csvService: any CSVImportServicing,
        backupService: any BackupServicing,
        bankSyncPerformer: any BankSyncPerforming
    ) {
        self.repository = repository
        self.csvService = csvService
        self.backupService = backupService
        self.bankSyncPerformer = bankSyncPerformer
    }

    func loadAllBarsAndSnapshot(
        selectedMonthKey: Int,
        selectedWalletID: UUID?,
        selectedTimelinePeriod: TimelinePeriod,
        transactionQuery: TransactionQuery
    ) throws -> (bars: [TimelineBarPoint], snapshot: AppModelSnapshot) {
        let bars = try repository.allBars(walletID: selectedWalletID, period: selectedTimelinePeriod)
        let snapshot = try CashRunwayAppModel.loadSnapshot(
            repository: repository,
            selectedMonthKey: selectedMonthKey,
            selectedWalletID: selectedWalletID,
            selectedTimelinePeriod: selectedTimelinePeriod,
            transactionQuery: transactionQuery
        )
        return (bars, snapshot)
    }

    func loadOverviewSnapshot(monthKey: Int, walletID: UUID?) throws -> OverviewSnapshot {
        try repository.overviewSnapshot(monthKey: monthKey, walletID: walletID)
    }

    func loadMutableSnapshots(
        selectedMonthKey: Int,
        selectedWalletID: UUID?,
        selectedTimelinePeriod: TimelinePeriod,
        transactionQuery: TransactionQuery
    ) throws -> MutableSnapshots {
        try CashRunwayAppModel.loadMutableSnapshots(
            repository: repository,
            selectedMonthKey: selectedMonthKey,
            selectedWalletID: selectedWalletID,
            selectedTimelinePeriod: selectedTimelinePeriod,
            transactionQuery: transactionQuery
        )
    }

    func refreshForegroundSnapshot(
        selectedMonthKey: Int,
        selectedWalletID: UUID?,
        selectedTimelinePeriod: TimelinePeriod,
        transactionQuery: TransactionQuery
    ) async throws -> (snapshot: AppModelSnapshot, bankSyncMessage: String?) {
        let bankSyncMessage: String?
        do {
            _ = try await bankSyncPerformer.syncOnForeground()
            bankSyncMessage = nil
        } catch {
            bankSyncMessage = error.localizedDescription
        }
        try repository.runMaintenance()
        try repository.refreshRecurringInstances()
        let snapshot = try CashRunwayAppModel.loadSnapshot(
            repository: repository,
            selectedMonthKey: selectedMonthKey,
            selectedWalletID: selectedWalletID,
            selectedTimelinePeriod: selectedTimelinePeriod,
            transactionQuery: transactionQuery
        )
        return (snapshot, bankSyncMessage)
    }

    func exportCSV(query: TransactionQuery) throws -> String {
        try csvService.exportCSV(query: query)
    }
}

fileprivate struct AppModelSnapshot: Sendable {
    var wallets: [Wallet]
    var walletCategories: [WalletCategory]
    var expenseCategories: [CashRunwayCategory]
    var incomeCategories: [CashRunwayCategory]
    var labels: [CashRunwayLabel]
    var templates: [RecurringTemplate]
    var instances: [RecurringInstance]
    var budgets: [BudgetProgress]
    var transactions: [TransactionListItem]
    var dashboardSnapshot: DashboardSnapshot?
    var timelineSnapshot: TimelineSnapshot?
    var overviewSnapshot: OverviewSnapshot?
    var transactionQuery: TransactionQuery
}

fileprivate struct MutableSnapshots: Sendable {
    var budgets: [BudgetProgress]
    var walletCategories: [WalletCategory]
    var transactions: [TransactionListItem]
    var dashboardSnapshot: DashboardSnapshot?
    var timelineSnapshot: TimelineSnapshot?
    var overviewSnapshot: OverviewSnapshot?
    var transactionQuery: TransactionQuery
}

fileprivate struct PreRestoreState {
    let selectedWalletID: UUID?
    let overviewSnapshotCache: [String: OverviewSnapshot]
    let overviewSnapshotCacheOrder: [String]
}
