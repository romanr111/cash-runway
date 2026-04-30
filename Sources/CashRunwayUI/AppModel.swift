import Foundation
import Observation
import SwiftUI
#if canImport(CashRunwayCore)
import CashRunwayCore
#endif

public typealias CashRunwayCategory = Category
public typealias CashRunwayLabel = Label

@MainActor
@Observable
public final class CashRunwayAppModel {
    public var repository: CashRunwayRepository
    public var csvService: CSVService
    public var lockStore: AppLockStore

    public var wallets: [Wallet] = []
    public var expenseCategories: [CashRunwayCategory] = []
    public var incomeCategories: [CashRunwayCategory] = []
    public var labels: [CashRunwayLabel] = []
    public var transactions: [TransactionListItem] = []
    public var budgets: [BudgetProgress] = []
    public var templates: [RecurringTemplate] = []
    public var instances: [RecurringInstance] = []
    public var dashboardSnapshot: DashboardSnapshot?
    public var timelineSnapshot: TimelineSnapshot?
    public var overviewSnapshot: OverviewSnapshot?

    public var selectedMonthKey = DateKeys.monthKey(for: .now)
    public var selectedWalletID: UUID?
    public var selectedTimelinePeriod: TimelinePeriod = .month
    public var transactionQuery = TransactionQuery()
    public var isLocked = false
    public var lockMessage: String?
    public var errorMessage: String?
    public var isLoading = false
    public private(set) var latestTransactionMonthKey: Int?
    private var foregroundRefreshTask: Task<Void, Never>?
    private var lastForegroundRefreshAt: Date?
    private let foregroundRefreshMinimumInterval: TimeInterval = 10
    private var overviewSnapshotCache: [String: OverviewSnapshot] = [:]

    public var maxMonthKey: Int {
        max(DateKeys.monthKey(for: .now), latestTransactionMonthKey ?? 0)
    }

    public init(
        repository: CashRunwayRepository = CashRunwayRepository(),
        lockStore: AppLockStore = AppLockStore(keychain: KeychainStore(service: "dev.roman.cash-runway"))
    ) {
        self.repository = repository
        self.csvService = CSVService(repository: repository)
        self.lockStore = lockStore
    }

    public func bootstrap() {
        do {
            try repository.seedIfNeeded()
            try repository.runMaintenance()
            try repository.refreshRecurringInstances()
            try reloadAll()
            if let configuration = lockStore.configuration(), configuration.isEnabled {
                isLocked = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func reloadAll() throws {
        isLoading = true
        defer { isLoading = false }
        let snapshot = try Self.loadSnapshot(
            repository: repository,
            selectedMonthKey: selectedMonthKey,
            selectedWalletID: selectedWalletID,
            selectedTimelinePeriod: selectedTimelinePeriod,
            transactionQuery: transactionQuery
        )
        apply(snapshot)
        latestTransactionMonthKey = try? repository.latestTransactionMonthKey()
        if let overview = snapshot.overviewSnapshot {
            overviewSnapshotCache[overviewCacheKey(monthKey: overview.selectedMonthKey, walletID: overview.walletFilterID)] = overview
        }
    }

    /// Reloads only the mutable snapshots (dashboard, timeline, overview) without re-fetching
    /// static metadata like categories, wallets, or labels. Used for month navigation.
    public func reloadSnapshots() throws {
        let cacheKey = overviewCacheKey(monthKey: selectedMonthKey, walletID: selectedWalletID)
        if let cached = overviewSnapshotCache[cacheKey] {
            overviewSnapshot = cached
        }
        isLoading = true
        defer { isLoading = false }
        let mutable = try Self.loadMutableSnapshots(
            repository: repository,
            selectedMonthKey: selectedMonthKey,
            selectedWalletID: selectedWalletID,
            selectedTimelinePeriod: selectedTimelinePeriod,
            transactionQuery: transactionQuery
        )
        budgets = mutable.budgets
        transactions = mutable.transactions
        dashboardSnapshot = mutable.dashboardSnapshot
        timelineSnapshot = mutable.timelineSnapshot
        overviewSnapshot = mutable.overviewSnapshot
        transactionQuery = mutable.transactionQuery
        latestTransactionMonthKey = try? repository.latestTransactionMonthKey()
        overviewSnapshotCache[overviewCacheKey(monthKey: selectedMonthKey, walletID: selectedWalletID)] = mutable.overviewSnapshot
    }

    public func navigateMonth(by offset: Int) {
        guard let newDate = DateKeys.calendar.date(byAdding: .month, value: offset, to: DateKeys.startOfMonth(for: selectedMonthKey)) else { return }
        let newMonthKey = DateKeys.monthKey(for: newDate)
        guard newMonthKey <= maxMonthKey else { return }
        selectedMonthKey = newMonthKey
        do {
            try reloadSnapshots()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func unlock(pin: String) {
        guard lockStore.validate(pin: pin) else {
            lockMessage = "Incorrect PIN."
            return
        }
        isLocked = false
        lockMessage = nil
    }

    public func unlockWithBiometrics() async {
        guard await lockStore.unlockWithBiometrics() else {
            lockMessage = "Biometric unlock failed."
            return
        }
        isLocked = false
        lockMessage = nil
    }

    public func enableLock(pin: String, biometrics: Bool) {
        do {
            try lockStore.save(pin: pin, biometrics: biometrics, backgroundLockSeconds: 15)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func saveTransaction(_ draft: TransactionDraft) {
        saveTransaction(draft, recurringTemplate: nil)
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

    public func saveWallet(_ wallet: Wallet) {
        runMutation {
            try repository.saveWallet(wallet)
        }
    }

    public func deleteWallet(id: UUID) {
        guard wallets.count > 1 else {
            errorMessage = "At least one active wallet must remain."
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

    public func saveBudget(_ budget: Budget) {
        runMutation {
            try repository.saveBudget(budget)
        }
    }

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

    public func mergeCategory(oldCategoryID: UUID, into newCategoryID: UUID) {
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

    @discardableResult
    public func importCSV(data: Data, fileName: String, mapping: CSVImportMapping) throws -> CSVImportResult {
        do {
            let result = try csvService.importCSV(data: data, fileName: fileName, mapping: mapping)
            try reloadAll()
            errorMessage = nil
            return result
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    public func exportCSV() -> String {
        (try? csvService.exportCSV(query: transactionQuery)) ?? ""
    }

    public func previewCSV(data: Data) throws -> CSVImportPreview {
        try csvService.preview(data: data)
    }

    public func detectPreset(headers: [String]) -> CSVPreset {
        csvService.detectPreset(headers: headers)
    }

    public func handleForegroundResume() {
        guard !isLocked else { return }
        let now = Date()
        if let lastForegroundRefreshAt, now.timeIntervalSince(lastForegroundRefreshAt) < foregroundRefreshMinimumInterval {
            return
        }
        guard foregroundRefreshTask == nil else { return }

        let repository = repository
        let selectedMonthKey = selectedMonthKey
        let selectedWalletID = selectedWalletID
        let selectedTimelinePeriod = selectedTimelinePeriod
        let transactionQuery = transactionQuery
        foregroundRefreshTask = Task { [weak self] in
            defer {
                self?.foregroundRefreshTask = nil
            }
            do {
                let snapshot = try await Task.detached(priority: .utility) {
                    try repository.runMaintenance()
                    try repository.refreshRecurringInstances()
                    return try Self.loadSnapshot(
                        repository: repository,
                        selectedMonthKey: selectedMonthKey,
                        selectedWalletID: selectedWalletID,
                        selectedTimelinePeriod: selectedTimelinePeriod,
                        transactionQuery: transactionQuery
                    )
                }.value
                guard !Task.isCancelled else { return }
                guard let self else { return }
                guard self.currentRefreshScopeMatches(monthKey: selectedMonthKey, walletID: selectedWalletID, period: selectedTimelinePeriod, query: transactionQuery) else {
                    return
                }
                self.apply(snapshot)
                self.latestTransactionMonthKey = try? self.repository.latestTransactionMonthKey()
                if let overview = snapshot.overviewSnapshot {
                    self.overviewSnapshotCache[self.overviewCacheKey(monthKey: overview.selectedMonthKey, walletID: overview.walletFilterID)] = overview
                }
                self.lastForegroundRefreshAt = Date()
                self.errorMessage = nil
            } catch is CancellationError {
                // The next foreground resume can schedule a fresh refresh.
            } catch {
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    private func runMutation(_ mutation: () throws -> Void) {
        foregroundRefreshTask?.cancel()
        foregroundRefreshTask = nil
        do {
            try mutation()
            overviewSnapshotCache.removeAll()
            try reloadAll()
            lastForegroundRefreshAt = Date()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private nonisolated static func loadSnapshot(
        repository: CashRunwayRepository,
        selectedMonthKey: Int,
        selectedWalletID: UUID?,
        selectedTimelinePeriod: TimelinePeriod,
        transactionQuery: TransactionQuery
    ) throws -> AppModelSnapshot {
        var query = transactionQuery
        query.walletID = selectedWalletID
        return AppModelSnapshot(
            wallets: try repository.wallets(),
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

    private nonisolated static func loadMutableSnapshots(
        repository: CashRunwayRepository,
        selectedMonthKey: Int,
        selectedWalletID: UUID?,
        selectedTimelinePeriod: TimelinePeriod,
        transactionQuery: TransactionQuery
    ) throws -> MutableSnapshots {
        var query = transactionQuery
        query.walletID = selectedWalletID
        return MutableSnapshots(
            budgets: try repository.budgets(monthKey: selectedMonthKey),
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

    private func currentRefreshScopeMatches(monthKey: Int, walletID: UUID?, period: TimelinePeriod, query: TransactionQuery) -> Bool {
        var currentQuery = transactionQuery
        currentQuery.walletID = selectedWalletID
        var capturedQuery = query
        capturedQuery.walletID = walletID
        return selectedMonthKey == monthKey && selectedWalletID == walletID && selectedTimelinePeriod == period && currentQuery == capturedQuery
    }
}

private struct AppModelSnapshot: Sendable {
    var wallets: [Wallet]
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

private struct MutableSnapshots: Sendable {
    var budgets: [BudgetProgress]
    var transactions: [TransactionListItem]
    var dashboardSnapshot: DashboardSnapshot?
    var timelineSnapshot: TimelineSnapshot?
    var overviewSnapshot: OverviewSnapshot?
    var transactionQuery: TransactionQuery
}

enum CSVImportFileReader {
    static func readData(from url: URL) throws -> Data {
        let copyURL = try temporaryAccessibleCopy(from: url)
        defer { try? FileManager.default.removeItem(at: copyURL) }
        return try Data(contentsOf: copyURL)
    }

    private static func temporaryAccessibleCopy(from url: URL) throws -> URL {
        let fileManager = FileManager.default
        let directoryURL = fileManager.temporaryDirectory.appendingPathComponent("CashRunwayCSVImports", isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let fileName = url.lastPathComponent.isEmpty ? "import.csv" : url.lastPathComponent
        let destinationURL = directoryURL.appendingPathComponent("\(UUID().uuidString)-\(fileName)")
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        var coordinatedError: NSError?
        var copyError: (any Error)?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinatedError) { coordinatedURL in
            do {
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.copyItem(at: coordinatedURL, to: destinationURL)
            } catch {
                copyError = error
            }
        }

        if let copyError {
            throw copyError
        }
        if let coordinatedError {
            throw coordinatedError
        }
        guard fileManager.fileExists(atPath: destinationURL.path) else {
            throw CashRunwayError.validation("Imported CSV could not be copied into the app sandbox.")
        }
        return destinationURL
    }
}
